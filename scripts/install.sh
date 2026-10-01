#!/bin/zsh
set -euo pipefail

repository="${DEVNOTIFY_REPOSITORY:-viniciuscodc/devnotify}"
install_dir="${DEVNOTIFY_INSTALL_DIR:-$HOME/Applications}"
relaunch="${DEVNOTIFY_RELAUNCH:-1}"
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
commit_hash="${DEVNOTIFY_COMMIT:-}"
if [[ -z "$commit_hash" ]]; then
  commit_hash="$(gh api "repos/$repository/commits?per_page=1" --jq '.[0].sha')"
fi
if [[ ! "$commit_hash" =~ ^[0-9a-f]{40}$ ]]; then
  print -u2 "Could not resolve a valid commit hash for $repository."
  exit 1
fi
gh api "repos/$repository/tarball/$commit_hash" > "$temp_dir/source.tar.gz"
mkdir -p "$temp_dir/source"
tar -xzf "$temp_dir/source.tar.gz" -C "$temp_dir/source" --strip-components=1
cd "$temp_dir/source"

print "Building DevNotify…"
swift build -c release
app_path="$temp_dir/DevNotify.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp ".build/release/DevNotify" "$app_path/Contents/MacOS/DevNotify"
cp "Info.plist" "$app_path/Contents/Info.plist"
cp "scripts/DevNotify.icns" "$app_path/Contents/Resources/DevNotify.icns"
/usr/libexec/PlistBuddy -c "Set :DevNotifyCommitHash $commit_hash" "$app_path/Contents/Info.plist"
bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Contents/Info.plist")"
codesign --force --deep --sign - --requirements "=designated => identifier \"$bundle_identifier\"" "$app_path"

mkdir -p "$install_dir"
destination="$install_dir/DevNotify.app"
if [[ -e "$destination" ]]; then
  backup="$temp_dir/DevNotify.previous.app"
  mv "$destination" "$backup"
fi
mv "$app_path" "$destination"
xattr -dr com.apple.quarantine "$destination" 2>/dev/null || true
if [[ "$relaunch" == "1" ]]; then
  open "$destination"
fi
print "Installed DevNotify in $destination"
