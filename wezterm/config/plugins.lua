local wezterm = require("wezterm")

local M = {}

-- IMPORTANT: this module deliberately uses NO `wezterm.plugin.require`. On
-- Windows that system shells out to git on every startup, which pops a cluster
-- of flashing cmd windows and slows launch. Everything here uses built-in
-- WezTerm APIs only — no spawned processes.
--
-- We also deliberately do NOT bind Ctrl/Alt+h/j/k/l at the WezTerm level: across
-- the WSL boundary WezTerm can't reliably tell when Neovim is focused, so a
-- WezTerm binding would swallow those keys before nvim sees them. Instead the
-- keys pass straight through to nvim (smart-splits.nvim handles splits there),
-- and WezTerm pane navigation lives on `leader h/j/k/l` (see keys.lua).

function M.apply(config, platform, opts)
  opts = opts or {}

  -- right status: LEADER indicator, workspace, battery, date/time (all built-in)
  wezterm.on("update-right-status", function(window, _pane)
    local cells = {}
    if window:leader_is_active() then
      table.insert(cells, "LEADER")
    end
    table.insert(cells, window:active_workspace())
    for _, b in ipairs(wezterm.battery_info()) do
      table.insert(cells, string.format("%.0f%%", b.state_of_charge * 100))
    end
    table.insert(cells, wezterm.strftime("%a %b %-d  %H:%M"))
    window:set_right_status(wezterm.format({ { Text = " " .. table.concat(cells, "  •  ") .. "  " } }))
  end)

  -- tab titles: "<index> <process>" with a * marker when the pane is zoomed
  wezterm.on("format-tab-title", function(tab, _tabs, _panes, _cfg, _hover, _maxw)
    local proc = tab.active_pane.foreground_process_name or ""
    proc = proc:match("([^/\\]+)%.exe$") or proc:match("([^/\\]+)$") or proc
    local zoom = tab.active_pane.is_zoomed and " *" or ""
    return string.format(" %d  %s%s ", tab.tab_index + 1, proc, zoom)
  end)
end

return M
