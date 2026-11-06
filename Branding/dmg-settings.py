# dmgbuild settings for the Declic installer window:
# the app icon, large, on the left; the Applications folder on the right.
# Used by `./build.sh dmg` (pip install dmgbuild).
import os

app = defines["app"]  # noqa: F821 (provided by dmgbuild)
appname = os.path.basename(app)

format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = defines.get("icon")  # noqa: F821
background = defines.get("background")  # noqa: F821

window_rect = ((200, 140), (680, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
include_icon_view_settings = True

icon_size = 144
text_size = 14
label_pos = "bottom"
arrange_by = None
icon_locations = {
    appname: (190, 190),
    "Applications": (490, 190),
}
hide_extensions = [appname]
