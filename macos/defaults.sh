#!/bin/sh
# macOS system settings that differ from the defaults. Safe to re-run. See
# AGENTS.md.
set -eu

[ "$(uname)" = Darwin ] || exit 0

# Hide the Dock until the pointer reaches it, and show only open apps in it.
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock static-only -bool true

# Keep the wallpaper clean: no widgets, files or drives on it. Files stay in
# ~/Desktop, where Finder still shows them.
defaults write com.apple.WindowManager StandardHideWidgets -bool true
defaults write com.apple.WindowManager StageManagerHideWidgets -bool true
defaults write com.apple.finder CreateDesktop -bool false

# Chinese input, Traditional: Zhuyin and Pinyin. The input API applies them at
# once and ignores ones that are already on.
swift - <<'EOF'
import Carbon
for id in ["com.apple.inputmethod.TCIM.Zhuyin", "com.apple.inputmethod.TCIM.Pinyin"] {
	let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
	let sources = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource] ?? []
	sources.forEach { TISEnableInputSource($0) }
}
EOF

# Switch input sources with ctrl+space (previous) and ctrl+alt+space (next), as
# System Settings sets up when adding one. These should take effect at the next
# login.
for hotkey in "60 262144" "61 786432"; do
	set -- $hotkey
	defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add "$1" \
		"<dict><key>enabled</key><true/><key>value</key><dict><key>parameters</key><array><integer>32</integer><integer>49</integer><integer>$2</integer></array><key>type</key><string>standard</string></dict></dict>"
done

# Restart what reads these settings.
killall Dock Finder WindowManager

# On the power adapter, never sleep on its own, so long jobs keep running. The
# screen still turns off and locks, closing the lid still sleeps, and battery is
# unchanged. Last, because pmset needs root and asks for a password.
sudo pmset -c sleep 0
