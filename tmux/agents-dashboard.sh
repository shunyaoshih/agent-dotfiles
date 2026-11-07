#!/bin/sh
# The agent dashboard: an fzf list of every Claude Code pane on this server, with
# a live preview. One copy runs in the hidden session _agents, and its window is
# also linked into one visible session, its home: window 1 of "main" by default.
# prefix a always goes to the dashboard, wherever it is, and Esc goes back to the
# pane you came from. To give it another home, use the default prefix . in it.
#
# Usage: agents-dashboard.sh open CLIENT PANE_ID SESSION_ID   go to it (prefix a)
#        agents-dashboard.sh view                             fzf, in the _agents pane
#        agents-dashboard.sh cursor                           fzf's load handler
#        agents-dashboard.sh keep                             tmux's window-unlinked hook
#
# fzf can't follow a row across a reload, so the cursor is restored by pane id:
# F12 saves {1}, reloads, and the load handler moves back to that row with pos().
# That only needs doing when rows change, so tick only sends F12 when they have.
# The tick has to be separate from the reload: {1} is evaluated when an action
# fires, so a sleep inside the reload would save the row from before the wait.
# {1} is also kept out of the reload itself, because fzf skips any command that
# uses it when nothing matches the query, so the list would stop updating. F11
# and F12 are sent only to the dashboard's own pane.

self=$HOME/.config/tmux/agents-dashboard.sh
snapshot=$HOME/.config/tmux/agents-snapshot.pl
tab=$(printf '\t')

# Send the client viewing the dashboard to pane $1. It's the most recently active
# one if there are several. tmux only tracks that to the second, so another
# client's key or focus event in the same second can make this pick that client.
go_to_pane() {
	tmux set-option -gu @agents_return
	window=$(tmux display-message -p -t "$TMUX_PANE" '#{window_id}')
	client=$(tmux list-clients -f "#{==:#{window_id},$window}" -F '#{client_activity} #{client_name}' |
		sort -n | tail -n 1 | cut -d ' ' -f 2-)
	tmux switch-client -c "$client" -t "$1" 2>/dev/null ||
		tmux display-message -c "$client" "Pane $1 is gone"
}

# Refresh what's on screen every 2 seconds, while a client is viewing it. Stops
# when the pane is gone, so it can't outlive the dashboard.
tick() {
	while sleep 2; do
		viewers=$(tmux display-message -p -t "$TMUX_PANE" '#{window_active_clients}') || exit 0
		[ "$viewers" != 0 ] || continue
		# Any key cancels fzf's jump mode, so give the user time to press a label.
		if [ -e "$AGENTS_DIR/pause" ]; then
			rm -f "$AGENTS_DIR/pause"
			continue
		fi
		"$snapshot" >"$AGENTS_DIR/next"
		cmp -s "$AGENTS_DIR/next" "$AGENTS_DIR/shown" || tmux send-keys -t "$TMUX_PANE" F12
		tmux send-keys -t "$TMUX_PANE" F11
	done
}

case $1 in
open)
	client=$2 pane=$3 session=$4
	if tmux has-session -t =_agents 2>/dev/null; then
		running=1
	else
		tmux new-session -d -s _agents -n agents "$self view"
	fi
	window=$(tmux display-message -p -t '=_agents:=agents' '#{window_id}')
	# Already on it: keep the pane that Esc returns to.
	[ "$pane" != "$(tmux display-message -p -t "$window" '#{pane_id}')" ] || exit 0
	tmux set-option -g @agents_return "$pane"

	home=$(tmux list-windows -a -f "#{==:#{window_id},$window}" -F '#{session_id} #{session_name}' |
		awk '$2 != "_agents" { print $1; exit }')
	if [ -z "$home" ]; then
		if tmux has-session -t =main 2>/dev/null; then
			home=$(tmux display-message -p -t =main: '#{session_id}')
			tmux link-window -d -b -s "$window" -t '=main:^'
		else
			home=$session
			tmux link-window -d -s "$window" -t "$home:"
		fi
	fi
	tmux switch-client -c "$client" -t "$home:$window"
	# It doesn't refresh while nobody is looking, so catch up now.
	[ -z "$running" ] || tmux send-keys -t "$window" F12 F11
	;;
view)
	# The pane inherits the tmux server's environment, which lacks fzf's theme if
	# the server was started outside fish. The theme file is POSIX sh too.
	[ -n "$FZF_DEFAULT_OPTS" ] || . ~/.config/fish/conf.d/tokyonight_night_fzf.fish
	# fzf runs its commands with $SHELL. They use POSIX syntax and run often.
	SHELL=/bin/sh
	AGENTS_DIR=$(mktemp -d)
	export SHELL AGENTS_DIR FZF_DEFAULT_OPTS

	tick &
	ticker=$!
	trap 'kill "$ticker" 2>/dev/null; rm -rf "$AGENTS_DIR"' EXIT
	trap 'exit 0' HUP INT TERM

	# awk drops trailing blank lines, so "follow" shows the end of the pane's text.
	while :; do
		row=$("$snapshot" | tee "$AGENTS_DIR/shown" | fzf \
			--no-sort --delimiter="$tab" --with-nth=4 --prompt='agents> ' \
			--header-first \
			--preview 'tmux capture-pane -ep -t {1} | awk '\''NF { for (; n > 0; n--) print ""; print; next } { n++ }'\' \
			--preview-window='right,42%,wrap,follow' \
			--jump-labels "ntesaroibwfmuc,l'yzkhd\"gjxqpv" \
			--bind 'enter:accept-non-empty' \
			--bind '.:execute-silent(touch "$AGENTS_DIR/pause")+jump-accept' \
			--bind "f12:execute-silent(printf %s {1} >\"\$AGENTS_DIR/cursor\")+reload-sync(\"$snapshot\" | tee \"\$AGENTS_DIR/shown\")" \
			--bind "load:transform(\"$self\" cursor)" \
			--bind 'f11:refresh-preview+transform-preview-label(echo {3})' \
			--bind 'focus:transform-preview-label(echo {3})')
		case $? in
		0)
			pane=${row%%"$tab"*}
			printf %s "$pane" >"$AGENTS_DIR/cursor"
			go_to_pane "$pane"
			;;
		130) # Esc or Ctrl-C: back to where prefix a was pressed, if it's known.
			pane=$(tmux show-options -gqv @agents_return)
			[ -z "$pane" ] || go_to_pane "$pane"
			;;
		*) sleep 1 ;;
		esac
	done
	;;
cursor)
	# Rows as fzf has them: filtered by the query, in input order (--no-sort).
	rows=$AGENTS_DIR/shown
	id=$(cat "$AGENTS_DIR/cursor" 2>/dev/null)
	if [ -n "$FZF_QUERY" ]; then
		# --nth searches the same text as the view's --with-nth, but keeps field 1.
		position=$(fzf --filter="$FZF_QUERY" --no-sort --delimiter="$tab" --nth=4 <"$rows" |
			awk -F '\t' -v id="$id" '$1 == id { print NR; exit }')
	else
		position=$(awk -F '\t' -v id="$id" '$1 == id { print NR; exit }' "$rows")
	fi
	[ -z "$position" ] || printf 'pos(%s)+' "$position"
	awk -F '\t' '
		$2 == "working" { working++ }
		$2 == "background" { background++ }
		$2 == "idle" { idle++ }
		END {
			printf "change-header(\033[1;38;2;122;162;247m● %d working\033[0m  \033[1;38;2;187;154;247m◐ %d background\033[0m  \033[1;38;2;115;122;162m○ %d idle\033[0m\n", working, background, idle
			printf "\033[38;2;115;122;162menter jump · esc back · type to search · . jump labels\033[0m)"
		}' "$rows"
	;;
keep)
	# A session can't be empty, so moving the dashboard out of a session where it's
	# the only window would close that session. tmux has no hook before a move, so
	# whenever a window closes, give the dashboard's home a shell beside it.
	window=$(tmux display-message -p -t '=_agents:=agents' '#{window_id}' 2>/dev/null) || exit 0
	tmux list-windows -a -f "#{==:#{window_id},$window}" -F '#{session_id} #{session_windows} #{session_name}' |
		while read -r id count name; do
			[ "$name" = _agents ] || [ "$count" != 1 ] || tmux new-window -d -t "$id:"
		done
	;;
esac
