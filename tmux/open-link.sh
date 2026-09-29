#!/bin/sh
# Open a link from tmux copy mode. Called by copy-pipe with the OSC 8 hyperlink
# under the cursor as $1 (may be empty) and the selected text on stdin; the
# hyperlink wins. Text without a scheme (e.g. cl/123) gets http://.
#
# On macOS, opens the default browser. Elsewhere (the workstation, reached over
# SSH with no browser), copies the URL to the local clipboard via OSC 52.

url=$1
[ -n "$url" ] || url=$(tr -d '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
[ -n "$url" ] || exit 0
case $url in
*://*) ;;
*) url="http://$url" ;;
esac

if [ "$(uname)" = Darwin ]; then
	open "$url"
else
	tmux set-buffer -w -- "$url"
	tmux display-message "Copied $url (no browser here)"
fi
