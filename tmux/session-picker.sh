#!/bin/sh
# Pick tmux sessions with fzf, then switch to, kill, or rename them. "main"
# comes first, then sessions containing "controller", then the rest, and those
# containing "worker" last; each group is sorted by name. Run from tmux.conf in
# a display-popup.
#
# Usage: session-picker.sh switch|kill|rename CLIENT
# kill accepts several sessions (mark them with Tab). Press . to label each row,
# then a label to pick that row at once (tmux turns . into _ in session names, so
# it is never part of a search). The labels are hop.pl's, minus the ".".

# The popup inherits the tmux server's environment, which lacks fzf's theme if
# the server was started outside fish. The theme file is POSIX sh too.
[ -n "$FZF_DEFAULT_OPTS" ] || . ~/.config/fish/conf.d/tokyonight_night_fzf.fish

action=$1
client=$2
multi=
[ "$action" = kill ] && multi=--multi

tmux list-sessions -F '#{session_name}' |
	awk '{ print ($0 == "main" ? 0 : /controller/ ? 1 : /worker/ ? 3 : 2) "\t" $0 }' |
	sort -t "$(printf '\t')" -k1,1n -k2 |
	cut -f2- |
	fzf $multi --bind '.:jump-accept' --jump-labels "ntesaroibwfmuc,l'yzkhd\"gjxqpv" --prompt "$action> " --preview 'tmux capture-pane -ep -t ={}:' |
	while IFS= read -r name; do
		case $action in
		switch) tmux switch-client -c "$client" -t "=$name" ;;
		kill) tmux kill-session -t "=$name" ;;
		rename) tmux command-prompt -b -t "$client" -I "$name" -p 'Rename session:' \
			"rename-session -t '=$name' -- '%%'" ;;
		esac
	done
