#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
configuration="${1:-debug}"
app_dir="$repo_root/build/NotchNook.app"
binary_path="$repo_root/.build/$configuration/NotchNook"

cd "$repo_root"
swift build -c "$configuration"

mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_path" "$app_dir/Contents/MacOS/NotchNook"
cp "$repo_root/NotchApp/Resources/Info.plist" "$app_dir/Contents/Info.plist"
# Ikona aplikacji
if [[ -f "$repo_root/NotchApp/Resources/AppIcon.icns" ]]; then
    cp "$repo_root/NotchApp/Resources/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
fi
codesign --force --deep --sign - "$app_dir"

echo "$app_dir"
