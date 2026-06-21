local wezterm = require("wezterm")

local M = {}

-- os.getenv("OS") is "Windows_NT" on native Windows; guard against nil.
M.is_windows = ((os.getenv("OS") or ""):lower():find("windows")) ~= nil
M.is_macos = wezterm.target_triple:lower():find("darwin") ~= nil
M.is_linux = wezterm.target_triple:lower():find("linux") ~= nil

return M
