# agent-dotfiles

Minimal configs for Ghostty, AeroSpace, tmux, fish, and Neovim, plus macOS
settings and Claude Code skills, built for working mostly through AI agents. All
in the Tokyo Night theme.
Maintained by agents; see [AGENTS.md](AGENTS.md) for the conventions.

## Install

On a new Mac, install [Homebrew](https://brew.sh) and the Claude desktop app by
hand and sign in to the App Store (`brew bundle` installs Xcode and LINE from it), then
ask Claude Code to set up this repo. Check the dependencies first;
they're listed under "Setting up a machine" in [AGENTS.md](AGENTS.md).

```sh
git clone https://github.com/shunyaoshih/agent-dotfiles.git ~/agent-dotfiles
brew bundle --file ~/agent-dotfiles/Brewfile   # macOS only
~/agent-dotfiles/install.sh ~/local-dotfiles   # or omit the argument
nvim --headless "+Lazy! restore" +qa           # plugins at the pinned versions
```

`install.sh` symlinks `~/.config/{nvim,tmux,fish,ghostty,aerospace,git}`,
`~/.claude/CLAUDE.md` and each skill in `~/.claude/skills` to this repo and backs
up any real config it replaces.

On macOS, finish with these yourself, since they need a browser login or your
password:

```sh
gh auth login && gh auth setup-git             # git over HTTPS
echo /opt/homebrew/bin/fish | sudo tee -a /etc/shells
chsh -s /opt/homebrew/bin/fish                 # Ghostty and tmux use the login shell
sudo xcode-select -s /Applications/Xcode.app   # xcodebuild needs Xcode, not the command line tools
```

Then:

1. Run `~/agent-dotfiles/macos/defaults.sh` to apply the macOS settings. It asks
   for your password for the power setting and to confirm Chrome as the default
   browser.
2. Open Ghostty and AeroSpace and allow Accessibility access for each: Ghostty's
   `alt+space` global keybind needs it, and AeroSpace can't manage windows
   without it.
3. Open Xcode once to accept its license and install its components, then
   download the iOS simulator under Settings › Components.
4. Remove the desktop widgets a new Mac comes with: reveal the desktop,
   right-click each widget, and choose Remove Widget. The script only hides
   widgets while windows are open.
5. Log out and back in, so dark mode, the second language and the input source
   shortcuts (`ctrl+space`) take effect.

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
| `c` | `claude` |
| `t` | Attach to tmux session `main`, creating it if needed |
| `vinit`, `tinit`, `finit`, `ginit` | Edit the Neovim, tmux, fish, or Ghostty config |
| `st`, `sf`, `sg` | Reload the tmux, fish, or Ghostty config |

`ginit` and `sg` exist only on macOS, where Ghostty runs.

In AeroSpace, each main app has its own workspace:

| Keys | Does |
|---|---|
| `ctrl+alt+c`, `d`, `g`, `m`, `s`, `t` | Jump to Claude, Discord and Messenger, Chrome, messaging (LINE and Telegram), Steam, or Ghostty, opening them if needed |
| `ctrl+alt+shift+` the same letter | Send the current window to that workspace, where it splits the screen |
| `ctrl+alt+left`, `right` | Switch between windows on a workspace |
| `ctrl+alt+shift+left`, `right` | Swap their sides |
