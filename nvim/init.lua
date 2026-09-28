-- Neovim config for reading code and light editing. Must work on Neovim 0.11+.
-- See AGENTS.md for the conventions this file follows.

vim.g.mapleader = " "

-- Options. Only non-defaults belong here.
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.cursorline = true
vim.opt.scrolloff = 8
vim.opt.breakindent = true
vim.opt.list = true
vim.opt.listchars = "tab:»·,trail:·,nbsp:+"
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.splitright = true
vim.opt.splitbelow = true
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.undofile = true
vim.opt.swapfile = false
vim.opt.clipboard = "unnamedplus"

-- Over SSH, copy to the local machine's clipboard with OSC 52. Paste from the
-- unnamed register instead, because terminals often block OSC 52 reads.
if vim.env.SSH_TTY then
	local osc52 = require("vim.ui.clipboard.osc52")
	local function paste()
		return { vim.fn.split(vim.fn.getreg(""), "\n"), vim.fn.getregtype("") }
	end
	vim.g.clipboard = {
		name = "OSC 52",
		copy = { ["+"] = osc52.copy("+"), ["*"] = osc52.copy("*") },
		paste = { ["+"] = paste, ["*"] = paste },
	}
end

-- Autocmds.
local group = vim.api.nvim_create_augroup("user", { clear = true })

-- Reload files changed on disk, e.g. by an agent in another tmux pane.
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold" }, {
	group = group,
	callback = function()
		if vim.o.buftype ~= "nofile" then
			vim.cmd("checktime")
		end
	end,
})

-- Use treesitter highlighting when a parser is available (Neovim bundles c,
-- lua, markdown, vim, vimdoc and query); otherwise keep regex syntax.
vim.api.nvim_create_autocmd("FileType", {
	group = group,
	callback = function(event)
		pcall(vim.treesitter.start, event.buf)
	end,
})

-- Jump to the last position when reopening a file.
vim.api.nvim_create_autocmd("BufReadPost", {
	group = group,
	callback = function(event)
		local mark = vim.api.nvim_buf_get_mark(event.buf, '"')
		if mark[1] > 1 and mark[1] <= vim.api.nvim_buf_line_count(event.buf) then
			pcall(vim.api.nvim_win_set_cursor, 0, mark)
		end
	end,
})

vim.api.nvim_create_autocmd("TextYankPost", {
	group = group,
	callback = function()
		vim.hl.on_yank()
	end,
})

vim.api.nvim_create_autocmd("FileType", {
	group = group,
	pattern = { "checkhealth", "help", "qf" },
	callback = function(event)
		vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = event.buf, silent = true })
	end,
})

-- Machine-specific config. local.lua is untracked (usually a symlink into a
-- separate per-machine repo); it may set anything and returns extra lazy.nvim
-- specs, which are merged by plugin name. See local.example.lua.
local local_specs = {}
local local_file = vim.fn.stdpath("config") .. "/local.lua"
if vim.uv.fs_stat(local_file) then
	local_specs = dofile(local_file) or {}
end

-- Plugins.
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
	vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", "https://github.com/folke/lazy.nvim.git", lazypath })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
	spec = {
		{
			"folke/tokyonight.nvim",
			lazy = false,
			priority = 1000,
			config = function()
				vim.cmd.colorscheme("tokyonight-night")
			end,
		},
		local_specs,
	},
	rocks = { enabled = false },
})
