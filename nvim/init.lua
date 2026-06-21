-- ~\AppData\Local\nvim\init.lua
-- IDE layout: file tree (left) + editor + Claude split (right), with LSP

vim.g.mapleader = " "
vim.g.maplocalleader = " "
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.termguicolors = true -- required for rose-pine / true color
vim.opt.signcolumn = "yes"   -- stable gutter for diagnostics

-- Ctrl+h/j/k/l window navigation is provided by smart-splits.nvim below — it
-- also crosses seamlessly into adjacent WezTerm panes. Here we only keep the
-- quick escape from terminal mode (e.g. the Claude split) to normal mode.
vim.keymap.set("t", "<C-q>", "<C-\\><C-n>", { desc = "Terminal -> normal mode" })

-- Quality-of-life (borrowed from vossenwout/pookie-dotfiles) -----------------

-- Briefly flash text on yank.
vim.api.nvim_create_autocmd("TextYankPost", {
  desc = "Highlight on yank",
  callback = function() vim.hl.on_yank({ timeout = 300 }) end,
})

-- Copy the current file's path to the system clipboard (handy for pasting to
-- Claude). NOTE: on WSL the "+" register needs a clipboard provider (win32yank,
-- or a clip.exe/win32yank shim); without one these copy to nvim's register only.
vim.keymap.set("n", "<leader>cp", function()
  local p = vim.fn.expand("%:p")
  vim.fn.setreg("+", p)
  vim.notify("Copied " .. p)
end, { desc = "Copy absolute file path" })
vim.keymap.set("n", "<leader>cr", function()
  local p = vim.fn.expand("%:.")
  vim.fn.setreg("+", p)
  vim.notify("Copied " .. p)
end, { desc = "Copy relative file path" })

-- Emacs-style motions on the : command line.
vim.keymap.set("c", "<C-a>", "<Home>")
vim.keymap.set("c", "<C-e>", "<End>")

-- Cleaner diagnostics: severity-sorted, source shown in the float, no underline.
vim.diagnostic.config({
  severity_sort = true,
  underline = false,
  float = { source = true },
})

-- WSL clipboard: route the "+"/"*" registers through the Windows clipboard so
-- `"+y` and the copy-path maps above reach Windows apps. clip.exe copies (same
-- tool tmux uses); it can't read back, so PowerShell's Get-Clipboard pastes
-- (stripping the CR that Windows appends). Guarded to WSL so native-Windows
-- setup A keeps nvim's built-in provider.
-- Tradeoff: each paste spawns powershell.exe (~slow). For snappier paste install
-- win32yank.exe and delete this block — Neovim then auto-detects win32yank.
if vim.fn.has("wsl") == 1 and vim.fn.executable("clip.exe") == 1 then
  vim.g.clipboard = {
    name = "WslClipboard",
    copy = {
      ["+"] = "clip.exe",
      ["*"] = "clip.exe",
    },
    paste = {
      ["+"] = 'powershell.exe -NoProfile -Command [Console]::Out.Write($(Get-Clipboard -Raw).tostring().replace("`r", ""))',
      ["*"] = 'powershell.exe -NoProfile -Command [Console]::Out.Write($(Get-Clipboard -Raw).tostring().replace("`r", ""))',
    },
    cache_enabled = 0,
  }
end

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

  -- Visual git UI (lazygit in a float): diffs, stage, commit, push/pull, branches.
  -- Needs the `lazygit` binary on PATH. snacks.nvim is already pulled in by
  -- claudecode.nvim; here we set it up explicitly so the Snacks global exists.
  {
    "folke/snacks.nvim",
    opts = { lazygit = {} },
    keys = {
      { "<leader>gg", function() Snacks.lazygit() end,          desc = "Lazygit (status)" },
      { "<leader>gl", function() Snacks.lazygit.log() end,      desc = "Lazygit (repo log)" },
      { "<leader>gf", function() Snacks.lazygit.log_file() end, desc = "Lazygit (file history)" },
    },
  },

  -- Ctrl+h/j/k/l moves between Neovim splits; Alt+h/j/k/l resizes. The WezTerm
  -- side (wezterm/config/plugins.lua) detects when nvim is focused and passes
  -- these keys through, so the same keys move WezTerm panes when nvim isn't.
  -- multiplexer_integration is off: WezTerm drives the crossing, not nvim, so
  -- nvim never shells out to `wezterm cli`.
  {
    "mrjones2014/smart-splits.nvim",
    lazy = false,
    config = function()
      local ss = require("smart-splits")
      ss.setup({ multiplexer_integration = false })
      vim.keymap.set("n", "<C-h>", ss.move_cursor_left,  { desc = "Go to left split/pane" })
      vim.keymap.set("n", "<C-j>", ss.move_cursor_down,  { desc = "Go to below split/pane" })
      vim.keymap.set("n", "<C-k>", ss.move_cursor_up,    { desc = "Go to above split/pane" })
      vim.keymap.set("n", "<C-l>", ss.move_cursor_right, { desc = "Go to right split/pane" })
      vim.keymap.set("n", "<A-h>", ss.resize_left)
      vim.keymap.set("n", "<A-j>", ss.resize_down)
      vim.keymap.set("n", "<A-k>", ss.resize_up)
      vim.keymap.set("n", "<A-l>", ss.resize_right)
      -- from a terminal split (e.g. claudecode.nvim): exit term mode, then move
      for key, dir in pairs({ h = "left", j = "down", k = "up", l = "right" }) do
        vim.keymap.set("t", "<C-" .. key .. ">",
          string.format("<C-\\><C-n><cmd>lua require('smart-splits').move_cursor_%s()<cr>", dir))
      end
    end,
  },

  -- Keybinding popup: shows available <leader> mappings as you type.
  { "folke/which-key.nvim", event = "VeryLazy", opts = {} },

  -- Pretty diagnostics / references / quickfix list.
  {
    "folke/trouble.nvim",
    cmd = "Trouble",
    keys = {
      { "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>",              desc = "Diagnostics (Trouble)" },
      { "<leader>xX", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>", desc = "Buffer diagnostics" },
      { "<leader>xs", "<cmd>Trouble symbols toggle<cr>",                  desc = "Symbols" },
      { "<leader>xq", "<cmd>Trouble qflist toggle<cr>",                   desc = "Quickfix list" },
    },
    opts = {},
  },

  -- Highlight + search TODO / FIXME / HACK comments.
  {
    "folke/todo-comments.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    event = "VeryLazy",
    opts = {},
  },

  -- Indentation guides.
  { "lukas-reineke/indent-blankline.nvim", main = "ibl", event = "VeryLazy", opts = {} },

  -- Auto-close brackets/quotes (integrates with blink.cmp automatically).
  { "windwp/nvim-autopairs", event = "InsertEnter", opts = {} },

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

  -- Edit the filesystem like a buffer; "-" jumps to the parent dir. Complements
  -- neo-tree (which handles browsing + `nvim .`): default_file_explorer = false
  -- so oil does NOT hijack netrw and fight neo-tree — it opens only via "-".
  {
    "stevearc/oil.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = { default_file_explorer = false },
    keys = {
      { "-", "<cmd>Oil<cr>", desc = "Open parent dir (Oil)" },
    },
  },

  -- Prettify markdown in-buffer (headings, code fences, tables, checkboxes).
  -- Needs the `markdown` treesitter parser (already in ensure_installed above).
  {
    "MeanderingProgrammer/render-markdown.nvim",
    ft = { "markdown" },
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
      "nvim-tree/nvim-web-devicons",
    },
    opts = {},
  },

  -- Claude Code (the IDE integration)
  {
    "coder/claudecode.nvim",
    dependencies = { "folke/snacks.nvim" },
    opts = {
      -- If nvim can't find claude, run `where.exe claude` in PowerShell and set:
      -- terminal_cmd = vim.fn.expand("~/.local/bin/claude.exe"),
      terminal = {
        -- Open Claude in a bottom split (50% tall) instead of a right vsplit.
        -- The native provider only does left/right vsplits, so use snacks, whose
        -- window position we override to "bottom".
        provider = "snacks",
        snacks_win_opts = { position = "bottom", height = 0.50 },
      },
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
