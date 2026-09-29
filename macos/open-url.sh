#!/bin/sh
# Opens an http(s) URL in the default browser. launchd runs this once per
# connection to ~/.local/state/agent-dotfiles/open-url.sock (see install.sh),
# with the connection as stdin. The workstation reaches that socket through an
# SSH RemoteForward, so tmux's copy-mode O there can open links on this Mac.

IFS= read -r url || exit 0
case $url in
*[[:space:][:cntrl:]]*) exit 1 ;;
http://*|https://*) open "$url" ;;
esac
