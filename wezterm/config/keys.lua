local wezterm = require("wezterm")
local act = wezterm.action

local M = {}

local maximize_window = wezterm.action_callback(function(window, _pane)
  window:maximize()
end)

function M.apply(config, platform, opts)
  opts = opts or {}
  config.disable_default_key_bindings = true
  config.leader = { key = "Space", mods = "CTRL" }

  -- How to launch Claude. On native Windows wrap in PowerShell so the
  -- interactive TUI works. On WSL/Unix go through a login shell (`bash -lc`):
  -- WezTerm execs the program directly, so it never sources ~/.profile and
  -- ~/.local/bin (where `claude` lives) is missing from PATH -> "can't find".
  -- A login shell sources the profile first, then exec replaces it with claude.
  local claude_cmd
  if platform.is_windows and not opts.use_wsl then
    claude_cmd = { "pwsh.exe", "-NoExit", "-Command", "claude" }
  else
    claude_cmd = { "bash", "-lc", "exec claude" }
  end

  -- Directory new tabs/panes open in. nil -> inherit / domain default.
  -- Set explicitly (not just via default_cwd) because on Windows WezTerm can't
  -- read a WSL pane's cwd, so SpawnTab would otherwise fall back to the host cwd.
  local cwd = (opts.dev_dir and opts.dev_dir ~= "") and opts.dev_dir or nil

  config.keys = {
    -- clipboard (Cmd on macOS, Ctrl+Shift on Windows/Linux)
    { key = "v", mods = "CMD", action = act.PasteFrom("Clipboard") },
    { key = "v", mods = "CTRL|SHIFT", action = act.PasteFrom("Clipboard") },
    { key = "c", mods = "CTRL|SHIFT", action = act.CopyTo("Clipboard") },

    -- tabs (open in DEV_DIR when set; SpawnCommandInNewTab accepts a cwd)
    { key = "c", mods = "LEADER", action = act.SpawnCommandInNewTab({ domain = "CurrentPaneDomain", cwd = cwd }) },
    { key = "n", mods = "LEADER", action = act.ActivateTabRelative(1) },
    { key = "p", mods = "LEADER", action = act.ActivateTabRelative(-1) },

    -- split panes
    { key = "\\", mods = "LEADER", action = act.SplitHorizontal({ domain = "CurrentPaneDomain", cwd = cwd }) },
    { key = "-", mods = "LEADER", action = act.SplitVertical({ domain = "CurrentPaneDomain", cwd = cwd }) },

    -- move between panes (vim-style)
    { key = "h", mods = "LEADER", action = act.ActivatePaneDirection("Left") },
    { key = "j", mods = "LEADER", action = act.ActivatePaneDirection("Down") },
    { key = "k", mods = "LEADER", action = act.ActivatePaneDirection("Up") },
    { key = "l", mods = "LEADER", action = act.ActivatePaneDirection("Right") },

    -- pane management
    { key = "x", mods = "LEADER", action = act.CloseCurrentPane({ confirm = true }) },
    { key = "z", mods = "LEADER", action = act.TogglePaneZoomState },
    { key = "m", mods = "LEADER", action = maximize_window },

    -- Claude Code in a 40% right pane (runs in the current domain)
    {
      key = "a",
      mods = "LEADER",
      action = act.SplitPane({
        direction = "Right",
        size = { Percent = 40 },
        command = { args = claude_cmd, cwd = cwd },
      }),
    },
  }

  -- Windows-only hybrid switches
  if platform.is_windows then
    -- LEADER+w: open a native Windows PowerShell tab (for .NET / Visual Studio CLI)
    table.insert(config.keys, {
      key = "w",
      mods = "LEADER",
      action = act.SpawnCommandInNewTab({
        domain = { DomainName = "local" },
        args = { "pwsh.exe" },
      }),
    })
    if opts.use_wsl then
      -- LEADER+u: open an extra WSL pane on the right
      table.insert(config.keys, {
        key = "u",
        mods = "LEADER",
        action = act.SplitPane({
          direction = "Right",
          -- the target domain belongs inside `command`, not at the top level
          command = { domain = { DomainName = "WSL:" .. (opts.wsl_distro or "Ubuntu-24.04") }, cwd = cwd },
        }),
      })
    end
  end
end

return M
