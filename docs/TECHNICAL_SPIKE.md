# OverlayFeasibilitySpike

## Work log

```text
Phase: Task 001 - OverlayFeasibilitySpike
Goal: Prove a top-center nonactivating overlay can expand and collapse.
Files to create/change: app lifecycle, display resolver, NSPanel, overlay controller, package metadata.
Technical assumptions: macOS 14.6+, public AppKit APIs, one panel on the main display for this spike.
Expected test: build, geometry tests, launch, focus check, Desktop/fullscreen/Spaces observation.
```

## Implementation

The prototype uses a borderless `NSPanel` with `nonactivatingPanel`, a transparent window background, no system shadow, and `canBecomeKey`/`canBecomeMain` disabled. The panel is top-center anchored using `NSScreen.frame`. Physical notch detection uses `safeAreaInsets` and the gap between `auxiliaryTopLeftArea` and `auxiliaryTopRightArea`; other displays receive a virtual handler.

The provisional window level is one point above `statusBar`. It is intentionally recorded as a spike decision and must be re-evaluated after the fullscreen and menu-bar interference matrix.

## Results

| Area | Status | Solution | Risk |
|---|---|---|---|
| Overlay | AUTOMATED PASS | Borderless, transparent, nonactivating `NSPanel` | Visual fit still needs device calibration |
| Geometry | AUTOMATED PASS | Top-center frame function with unit coverage | Physical notch requires notched hardware observation |
| Fullscreen | PENDING MANUAL | `.fullScreenAuxiliary` | Application-specific behavior is P0 |
| Spaces | PENDING MANUAL | `.canJoinAllSpaces` and `.stationary` | Mission Control/Stage Manager require observation |
| Focus | PENDING MANUAL | `canBecomeKey == false`, `canBecomeMain == false` | Verify while typing in another app |
| Physical notch detection | PENDING DEVICE | Public `NSScreen` safe/auxiliary geometry | Current display may be non-notched |
| Pointer monitor | NOT IN TASK 001 | Planned for Task 004 | None accepted yet |
| Gestures | NOT IN TASK 001 | Planned after stable mouse interaction | API behavior remains a risk |
| Drag destination | NOT IN TASK 001 | Planned for Tray milestone | Sandbox and access lifetime remain risks |

## Exit gate

Task 001 remains open until the panel is observed on Desktop and over a fullscreen application without stealing focus. No feature-widget implementation should start before that manual gate passes.

The current machine has Apple Command Line Tools and Swift 6.3, but not the full Xcode application; therefore XCTest is present in source but unavailable to this selected toolchain. `scripts/run-core-checks.sh` compiles the same production geometry code with executable assertions so the spike still has an automated gate.

## Hover and haptics increment

The collapsed panel now has a dedicated `hovered` presentation state. Entering its interaction zone grows the surface by 20 pt on each side and 20 pt downward while retaining the top-center anchor. A thin animated rainbow outline is visible only in this pre-open state and becomes static when Reduce Motion is enabled. `PointerMonitor` observes global and local mouse movement, dragging, and mouse-down events without polling. A new entry returns a one-shot signal to `HapticService`, which uses the public `NSHapticFeedbackManager` alignment pattern. Unsupported pointing hardware degrades to the visual response without affecting the overlay.

Visual observation on the current physical-notch display confirmed the hover frame at 186 x 32 pixels. The physical sensation of the haptic remains a human hardware check and cannot be asserted by software.
