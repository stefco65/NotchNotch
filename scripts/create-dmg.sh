#!/bin/zsh
# create-dmg.sh — tworzy instalator DMG dla NotchNook
# Użycie: ./scripts/create-dmg.sh [debug|release]
set -euo pipefail

repo_root="${0:A:h:h}"
configuration="${1:-release}"
app_bundle="$repo_root/build/NotchNook.app"
dmg_name="NotchNook"
dmg_out="$repo_root/build/${dmg_name}.dmg"
staging="$repo_root/build/dmg-staging"

# ── 1. Upewnij się że .app istnieje ──────────────────────────────────────────
if [[ ! -d "$app_bundle" ]]; then
    echo "Brak $app_bundle — buduję najpierw aplikację…"
    "$repo_root/scripts/package-app.sh" "$configuration"
fi

echo "→ App bundle: $app_bundle"

# ── 2. Staging directory ─────────────────────────────────────────────────────
rm -rf "$staging"
mkdir -p "$staging"

# Skopiuj .app do stagingu
cp -R "$app_bundle" "$staging/"

# Utwórz symlink do /Applications (standardowy drag-install)
ln -s /Applications "$staging/Applications"

# ── 3. Wylicz rozmiar i utwórz DMG ───────────────────────────────────────────
app_size_kb=$(du -sk "$staging" | awk '{print $1}')
# Dodaj 20% zapasu
dmg_size_kb=$(( app_size_kb * 12 / 10 ))
dmg_size_mb=$(( (dmg_size_kb / 1024) + 5 ))

echo "→ Rozmiar aplikacji: ${app_size_kb} KB → DMG: ${dmg_size_mb} MB"

# Usuń poprzedni DMG jeśli istnieje
rm -f "$dmg_out"

# Utwórz tymczasowy r/w DMG
tmp_dmg="$repo_root/build/${dmg_name}-tmp.dmg"
rm -f "$tmp_dmg"

hdiutil create \
    -srcfolder "$staging" \
    -volname "$dmg_name" \
    -fs HFS+ \
    -fsargs "-c c=64,a=16,b=16" \
    -format UDRW \
    -size "${dmg_size_mb}m" \
    "$tmp_dmg"

# ── 4. Zamontuj i opcjonalnie dostosuj tło / układ ────────────────────────────
device=$(hdiutil attach -readwrite -noverify -noautoopen "$tmp_dmg" \
    | grep -E '^/dev/' | sed 1q | awk '{print $1}')
vol_path="/Volumes/$dmg_name"

# Poczekaj aż wolumin się pojawi
sleep 1

# Ustaw ikonę folderu .app i opcje Findera (layout 2-ikon)
osascript <<APPLESCRIPT 2>/dev/null || true
tell application "Finder"
    tell disk "$dmg_name"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {400, 100, 920, 440}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 128
        set position of item "NotchNook.app" of container window to {160, 180}
        set position of item "Applications" of container window to {360, 180}
        close
        open
        update without registering applications
        delay 2
    end tell
end tell
APPLESCRIPT

# Odmontuj
hdiutil detach "$device" -quiet || hdiutil detach "$device" -force

# ── 5. Konwertuj do finalnego skompresowanego DMG ─────────────────────────────
echo "→ Kompresowanie DMG…"
hdiutil convert "$tmp_dmg" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$dmg_out"

rm -f "$tmp_dmg"
rm -rf "$staging"

echo ""
echo "✅ Gotowy instalator: $dmg_out"
echo "   Rozmiar: $(du -sh "$dmg_out" | awk '{print $1}')"
echo ""
echo "Aby zainstalować na innym urządzeniu:"
echo "  1. Wyślij plik $dmg_out"
echo "  2. Otwórz DMG (dwuklik)"
echo "  3. Przeciągnij NotchNook.app do folderu Applications"
echo "  4. Przy pierwszym uruchomieniu: prawy klik → Otwórz (ominięcie Gatekeeper)"
