#!/bin/bash
set -euo pipefail
scratch="$HOME/Library/Caches/local.vibeapps.quicklaunch"
mkdir -p "$scratch"
fixture=$(mktemp -d "$scratch/test-publish.XXXXXX")
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/project/macos" "$fixture/outside"
cp macos/build.sh "$fixture/project/macos/build.sh"
ln -s "$fixture/outside" "$fixture/project/dist"
if output=$(/bin/bash "$fixture/project/macos/build.sh" 2>&1); then
    echo 'Build accepted a symlinked dist directory' >&2
    exit 1
fi
[[ "$output" == *'Refusing a symlink at dist.'* ]] || { printf '%s\n' "$output" >&2; exit 1; }
[[ -z "$(/usr/bin/find "$fixture/outside" -mindepth 1 -print -quit)" ]]
echo 'Publishing refuses a symlinked dist directory.'
