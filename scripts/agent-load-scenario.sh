#!/bin/zsh
# agent-load-scenario.sh — two-agent DI load scenario + background resource sampling
# Timeline:
#   0s  agent-a + agent-b → working
#   6s  agent-a → waitingForUser (stopped / orange)
#   9s  agent-a → working (resumed after decision)
#  12s  agent-a → completed
#  15s  agent-b → completed
set -euo pipefail

repo_root="${0:A:h:h}"
cd "$repo_root"

provider="${1:-cursor}"
out_dir="$repo_root/tmp-notch-qa"
mkdir -p "$out_dir"
stamp="$(date +%Y%m%d-%H%M%S)"
csv="$out_dir/agent-load-$stamp.csv"
summary="$out_dir/agent-load-$stamp-summary.txt"

echo "→ Building agentbridge + packaging NotchNook (release)…"
swift build -c release --product agentbridge >/dev/null
./scripts/package-app.sh release >/dev/null

bridge="$repo_root/.build/release/agentbridge"
sock="$HOME/Library/Application Support/NotchNook/agent-events.sock"

pkill -x NotchNook 2>/dev/null || true
sleep 0.4
rm -f "$sock"
open "$repo_root/build/NotchNook.app"

echo -n "→ Waiting for IPC socket"
for _ in {1..40}; do
  if [[ -S "$sock" ]]; then
    echo " OK"
    break
  fi
  echo -n "."
  sleep 0.25
done
if [[ ! -S "$sock" ]]; then
  echo "\nFAIL: agent-events.sock never appeared (is Agents monitoring started?)"
  exit 1
fi
# Give presence monitor a beat to mark Cursor/Codex running.
sleep 1.5

emit() {
  local agent="$1" state="$2"
  "$bridge" emit --provider "$provider" --agent "$agent" --state "$state" >/dev/null
  echo "  [$(date +%H:%M:%S)] $provider/$agent → $state"
}

# Background sampler: NotchNook + system load
python3 - "$csv" <<'PY' &
import csv, subprocess, time, sys
csv_path = sys.argv[1]
def notch_pid():
    try:
        return subprocess.check_output(["pgrep", "-nx", "NotchNook"], text=True).strip()
    except subprocess.CalledProcessError:
        return None

with open(csv_path, "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["t_s", "notch_cpu", "notch_rss_kb", "load1", "load5", "load15"])
    t0 = time.time()
    while True:
        pid = notch_pid()
        if not pid:
            break
        try:
            cpu, rss = subprocess.check_output(
                ["ps", "-p", pid, "-o", "%cpu=,rss="], text=True
            ).split()
        except subprocess.CalledProcessError:
            break
        la = subprocess.check_output(["sysctl", "-n", "vm.loadavg"], text=True)
        # macOS: "{ 1.23 1.45 1.67 }"
        parts = la.replace("{", "").replace("}", "").split()
        parts = [p for p in parts if p.replace(".", "", 1).isdigit()]
        while len(parts) < 3:
            parts.append("0")
        w.writerow([
            f"{time.time() - t0:.2f}",
            cpu,
            rss,
            parts[0],
            parts[1],
            parts[2],
        ])
        f.flush()
        time.sleep(0.5)
PY
sampler_pid=$!

echo "→ Scenario start (provider=$provider). Sampling → $csv"
emit "load-agent-a" "working"
emit "load-agent-b" "working"

sleep 6
emit "load-agent-a" "waitingForUser"

sleep 3
emit "load-agent-a" "working"

sleep 3
emit "load-agent-a" "completed"

sleep 3
emit "load-agent-b" "completed"

sleep 3
echo "→ Scenario finished; stopping sampler"

kill "$sampler_pid" 2>/dev/null || true
wait "$sampler_pid" 2>/dev/null || true

python3 - "$csv" "$summary" <<'PY'
import csv, statistics, sys
from pathlib import Path
csv_path, summary_path = sys.argv[1], sys.argv[2]
rows = list(csv.DictReader(open(csv_path)))
if not rows:
    Path(summary_path).write_text("NO SAMPLES\n")
    raise SystemExit(1)
cpus = [float(r["notch_cpu"]) for r in rows]
rss = [int(r["notch_rss_kb"]) for r in rows]
load1 = [float(r["load1"]) for r in rows]
def pct(xs, p):
    xs = sorted(xs)
    return xs[max(0, min(len(xs)-1, int(round((p/100)*(len(xs)-1)))))]
text = f"""Agent load scenario summary
samples={len(rows)} duration_s={rows[-1]['t_s']}
NotchNook CPU: avg={statistics.mean(cpus):.2f}%  p95={pct(cpus,95):.2f}%  max={max(cpus):.2f}%
NotchNook RSS: avg={statistics.mean(rss)/1024:.1f} MB  max={max(rss)/1024:.1f} MB
System load1:  avg={statistics.mean(load1):.2f}  max={max(load1):.2f}

Verdict guide:
  idle-like avg CPU < 2% during sparse IPC events = good
  sustained avg CPU > 10% during this light scenario = investigate
"""
Path(summary_path).write_text(text)
print(text)
PY

# Leave app running for visual DI check; comment kill if desired
# pkill -x NotchNook 2>/dev/null || true
echo "Artifacts:"
echo "  $csv"
echo "  $summary"
