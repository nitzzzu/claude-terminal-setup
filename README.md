# Dev Terminal Setup — WezTerm + Neovim + Claude Code

One set of config files, **three setups** chosen by a single flag:

| Setup                  | Who it's for                                                            | `USE_WSL` |
| ---------------------- | ----------------------------------------------------------------------- | --------- |
| **A — Native Windows** | No WSL; pure Windows toolchain                                          | `false`   |
| **B — WSL**            | Smoothest Linux-style dev; real tmux                                    | `true`    |
| **C — Hybrid**         | WSL for daily dev **+** Visual Studio on Windows for a big .NET project | `true`    |

The flag lives at the top of `wezterm/wezterm.lua`:

```lua
local USE_WSL = true          -- B / C
local WSL_DISTRO = "Ubuntu-24.04"
local DEV_DIR = ""            -- "" = shell default; e.g. "/home/you/dev" for WSL
```

`DEV_DIR` is the directory new tabs/panes open in. Left empty, WSL tabs inherit
WezTerm's Windows cwd and land in `/mnt/c/Users/<you>`; set it to a Linux path
(e.g. `/home/you/dev`) to start in your project instead. On native Windows/macOS
use a native path. `onboard.py --dev-dir PATH` fills it in (and `~` is expanded).

Setups B and C share the same config; **Hybrid is just the WSL setup plus the
`LEADER+w` keybind** that opens a native Windows PowerShell tab for .NET work.

## Quick install

Once the requirements for your setup are installed (see the per-setup sections
below), run the bundled installer. It patches the `USE_WSL` / `WSL_DISTRO`
flags, copies every config to the right place, **installs Hack Nerd Font**
(per-user, no admin — on the Windows side for A/B/C), and verifies your tools.

```bash
# Setup B / C — run INSIDE WSL:
python3 onboard.py                 # auto-detects WSL + distro, defaults to B

# Setup A — run on Windows:
python onboard.py --setup A
```

Useful flags:

```bash
python3 onboard.py --dry-run       # show what it would do, change nothing
python3 onboard.py --setup C       # hybrid (WSL + Windows PowerShell pane)
python3 onboard.py --distro Ubuntu # override the auto-detected distro name
python3 onboard.py --dev-dir ~/dev # new tabs open here instead of the home dir
python3 onboard.py --skip-font     # skip the Hack Nerd Font install
python3 onboard.py --skip-tpm      # skip TPM + the tmux plugins (WSL)
```

The installer is dependency-free (Python stdlib only) and idempotent — safe to
re-run. The manual steps in each setup section below remain as a reference for
doing it by hand.

## Bundle contents

```
claude-terminal-setup/
├── README.md
├── onboard.py                 # one-command installer (see Quick install)
├── wezterm/
│   ├── wezterm.lua            -> %USERPROFILE%\.config\wezterm\wezterm.lua
│   └── config/{platform,appearance,keys,plugins}.lua
├── nvim/
│   └── init.lua               -> Windows: %LOCALAPPDATA%\nvim\init.lua
│                              -> WSL:     ~/.config/nvim/init.lua
└── tmux/
    └── .tmux.conf             -> WSL only: ~/.tmux.conf
```

---

## Two rules that decide everything

**1. Don't mix sides.** Neovim and Claude Code must be on the same side (both
WSL, or both Windows) for the claudecode.nvim `/ide` integration to work.

**2. Each tool is fast on its own filesystem, slow across the bridge.**
- Linux CLI tools (nvim, tmux, Claude-in-WSL) are fast on the WSL disk (`~/`),
  slow on `/mnt/c`.
- Windows GUI tools (Visual Studio) are fast on `C:\`, slow on `\\wsl$`.
- So: **WSL projects live in `~/`**, the **big .NET project stays on `C:\`** and
  is edited in Visual Studio. Don't force either across the bridge.

**Data safety (WSL):** your WSL files sit in one virtual disk. Treat **git +
a remote** as your source of truth, shut down with `wsl --shutdown`, and take
occasional snapshots: `wsl --export Ubuntu-24.04 D:\backups\wsl.tar`.

---

## Setup A — Native Windows

In **PowerShell**:

```powershell
winget install wez.wezterm
winget install Microsoft.PowerShell
winget install Neovim.Neovim
winget install Git.Git
winget install zig.zig                  # treesitter compiler
winget install BurntSushi.ripgrep.MSVC  # Telescope
winget install JesseDuffield.lazygit    # visual git UI (<leader>gg in nvim)
irm https://claude.ai/install.ps1 | iex # Claude Code
```

- Install **Hack Nerd Font** from nerdfonts.com (select `.ttf` -> Install).
- Run `python onboard.py --setup A` to do the rest, **or** by hand:
  - Set `USE_WSL = false` in `wezterm/wezterm.lua`.
  - Copy `wezterm/` -> `%USERPROFILE%\.config\wezterm\`.
  - Copy `nvim/init.lua` -> `%LOCALAPPDATA%\nvim\init.lua`.
- `claude doctor`, then `claude` once to log in.

---

## Setup B — WSL (recommended baseline)

choco install wezterm -y

Install WSL (PowerShell as admin), then work **inside** Ubuntu:

```powershell
wsl --install -d Ubuntu-24.04
```

Inside WSL:

```bash
sudo apt update
sudo apt install -y build-essential ripgrep tmux unzip
sudo apt install -y neovim   # or the latest from github.com/neovim/neovim/releases
curl -fsSL https://claude.ai/install.sh | bash   # Claude Code (Linux build)
```

`onboard.py` also installs **lazygit** (the `<leader>gg` git UI in Neovim) into
`~/.local/bin`, the **wezterm terminfo** (so tmux/nvim work under `TERM=wezterm`),
and **TPM + the tmux plugins** the config declares (rose-pine theme,
`tmux-resurrect`, `tmux-continuum`). To do lazygit by hand, grab the
`Linux_x86_64` tarball from `github.com/jesseduffield/lazygit/releases` and put
it on your PATH. (`.tmux.conf` also self-bootstraps TPM on first launch, so the
plugins install even if you skip the installer.)

- Keep **WezTerm + Hack Nerd Font installed on Windows** (WezTerm is the Windows
  host app that renders WSL).
- Run `python3 onboard.py` inside WSL to do the rest, **or** by hand:
  - Set `USE_WSL = true` and `WSL_DISTRO` to your distro name (`wsl -l -q` lists it).
  - Copy `wezterm/` -> `%USERPROFILE%\.config\wezterm\` (Windows side).
  - Copy `nvim/init.lua` -> `~/.config/nvim/init.lua` (inside WSL).
  - Copy `tmux/.tmux.conf` -> `~/.tmux.conf` (inside WSL).
- `claude` once to log in.

Treesitter uses the preinstalled gcc — no zig needed (the config prefers zig but
falls back to gcc/clang automatically).

---

## Setup C — Hybrid (WSL + Visual Studio for .NET)

Do everything in **Setup B**, then:

- Keep your big **.NET solution on `C:\`** and open it in **Visual Studio** as
  normal — do not move it into WSL.
- In WezTerm, `LEADER+w` opens a **native Windows PowerShell tab** for `dotnet`
  CLI work next to Visual Studio.
- For a quick read of the .NET project from the WSL side, reach it via
  `/mnt/c/...` — fine for light work, not heavy file operations.
- Run **Claude Code on whichever side the project lives**: `claude` in WSL for
  WSL projects; a Windows `claude` (install via the `.ps1` from Setup A) in the
  `LEADER+w` PowerShell tab for the .NET project.

---

## Keybindings

**WezTerm** (leader = `Ctrl+Space`):

| Keys                            | Action                                    |
| ------------------------------- | ----------------------------------------- |
| `leader` `c` / `n` / `p`        | new / next / prev tab                     |
| `leader` `\` / `-`              | split right / down                        |
| `leader` `h/j/k/l`              | move between panes                        |
| `leader` `z` / `x` / `m`        | zoom / close pane / maximize              |
| `leader` `a`                    | Claude Code in a right pane               |
| `leader` `w`                    | **Windows PowerShell tab** (Windows only) |
| `leader` `u`                    | extra WSL pane (Windows + `USE_WSL`)      |
| `Ctrl+Shift+V` / `Ctrl+Shift+C` | paste / copy                              |

**Neovim** (leader = `Space`):

| Keys                       | Action                                |
| -------------------------- | ------------------------------------- |
| `<leader>e`                | toggle file tree                      |
| `-`                        | parent dir as an editable buffer (oil)|
| `<leader>ac` / `af`        | toggle / focus Claude                 |
| `<leader>as` (visual)      | send selection to Claude              |
| `<leader>as` (in tree)     | add file under cursor to Claude       |
| `<leader>ab`               | add current buffer to Claude          |
| `<leader>aa` / `ad`        | accept / reject Claude diff           |
| `gd` / `gr` / `K`          | definition / references / hover (LSP) |
| `<leader>rn` / `ca`        | rename / code action (LSP)            |
| `[d` / `]d`                | prev / next diagnostic                |
| `<leader>ff` / `fg` / `fb` | find files / live grep / buffers      |
| `<leader>cp` / `cr`        | copy absolute / relative file path    |
| `<leader>gg` / `gl` / `gf` | lazygit status / repo log / file log  |
| `<leader>xx` / `xX`        | diagnostics: workspace / buffer (Trouble) |
| `<leader>xs` / `xq`        | symbols / quickfix (Trouble)          |
| `Ctrl+h/j/k/l`             | move between Neovim splits            |
| `Alt+h/j/k/l`              | resize the active Neovim split        |
| `Ctrl+q` (in a terminal)   | leave terminal mode -> normal mode    |

Press `<leader>` and pause to see every mapping in a **which-key** popup.

`Ctrl+h/j/k/l` also work **from inside the Claude terminal** — they drop you out
of terminal mode and into the next split in one keystroke (so use `Backspace`,
not `Ctrl+h`, to delete inside Claude). `Ctrl+w` is left untouched in the
terminal so Claude's "delete word" still works.

**tmux** (WSL): default prefix `Ctrl+b`; mouse enabled.

| Keys                       | Action                                   |
| -------------------------- | ---------------------------------------- |
| `prefix` `h/j/k/l`         | move between panes                       |
| `prefix` `"` / `%`         | split below / right (in the current cwd) |
| `prefix` `c`               | new window (in the current cwd)          |
| `prefix` `y`               | enter copy-mode                          |
| `v` / `y` (in copy-mode)   | start selection / copy to Windows clipboard |

Styled with the **rose-pine (moon)** theme via TPM, with `tmux-resurrect` +
`tmux-continuum` auto-saving and restoring sessions. Copy-mode yanks pipe to
`clip.exe` (the Windows clipboard). First launch fetches the plugins — if the
bar looks unthemed, reload a running session with `prefix + I`.

---

## Using Claude

- **Inside Neovim:** `:ClaudeCode` (or `<leader>ac`), select code + `<leader>as`
  to send, accept edits as native diffs with `<leader>aa`.
- **In a pane:** `LEADER+a` opens Claude; type `/ide` inside it to connect to the
  running Neovim on the same side.

---

## Troubleshooting

- **`claude` not found in Neovim** -> set `terminal_cmd` in the claudecode.nvim
  `opts` (Windows: `where.exe claude`; WSL: `which claude`).
- **Treesitter "no C compiler"** -> Windows: `winget install zig.zig`;
  WSL: `sudo apt install build-essential`. Then `:TSUpdate`.
- **`missing or unsuitable terminal: wezterm`** (tmux/nvim) -> the wezterm
  terminfo isn't installed on this side. `onboard.py` installs it; by hand:
  `curl -fsSL -o /tmp/w.ti https://raw.githubusercontent.com/wez/wezterm/main/termwiz/data/wezterm.terminfo && tic -x -o ~/.terminfo /tmp/w.ti`
  (needs `tic` from `ncurses-bin`).
- **nvim washed out / no undercurl in tmux** -> ensure `~/.tmux.conf` has the
  truecolor + `usstyle` lines (it does here); restart tmux (`tmux kill-server`).
- **tmux bar unthemed / plugins missing** -> TPM hasn't fetched them yet. Re-run
  `onboard.py` (WSL), or in a running tmux press `prefix + I` to install.
- **Paste in nvim is slow (WSL)** -> each paste spawns `powershell.exe` to read
  the Windows clipboard. Put `win32yank.exe` on PATH and delete the
  `vim.g.clipboard` block in `init.lua`; Neovim auto-detects win32yank (faster
  both directions). `"+y` and `<leader>cp`/`cr` need a provider to reach Windows.
- **`/ide` won't connect** -> Neovim and Claude are on different sides; put both
  in WSL or both on Windows.
- **`<leader>gg` errors / "lazygit not found"** -> the `lazygit` binary isn't on
  PATH. Re-run `onboard.py`, or install it (WSL: GitHub release into
  `~/.local/bin`, ensure that's on PATH; Windows: `winget install JesseDuffield.lazygit`).
- **Visual Studio slow on a WSL project** -> expected; move that project to `C:\`.
- **`pwsh.exe` not found** -> install PowerShell 7 or change `pwsh.exe` to
  `powershell.exe` in `wezterm.lua` / `keys.lua`.
- **LSP server won't install** -> some servers (pyright, ts_ls) need Node.js;
  WSL `sudo apt install nodejs npm`, Windows install Node separately.

---

## Optional next steps

Install language servers/formatters via `:Mason` (stylua, ruff, prettierd,
pyright, csharp_ls/omnisharp for .NET if you ever edit it in nvim). Nice extras:
`bufferline.nvim` (styled tabs), `flash.nvim` (jump motions),
`nvim-treesitter-textobjects` (function/class text objects).

## Bundled extras

Beyond the core editor, these popular plugins are wired in:

- **Neovim:** which-key (keybinding popup), smart-splits (`Ctrl+hjkl` split
  navigation, `Alt+hjkl` resize), Trouble (`<leader>x…` diagnostics),
  todo-comments, indent-blankline, nvim-autopairs, gitsigns + lazygit, oil
  (`-` edits the filesystem as a buffer), render-markdown (in-buffer markdown),
  highlight-on-yank, and a WSL clipboard provider (`clip.exe` copy / PowerShell
  paste) so `"+y` reaches Windows.
- **tmux (WSL):** rose-pine (moon) theme + session save/restore
  (`tmux-resurrect` / `tmux-continuum`) via TPM; vim-style `prefix h/j/k/l` pane
  navigation; splits/windows inherit the current pane's cwd; copy-mode yanks to
  `clip.exe`.
- **WezTerm:** no plugin manager — the config uses only built-in APIs (a right
  status bar with workspace/battery/clock + a leader indicator, and custom tab
  titles). This keeps startup fast and avoids the flashing cmd windows the
  WezTerm plugin system spawns on Windows. `Ctrl/Alt+hjkl` are left unbound at
  the WezTerm level so they pass straight through to Neovim's smart-splits;
  WezTerm pane navigation is on `leader h/j/k/l`.
