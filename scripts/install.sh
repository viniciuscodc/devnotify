#!/bin/zsh
set -euo pipefail

repository="${DEVNOTIFY_REPOSITORY:-ebanx/devnotify}"
install_dir="${DEVNOTIFY_INSTALL_DIR:-$HOME/Applications}"
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

if ! command -v gh >/dev/null 2>&1; then
  print -u2 "DevNotify requires GitHub CLI (gh): https://cli.github.com/"
  exit 1
fi
if ! command -v swift >/dev/null 2>&1; then
  print -u2 "DevNotify requires Xcode Command Line Tools. Run: xcode-select --install"
  exit 1
fi

print "Downloading DevNotify from $repository…"
gh api "repos/$repository/tarball" > "$temp_dir/source.tar.gz"
mkdir -p "$temp_dir/source"
tar -xzf "$temp_dir/source.tar.gz" -C "$temp_dir/source" --strip-components=1
cd "$temp_dir/source"

print "Building DevNotify…"
swift build -c release
app_path="$temp_dir/DevNotify.app"
mkdir -p "$app_path/Contents/MacOS"
cp ".build/release/DevNotify" "$app_path/Contents/MacOS/DevNotify"
cp "Info.plist" "$app_path/Contents/Info.plist"
codesign --force --deep --sign - "$app_path"

mkdir -p "$install_dir"
destination="$install_dir/DevNotify.app"
if [[ -e "$destination" ]]; then
  backup="$temp_dir/DevNotify.previous.app"
  mv "$destination" "$backup"
fi
mv "$app_path" "$destination"
xattr -dr com.apple.quarantine "$destination" 2>/dev/null || true
open "$destination"
print "Installed DevNotify in $destination"
