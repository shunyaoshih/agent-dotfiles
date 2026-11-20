#!/bin/sh
# Sets the focused window's width to a fraction of its monitor's width, e.g.
# `resize-fraction.sh 1 3` for a third. AeroSpace's resize only takes pixels and
# doesn't report monitor sizes, so the width comes from AppKit.
screen=$(aerospace list-windows --focused --format '%{monitor-appkit-nsscreen-screens-id}') || exit
width=$(osascript -l JavaScript -e "ObjC.import('AppKit'); \$.NSScreen.screens.objectAtIndex($screen - 1).visibleFrame.size.width")
aerospace resize width $((${width%.*} * $1 / $2))
