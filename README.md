# agent-dotfiles

Minimal configs for Ghostty, tmux, fish, and Neovim, built for working mostly
through AI agents. Maintained by agents; see [AGENTS.md](AGENTS.md).

## Install

```sh
git clone <this repo> ~/agent-dotfiles
~/agent-dotfiles/install.sh                 # personal machine
~/agent-dotfiles/install.sh ~/work-dotfiles # with per-machine overrides
```

`install.sh` backs up any existing real config directory before linking.

## Per-machine overrides

Keep machine-specific files in a separate directory that mirrors this repo's
layout, e.g. `~/work-dotfiles/nvim/local.lua`. `install.sh DIR` symlinks every
`local.*` file from `DIR` to the same path here. Those paths are gitignored.
See `nvim/local.example.lua` for the Neovim format.
