"""Check the Finder layout serialized into a mounted QuickLaunch image."""
import sys
from pathlib import Path
from ds_store import DSStore

def check(property_name, actual, expected):
    if actual != expected:
        raise SystemExit(f"Finder {property_name}: expected {expected!r}, found {actual!r}")


mount = Path(sys.argv[1])
with DSStore.open(str(mount / ".DS_Store"), "r") as layout:
    root = layout["."]
    check("window bounds", root["bwsp"]["WindowBounds"], "{{140, 145}, {720, 440}}")
    check("toolbar visibility", root["bwsp"]["ShowToolbar"], False)
    check("background type", root["icvp"]["backgroundType"], 2)
    check("icon size", root["icvp"]["iconSize"], 110)
    check("arrangement", root["icvp"]["arrangeBy"], "none")
    check("app position", layout["QuickLaunch.app"]["Iloc"], (200, 252))
    check("Applications position", layout["Applications"]["Iloc"], (520, 252))
check("background has content", (mount / ".background.tiff").stat().st_size > 0, True)
print("Finder layout verified: custom background, window bounds, icon positions.")
