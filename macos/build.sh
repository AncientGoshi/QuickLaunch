#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export MACOSX_DEPLOYMENT_TARGET=13.0
# Build outside synced folders; File Provider can add FinderInfo even during signing.
cache="$HOME/Library/Caches/local.vibeapps.quicklaunch"
if [[ -L dist ]]; then
    echo 'Refusing a symlink at dist.' >&2
    exit 1
fi
mkdir -p "$cache" dist
lock="$cache/publish.lock"
if ! mkdir "$lock"; then
    echo "QuickLaunch build is already locked: $lock" >&2
    exit 1
fi
stage=''
publish=''
cleanup() {
    [[ -z "$stage" ]] || rm -rf "$stage"
    [[ -z "$publish" ]] || rm -rf "$publish"
    rmdir "$lock"
}
trap cleanup EXIT
stage=$(mktemp -d "$cache/build.XXXXXX")
publish=$(mktemp -d "$PWD/dist/.publish.XXXXXX")
app="$stage/QuickLaunch.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp macos/Info.plist "$app/Contents/Info.plist"
xcrun swift macos/icon.swift "$stage/QuickLaunch.iconset"
/usr/bin/iconutil -c icns "$stage/QuickLaunch.iconset" -o "$app/Contents/Resources/QuickLaunch.icns"
cargo build --locked --release --target-dir target
xcrun clang -fobjc-arc -Wall -Wextra -Werror -O2 \
  -framework Cocoa -framework Carbon -framework Security -liconv \
  macos/main.m target/release/libquicklaunch_core.a -o "$app/Contents/MacOS/QuickLaunch"
# File Provider / Finder can attach metadata that codesign rejects.
/usr/bin/xattr -cr "$app"
/usr/bin/codesign --force --sign - "$app"
/usr/bin/codesign --verify --strict "$app"
# Refuse to write through a destination bundle symlink.
if [[ -L dist/QuickLaunch.app ]]; then
    echo 'Refusing to replace a symlink at dist/QuickLaunch.app.' >&2
    exit 1
fi
# Copy across volumes before moving the old bundle; verify the copied seal.
/usr/bin/ditto --noextattr --norsrc "$app" "$publish/QuickLaunch.app"
/usr/bin/codesign --verify "$publish/QuickLaunch.app"
# The bundle has a fixed layout; replace it whole so obsolete files cannot survive.
if [[ -d dist/QuickLaunch.app ]]; then
    mv dist/QuickLaunch.app "$publish/previous.app"
fi
installed=false
if mv "$publish/QuickLaunch.app" dist/QuickLaunch.app; then
    installed=true
fi
if [[ "$installed" != true ]] || ! /usr/bin/codesign --verify dist/QuickLaunch.app; then
    if [[ "$installed" == true ]]; then
        mv dist/QuickLaunch.app "$publish/rejected.app" || true
    fi
    if [[ -d "$publish/previous.app" ]]; then
        if [[ -e dist/QuickLaunch.app ]] || ! mv "$publish/previous.app" dist/QuickLaunch.app; then
            printf 'Previous bundle kept at %s/previous.app\n' "$publish" >&2
            publish=''
        fi
    fi
    exit 1
fi
printf 'Built %s/dist/QuickLaunch.app\n' "$PWD"
