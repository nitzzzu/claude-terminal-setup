local wezterm = require("wezterm")

local M = {}

-- josean.com's "coolnight" palette. To use it instead of the named
-- color_scheme below, comment out `config.color_scheme` and uncomment
-- `config.colors = coolnight`.
local coolnight = {
  foreground = "#CBE0F0",
  background = "#011423",
  cursor_bg = "#47FF9C",
  cursor_border = "#47FF9C",
  cursor_fg = "#011423",
  selection_bg = "#033259",
  selection_fg = "#CBE0F0",
  ansi = { "#214969", "#E52E2E", "#44FFB1", "#FFE073", "#0FC5ED", "#A277FF", "#24EAF7", "#24EAF7" },
  brights = { "#214969", "#E52E2E", "#44FFB1", "#FFE073", "#A277FF", "#A277FF", "#24EAF7", "#24EAF7" },
}

-- Version guard: config_builder validates keys on assignment, so this
-- swallows "unknown option" errors on older WezTerm builds instead of
-- breaking the whole config.
local function try(config, key, value)
  local ok, err = pcall(function()
    config[key] = value
  end)
  if not ok then
    wezterm.log_warn("appearance: skipping unsupported option '" .. key .. "': " .. tostring(err))
  end
end

function M.apply(config, platform)
  -- theme: pick ONE
  --config.color_scheme = "rose-pine-moon"
  config.colors = coolnight  -- josean's coolnight instead

  config.max_fps = 120

  -- font_with_fallback degrades gracefully when a glyph is missing
  config.font = wezterm.font_with_fallback({
    { family = "Hack Nerd Font", weight = "Regular" },
    "Symbols Nerd Font",
    "Noto Sans",
  })

  config.enable_tab_bar = true
  config.hide_tab_bar_if_only_one_tab = false
  -- INTEGRATED_BUTTONS keeps the frameless look but embeds clickable
  -- minimize/maximize/close buttons into the tab bar. Plain "RESIZE"
  -- removed them entirely.
  config.window_decorations = "INTEGRATED_BUTTONS|RESIZE"
  config.integrated_title_buttons = { "Hide", "Maximize", "Close" }
  config.window_frame = {
    font = wezterm.font("Hack Nerd Font", { weight = "Bold" }),
  }

  -- Start maximized.
  wezterm.on("gui-startup", function(cmd)
    local _, _, window = wezterm.mux.spawn_window(cmd or {})
    window:gui_window():maximize()
  end)

  config.inactive_pane_hsb = {
    saturation = 0.0,
    brightness = 0.5,
  }

  if platform.is_windows then
    try(config, "win32_system_backdrop", "Acrylic") -- newer builds only
    config.window_background_opacity = 0.8
    config.font_size = 11.0
    config.window_frame.font_size = 10.0
  end

  if platform.is_macos then
    config.window_background_opacity = 0.8
    try(config, "macos_window_background_blur", 50)
    config.font_size = 15.0
    config.window_frame.font_size = 13.0
  end
end

return M
