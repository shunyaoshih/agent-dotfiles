# agent-dotfiles

Minimal configs for Ghostty, tmux, fish, and Neovim, built for working mostly
through AI agents. All in the Tokyo Night theme. Maintained by agents; see
[AGENTS.md](AGENTS.md) for the conventions.

## Install

Check the dependencies first; they're listed under "Setting up a machine" in
[AGENTS.md](AGENTS.md).

```sh
git clone https://github.com/shunyaoshih/agent-dotfiles.git ~/agent-dotfiles
brew bundle --file ~/agent-dotfiles/Brewfile   # macOS only
~/agent-dotfiles/install.sh ~/local-dotfiles   # or omit the argument
nvim --headless "+Lazy! restore" +qa           # plugins at the pinned versions
```

`install.sh` symlinks `~/.config/{nvim,tmux,fish,ghostty}` to this repo and
backs up any real config it replaces. Then open a new shell and restart tmux.

## Per-machine overrides

Keep machine-specific files in a separate directory outside this repo that
mirrors its layout, e.g. `~/local-dotfiles/fish/local.fish`. `install.sh DIR`
symlinks every `local.*` file from `DIR` to the same path here; those paths are
gitignored. Each tool has a template: `nvim/local.example.lua`,
`tmux/local.example.conf`, `fish/local.example.fish`, and
`ghostty/local.example.ghostty`.

## Shortcuts

| Command | Does |
|---|---|
| `v` | `nvim` |
| `t` | Attach to tmux session `0`, creating it if needed |
| `vinit`, `tinit`, `finit`, `ginit` | Edit the Neovim, tmux, fish, or Ghostty config |
| `st`, `sf`, `sg` | Reload the tmux, fish, or Ghostty config |

`ginit` and `sg` exist only on macOS, where Ghostty runs.
