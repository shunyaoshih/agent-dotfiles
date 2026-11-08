# macOS dependencies (see "Setting up a machine" in AGENTS.md).
# Install with: brew bundle --file ~/agent-dotfiles/Brewfile

tap "hamed-elfayome/claude-usage" # Claude Usage Tracker isn't in Homebrew's own casks
tap "nikitabobko/tap" # AeroSpace isn't in Homebrew's own casks

brew "fish"
brew "fzf"
brew "git"
brew "gh" # git uses it to log in to GitHub (gh auth setup-git)
brew "mas" # installs the App Store apps below; it can't sign in, so do that first
brew "neovim"
brew "picotool" # flashes the keyboard firmware
brew "python@3.11" # for the qmk CLI's venv
brew "tmux"
brew "zstd" # Arm's compiler for the keyboard firmware needs it

cask "1password" # fills logins in native apps too (Universal Autofill)
cask "1password-cli" # `op`, for reading items from scripts
cask "claude-code" # the `claude` CLI; the desktop app doesn't put one on PATH
cask "discord"
cask "ghostty"
cask "hamed-elfayome/claude-usage/claude-usage-tracker" # Claude usage limits in the menu bar
cask "google-chrome"
cask "google-drive" # Drive as a Finder folder
cask "nikitabobko/tap/aerospace"
cask "steam"
cask "telegram"

mas "LINE", id: 539883307
mas "Xcode", id: 497799835 # not on Homebrew; Apple ships it only through the App Store
