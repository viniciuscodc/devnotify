#!/bin/zsh
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
swift build

app_path="$project_dir/.build/DevNotify.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
pkill -x DevNotify 2>/dev/null || true
cp "$project_dir/.build/debug/DevNotify" "$app_path/Contents/MacOS/DevNotify"
cp "$project_dir/Info.plist" "$app_path/Contents/Info.plist"
cp "$project_dir/scripts/DevNotify.icns" "$app_path/Contents/Resources/DevNotify.icns"
commit_hash="$(git rev-parse HEAD 2>/dev/null || print unknown)"
/usr/libexec/PlistBuddy -c "Set :DevNotifyCommitHash development-$commit_hash" "$app_path/Contents/Info.plist"
bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Contents/Info.plist")"
codesign --force --deep --sign - --requirements "=designated => identifier \"$bundle_identifier\"" "$app_path"
open -n "$app_path"
