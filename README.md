# NotchNook

Native macOS utility that turns the physical notch, or a virtual top-center handler, into a contextual surface.

Pełny opis produktu, stanów aplikacji, widoków, przepływów danych i aktualnego zakresu implementacji znajduje się w [docs/KONTEKST_APLIKACJI.md](docs/KONTEKST_APLIKACJI.md).

The repository currently implements the mandatory `OverlayFeasibilitySpike` from the supplied build plan. The panel is a SwiftUI surface hosted inside a deliberately managed AppKit `NSPanel`; it is not a conventional application window.

## Requirements

- macOS 14.6 or newer
- Swift 6 toolchain
- Xcode 16+ for regular IDE development (Swift Package Manager also builds from Terminal)

## Build and test

```bash
./scripts/run-core-checks.sh
./scripts/package-app.sh debug
open build/NotchNook.app
```

`swift test` runs the XCTest suite when a full Xcode toolchain is selected. Apple's standalone Command Line Tools do not ship the XCTest module, so `run-core-checks.sh` provides an equivalent executable assertion pass in that environment.

The application runs as an accessory utility without a Dock icon. Use the top menu-bar icon to expand/collapse the spike surface, open Settings, or copy display diagnostics.

Moving the pointer into the notch interaction zone extends the surface 20 pt downward and 20 pt on each side, shows a subtle flowing rainbow glow, and emits one alignment haptic through the built-in trackpad. The glow is rendered only while the pointer remains over the compact notch or its music preview and follows only the side and bottom edges; the top edge is intentionally omitted so it visually joins the physical notch. It can be disabled under **Wygląd** in Settings, disappears when the pointer leaves or the panel opens, and respects Reduce Motion. Clicking anywhere outside an expanded panel collapses it without consuming the click intended for the underlying application. The haptic is best-effort: Macs and pointing devices without supported haptic hardware still receive the visual hover response.

The gear button in the expanded panel opens native Settings. Panel width and the configured component list persist in `UserDefaults`. Components can be added, removed, reordered, and assigned relative width weights only in Settings. Adding a component automatically raises the panel's minimum width so cards do not collapse into each other; the width slider can still make the notch wider. Dividers in the expanded notch are visual and intentionally not interactive.

The notch is always created on the Mac's primary display. Settings contains an optional switch that creates an independent notch on every connected external display; the selection persists and reacts immediately to display connection or disconnection.

The Music component shows Spotify artwork, source, track, album, artist, and playback controls. It combines Spotify playback notifications with an independent one-second availability poll that runs even while the notch is collapsed. A transition from a closed to a running Spotify process immediately starts a metadata read, so launching Spotify after NotchNook synchronizes automatically. Metadata reads and playback commands target the newest live Spotify process by PID through ScriptingBridge instead of relying on LaunchServices bundle lookup; this avoids stale Spotify registrations blocking automatic detection. The read is attempted directly rather than waiting on a separate Automation preflight that can block when LaunchServices retains a dead Spotify port. Source availability is published as one atomic state derived from the process and track. The emitted availability value is passed directly into window geometry calculation, avoiding `@Published`'s will-set timing from briefly re-reading the previous state. When a valid Spotify source appears, the opaque surface widens and the compact music controls fade in as one coordinated transition. When Spotify closes, playback stops, or the active source becomes unavailable, the controls fade out while the surface animates back to the ordinary compact notch. Two consecutive metadata failures are required before clearing an otherwise running source to avoid flicker from a single transient Apple Event failure. When Spotify is closed, the component play button launches Spotify. While a track is active, the transparent host window keeps a fixed 300-point width while the opaque `#000000` surface renders at 280 points, showing miniature artwork on the left and an animated playback indicator on the right. Hovering any non-artwork part animates only that inner black surface from 280 to 300 points and grows it 20 points downward, with the rainbow outline. Artwork and playback use fixed coordinates in the unchanged host window, so neither participates in the background animation or requires compensating movement. The artwork zone uses both direct continuous SwiftUI hover tracking and the global pointer monitor; entering it switches to the deeper music preview, enlarges and lowers the artwork, and reveals a title • album • artist information line. After one second the line always scrolls from right to left in a seamless ticker loop. Short lines receive adaptive spacing so each repeated copy re-enters from the right edge instead of remaining stationary. Clicking the right playback zone toggles Spotify without opening the panel; clicking the remaining compact surface opens the full notch. No surface state uses a translucent window shadow or material background. Track changes update inside the fixed music layout so neighboring components do not jump.

The borderless panel itself remains transparent, but its hosting view owns a native opaque-black `CAShapeLayer` beneath SwiftUI. That layer follows the same state-dependent notch path and radii as the SwiftUI clip, leaving pixels outside the notch transparent while forcing every pixel inside the rendered surface to sRGB `#000000`.

The central Shortcuts component discovers actions from the macOS Shortcuts app and runs them through the system `shortcuts` command. Its buttons are stacked vertically and mirror the icon and color treatment of the corresponding Shortcuts cards. Settings can add or remove buttons, change their order, and assign each button a relative height; the configuration persists between launches.

The Tasks component keeps a persistent local to-do list with an add field at the top. Clicking a row fills its completion circle and dims the title; one second later it slides out to the right while the remaining rows animate into place. Right-clicking a task exposes Edit and Delete actions.

The Calendar component uses EventKit to show a centered seven-day strip and the events for the selected day. Access is requested only when the component is first displayed; denied access can be changed later in macOS Privacy settings.

The Agents component monitors open local AI sessions from Codex, Google Antigravity, and Cursor through a pluggable `AgentToolFactory` / `AgentToolInterface` layer (`NotchApp/Features/Agents/Interfaces/`). Each tool owns a native status enum (mapped to shared `working` / `waitingForUser` / `completed` buckets), a provider adapter, and a filesystem signal monitor that triggers resync so counters and the Dynamic Island stay current. Adding another AI product means registering a new interface in the factory rather than special-casing `AgentMonitorStore`. Each application has its own icon and three live counters: blue for working agents, orange for agents waiting on user approval or a decision, and green for completed agents. Dynamic Island priority is orange → blue → green. The view refreshes about every second (and on SQLite/WAL file changes) and shows zeroes when its source application is not running.

The expanded surface has two tabs: `Notch` for configured components and `Tray` for persistent file drops. Dropped files and folders are copied to `~/Library/Application Support/com.notchnook.app/Tray`, indexed in JSON, restored after relaunch, and can be removed individually from the Tray UI.

While `Tray` is selected, outside clicks intentionally keep the panel open so files can be collected from other applications. A dedicated close button appears below Settings in this mode. The regular `Notch` tab retains outside-click dismissal.

## Current scope

See `docs/TECHNICAL_SPIKE.md` for the acceptance matrix. Per the project plan, geometry, state-machine, input, Tray, AirDrop, and widget milestones follow only after the overlay feasibility gate has passed on Desktop and fullscreen.
