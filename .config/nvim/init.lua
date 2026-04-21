vim.g.mapleader = ' '

-- ui
vim.o.number = true
vim.o.relativenumber = true
vim.o.cursorline = true
vim.o.scrolloff = 10
vim.o.signcolumn = 'yes'
vim.o.winborder = 'rounded'
vim.opt.wrap = false
vim.o.confirm = true

-- indentation
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.smartindent = true

-- splits
vim.opt.splitbelow = true

-- lists / invisible chars
vim.o.list = true
vim.opt.listchars = { tab = '» ', trail = '·', nbsp = '␣' }

-- completion
vim.opt.completeopt = { "popup", "menuone", "noinsert" }

-- search
vim.o.ignorecase = true
vim.o.smartcase = true

-- clipboard
vim.api.nvim_create_autocmd('UIEnter', {
	callback = function()
		vim.o.clipboard = 'unnamedplus'
	end,
})

-- terminal mode
vim.keymap.set('t', '<Esc>', '<C-\\><C-n>')

-- highlight on yank
vim.api.nvim_create_autocmd('TextYankPost', {
	callback = function()
		vim.hl.on_yank()
	end,
})

vim.pack.add({
	{ src = "https://github.com/nvim-treesitter/nvim-treesitter", version = "master" },
	{ src = "https://github.com/rebelot/kanagawa.nvim" },
	{ src = "https://github.com/stevearc/oil.nvim" },
	{ src = "https://github.com/echasnovski/mini.nvim" },
	{ src = 'https://github.com/neovim/nvim-lspconfig' },
	{ src = "https://github.com/mason-org/mason.nvim" },
	{ src = "https://github.com/chomosuke/typst-preview.nvim" },
	{ src = "https://github.com/vague2k/vague.nvim" },
	{ src = "https://github.com/nvim-tree/nvim-web-devicons" },
	{ src = "https://github.com/tpope/vim-fugitive" },
	{ src = "https://github.com/mfussenegger/nvim-dap" },
	{ src = "https://github.com/rcarriga/nvim-dap-ui" },
	{ src = "https://github.com/sindrets/diffview.nvim" },
	{ src = "https://github.com/nvim-neotest/nvim-nio" },
	{ src = "https://github.com/chentoast/marks.nvim" }
})

require "marks".setup {
	builtin_marks = { "<", ">", "^" },
}

require "mason".setup()
require "mini.pick".setup()
require "vague".setup({ transparent = true })
require "mini.statusline".setup()
require "mini.bufremove".setup()
require("oil").setup({
	default_file_explorer = true,
	lsp_file_methods = {
		enabled = true,
		timeout_ms = 1000,
		autosave_changes = true,
	},
	columns = {
		"permissions",
		"icon",
	},
	float = {
		max_width = 0.7,
		max_height = 0.6,
		border = "rounded",
	},
	keymaps = {
		["-"] = { "actions.parent", mode = "n" },
	}
})

require 'nvim-treesitter.configs'.setup {
	ensure_installed = { "typst", "kotlin", "python", "go", "c", "lua", "vim", "vimdoc", "query", "markdown", "markdown_inline", "typescript" },
	sync_install = false,
	auto_install = true,
	ignore_install = { "javascript" },
	highlight = {
		enable = true,
		additional_vim_regex_highlighting = false,
	},
}

if not vim.env.TYPST_ROOT then
	vim.env.TYPST_ROOT = vim.fn.expand('~/uni')
end
require "typst-preview".setup {
	--invert_colors = 'always',
	port = 8000,
}

vim.api.nvim_create_autocmd('LspAttach', {
	group = vim.api.nvim_create_augroup('my.lsp', {}),
	callback = function(args)
		local client = assert(vim.lsp.get_client_by_id(args.data.client_id))
		if client:supports_method('textDocument/completion') then
			-- Optional: trigger autocompletion on EVERY keypress. May be slow!
			local chars = {}; for i = 32, 126 do table.insert(chars, string.char(i)) end
			client.server_capabilities.completionProvider.triggerCharacters = chars
			vim.lsp.completion.enable(true, client.id, args.buf, { autotrigger = true })
		end

		if client:supports_method('textDocument/formatting') then
			vim.api.nvim_create_autocmd('BufWritePre', {
				group = vim.api.nvim_create_augroup('my.lsp', { clear = false }),
				buffer = args.buf,
				callback = function()
					-- vim.lsp.buf.format({ bufnr = args.buf, id = client.id, timeout_ms = 1000 })
				end,
			})
		end
	end,
})

-- lsp
vim.lsp.enable({
	"lua_ls",
	"rust_analyzer",
	"clangd",
	"ruff",
	"gopls",
	"kotlin_lsp",
	"tinymist",
	"typstyle",
	"vtsls",
	"pyright"
})
--vim.cmd("colorscheme kanagawa")
vim.cmd("colorscheme vague")

local map = vim.keymap.set
map({ 'n', 'v' }, '<leader>o', ':update<CR> :source<CR>')
map("n", "<Esc>", "<cmd>nohlsearch<CR><Esc>", { silent = true })
--lsp and language
map('n', '<leader>lf', vim.lsp.buf.format)
map('n', 'gd', vim.lsp.buf.definition)
map('n', 'gD', vim.lsp.buf.declaration)
map('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostic quickfix list' })

-- navigation
map('n', '<C-h>', '<C-w><C-h>', { desc = 'Move focus to the left window' })
map('n', '<C-l>', '<C-w><C-l>', { desc = 'Move focus to the right window' })
map('n', '<C-j>', '<C-w><C-j>', { desc = 'Move focus to the lower window' })
map('n', '<C-k>', '<C-w><C-k>', { desc = 'Move focus to the upper window' })
map({ "n", "v" }, "k", "v:count == 0 ? 'gk' : 'k'", { expr = true })
map({ "n", "v" }, "j", "v:count == 0 ? 'gj' : 'j'", { expr = true })
map('n', '<leader>s', '<Cmd>e #<CR>')
map('n', '<leader>S', '<Cmd>bot sf #<CR>')
for i = 1, 8 do
	map({ "n", "t" }, "<Leader>" .. i, "<Cmd>tabnext " .. i .. "<CR>")
end

-- pick
map('n', '<leader>g', "<Cmd>Pick grep_live<CR>")
map('n', '<leader>f', "<Cmd>Pick files<CR>")
map('n', '<leader>r', "<Cmd>Pick buffers<CR>")
map('n', '<leader>h', "<Cmd>Pick help<CR>")

-- diff
map('n', '<leader>do', "<Cmd>DiffviewOpen<CR>")
map('n', '<leader>dc', "<Cmd>DiffviewClose<CR>")
map('n', '<leader>dm', "<Cmd>DiffviewClose<CR>")

-- oil
map('n', '<leader>e', "<Cmd>Oil<CR>")
map('n', '-', "<Cmd>Oil<CR>")


map({ "n", "v", "x" }, "<leader>n", ":norm ", { desc = "ENTER NORM COMMAND." })
