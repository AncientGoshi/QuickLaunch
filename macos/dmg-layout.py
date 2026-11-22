# Settings consumed by dmgbuild. Inputs are passed explicitly by dmg.sh.
format = "UDZO"
filesystem = "HFS+"
files = [defines["app"]]
symlinks = {"Applications": "/Applications"}
icon_locations = {"QuickLaunch.app": (200, 252), "Applications": (520, 252)}
background = defines["background"]
window_rect = ((140, 145), (720, 440))
default_view = "icon-view"
show_toolbar = False
show_status_bar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
arrange_by = None
icon_size = 110
text_size = 13
