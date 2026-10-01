#!/bin/zsh
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
swift build

build_path="$project_dir/.build/DevNotify.app"
app_path="$HOME/Applications/DevNotify.app"
mkdir -p "$build_path/Contents/MacOS" "$build_path/Contents/Resources"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
pkill -x DevNotify 2>/dev/null || true
cp "$project_dir/.build/debug/DevNotify" "$build_path/Contents/MacOS/DevNotify"
cp "$project_dir/Info.plist" "$build_path/Contents/Info.plist"
cp "$project_dir/scripts/DevNotify.icns" "$build_path/Contents/Resources/DevNotify.icns"
commit_hash="$(git rev-parse HEAD 2>/dev/null || print unknown)"
/usr/libexec/PlistBuddy -c "Set :DevNotifyCommitHash development-$commit_hash" "$build_path/Contents/Info.plist"
bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$build_path/Contents/Info.plist")"
codesign --force --deep --sign - --requirements "=designated => identifier \"$bundle_identifier\"" "$build_path"
cp -R "$build_path/." "$app_path"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app_path"
open -n "$app_path"
