local wezterm = require("wezterm")

-- ============================================================
--  USER SETTING
--  On Windows, route the default shell into WSL?
--    true  -> WSL / Hybrid (boots into WSL; LEADER+w opens a Windows pane)
--    false -> Native Windows (PowerShell)
--  Ignored on macOS / Linux.
local USE_WSL = true
local WSL_DISTRO = "Ubuntu"
-- ============================================================

-- Make the config/ modules importable.
package.path = wezterm.config_dir .. "/?.lua;" .. wezterm.config_dir .. "/?/init.lua;" .. package.path

local config = wezterm.config_builder()
local platform = require("config.platform")

-- Advertise advanced terminal features (undercurl / true color) for Neovim.
config.term = "wezterm"

require("config.appearance").apply(config, platform)
require("config.keys").apply(config, platform, { use_wsl = USE_WSL, wsl_distro = WSL_DISTRO })

-- shell / default domain
if platform.is_windows then
  if USE_WSL then
    config.default_domain = "WSL:" .. WSL_DISTRO
  else
    config.default_prog = { "pwsh.exe" } -- use "powershell.exe" if you lack pwsh
  end
end

return config
