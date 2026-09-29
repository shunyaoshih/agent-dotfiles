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
gh auth login && gh auth setup-git             # macOS only: git over HTTPS
```

`install.sh` symlinks `~/.config/{nvim,tmux,fish,ghostty,git}` to this repo and
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

## Opening workstation links on your Mac

In tmux copy mode, `O` opens the selected link. On a Mac it opens the browser
directly. On a remote machine it sends the URL back to the Mac you SSH'd from,
which needs one line in that Mac's `~/.ssh/config` (after running `install.sh`
there):

```
Host <workstation>
    RemoteForward /home/<remote-user>/.ssh/open-url.sock %d/.local/state/agent-dotfiles/open-url.sock
```

Without it, `O` copies the URL to your clipboard instead. If SSH warns
"remote port forwarding failed", a stale socket from an earlier session is in
the way: run `rm ~/.ssh/open-url.sock` on the workstation and reconnect. Only the
first of several simultaneous SSH sessions gets the forward.
