#!/bin/sh
# Open a link from tmux copy mode. Called by copy-pipe with the OSC 8 hyperlink
# under the cursor as $1 (may be empty) and the selected text on stdin; the
# hyperlink wins. Text without a scheme (e.g. cl/123) gets http://.
#
# On macOS, opens the default browser. On the workstation, sends the URL to the
# Mac you SSH'd from through ~/.ssh/open-url.sock, an SSH RemoteForward to that
# Mac's macos/open-url.sh listener (see README). Without the socket, copies the
# URL to the local clipboard via OSC 52 instead.

url=$1
[ -n "$url" ] || url=$(tr -d '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
[ -n "$url" ] || exit 0
case $url in
*://*) ;;
*) url="http://$url" ;;
esac

sock=$HOME/.ssh/open-url.sock
if [ "$(uname)" = Darwin ]; then
	open "$url"
elif [ -S "$sock" ] && printf '%s\n' "$url" | perl -MIO::Socket::UNIX -e \
	'$s = IO::Socket::UNIX->new(Peer => shift) or exit 1; print $s scalar <STDIN>' "$sock"; then
	tmux display-message "Opened $url on the local machine"
else
	tmux set-buffer -w -- "$url"
	tmux display-message "Copied $url (no connection to the local machine's browser)"
fi
