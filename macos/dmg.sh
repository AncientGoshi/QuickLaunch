#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -L dist || -L dist/QuickLaunch.dmg || -d dist/QuickLaunch.dmg ]]; then
    echo 'Refusing an unexpected disk image output path.' >&2
    exit 1
fi
cache="$HOME/Library/Caches/local.vibeapps.quicklaunch"
mkdir -p "$cache"
stage=$(mktemp -d "$cache/dmg.XXXXXX")
mountpoint=''
publish=''
cleanup() {
    if [[ -n "$mountpoint" ]]; then
        /usr/bin/hdiutil detach "$mountpoint" >&2 || return
    fi
    [[ -z "$publish" ]] || rm -f "$publish"
    rm -rf "$stage"
}
trap cleanup EXIT
mkdir "$stage/payload" "$stage/mount"
/usr/bin/ditto --noextattr --norsrc dist/QuickLaunch.app "$stage/payload/QuickLaunch.app"
/usr/bin/codesign --verify --strict "$stage/payload/QuickLaunch.app"
python3 -m venv "$stage/venv"
python="$stage/venv/bin/python"
"$python" -m pip --disable-pip-version-check --quiet install \
    --require-hashes --only-binary=:all: -r macos/dmg-requirements.txt
export TMPDIR="$stage/"
xcrun swift macos/dmg-background.swift "$stage/installer.png"
"$python" -m dmgbuild -s macos/dmg-layout.py \
    -D "app=$stage/payload/QuickLaunch.app" -D "background=$stage/installer.png" \
    QuickLaunch "$stage/QuickLaunch.dmg"
/usr/bin/hdiutil verify "$stage/QuickLaunch.dmg"
/usr/bin/hdiutil attach -quiet -readonly -nobrowse -mountpoint "$stage/mount" "$stage/QuickLaunch.dmg"
mountpoint="$stage/mount"
[[ "$(readlink "$mountpoint/Applications")" == /Applications ]]
[[ -s "$mountpoint/QuickLaunch.app/Contents/Resources/QuickLaunch.icns" ]]
/usr/bin/codesign --verify --strict "$mountpoint/QuickLaunch.app"
"$python" tests/dmg-layout.py "$mountpoint"
/usr/bin/hdiutil detach -quiet "$mountpoint"
mountpoint=''
publish=$(mktemp "$PWD/dist/.dmg.XXXXXX")
cp "$stage/QuickLaunch.dmg" "$publish"
chmod 644 "$publish"
mv -f "$publish" dist/QuickLaunch.dmg
publish=''
printf 'Built and verified %s/dist/QuickLaunch.dmg\n' "$PWD"
