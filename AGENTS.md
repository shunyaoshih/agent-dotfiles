# agent-dotfiles

Dotfiles for a user who develops mostly through AI agents and rarely edits text
by hand. Agents maintain this repo. Tools: Ghostty, tmux, fish, Neovim.

## Principles

- Minimal. Add config only when a default is unreasonable. Prefer deleting
  config over adding it.
- Default keybindings. Do not add keymaps that duplicate or shadow built-in ones.
- Ask the user before adding a plugin.
- Every file must work on both machines: the personal MacBook (macOS) and the
  work Linux workstation, reached over SSH from the MacBook. Versions differ
  between them; see "Setting up a machine".
- fish syntax must work in both 3.7 and 4.x (notably, `bind` key names changed
  in 4.0).
- Do not use APIs newer than Neovim 0.11 (e.g. `vim.pack`) until the
  workstation upgrades. nvim-treesitter is out for the same reason: its master
  branch doesn't support 0.12, and its main branch is a different API.
- Nothing work-specific goes in this repo (internal paths, hostnames, tools).
- One color theme everywhere: Tokyo Night, "night" variant. Neovim uses
  [folke/tokyonight.nvim](https://github.com/folke/tokyonight.nvim). For any
  other tool, start from that repo's
  [`extras/`](https://github.com/folke/tokyonight.nvim/tree/main/extras)
  directory, which has ready-made themes for tmux, fish, Ghostty and more
  (e.g. `extras/tmux/tokyonight_night.tmux`). If a tool has a built-in Tokyo
  Night theme, use it only if it matches those colors.

## Setting up a machine

When setting up a new machine, check these dependencies first and tell the user
about anything missing or too old. Don't install system packages without asking.

| Dependency | Minimum | MacBook | Workstation | Needed for |
|---|---|---|---|---|
| Neovim | 0.11 | 0.12 | 0.11.x | `nvim/` |
| git | any | ✓ | ✓ | lazy.nvim bootstraps and installs plugins with it |
| tmux | 3.5 | 3.5a | 3.6b | `tmux/` (`send-keys -K`, popups) |
| perl | 5 at `/usr/bin/perl` | ✓ | ✓ | `tmux/hop.pl` |
| fish | 3.7 | 3.7 | 4.x | `fish/` |
| fzf | 0.53 (`--highlight-line` in the theme; `fzf --fish` needs 0.48) | 0.55 | check | Ctrl-T / Ctrl-R / Alt-C in fish; skipped silently if missing, so a missing fzf won't show as an error |
| Ghostty | 1.3 | 1.3.1 | not used | `ghostty/`; 1.3 is needed for the AppleScript used by the `sg` alias |
| Hack Nerd Font Mono | | ✓ | not used | Ghostty `font-family` |

On macOS, `brew bundle --file Brewfile` installs all of these; keep the
Brewfile in sync with this table. Then run `./install.sh LOCAL_DIR` (see below)
and open a new shell. On macOS, also run `gh auth login` and `gh auth
setup-git` so git can push to GitHub over HTTPS. Update the version columns when a machine's versions
change.

## Per-machine config

Machine-specific settings live in a separate directory outside this repo that
mirrors its layout, and `./install.sh LOCAL_DIR` symlinks each `local.*` file
from it into place here. `local.*` is gitignored; `local.example.*` files are
tracked templates.

| Tool   | Local file       | How it's loaded                                        |
|--------|------------------|--------------------------------------------------------|
| Neovim | `nvim/local.lua` | `dofile`d by `init.lua` if present; returns lazy.nvim specs |
| tmux   | `tmux/local.conf` | `source-file -q` at the end of `tmux.conf`             |
| fish   | `fish/local.fish` | `source`d at the end of `config.fish` if present       |
| Ghostty | `ghostty/local.ghostty` | `config-file = ?local.ghostty` (optional include) |

Exception: git is only used on the MacBook, so `git/config` is fully tracked
and there is no `local.*` file. The untracked `~/.gitconfig` is read after it
and holds only what tools write (`git config --global`, `gh auth setup-git`).
Put shared settings in `git/config`, never in `~/.gitconfig`.

When adding a tool, give it a `local.*` hook that is skipped silently when the
file is absent, and add a row above.

## Layout

- `install.sh`: symlinks configs into `~/.config` and links local files.
- `Brewfile`: macOS dependencies for `brew bundle`.
- `git/config`: git config (MacBook only), linked as `~/.config/git`.
- `nvim/init.lua`: the whole Neovim config. `nvim/lazy-lock.json` pins plugins.
- `tmux/tmux.conf`: tmux config, linked as `~/.config/tmux`. `hop.pl` is a
  hop.nvim-style jump for copy mode (`s`). `session-picker.sh` is the fzf
  session picker behind `prefix s`/`X`/`$` (switch/kill/rename; custom order:
  "controller" first, "worker" last), falling back to `choose-tree` without
  fzf. When testing it, pass the user's `FZF_DEFAULT_OPTS` to the test server:
  the Tokyo Night fzf theme sets `--layout=reverse`, which changes which way
  Tab moves. `tokyonight_night.tmux` is a verbatim
  copy of the upstream extra; refresh it from upstream rather than editing it.
- `fish/config.fish`: env, PATH and aliases. `conf.d/tokyonight_night.fish`
  and `conf.d/tokyonight_night_fzf.fish` are verbatim upstream extras (the
  latter is `extras/fzf/tokyonight_night.sh`, whose `export` syntax fish also
  accepts); `functions/fish_prompt.fish` is the prompt.
  `fish/fish_variables` is fish's own state and is gitignored.
- `ghostty/config.ghostty`: Ghostty config (MacBook only). `themes/tokyonight_night`
  is a verbatim upstream extra. Validate with
  `/Applications/Ghostty.app/Contents/MacOS/ghostty +validate-config`; check the
  effective config with `+show-config`.

## Testing Neovim changes

Test without touching the live config by using a separate app name:

```sh
ln -sfn "$PWD/nvim" ~/.config/agent-nvim
NVIM_APPNAME=agent-nvim nvim --headless "+Lazy! sync" +qa
NVIM_APPNAME=agent-nvim nvim --headless +qa   # must print nothing
```

Check that the config also starts cleanly under Neovim 0.11.

## Testing tmux changes

Use a separate server (`tmux -L probe -f tmux/tmux.conf ...`) so the user's
sessions are untouched. Prompts, choosers and popups need an attached client:
attach one from a pty (e.g. Python's `pty.fork()` running `tmux -L probe
attach`), then drive key bindings with `tmux -L probe send-keys -K -c CLIENT
...`. Plain `send-keys` types into the pane and bypasses key bindings. Apply
changes to the live server with `tmux source-file ~/.config/tmux/tmux.conf`.
