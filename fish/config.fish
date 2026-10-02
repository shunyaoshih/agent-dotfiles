# fish config. Must work on fish 3.7+ and 4.x. See AGENTS.md.
# Colors come from conf.d/tokyonight_night.fish, a verbatim copy of
# tokyonight.nvim's extras/fish/tokyonight_night.fish.

set -g fish_greeting
set -gx EDITOR nvim
fish_add_path -g ~/.local/bin

# fzf key bindings: Ctrl-T inserts a file path, Ctrl-R searches history, Alt-C
# cds into a subdirectory.
if status is-interactive; and command -q fzf
    fzf --fish | source
end

alias v=nvim
alias t='tmux new-session -A -s main'
alias md=mkdir
alias lla='ls -a -l'
alias vinit='v ~/.config/nvim/init.lua'
alias tinit='v ~/.config/tmux/tmux.conf'
alias finit='v ~/.config/fish/config.fish'
alias sf='source ~/.config/fish/config.fish'
alias st='tmux source-file ~/.config/tmux/tmux.conf'

# Ghostty only runs on the MacBook; `sg` would also shadow a Linux command.
if test -d /Applications/Ghostty.app
    alias ginit='v ~/.config/ghostty/config.ghostty'
    alias sg='osascript -e \'tell application "Ghostty" to perform action "reload_config" on terminal 1\' >/dev/null'
end

# Machine-specific config (untracked). See local.example.fish.
set -l local_config (status dirname)/local.fish
test -f $local_config; and source $local_config
