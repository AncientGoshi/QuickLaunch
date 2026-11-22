#!/bin/bash
set -euo pipefail
app="$PWD/dist/QuickLaunch.app"
plist="$app/Contents/Info.plist"
bin="$app/Contents/MacOS/QuickLaunch"
[[ -x "$bin" ]] || { echo 'QuickLaunch.app has not been built' >&2; exit 1; }
/usr/bin/plutil -lint "$plist"
[[ "$(/usr/bin/plutil -extract LSUIElement raw "$plist")" == true ]]
icon=$(/usr/bin/plutil -extract CFBundleIconFile raw "$plist")
[[ "$icon" == QuickLaunch.icns && -s "$app/Contents/Resources/$icon" ]]
/usr/bin/sips -g pixelWidth -g pixelHeight "$app/Contents/Resources/$icon" | /usr/bin/awk '/pixelWidth: 1024/ {w=1} /pixelHeight: 1024/ {h=1} END {exit !(w && h)}'
# The staged bundle is checked strictly before publication. A synced folder
# can reattach FinderInfo after publication; check the seal without that policy.
/usr/bin/codesign --verify "$app"
[[ "$(printf '%s\n' '/Applications' 'app:Finder' 'https://example.com/' | "$bin" --validate)" == '3 targets' ]]
[[ "$(printf '%s\n' '# no saved targets' | "$bin" --validate)" == '0 targets' ]]
if printf '%s\n' 'relative/path' | "$bin" --validate; then
    echo 'Unexpectedly accepted a relative path' >&2
    exit 1
fi
echo 'Bundle and Rust validation smoke checks passed.'
