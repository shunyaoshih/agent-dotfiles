#!/bin/sh
# Symlink configs into place. Safe to re-run.
#
# Usage: ./install.sh [LOCAL_DIR]
#   LOCAL_DIR mirrors this repo's layout. Each local.* file in it is symlinked
#   to the same relative path in this repo, e.g. LOCAL_DIR/nvim/local.lua ->
#   nvim/local.lua.
set -eu

repo=$(cd "$(dirname "$0")" && pwd)

# retire PATH: remove PATH if it is a symlink, back it up if it is real.
retire() {
	if [ -L "$1" ]; then
		rm "$1"
	elif [ -e "$1" ]; then
		backup="$1.bak.$(date +%Y%m%d%H%M%S)"
		mv "$1" "$backup"
		echo "backed up $1 to $backup"
	fi
}

# link SRC DEST: point DEST at SRC.
link() {
	retire "$2"
	mkdir -p "$(dirname "$2")"
	ln -s "$1" "$2"
	echo "$2 -> $1"
}

link "$repo/nvim" "$HOME/.config/nvim"
link "$repo/tmux" "$HOME/.config/tmux"
link "$repo/fish" "$HOME/.config/fish"
link "$repo/ghostty" "$HOME/.config/ghostty"
link "$repo/git" "$HOME/.config/git"
# These are loaded after (and override) the ~/.config versions.
retire "$HOME/.tmux.conf"
retire "$HOME/Library/Application Support/com.mitchellh.ghostty/config"
retire "$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty"

if [ $# -gt 0 ]; then
	local_dir=$(cd "$1" && pwd)
	find "$local_dir" -type f -name 'local.*' ! -path '*/.git/*' | while read -r f; do
		link "$f" "$repo/${f#"$local_dir"/}"
	done
fi
