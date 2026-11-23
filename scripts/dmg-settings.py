# dmgbuild settings for the LightSpot installer DMG.
# Used by scripts/make-dmg.sh. Icon positions must match Design/render-dmg-background.swift.
import os

app_path = defines["app"]
app_name = os.path.basename(app_path)

format = "UDZO"
filesystem = "HFS+"
files = [app_path]
symlinks = {"Applications": "/Applications"}

background = defines["background"]
window_rect = ((200, 140), (660, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

icon_size = 128
text_size = 13
arrange_by = None
icon_locations = {
    app_name: (170, 190),
    "Applications": (490, 190),
}
hide_extensions = [app_name]
