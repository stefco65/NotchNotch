#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
output_path="${TMPDIR:-/tmp}/notchnook-geometry-checks"

cd "$repo_root"

agent_sources=(NotchApp/Features/Agents/**/*.swift(N.))

swiftc \
    NotchApp/Core/Display/DisplayDescriptor.swift \
    NotchApp/Core/Window/NotchPanel.swift \
    NotchApp/Core/Window/NotchGeometryAnimator.swift \
    NotchApp/Core/Window/PassiveHostingView.swift \
    NotchApp/Core/Window/PhysicalNotchGuideController.swift \
    NotchApp/Core/Window/SolidBlackNotchHostingView.swift \
    NotchApp/Core/Window/NotchWindowController.swift \
    NotchApp/Core/Input/InteractionZone.swift \
    NotchApp/Core/Logging/AppErrorLog.swift \
    NotchApp/Core/Logging/AppLogger.swift \
    NotchApp/Features/Settings/SettingsStore.swift \
    NotchApp/Features/Shortcuts/ShortcutCommandService.swift \
    NotchApp/Features/Shortcuts/ShortcutsComponentView.swift \
    NotchApp/Features/Tasks/TaskStore.swift \
    NotchApp/Features/Tasks/TaskComponentView.swift \
    NotchApp/Features/Calendar/CalendarStore.swift \
    NotchApp/Features/Calendar/CalendarComponentView.swift \
    "${agent_sources[@]}" \
    NotchApp/Features/LiveActivity/LiveActivityCenter.swift \
    NotchApp/Features/LiveActivity/DynamicIslandLayout.swift \
    NotchApp/Features/LiveActivity/DynamicIslandBubbleController.swift \
    NotchApp/Features/Music/SpotifyMusicStore.swift \
    NotchApp/Features/Music/MusicComponentView.swift \
    NotchApp/Features/Tray/TrayItem.swift \
    NotchApp/Features/Tray/TrayFileStorage.swift \
    NotchApp/Features/Tray/TrayItemDragSource.swift \
    NotchApp/Features/Tray/TrayStore.swift \
    NotchApp/Features/Tray/TrayView.swift \
    scripts/GeometryChecks.swift \
    -o "$output_path"

"$output_path"
