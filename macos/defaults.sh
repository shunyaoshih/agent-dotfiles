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

# Restart what reads these settings.
killall Dock Finder WindowManager
