#!/bin/zsh
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
swift build

app_path="$project_dir/.build/DevNotify.app"
mkdir -p "$app_path/Contents/MacOS"
pkill -x DevNotify 2>/dev/null || true
cp "$project_dir/.build/debug/DevNotify" "$app_path/Contents/MacOS/DevNotify"
cp "$project_dir/Info.plist" "$app_path/Contents/Info.plist"
codesign --force --deep --sign - "$app_path"
open -n "$app_path"
