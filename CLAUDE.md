# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A **dotfiles bundle**, not an application — config files for WezTerm + Neovim +
tmux + Claude Code, plus a single-file Python installer (`onboard.py`). There is
no build, no test suite, no dependencies (stdlib only). "Running" the project
means running the installer, which copies these configs onto the host.

## Commands

```bash
python3 onboard.py --dry-run        # preview every action, change nothing — use this first
python3 onboard.py                  # install (auto-detects: B inside WSL, A on native Windows)
python3 onboard.py --setup C        # hybrid (WSL + Windows PowerShell pane)
python3 onboard.py --distro Ubuntu  # override auto-detected WSL distro
python3 onboard.py --dev-dir ~/dev  # dir new WezTerm tabs open in (~ is expanded)
python3 onboard.py --skip-font --skip-lazygit --skip-terminfo   # skip slow/network steps
```

When iterating on `onboard.py` itself, always validate with `--dry-run`; it is
idempotent and safe to re-run for real.

## The three setups (one config, one flag)

Everything keys off three variables at the top of `wezterm/wezterm.lua`:
`USE_WSL`, `WSL_DISTRO`, `DEV_DIR`. `onboard.py` **rewrites these in place** in the
repo's own `wezterm.lua` (see `patch_wezterm`) before copying — so the source file
is mutated by an install; expect git diffs there.

- **A — Native Windows** (`USE_WSL=false`): PowerShell toolchain.
- **B — WSL** (`USE_WSL=true`): Linux-style dev, real tmux. The recommended baseline.
- **C — Hybrid**: identical to B plus the `LEADER+w` keybind for a native Windows
  PowerShell tab (for a .NET project that stays on `C:\`). There is no separate
  "C config" — it is B with one extra keybind.

## Two invariants that drive most decisions

1. **Don't mix sides.** Neovim and Claude Code must run on the *same* side (both
   WSL or both Windows) or the `claudecode.nvim` `/ide` integration silently
   fails to connect. This is the most common user-facing breakage.
2. **Each tool is fast only on its own filesystem.** WSL CLI tools are fast on
   `~/`, slow on `/mnt/c`; Windows GUI tools are fast on `C:\`, slow on `\\wsl$`.
   Configs reflect this — e.g. `DEV_DIR` is a Linux path for B/C, a Windows path for A.

## Architecture

**`onboard.py`** — the only non-config code. Cross-platform-aware: it detects WSL
(`in_wsl`), resolves the *Windows* `%USERPROFILE%` from inside WSL (via cmd.exe,
`windows_userprofile`), and copies each config to the correct side:

- WezTerm config **always** goes to the Windows side
  (`%USERPROFILE%\.config\wezterm\`), because WezTerm is the Windows host app
  even when it renders WSL. See `install_wezterm_windows`.
- `nvim/init.lua` and `tmux/.tmux.conf` go to the side that *runs* them: into the
  Linux `~/` when inside WSL, into `%LOCALAPPDATA%\nvim\` for native Windows.

It also installs Hack Nerd Font, lazygit, the `wezterm` terminfo (so
`TERM=wezterm` works under tmux/nvim), and — inside WSL — TPM plus the tmux
plugins `.tmux.conf` declares (rose-pine theme, resurrect, continuum). Each is
skippable via a flag. `install_tpm` must run *after* `.tmux.conf` is copied,
since TPM's `bin/install_plugins` reads the `@plugin` lines out of it.

**`wezterm/`** — `wezterm.lua` is the entry point; it sets `package.path` then
requires `config/{platform,appearance,keys,plugins}.lua`. Each is a module
returning `M` with an `M.apply(config, platform, opts)` function. **Load order
matters: `keys.apply` must run before `plugins.apply`** because plugins append to
the keybinding table `keys` built. `platform.lua` exposes `is_windows /
is_macos / is_linux` derived from env + `wezterm.target_triple`.

WezTerm uses **no plugin manager** — only built-in APIs — deliberately, to avoid
the flashing cmd windows the plugin system spawns on Windows. `Ctrl/Alt+hjkl`
are intentionally left *unbound* at the WezTerm level so they pass through to
Neovim's smart-splits; WezTerm pane navigation lives on `leader h/j/k/l`.

**`nvim/init.lua`** — a single-file Neovim config (lazy.nvim bootstrapped
inline). Integrates `claudecode.nvim` for the `/ide` diff workflow. Also wires in
oil (`-`), render-markdown, highlight-on-yank, copy-path maps (`<leader>cp/cr`),
and a WSL-only `clip.exe` clipboard provider.

**`tmux/.tmux.conf`** — WSL only. Truecolor/undercurl passthrough plus the
rose-pine (moon) theme, `tmux-resurrect`/`tmux-continuum`, and vim-style pane
nav, all managed by TPM (which it self-bootstraps on first launch).

## Editing-the-config gotchas

- **Launching `claude` from WezTerm under WSL** uses `{ "bash", "-lc", "exec
  claude" }`, not bare `{ "claude" }` (see `keys.lua`). WezTerm execs programs
  *directly* without sourcing `~/.profile`, so `~/.local/bin` (where `claude`
  installs) is absent from `PATH` and the spawn fails. The login shell sources
  the profile, then `exec` replaces it. On native Windows it wraps in `pwsh.exe`.
- **After changing any `wezterm/config/*.lua`, fully quit and relaunch WezTerm.**
  A `Ctrl+Shift+R` reload reuses the cached `package.loaded` modules; if a file
  was ever read mid-write (e.g. during `onboard.py`'s copy), Lua caches the
  boolean `true` a return-less module yields and you get `attempt to index a
  boolean value`. Only a fresh process re-`require`s the file.
- **`oil.nvim` is set `default_file_explorer = false`** so it does *not* hijack
  netrw and fight neo-tree (which owns browsing and `nvim .` via
  `hijack_netrw_behavior`). oil opens only via the explicit `-` map.
- **The nvim WSL clipboard provider is `clip.exe` (copy) + PowerShell
  `Get-Clipboard` (paste)**, guarded by `has('wsl')` so native-Windows setup A
  keeps nvim's built-in provider. Paste spawns `powershell.exe` (slow);
  `win32yank.exe` on PATH + deleting the `vim.g.clipboard` block is the fast
  alternative. The provider is what makes `"+y` / `<leader>cp` reach Windows.
- **`install_tpm` in `onboard.py` must run after the `.tmux.conf` copy** — TPM's
  `bin/install_plugins` reads the `@plugin` lines out of `~/.tmux.conf`. The conf
  also self-bootstraps TPM on first tmux launch, so the two are belt-and-braces.
