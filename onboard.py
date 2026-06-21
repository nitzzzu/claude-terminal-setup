#!/usr/bin/env python3
"""Onboarding installer for the WezTerm + Neovim + Claude Code dev terminal setup.

Installs one of three setups by copying the bundled configs into place and
patching the USE_WSL / WSL_DISTRO flags in wezterm/wezterm.lua:

    A  Native Windows   (USE_WSL = false)
    B  WSL              (USE_WSL = true)   <- default, recommended baseline
    C  Hybrid           (USE_WSL = true; same as B + the LEADER+w Windows pane)

Run it from inside WSL for setup B/C, or from Windows (python) for setup A.

    python3 onboard.py                 # auto-detect, default to B inside WSL
    python3 onboard.py --setup B
    python3 onboard.py --setup A
    python3 onboard.py --distro Ubuntu # override detected WSL distro name
    python3 onboard.py --dev-dir ~/dev # new WezTerm tabs open here, not the home dir
    python3 onboard.py --skip-font     # don't install Hack Nerd Font
    python3 onboard.py --skip-lazygit  # don't install lazygit (the <leader>gg UI)
    python3 onboard.py --dry-run       # show what would happen, change nothing

Besides copying configs, it installs Hack Nerd Font, the lazygit binary (the
visual git UI Neovim opens with <leader>gg), and the wezterm terminfo (so tmux
and nvim work under TERM=wezterm) on whichever side the shell runs from.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import zipfile
from pathlib import Path
from urllib.request import urlopen, Request

REPO = Path(__file__).resolve().parent

# Tools we expect on PATH, per side.
WSL_TOOLS = ["nvim", "tmux", "rg", "claude", "gcc", "lazygit"]
WIN_TOOLS = ["wezterm", "nvim", "rg", "claude", "lazygit"]

# Hack Nerd Font — the patched font the appearance config expects.
FONT_URL = "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Hack.zip"

# WezTerm terminfo — needed inside WSL/Linux because wezterm.lua sets
# TERM=wezterm; without it tmux/nvim error ("missing or unsuitable terminal").
TERMINFO_URL = "https://raw.githubusercontent.com/wez/wezterm/main/termwiz/data/wezterm.terminfo"

# lazygit — the visual git UI opened from Neovim with <leader>gg (via snacks).
LAZYGIT_API = "https://api.github.com/repos/jesseduffield/lazygit/releases/latest"
# uname -m -> the arch token used in lazygit's Linux release asset names.
_LAZYGIT_ARCH = {
    "x86_64": "x86_64", "amd64": "x86_64",
    "aarch64": "arm64", "arm64": "arm64",
}


# ----------------------------------------------------------------------------- helpers

class C:
    """Tiny ANSI palette; disabled when stdout is not a tty."""
    _on = sys.stdout.isatty()
    G = "\033[32m" if _on else ""
    R = "\033[31m" if _on else ""
    Y = "\033[33m" if _on else ""
    B = "\033[34m" if _on else ""
    DIM = "\033[2m" if _on else ""
    END = "\033[0m" if _on else ""


def say(msg: str) -> None:
    print(msg)


def ok(msg: str) -> None:
    print(f"{C.G}✓{C.END} {msg}")


def warn(msg: str) -> None:
    print(f"{C.Y}⚠{C.END} {msg}")


def err(msg: str) -> None:
    print(f"{C.R}✗{C.END} {msg}")


def header(msg: str) -> None:
    print(f"\n{C.B}== {msg} =={C.END}")


def in_wsl() -> bool:
    if os.environ.get("WSL_DISTRO_NAME"):
        return True
    try:
        return "microsoft" in Path("/proc/version").read_text().lower()
    except OSError:
        return False


def detect_distro() -> str | None:
    return os.environ.get("WSL_DISTRO_NAME") or None


def windows_userprofile() -> Path | None:
    """Resolve %USERPROFILE% as a WSL path (e.g. /mnt/c/Users/nitzu)."""
    try:
        raw = subprocess.check_output(
            ["cmd.exe", "/c", "echo %USERPROFILE%"],
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()
    except (OSError, subprocess.CalledProcessError):
        return None
    if not raw or "%" in raw:
        return None
    try:
        wsl_path = subprocess.check_output(
            ["wslpath", "-u", raw], stderr=subprocess.DEVNULL, text=True
        ).strip()
    except (OSError, subprocess.CalledProcessError):
        return None
    return Path(wsl_path) if wsl_path else None


def find_powershell() -> str | None:
    """Locate a PowerShell executable usable from here (WSL or native Windows)."""
    for exe in ("pwsh.exe", "powershell.exe", "pwsh", "powershell"):
        if shutil.which(exe):
            return exe
    return None


# PowerShell that downloads Hack Nerd Font and installs it per-user (no admin):
# copies the .ttf into %LOCALAPPDATA%\Microsoft\Windows\Fonts and registers
# each face under HKCU so apps (WezTerm) pick it up without a reboot.
_PS_FONT_INSTALL = r"""
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # avoid CLIXML progress spam over WSL
$url = '__URL__'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$tmp = Join-Path $env:TEMP ('HackNF_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
$zip = Join-Path $tmp 'Hack.zip'
Write-Host 'Downloading Hack Nerd Font...'
Invoke-WebRequest -Uri $url -OutFile $zip
Expand-Archive -Path $zip -DestinationPath $tmp -Force
$fontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
New-Item -ItemType Directory -Force -Path $fontDir | Out-Null
$regKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
$n = 0
Get-ChildItem -Path $tmp -Filter *.ttf -Recurse | ForEach-Object {
    $dest = Join-Path $fontDir $_.Name
    Copy-Item $_.FullName $dest -Force
    $name = [IO.Path]::GetFileNameWithoutExtension($_.Name) + ' (TrueType)'
    New-ItemProperty -Path $regKey -Name $name -Value $dest -PropertyType String -Force | Out-Null
    $n++
}
Remove-Item $tmp -Recurse -Force
Write-Host "Installed $n Hack Nerd Font face(s)."
"""


def install_font_windows(dry: bool) -> bool:
    """Install Hack Nerd Font on the Windows side via PowerShell."""
    ps = find_powershell()
    if not ps:
        err("no PowerShell found; install Hack Nerd Font from nerdfonts.com by hand")
        return False
    if dry:
        warn(f"[dry-run] would run {ps} to download + install Hack Nerd Font")
        return True
    script = _PS_FONT_INSTALL.replace("__URL__", FONT_URL)
    encoded = base64.b64encode(script.encode("utf-16-le")).decode("ascii")
    say(f"  {C.DIM}installing Hack Nerd Font via {ps} (per-user, no admin)...{C.END}")
    try:
        subprocess.run(
            [ps, "-NoProfile", "-ExecutionPolicy", "Bypass", "-EncodedCommand", encoded],
            check=True,
        )
    except (OSError, subprocess.CalledProcessError) as e:
        err(f"font install failed ({e}); install Hack Nerd Font from nerdfonts.com by hand")
        return False
    ok("Hack Nerd Font installed (Windows side)")
    return True


def install_font_linux(dry: bool) -> bool:
    """Install Hack Nerd Font into ~/.local/share/fonts on a pure-Linux host."""
    dest = Path.home() / ".local" / "share" / "fonts" / "HackNerdFont"
    if dry:
        warn(f"[dry-run] would download Hack Nerd Font -> {dest} and refresh fc-cache")
        return True
    try:
        dest.mkdir(parents=True, exist_ok=True)
        say(f"  {C.DIM}downloading Hack Nerd Font...{C.END}")
        with tempfile.NamedTemporaryFile(suffix=".zip", delete=False) as tf:
            tmp_zip = Path(tf.name)
            with urlopen(FONT_URL) as resp:  # noqa: S310 (trusted GitHub release)
                shutil.copyfileobj(resp, tf)
        n = 0
        with zipfile.ZipFile(tmp_zip) as z:
            for member in z.namelist():
                if member.lower().endswith(".ttf"):
                    data = z.read(member)
                    (dest / Path(member).name).write_bytes(data)
                    n += 1
        tmp_zip.unlink(missing_ok=True)
    except Exception as e:  # network / zip / IO
        err(f"font install failed ({e}); install Hack Nerd Font by hand")
        return False
    if shutil.which("fc-cache"):
        subprocess.run(["fc-cache", "-f", str(dest.parent)], check=False)
    ok(f"Installed {n} Hack Nerd Font face(s) -> {dest}")
    return True


def install_font(setup: str, wsl: bool, dry: bool) -> None:
    """Install the font on the side WezTerm renders from."""
    header("Installing Hack Nerd Font")
    # Setups A/B/C all use WezTerm as a Windows host -> font goes on Windows.
    if wsl or os.name == "nt":
        install_font_windows(dry)
    else:
        install_font_linux(dry)


def _latest_lazygit_version() -> str:
    """Return the latest lazygit version (no leading 'v') from the GitHub API."""
    req = Request(LAZYGIT_API, headers={"Accept": "application/vnd.github+json"})
    with urlopen(req) as resp:  # noqa: S310 (trusted GitHub API)
        data = json.load(resp)
    return str(data["tag_name"]).lstrip("v")


def install_lazygit_linux(dry: bool) -> bool:
    """Install the lazygit binary into ~/.local/bin from its GitHub release."""
    if shutil.which("lazygit"):
        ok(f"lazygit already installed {C.DIM}-> {shutil.which('lazygit')}{C.END}")
        return True
    arch = _LAZYGIT_ARCH.get(platform.machine().lower())
    if not arch:
        warn(f"lazygit: unrecognized arch {platform.machine()!r}; install it by hand "
             "from github.com/jesseduffield/lazygit/releases")
        return False
    dest = Path.home() / ".local" / "bin" / "lazygit"
    if dry:
        warn(f"[dry-run] would download lazygit ({arch}) -> {dest}")
        return True
    try:
        ver = _latest_lazygit_version()
        url = (f"https://github.com/jesseduffield/lazygit/releases/download/"
               f"v{ver}/lazygit_{ver}_Linux_{arch}.tar.gz")
        say(f"  {C.DIM}downloading lazygit v{ver}...{C.END}")
        dest.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(suffix=".tar.gz", delete=False) as tf:
            tmp_tar = Path(tf.name)
            with urlopen(url) as resp:  # noqa: S310 (trusted GitHub release)
                shutil.copyfileobj(resp, tf)
        with tarfile.open(tmp_tar) as t:
            member = t.extractfile("lazygit")
            if member is None:
                raise RuntimeError("no 'lazygit' binary in release tarball")
            dest.write_bytes(member.read())
        dest.chmod(0o755)
        tmp_tar.unlink(missing_ok=True)
    except Exception as e:  # network / tar / IO
        err(f"lazygit install failed ({e}); grab it from "
            "github.com/jesseduffield/lazygit/releases by hand")
        return False
    ok(f"Installed lazygit v{ver} -> {dest}")
    local_bin = str(dest.parent)
    if local_bin not in os.environ.get("PATH", "").split(os.pathsep):
        warn(f"  {local_bin} is not on PATH — add it so nvim's <leader>gg can find lazygit")
    return True


def install_lazygit_windows(dry: bool) -> bool:
    """Install lazygit on the Windows side via winget."""
    if shutil.which("lazygit"):
        ok(f"lazygit already installed {C.DIM}-> {shutil.which('lazygit')}{C.END}")
        return True
    winget = shutil.which("winget") or shutil.which("winget.exe")
    if not winget:
        warn("winget not found; install lazygit with `winget install JesseDuffield.lazygit`")
        return False
    if dry:
        warn("[dry-run] would run winget install JesseDuffield.lazygit")
        return True
    say(f"  {C.DIM}installing lazygit via winget...{C.END}")
    try:
        subprocess.run(
            [winget, "install", "--id", "JesseDuffield.lazygit", "-e",
             "--accept-package-agreements", "--accept-source-agreements"],
            check=True,
        )
    except (OSError, subprocess.CalledProcessError) as e:
        err(f"lazygit install failed ({e}); run `winget install JesseDuffield.lazygit` by hand")
        return False
    ok("lazygit installed (Windows side)")
    return True


def install_lazygit(setup: str, wsl: bool, dry: bool) -> None:
    """Install lazygit on the side Neovim runs from (where <leader>gg invokes it)."""
    header("Installing lazygit")
    if wsl or os.name != "nt":
        # B/C run inside WSL (nvim is on the Linux side); pure-Linux host likewise.
        install_lazygit_linux(dry)
    else:
        install_lazygit_windows(dry)


# ----------------------------------------------------------------------------- actions

def install_terminfo(dry: bool) -> bool:
    """Install the wezterm terminfo into ~/.terminfo (WSL/Linux side).

    wezterm.lua advertises TERM=wezterm; without the matching terminfo, tmux
    and nvim fail with "missing or unsuitable terminal: wezterm".
    """
    if subprocess.run(["infocmp", "-x", "wezterm"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
        ok("wezterm terminfo already present")
        return True
    if not shutil.which("tic"):
        warn("`tic` not found (install ncurses-bin); then re-run, or set "
             'config.term = "xterm-256color" in wezterm.lua')
        return False
    if dry:
        warn("[dry-run] would download wezterm terminfo and run tic -x -o ~/.terminfo")
        return True
    try:
        say(f"  {C.DIM}downloading wezterm terminfo...{C.END}")
        with tempfile.NamedTemporaryFile(suffix=".terminfo", delete=False) as tf:
            tmp = Path(tf.name)
            with urlopen(TERMINFO_URL) as resp:  # noqa: S310 (trusted source)
                shutil.copyfileobj(resp, tf)
        subprocess.run(["tic", "-x", "-o", str(Path.home() / ".terminfo"), str(tmp)],
                       check=True)
        tmp.unlink(missing_ok=True)
    except Exception as e:  # network / tic / IO
        err(f"terminfo install failed ({e}); install it by hand (see WezTerm docs)")
        return False
    ok("wezterm terminfo installed -> ~/.terminfo")
    return True


def patch_wezterm(use_wsl: bool, distro: str | None, dev_dir: str | None,
                  dry: bool) -> None:
    """Rewrite the USE_WSL / WSL_DISTRO / DEV_DIR flags at the top of wezterm.lua."""
    lua = REPO / "wezterm" / "wezterm.lua"
    text = lua.read_text()
    new = text

    new = re.sub(
        r"^local USE_WSL = (?:true|false)",
        f"local USE_WSL = {'true' if use_wsl else 'false'}",
        new,
        count=1,
        flags=re.M,
    )
    if distro:
        new = re.sub(
            r'^local WSL_DISTRO = "[^"]*"',
            f'local WSL_DISTRO = "{distro}"',
            new,
            count=1,
            flags=re.M,
        )
    if dev_dir is not None:
        # escape backslashes (Windows paths) for the Lua string literal
        lua_dir = dev_dir.replace("\\", "\\\\")
        new = re.sub(
            r'^local DEV_DIR = "[^"]*"',
            f'local DEV_DIR = "{lua_dir}"',
            new,
            count=1,
            flags=re.M,
        )

    label = f"USE_WSL={'true' if use_wsl else 'false'}" + (
        f', WSL_DISTRO="{distro}"' if distro else ""
    ) + (f', DEV_DIR="{dev_dir}"' if dev_dir is not None else "")
    if new == text:
        ok(f"wezterm.lua already set ({label})")
        return
    if dry:
        warn(f"[dry-run] would patch wezterm.lua -> {label}")
        return
    lua.write_text(new)
    ok(f"patched wezterm.lua -> {label}")


def copy_tree(src: Path, dst: Path, dry: bool) -> None:
    if dry:
        warn(f"[dry-run] would copy {src}/  ->  {dst}/")
        return
    dst.mkdir(parents=True, exist_ok=True)
    shutil.copytree(src, dst, dirs_exist_ok=True)
    ok(f"{src.name}/  ->  {dst}")


def copy_file(src: Path, dst: Path, dry: bool) -> None:
    if dry:
        warn(f"[dry-run] would copy {src.name}  ->  {dst}")
        return
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)
    ok(f"{src.name}  ->  {dst}")


def install_wezterm_windows(dry: bool) -> bool:
    """Copy wezterm/ to %USERPROFILE%\\.config\\wezterm (the Windows side)."""
    home = Path(os.path.expanduser("~")) if not in_wsl() else windows_userprofile()
    if home is None:
        err("could not resolve Windows %USERPROFILE% (is cmd.exe reachable?)")
        warn("  copy wezterm/ to %USERPROFILE%\\.config\\wezterm\\ by hand")
        return False
    copy_tree(REPO / "wezterm", home / ".config" / "wezterm", dry)
    return True


def verify_tools(tools: list[str]) -> None:
    header("Verifying tools on PATH")
    for t in tools:
        path = shutil.which(t)
        if path:
            ok(f"{t}  {C.DIM}-> {path}{C.END}")
        else:
            err(f"{t}  MISSING")


# ----------------------------------------------------------------------------- next steps

def next_steps(setup: str) -> None:
    header("Next steps")
    if setup == "A":
        steps = [
            "Restart WezTerm so it reloads the config (and picks up the new font).",
            "Run `claude` once to log in.",
            "In nvim: <leader>gg opens lazygit; Ctrl+h/j/k/l jump between splits.",
        ]
    else:
        steps = [
            "Make sure WezTerm is installed on the WINDOWS side "
            "(it's the host app that renders WSL; the font was installed there).",
            "Restart WezTerm so it boots into your distro with the new config.",
            "Run `claude` once in a WSL pane to log in.",
            "First `nvim` launch bootstraps plugins; then `:TSUpdate` and `:Mason`.",
            "In nvim: <leader>gg opens lazygit (diffs, stage, commit, push/pull); "
            "Ctrl+h/j/k/l jump between splits (incl. out of the Claude terminal).",
            "Test: LEADER+a (Ctrl+Space, a) opens Claude in a pane; type `/ide` to "
            "connect to a running Neovim on the same side.",
        ]
        if setup == "C":
            steps.append(
                "Hybrid: LEADER+w opens a native Windows PowerShell tab; keep the "
                ".NET solution on C:\\ and run a Windows `claude` there."
            )
    for i, s in enumerate(steps, 1):
        say(f"  {C.B}{i}.{C.END} {s}")


# ----------------------------------------------------------------------------- main

def main() -> int:
    ap = argparse.ArgumentParser(description="Install the dev terminal setup.")
    ap.add_argument("--setup", choices=["A", "B", "C"], help="which setup (default: auto)")
    ap.add_argument("--distro", help="WSL distro name (default: auto-detect)")
    ap.add_argument("--dev-dir", help="working directory new WezTerm tabs open in "
                    "(WSL/Linux: a Linux path like ~/dev; Windows: C:\\Users\\you\\dev)")
    ap.add_argument("--skip-font", action="store_true",
                    help="don't install Hack Nerd Font")
    ap.add_argument("--skip-lazygit", action="store_true",
                    help="don't install lazygit (the <leader>gg git UI)")
    ap.add_argument("--skip-terminfo", action="store_true",
                    help="don't install the wezterm terminfo (WSL/Linux)")
    ap.add_argument("--dry-run", action="store_true", help="show actions, change nothing")
    args = ap.parse_args()

    wsl = in_wsl()
    setup = args.setup or ("B" if wsl else "A")
    use_wsl = setup in ("B", "C")
    distro = args.distro or (detect_distro() if use_wsl else None)

    dev_dir = args.dev_dir
    if dev_dir is not None and dev_dir.startswith("~"):
        dev_dir = os.path.expanduser(dev_dir)  # ~/dev -> /home/you/dev inside WSL

    header(f"Onboarding setup {setup}")
    say(f"  running inside WSL : {'yes' if wsl else 'no'}")
    say(f"  USE_WSL            : {use_wsl}")
    say(f"  WSL_DISTRO         : {distro or '(unchanged)'}")
    say(f"  DEV_DIR            : {dev_dir or '(unchanged)'}")

    # Create the dev dir on the side we can actually see, so the WSL spawn
    # doesn't fail on a missing path. Skip Windows paths seen from WSL etc.
    if dev_dir:
        ours = (dev_dir.startswith("/") if (wsl or os.name != "nt")
                else (":" in dev_dir or dev_dir.startswith("\\\\")))
        if ours:
            p = Path(dev_dir)
            if args.dry_run:
                if not p.exists():
                    warn(f"[dry-run] would create dev dir {p}")
            elif not p.exists():
                p.mkdir(parents=True, exist_ok=True)
                ok(f"created dev dir {p}")
    if args.dry_run:
        warn("  DRY RUN — no files will be written")

    # sanity: B/C must run inside WSL so the ~/ copies land in the Linux home.
    if use_wsl and not wsl:
        warn("setup B/C copies nvim/tmux into the WSL home — run this INSIDE WSL.")
        warn("only the Windows-side wezterm copy will be attempted from here.")

    if use_wsl and not distro:
        warn("no WSL distro detected; wezterm.lua WSL_DISTRO left as-is "
             "(pass --distro NAME, see `wsl -l -q`).")

    header("Patching config flags")
    patch_wezterm(use_wsl, distro, dev_dir, args.dry_run)

    header("Installing config files")
    # WezTerm config always lives on the Windows side.
    install_wezterm_windows(args.dry_run)

    if wsl:
        # Neovim + tmux into the Linux home.
        home = Path.home()
        copy_file(REPO / "nvim" / "init.lua", home / ".config" / "nvim" / "init.lua",
                  args.dry_run)
        copy_file(REPO / "tmux" / ".tmux.conf", home / ".tmux.conf", args.dry_run)
    elif setup == "A":
        # Native Windows: nvim -> %LOCALAPPDATA%\nvim\init.lua
        local = os.environ.get("LOCALAPPDATA")
        if local:
            copy_file(REPO / "nvim" / "init.lua",
                      Path(local) / "nvim" / "init.lua", args.dry_run)
        else:
            warn("LOCALAPPDATA not set; copy nvim/init.lua to "
                 "%LOCALAPPDATA%\\nvim\\init.lua by hand")

    if args.skip_font:
        header("Installing Hack Nerd Font")
        warn("skipped (--skip-font); install from nerdfonts.com if needed")
    else:
        install_font(setup, wsl, args.dry_run)

    if args.skip_lazygit:
        header("Installing lazygit")
        warn("skipped (--skip-lazygit); <leader>gg in nvim needs lazygit on PATH")
    else:
        install_lazygit(setup, wsl, args.dry_run)

    # TERM=wezterm needs a matching terminfo on the side the shell runs (not
    # native Windows, which uses PowerShell + the WezTerm-provided terminfo).
    if wsl or os.name != "nt":
        if args.skip_terminfo:
            header("Installing wezterm terminfo")
            warn("skipped (--skip-terminfo); tmux/nvim need it under TERM=wezterm")
        else:
            header("Installing wezterm terminfo")
            install_terminfo(args.dry_run)

    verify_tools(WSL_TOOLS if wsl else WIN_TOOLS)
    next_steps(setup)

    print()
    ok("Onboarding complete." if not args.dry_run else "Dry run complete — nothing changed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
