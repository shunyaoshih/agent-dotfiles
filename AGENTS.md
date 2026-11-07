# agent-dotfiles

Dotfiles for a user who develops mostly through AI agents and rarely edits text
by hand. Agents maintain this repo. Tools: Ghostty, AeroSpace, tmux, fish, Neovim.

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
- Keep fish's non-interactive startup fast: put slow or interactive-only setup
  (e.g. conda, key bindings) inside `status is-interactive`. tmux runs popups and
  `run-shell` commands through `fish -c`, so their latency is fish's startup.
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
| tmux | 3.5 | 3.8 | 3.6b | `tmux/` (`send-keys -K`, popups) |
| perl | 5 at `/usr/bin/perl` | ✓ | ✓ | `tmux/hop.pl`; `tmux/agents-snapshot.pl` (MacBook only, needs core JSON::PP) |
| fish | 3.7 | 4.9 | 4.x | `fish/` |
| fzf | 0.53 (`--highlight-line` in the theme; `fzf --fish` needs 0.48) | 0.74 | check | Ctrl-T / Ctrl-R / Alt-C in fish and the tmux agent dashboard; skipped silently if missing, so a missing fzf won't show as an error |
| Ghostty | 1.3 | 1.4 | not used | `ghostty/`; 1.3 is needed for the AppleScript used by the `sg` alias |
| AeroSpace | 0.21 | 0.21 | not used | `aerospace/`; comes from the developer's own Homebrew tap |
| Chrome, Telegram | any | ✓ | not used | their AeroSpace workspaces |
| Claude Code | any | ✓ | check | the `c` alias, `claude/skills/` |

On macOS, `brew bundle --file Brewfile` installs all of these; keep the
Brewfile in sync with this table. Then run `./install.sh LOCAL_DIR` (see below)
and open a new shell. Update the version columns when a machine's versions
change.

A new Mac starts with only Homebrew and the Claude desktop app, which doesn't
put `claude` on PATH. Besides the README's install commands:

- Ask the user to run the README's last commands themselves: `gh auth login`
  needs their browser, and adding fish to `/etc/shells` and `chsh` need their
  password. Nothing else makes fish the shell, since Ghostty and tmux both start
  the login shell. Run `gh auth setup-git` once they've logged in.
- Ask the user to run `macos/defaults.sh`, which changes system settings.
- Ask the user to open Ghostty, approve the first launch, and allow Accessibility
  access, which the `alt+space` global keybind needs.
- Ask the user to open AeroSpace and allow Accessibility access, without which it
  can't manage windows. Then check its config with `aerospace reload-config
  --dry-run --no-gui`, which only works while it's running.
- Ask the user to install LINE from the App Store, since it isn't on Homebrew.
- Ask the user to remove the default desktop widgets by hand. `defaults.sh` hides
  widgets while windows are open, but revealing the desktop still shows them,
  and their storage isn't a stable file to script.

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
`install.sh` creates it, because git otherwise sends those writes to the tracked
file. Put shared settings in `git/config`, never in `~/.gitconfig`. AeroSpace has
no `local.*` file either: it's MacBook only, and its config has no include.

When adding a tool, give it a `local.*` hook that is skipped silently when the
file is absent, and add a row above.

## Layout

- `install.sh`: symlinks configs into `~/.config`, skills into
  `~/.claude/skills`, and links local files.
- `Brewfile`: macOS dependencies for `brew bundle`.
- `macos/defaults.sh`: macOS system settings that differ from the defaults
  (MacBook only, so there is no `local.*` file), one commented setting at a time.
  The user runs it, since it asks for their password for `pmset`; `install.sh`
  doesn't, so re-linking configs never changes system settings. To find a setting's key, diff `defaults read` from before and
  after the user changes it by hand. Settings that can't be scripted, such as
  privacy permissions, go in the README's install steps. The menu bar stays
  visible because hiding it on a notched display frees only about 5 points for
  windows: macOS still leaves the notch's strip out of `visibleFrame`, and a
  window manager can't place windows there (AeroSpace with a negative gap didn't;
  Rectangle's source says the same).
- `git/config`: git config (MacBook only), linked as `~/.config/git`.
- `nvim/init.lua`: the whole Neovim config. `nvim/lazy-lock.json` pins plugins.
- `tmux/tmux.conf`: tmux config, linked as `~/.config/tmux`. `hop.pl` is a
  hop.nvim-style jump for copy mode (`s`). `session-picker.sh` is the fzf
  session picker behind `prefix s`/`X`/`$` (switch/kill/rename; custom order:
  "main", then "controller", "worker" last), falling back to `choose-tree` without
  fzf. When testing the picker, pass the user's `FZF_DEFAULT_OPTS` to the test
  server: the Tokyo Night fzf theme sets `--layout=reverse`, which changes which
  way Tab moves. `agents-dashboard.sh` is the agent dashboard behind `prefix a`
  (MacBook only in practice, because Claude Code isn't used on the workstation):
  one fzf copy in the hidden session `_agents`, also linked into one visible
  session, window 1 of "main" by default. `agents-snapshot.pl` prints its rows and is the only part that
  knows where agent state comes from; it joins `tmux list-panes` to
  `~/.claude/sessions/*.json` on the %pane id and must never open the `.key` files
  there. `tokyonight_night.tmux` is a verbatim copy of the upstream extra; refresh
  it from upstream rather than editing it.
- `fish/config.fish`: env, PATH and aliases. `conf.d/tokyonight_night.fish`
  and `conf.d/tokyonight_night_fzf.fish` are verbatim upstream extras (the
  latter is `extras/fzf/tokyonight_night.sh`, whose `export` syntax fish also
  accepts); `functions/fish_prompt.fish` is the prompt.
  `fish/fish_variables` is fish's own state and is gitignored.
- `ghostty/config.ghostty`: Ghostty config (MacBook only). `themes/tokyonight_night`
  is a verbatim upstream extra. Validate with
  `/Applications/Ghostty.app/Contents/MacOS/ghostty +validate-config`; check the
  effective config with `+show-config`.
- `aerospace/aerospace.toml`: AeroSpace config (MacBook only), linked as
  `~/.config/aerospace`. Each main app gets a workspace, and LINE and Telegram
  share one, reached with `ctrl+alt+letter`, because AeroSpace's default
  `alt+letter` keys would take over fish's Alt bindings in Ghostty. Other apps
  float, through a catch-all rule that needs an explicit `if = 'true'`. Apply
  changes with `aerospace reload-config`. Test a binding without pressing keys
  using `aerospace trigger-binding --mode main KEYS`.
- `claude/skills/`: Claude Code skills, each linked into `~/.claude/skills` on
  its own (that directory also holds skills Claude Code syncs from claude.ai).
  `organize-iphone` arranges the iPhone home screen over USB (MacBook only). Its
  venv, app categories and layout backups are personal and live in
  `~/.local/share/organize-iphone`, never in this repo.

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
...`. Plain `send-keys` types into the pane and bypasses key bindings; use it for
keys meant for the program, because `-K` garbles unbound keys such as `Down`
(seen on 3.5a). `send-keys -K` can block until a binding's popup closes (seen on
3.8), so for popups write the keys to the client's pty instead.
`display-message -c CLIENT` without `-t` doesn't report that client's session; use
`list-clients -F`. To test the agent dashboard with fixtures, point the test
server's `CLAUDE_CONFIG_DIR` at a directory with a `sessions/` folder. Apply
changes to the live server with `tmux source-file ~/.config/tmux/tmux.conf`.
