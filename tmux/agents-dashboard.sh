#!/bin/sh
# The agent dashboard: an fzf list of every Claude Code pane on this server, with
# a live preview. One copy runs in the hidden session _agents, and its window is
# also linked into one visible session, its home: window 1 of "main" by default.
# prefix a always goes to the dashboard, wherever it is, and Esc goes back to the
# pane you came from. To give it another home, use the default prefix . in it.
#
# The preview follows the end of the selected agent's conversation. To read back,
# Ctrl-U and Ctrl-D scroll it half a page, and [ and ] jump to the previous and
# next prompt you wrote, as in copy mode. Going past the end, or to another row,
# follows the end again.
#
# Usage: agents-dashboard.sh open CLIENT PANE_ID SESSION_ID   go to it (prefix a)
#        agents-dashboard.sh view                             fzf, in the _agents pane
#        agents-dashboard.sh cursor                           fzf's load handler
#        agents-dashboard.sh scroll KEY PANE_ID               fzf's preview scrolling
#                                                             handler
#        agents-dashboard.sh header|preview PANE_ID           what fzf shows
#        agents-dashboard.sh keep                             tmux's window-unlinked hook
#        agents-dashboard.sh status                           blocked and done counts
#                                                             for tmux's status-right
#
# fzf can't follow a row across a reload, so the cursor is restored by pane id:
# F12 saves {1}, reloads, and the load handler moves back to that row with pos().
# That only needs doing when rows change, so tick only sends F12 when they have.
# The tick has to be separate from the reload: {1} is evaluated when an action
# fires, so a sleep inside the reload would save the row from before the wait.
# {1} is also kept out of the reload itself, because fzf skips any command that
# uses it when nothing matches the query, so the list would stop updating.

self=$HOME/.config/tmux/agents-dashboard.sh
snapshot=$HOME/.config/tmux/agents-snapshot.pl
tab=$(printf '\t')
preview="\"$self\" preview {1}"
# Below the list and as wide as the window, like the agents' own panes, so
# their lines fit without wrapping. Claude Code fills every column, so the
# preview has only a top border, and fzf runs with --no-scrollbar.
preview_window='down,70%,wrap,follow,noinfo,border-top'
label="transform-preview-label(printf ' %s · %s ' {3} {2})"
dim=$(printf '\033[38;2;115;122;162m') off=$(printf '\033[0m')
keys="${dim}enter go · esc back · . jump · ctrl-u/d scroll · [ ] prompts${off}"
reload="\"$snapshot\" | tee \"\$AGENTS_DIR/shown\""

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

	# fzf's theme is darker than Ghostty's background, which would show as a border
	# around this full-window list, so it uses Ghostty's color instead.
	while :; do
		row=$("$snapshot" | tee "$AGENTS_DIR/shown" | fzf \
			--color=bg:#1a1b26,gutter:#1a1b26 \
			--no-sort --delimiter="$tab" --with-nth=4 --prompt='agents> ' \
			--header-first --no-separator --no-scrollbar --footer="$keys" \
			--preview "$preview" \
			--preview-window="$preview_window" \
			--jump-labels "ntesaroibwfmuc,l'yzkhd\"gjxqpv" \
			--bind enter:accept-non-empty \
			--bind '.:execute-silent(touch "$AGENTS_DIR/pause")+jump-accept' \
			--bind "f12:execute-silent(printf %s {1} >\"\$AGENTS_DIR/cursor\")+reload-sync($reload)" \
			--bind "load:transform(\"$self\" cursor)" \
			--bind "f11:refresh-preview+$label" \
			--bind "ctrl-u:transform(\"$self\" scroll up {1})" \
			--bind "ctrl-d:transform(\"$self\" scroll down {1})" \
			--bind "[:transform(\"$self\" scroll previous {1})" \
			--bind "]:transform(\"$self\" scroll next {1})" \
			--bind "focus:$label+transform(\"$self\" scroll row {1})")
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
scroll)
	# fzf doesn't say how far the preview is scrolled, so while you read, the line
	# at its top is kept in the file scroll, as PANE_ID LINE. No file, or another
	# pane's, means the preview is following the end.
	read -r pane top 2>/dev/null <"$AGENTS_DIR/scroll"
	[ "$pane" = "$3" ] || top=
	if [ "$2" = row ]; then
		[ -n "$pane" ] && [ -z "$top" ] || exit 0
		top=end
	else
		# Copy mode starts at the end, so [ finds the last prompt even if it's on
		# screen. Half a page, like copy mode's Ctrl-U and Ctrl-D.
		top=$("$snapshot" prompts "$3" 2>/dev/null | awk -v key="$2" -v top="$top" -v height="$FZF_PREVIEW_LINES" '
			NR == 1 {
				end = $1 - height + 1
				if (end < 1) end = 1
				from = top == "" ? $1 + 1 : top
				if (top == "") top = end
				next
			}
			$1 < from { before = $1 }
			$1 > top && after == "" { after = $1 }
			END {
				if (NR == 0) exit
				if (key == "up") top -= int(height / 2)
				else if (key == "down") top += int(height / 2)
				else if (key == "previous") top = before == "" ? 1 : before
				else top = after == "" ? end : after
				print (top < 1 ? 1 : top >= end ? "end" : top)
			}')
	fi
	case $top in
	'') ;;
	end)
		rm -f "$AGENTS_DIR/scroll"
		echo "change-preview-window($preview_window)+preview-bottom"
		;;
	*)
		echo "$3 $top" >"$AGENTS_DIR/scroll"
		echo "change-preview-window(nofollow,+$top)"
		;;
	esac
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
	echo "transform-header(\"$self\" header)"
	;;
header)
	# Every state, even with no agents in it, in the rows' order.
	awk -F '\t' '
		{ count[$2]++ }
		END {
			split("blocked done working background idle", states, " ")
			split("⚠ ◆ ● ◐ ○", marks, " ")
			split("247;118;142 115;218;202 122;162;247 187;154;247 115;122;162", colors, " ")
			for (i = 1; i <= 5; i++)
				printf "%s\033[38;2;%sm%s %d %s\033[0m", (i > 1 ? "   " : ""), colors[i], marks[i], count[states[i]], states[i]
			print ""
		}' "$AGENTS_DIR/shown"
	;;
preview)
	# Without trailing blank lines, so "follow" shows the end of the pane's text.
	"$snapshot" transcript "$2"
	;;
status)
	# Empty when nothing is blocked or done, so the status line only changes when
	# an agent needs you.
	"$snapshot" | awk -F '\t' '
		{ count[$2]++ }
		END {
			if (count["blocked"]) printf "#[fg=#f7768e]⚠ %d ", count["blocked"]
			if (count["done"]) printf "#[fg=#73daca]◆ %d ", count["done"]
		}'
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
