-- ~\AppData\Local\nvim\init.lua
-- IDE layout: file tree (left) + editor + Claude split (right), with LSP

vim.g.mapleader = " "
vim.g.maplocalleader = " "
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.termguicolors = true -- required for rose-pine / true color
vim.opt.signcolumn = "yes"   -- stable gutter for diagnostics

-- bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  -- Colorscheme (matches your WezTerm rose-pine-moon)
  {
    "rose-pine/neovim",
    name = "rose-pine",
    priority = 1000,
    config = function()
      require("rose-pine").setup({ variant = "moon" })
      vim.cmd.colorscheme("rose-pine-moon")
    end,
  },

  -- File tree on the left
  {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-tree/nvim-web-devicons",
      "MunifTanjim/nui.nvim",
    },
    keys = {
      { "<leader>e", "<cmd>Neotree toggle<cr>", desc = "Toggle file tree" },
    },
    opts = {
      close_if_last_window = true,
      window = { position = "left", width = 32 },
      filesystem = {
        follow_current_file = { enabled = true },
        hijack_netrw_behavior = "open_current", -- `nvim .` opens the tree
      },
    },
  },

  -- Statusline
  {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      options = { theme = "rose-pine", globalstatus = true },
    },
  },

  -- Syntax highlighting (treesitter compiles parsers with zig on Windows)
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "master", -- the classic configs.setup API; `main` is an incompatible rewrite
    build = ":TSUpdate",
    config = function()
      -- Force zig as the parser compiler: the most reliable option on Windows.
      -- Install it once with: winget install zig.zig
      require("nvim-treesitter.install").compilers = { "zig", "clang", "gcc" }
      require("nvim-treesitter.configs").setup({
        ensure_installed = { "lua", "vim", "vimdoc", "bash", "python", "javascript", "json", "markdown" },
        highlight = { enable = true },
        auto_install = true,
        sync_install = false,
      })
    end,
  },

  -- Completion engine (prebuilt binary; no Rust/cargo needed)
  {
    "saghen/blink.cmp",
    version = "1.*", -- pulls a prebuilt fuzzy-matcher release
    opts = {
      keymap = { preset = "default" }, -- <C-y> to accept, <C-n>/<C-p> to cycle
      appearance = { nerd_font_variant = "mono" },
      sources = { default = { "lsp", "path", "snippets", "buffer" } },
      fuzzy = { implementation = "prefer_rust_with_warning" },
    },
    opts_extend = { "sources.default" },
  },

  -- LSP (mason installs servers, lspconfig + Neovim 0.11 enables them)
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      { "williamboman/mason.nvim", opts = {} },
      "williamboman/mason-lspconfig.nvim",
      "saghen/blink.cmp",
    },
    config = function()
      -- merge blink's completion capabilities into every server
      local capabilities = require("blink.cmp").get_lsp_capabilities()
      vim.lsp.config("*", { capabilities = capabilities })

      -- lua_ls works with zero extra runtimes. Add more via :Mason
      -- (note: pyright / ts_ls and similar need Node.js installed).
      require("mason-lspconfig").setup({
        ensure_installed = { "lua_ls" },
      })

      -- keymaps active once any LSP attaches to a buffer
      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(ev)
          local opts = { buffer = ev.buf, silent = true }
          vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
          vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)
          vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
          vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
          vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)
          vim.keymap.set("n", "[d", function() vim.diagnostic.jump({ count = -1, float = true }) end, opts)
          vim.keymap.set("n", "]d", function() vim.diagnostic.jump({ count = 1, float = true }) end, opts)
        end,
      })
    end,
  },

  -- Format on save
  {
    "stevearc/conform.nvim",
    event = "BufWritePre",
    opts = {
      formatters_by_ft = {
        lua = { "stylua" },
        python = { "ruff_format" },
        javascript = { "prettierd", "prettier", stop_after_first = true },
      },
      -- Falls back to LSP formatting if the formatter above isn't installed.
      -- Install formatters via :Mason (stylua, ruff, prettierd).
      format_on_save = { timeout_ms = 1000, lsp_format = "fallback" },
    },
  },

  -- Git signs in the gutter
  { "lewis6991/gitsigns.nvim", opts = {} },

  -- Fuzzy finder (needs ripgrep on PATH for live_grep / find_files)
  {
    "nvim-telescope/telescope.nvim",
    branch = "0.1.x",
    dependencies = { "nvim-lua/plenary.nvim" },
    keys = {
      { "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "Find files" },
      { "<leader>fg", "<cmd>Telescope live_grep<cr>",  desc = "Live grep" },
      { "<leader>fb", "<cmd>Telescope buffers<cr>",    desc = "Buffers" },
      { "<leader>fh", "<cmd>Telescope help_tags<cr>",  desc = "Help tags" },
    },
  },

  -- Claude Code (the IDE integration)
  {
    "coder/claudecode.nvim",
    dependencies = { "folke/snacks.nvim" },
    opts = {
      -- If nvim can't find claude, run `where.exe claude` in PowerShell and set:
      -- terminal_cmd = vim.fn.expand("~/.local/bin/claude.exe"),
    },
    config = true,
    keys = {
      { "<leader>ac", "<cmd>ClaudeCode<cr>",           desc = "Toggle Claude" },
      { "<leader>af", "<cmd>ClaudeCodeFocus<cr>",      desc = "Focus Claude" },
      { "<leader>as", "<cmd>ClaudeCodeSend<cr>",       mode = "v", desc = "Send selection" },
      { "<leader>ab", "<cmd>ClaudeCodeAdd %<cr>",      desc = "Add current buffer" },
      { "<leader>aa", "<cmd>ClaudeCodeDiffAccept<cr>", desc = "Accept diff" },
      { "<leader>ad", "<cmd>ClaudeCodeDiffDeny<cr>",   desc = "Deny diff" },
      {
        "<leader>as",
        "<cmd>ClaudeCodeTreeAdd<cr>",
        desc = "Add file to Claude",
        ft = { "neo-tree", "NvimTree", "oil", "minifiles", "netrw" },
      },
    },
  },
})
