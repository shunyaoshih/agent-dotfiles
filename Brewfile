# macOS dependencies (see "Setting up a machine" in AGENTS.md).
# Install with: brew bundle --file ~/agent-dotfiles/Brewfile

tap "nikitabobko/tap" # AeroSpace isn't in Homebrew's own casks

brew "fish"
brew "fzf"
brew "git"
brew "gh" # git uses it to log in to GitHub (gh auth setup-git)
brew "mas" # installs the App Store apps below; it can't sign in, so do that first
brew "neovim"
brew "tmux"

cask "1password" # fills logins in native apps too (Universal Autofill)
cask "claude-code" # the `claude` CLI; the desktop app doesn't put one on PATH
cask "ghostty"
cask "google-chrome"
cask "google-drive" # Drive as a Finder folder
cask "nikitabobko/tap/aerospace"
cask "telegram"

mas "LINE", id: 539883307
mas "Xcode", id: 497799835 # not on Homebrew; Apple ships it only through the App Store
