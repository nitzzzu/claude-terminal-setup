local wezterm = require("wezterm")

-- ============================================================
--  USER SETTING
--  On Windows, route the default shell into WSL?
--    true  -> WSL / Hybrid (boots into WSL; LEADER+w opens a Windows pane)
--    false -> Native Windows (PowerShell)
--  Ignored on macOS / Linux.
local USE_WSL = true
local WSL_DISTRO = "Ubuntu"
-- Working directory for new tabs/panes. Leave "" to use the shell default
-- (Linux/WSL home, or Windows home). Set it to land new tabs in your project:
--   WSL / Hybrid : a Linux path, e.g. "/home/nitzu/dev"
--   Native Windows / macOS / Linux : a native path, e.g. "C:\\Users\\nitzu\\dev"
-- (onboard.py can fill this in with --dev-dir PATH)
local DEV_DIR = "/home/nitzu/dev"
-- ============================================================

-- Make the config/ modules importable.
package.path = wezterm.config_dir .. "/?.lua;" .. wezterm.config_dir .. "/?/init.lua;" .. package.path

local config = wezterm.config_builder()
local platform = require("config.platform")

-- Advertise advanced terminal features (undercurl / true color) for Neovim.
config.term = "wezterm"

require("config.appearance").apply(config, platform)
require("config.keys").apply(config, platform, { use_wsl = USE_WSL, wsl_distro = WSL_DISTRO, dev_dir = DEV_DIR })

-- shell / default domain
if platform.is_windows then
  if USE_WSL then
    -- Redefine the WSL domain so new tabs start in DEV_DIR (a Linux path)
    -- instead of inheriting WezTerm's Windows cwd (/mnt/c/Users/...).
    if DEV_DIR ~= "" then
      config.wsl_domains = {
        { name = "WSL:" .. WSL_DISTRO, distribution = WSL_DISTRO, default_cwd = DEV_DIR },
      }
    end
    config.default_domain = "WSL:" .. WSL_DISTRO
  else
    config.default_prog = { "pwsh.exe" } -- use "powershell.exe" if you lack pwsh
    if DEV_DIR ~= "" then config.default_cwd = DEV_DIR end
  end
else
  -- macOS / Linux: WezTerm runs the shell directly.
  if DEV_DIR ~= "" then config.default_cwd = DEV_DIR end
end

return config
