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

# Trackpad: tap to click, so a two-finger tap is a right click, and drag with
# three fingers. Three-finger drag takes three-finger swipes, so swipes between
# spaces and to Mission Control use four fingers only, as System Settings does.
# The built-in and Bluetooth trackpads keep separate settings. These take
# effect at the next login.
for domain in com.apple.AppleMultitouchTrackpad com.apple.driver.AppleBluetoothMultitouch.trackpad; do
	defaults write "$domain" Clicking -bool true
	defaults write "$domain" TrackpadRightClick -bool true
	defaults write "$domain" TrackpadThreeFingerDrag -bool true
	defaults write "$domain" TrackpadThreeFingerHorizSwipeGesture -int 0
	defaults write "$domain" TrackpadThreeFingerVertSwipeGesture -int 0
done
defaults write -g com.apple.mouse.tapBehavior -int 1
defaults -currentHost write -g com.apple.mouse.tapBehavior -int 1

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

# Dark mode, and Traditional Chinese as the second language. These take effect
# at the next login.
defaults write -g AppleInterfaceStyle -string Dark
defaults write -g AppleLanguages -array en-US zh-Hant-US

# No gaps between tiled windows.
defaults write com.apple.WindowManager EnableTiledWindowMargins -bool false

# Open Finder windows in list view.
defaults write com.apple.finder FXPreferredViewStyle -string Nlsv

# Chrome as the default browser, which macOS asks to confirm unless it already
# is. Setting http changes https and HTML files with it.
swift - <<'EOF'
import AppKit
let done = DispatchSemaphore(value: 0)
let chrome = URL(fileURLWithPath: "/Applications/Google Chrome.app")
NSWorkspace.shared.setDefaultApplication(at: chrome, toOpenURLsWithScheme: "http") { error in
	if let error { print(error) }
	done.signal()
}
done.wait()
EOF

# Restart what reads these settings.
killall Dock Finder WindowManager

# On the power adapter, never sleep on its own, so long jobs keep running. The
# screen still turns off and locks, closing the lid still sleeps, and battery is
# unchanged. Last, because pmset needs root and asks for a password.
sudo pmset -c sleep 0
