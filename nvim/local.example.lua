-- Template for nvim/local.lua (untracked, per machine). Top-level code runs
-- before plugins load; put plugin-dependent setup in a spec's `config`.

vim.opt.colorcolumn = "100"

-- Return lazy.nvim specs. A spec for a plugin that init.lua already declares
-- is merged into it, so this can also disable or reconfigure that plugin.
return {
	-- { "folke/tokyonight.nvim", enabled = false },
	-- { "wakatime/vim-wakatime", event = "VeryLazy" },
}
