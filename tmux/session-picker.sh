#!/bin/sh
# Pick a tmux session with fzf and switch to it. Sessions containing
# "controller" come first and those containing "worker" last; each group is
# sorted by name. Run from tmux.conf in a display-popup.

tmux list-sessions -F '#{session_name}' |
	awk '{ print (/controller/ ? 0 : /worker/ ? 2 : 1) "\t" $0 }' |
	sort -t "$(printf '\t')" -k1,1n -k2 |
	cut -f2- |
	fzf --prompt 'session> ' --preview 'tmux capture-pane -ep -t ={}:' |
	{ IFS= read -r name && tmux switch-client -t "=$name"; }
