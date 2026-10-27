# /// script
# requires-python = ">=3.10"
# dependencies = ["click>=8.0", "rich>=11.2"]  # 11.2 = Ubuntu 22.04 python3-rich
# ///
"""dotfiles — command-line front end for this repository's installer.

A thin, typed layer over the bash profiles in profiles/. The profiles stay the
source of truth for *doing* things; this file is only about *presenting* them:
what is installed, what each profile does, and a clean record of each run.

Styling follows the team's rai-ledger CLI: click for commands, rich for output,
rounded tables, dim metadata footers, numbered menus answered with a number.

Run it via the `cli/dotfiles` shim, which picks uv or a system python that
already has click + rich. Commands:

    dotfiles                      status summary, then a numbered profile menu
    dotfiles status               links, tools and system info
    dotfiles profiles             what each profile does and needs
    dotfiles install PROFILE      run a profile (asks before changing anything)
    dotfiles logs                 recent install logs
"""

from __future__ import annotations

import os
import platform
import re
import shlex
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

import click
from rich import box
from rich.align import Align
from rich.console import Console, Group
from rich.highlighter import Highlighter
from rich.panel import Panel
from rich.prompt import Confirm, IntPrompt
from rich.table import Table
from rich.text import Text
from rich.theme import Theme

REPO = Path(__file__).resolve().parent.parent
HOME = Path.home()
LOG_DIR = Path(os.environ.get("XDG_CACHE_HOME", HOME / ".cache")) / "dotfiles" / "logs"


class LogHighlighter(Highlighter):
    """Same idea as rai-ledger's NotionLogHighlighter: colour the tokens that
    matter in otherwise plain text, but never re-style explicit markup."""

    PATTERNS = [
        (r"\b\d+\.?\d*%?\b", "yellow", 0),
        (r"\[\d+/\d+\]", "dim yellow", 0),
        (r"(?:~|\$HOME)?/[\w./~-]+", "magenta", 0),
        (r"\b(Complete|Linked|ok|installed)\b", "green", 0),
        (r"\b(Warning|Skipping|Dry[- ]run|Cancelled)\b", "yellow", re.IGNORECASE),
        (r"\b(Failed|Error|Missing|broken)\b", "red", re.IGNORECASE),
        (r"https?://\S+", "blue underline", 0),
    ]

    def highlight(self, text: Text) -> None:
        styled: set[int] = set()
        for span in text._spans:  # noqa: SLF001
            styled.update(range(span.start, span.end))
        plain = text.plain
        for pattern, style, flags in self.PATTERNS:
            for m in re.finditer(pattern, plain, flags):
                if styled.isdisjoint(range(m.start(), m.end())):
                    text.stylize(style, m.start(), m.end())


THEME = Theme({"ok": "green", "warn": "yellow", "bad": "red", "muted": "dim", "accent": "magenta"})
console = Console(theme=THEME, highlighter=LogHighlighter())


# ---------------------------------------------------------------------------
# Model
# ---------------------------------------------------------------------------
DEBIAN_LIKE = {"ubuntu", "debian", "pop", "linuxmint"}


@dataclass(frozen=True)
class Profile:
    key: str
    script: str
    title: str
    summary: str
    sudo: bool
    os: frozenset[str] | None = None  # None = any OS
    needs_x11: bool = False
    asks_shell: bool = True


PROFILES: list[Profile] = [
    Profile("terminal", "terminal-setup.sh", "Terminal",
            "tmux, kitty, neovim and your chosen shell. Links configs from this repo.", sudo=False),
    # desktop-setup.sh (and install-packages.sh under it) accept only these two.
    Profile("desktop", "desktop-setup.sh", "Desktop",
            "All packages + terminal setup + optional KDE look and top bar.", sudo=True,
            os=frozenset({"ubuntu", "debian"})),
    Profile("vm", "vm-setup.sh", "VM / headless",
            "Shell, neovim, tmux and CLI tools. No GUI, kitty or fonts.", sudo=True, os=frozenset(DEBIAN_LIKE)),
    Profile("bar", "bar-setup.sh", "Top bar",
            "Polybar: desktops, media card, bluetooth and wifi menus.", sudo=True, os=frozenset(DEBIAN_LIKE),
            needs_x11=True, asks_shell=False),
]
BY_KEY = {p.key: p for p in PROFILES}


@dataclass(frozen=True)
class Link:
    name: str
    path: Path
    source: Path
    profile: str


def _links() -> list[Link]:
    c = REPO / "config"
    return [
        Link("bashrc", HOME / ".bashrc", c / "bash/.bashrc", "terminal"),
        Link("bash_profile", HOME / ".bash_profile", c / "bash/.bash_profile", "terminal"),
        Link("zshrc", HOME / ".zshrc", c / "zsh/.zshrc", "terminal"),
        Link("tmux.conf", HOME / ".tmux.conf", c / "tmux/tmux.conf", "terminal"),
        Link("tmux", HOME / ".config/tmux", c / "tmux", "terminal"),
        Link("kitty", HOME / ".config/kitty", c / "kitty", "terminal"),
        Link("herdr", HOME / ".config/herdr/config.toml", c / "herdr/config.toml", "terminal"),
        Link("kt", HOME / ".local/bin/kt", REPO / "scripts/utilities/kt", "terminal"),
        Link("polybar", HOME / ".config/polybar", c / "polybar", "bar"),
        Link("rofi", HOME / ".config/rofi", c / "rofi", "bar"),
        Link("dotfiles", HOME / ".local/bin/dotfiles", REPO / "cli/dotfiles", "terminal"),
        Link("bar", HOME / ".local/bin/bar", c / "polybar/launch.sh", "bar"),
        Link("touchegg", HOME / ".config/touchegg/touchegg.conf", c / "kde/touchegg/touchegg.conf", "desktop"),
    ]


TOOLS = ["git", "zsh", "tmux", "nvim", "kitty", "fzf", "rg", "zoxide", "oh-my-posh",
         "polybar", "rofi", "playerctl", "bluetoothctl", "uv"]


@dataclass
class System:
    os_id: str
    os_name: str
    display: str
    desktop: str
    shell: str
    branch: str = "?"
    dirty: int = 0
    behind_ahead: str = ""
    extras: dict = field(default_factory=dict)


def _os_release() -> dict[str, str]:
    data = {}
    try:
        for line in Path("/etc/os-release").read_text().splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                data[k] = v.strip('"')
    except OSError:
        pass
    return data


def _git(*args: str) -> str:
    try:
        return subprocess.run(["git", "-C", str(REPO), *args], capture_output=True, text=True, timeout=3).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return ""


def detect_system() -> System:
    rel = _os_release()
    if os.environ.get("WAYLAND_DISPLAY") or os.environ.get("XDG_SESSION_TYPE") == "wayland":
        display = "wayland"
    elif os.environ.get("DISPLAY"):
        display = "x11"
    else:
        display = "none"
    s = System(
        os_id=rel.get("ID", platform.system().lower()),
        os_name=rel.get("PRETTY_NAME", platform.platform()),
        display=display,
        desktop=os.environ.get("XDG_CURRENT_DESKTOP", "—"),
        shell=Path(os.environ.get("SHELL", "?")).name,
    )
    s.branch = _git("rev-parse", "--abbrev-ref", "HEAD") or "?"
    s.dirty = len([ln for ln in _git("status", "--porcelain").splitlines() if ln])
    counts = _git("rev-list", "--left-right", "--count", "@{u}...HEAD").split()
    if len(counts) == 2:
        behind, ahead = map(int, counts)
        parts = ([f"{ahead} ahead"] if ahead else []) + ([f"{behind} behind"] if behind else [])
        s.behind_ahead = ", ".join(parts) or "up to date"
    return s


def profile_blocker(p: Profile, s: System) -> str | None:
    """Why a profile cannot run here, or None."""
    if p.os is not None and s.os_id not in p.os:
        return f"needs Ubuntu/Debian (this is {s.os_id})"
    if p.needs_x11 and s.display != "x11":
        return f"needs an X11 session (this is {s.display})"
    if not (REPO / "profiles" / p.script).is_file():
        return f"profiles/{p.script} is missing"
    return None


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------
def tilde(path: Path) -> str:
    s = str(path)
    return "~" + s[len(str(HOME)):] if s.startswith(str(HOME)) else s


def link_state(link: Link) -> tuple[str, str]:
    p = link.path
    if p.is_symlink():
        target = Path(os.path.realpath(p))
        if not p.exists():
            return "bad", f"broken → {os.readlink(p)}"
        if target == link.source.resolve():
            return "ok", "linked"
        return "warn", f"→ {tilde(target)}"
    if p.exists():
        return "warn", "file (not linked)"
    return "muted", "not installed"


def footer(s: System, title: str, width: int | None = None) -> Panel:
    repo = f"[cyan dim]{s.branch}[/]"
    if s.behind_ahead:
        repo += f" [dim]({s.behind_ahead})[/]"
    if s.dirty:
        repo += f" [yellow dim]{s.dirty} uncommitted[/]"
    lines = [
        f"[dim]System:[/]   [cyan dim]{s.os_name}[/] [dim]· {s.display} · {s.desktop}[/]",
        f"[dim]Shell:[/]    [cyan dim]{s.shell}[/]",
        f"[dim]Repo:[/]     {repo} [dim]{tilde(REPO)}[/]",
    ]
    return Panel("\n".join(lines), title=title, title_align="left", border_style="dim",
                 padding=(0, 1), box=box.ROUNDED, width=width)


def links_table(s: System) -> Table:
    t = Table(title=Align.left("[bold]Links[/]"), show_header=True, header_style="bold",
              box=box.ROUNDED, padding=(0, 1))
    t.add_column("Config", style="cyan", no_wrap=True)
    t.add_column("Path", style="dim", no_wrap=True)
    t.add_column("Profile", style="dim")
    t.add_column("State", no_wrap=True)
    for link in _links():
        style, label = link_state(link)
        t.add_row(link.name, tilde(link.path), link.profile, Text(label, style=style))
    return t


def tools_table() -> Table:
    t = Table(title=Align.left("[bold]Tools[/]"), show_header=True, header_style="bold",
              box=box.ROUNDED, padding=(0, 1))
    t.add_column("Tool", style="cyan", no_wrap=True)
    t.add_column("Location", style="dim", no_wrap=True)
    for tool in TOOLS:
        path = shutil.which(tool)
        t.add_row(tool, Text(tilde(Path(path)), style="dim") if path else Text("missing", style="red"))
    return t


def profiles_table(s: System, numbered: bool = False) -> Table:
    t = Table(title=Align.left("[bold]Profiles[/]"), show_header=True, header_style="bold",
              box=box.ROUNDED, padding=(0, 2))
    if numbered:
        t.add_column("#", style="dim", justify="right")
    t.add_column("Profile", style="cyan", no_wrap=True)
    t.add_column("What it does", style="white", max_width=64)
    t.add_column("Needs", style="dim", no_wrap=True)
    for i, p in enumerate(PROFILES, 1):
        needs = ["sudo" if p.sudo else "no sudo"]
        if p.os:
            needs.append("debian")
        if p.needs_x11:
            needs.append("x11")
        blocker = profile_blocker(p, s)
        desc = Text(p.summary)
        if blocker:
            desc.append(f"\n{blocker}", style="red dim")
        name = Text(p.key, style="dim strike" if blocker else "cyan")
        row = [name, desc, " · ".join(needs)]
        t.add_row(*([str(i)] if numbered else []), *row)
    return t


# ---------------------------------------------------------------------------
# Running a profile
# ---------------------------------------------------------------------------
# Top-level steps only: nested profiles print indented "· [n/N]" sub-steps.
STEP_RE = re.compile(r"^(?:==>|──) \[(\d+)/(\d+)\]\s*(.*)")  # lib/common.sh log_step
# Trailer appended by run_profile so `logs` can report the real outcome.
TRAILER_RE = re.compile(r"^# dotfiles: exit=(\d+) seconds=([\d.]+)")
LOG_NAME_RE = re.compile(r"^(\d{8}-\d{6})-([a-z]+)$")
# lib/common.sh _log: "HH:MM:SS LEVEL    message" (and the legacy "[LEVEL] message")
LEVEL_RE = re.compile(r"^\s*(?:\d\d:\d\d:\d\d\s+|\[)(WARNING|WARN|ERROR)\]?\s+(.*)")
ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b\][^\x07]*\x07|\r")


@dataclass
class RunResult:
    code: int | None
    seconds: float
    log: Path
    steps: list[str]
    step_total: int
    warnings: list[str]
    errors: list[str]


def _parse_log(path: Path) -> RunResult:
    """Steps, de-duplicated warnings/errors and the recorded outcome of a run.
    code is None for a log without the trailer (interrupted hard, or old)."""
    r = RunResult(None, 0.0, path, [], 0, [], [])
    steps, warnings, errors = r.steps, r.warnings, r.errors
    total = 0
    try:
        raw = path.read_text(errors="replace")
    except OSError:
        return r
    for line in ANSI_RE.sub("", raw).splitlines():
        if t := TRAILER_RE.match(line):
            r.code, r.seconds = int(t.group(1)), float(t.group(2))
        elif m := STEP_RE.search(line):
            steps.append(m.group(3).strip())
            total = int(m.group(2))
        elif m := LEVEL_RE.match(line):
            bucket = warnings if m.group(1).startswith("WARN") else errors
            msg = m.group(2).strip()
            if msg and msg not in bucket:  # profiles nest; the same notice can repeat
                bucket.append(msg)
    r.step_total = total
    return r


def run_profile(p: Profile, flags: list[str]) -> RunResult:
    """Run the profile on the real terminal so sudo and y/N prompts just work,
    while `script` records a full transcript for the summary and `dotfiles logs`."""
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    log = LOG_DIR / f"{datetime.now():%Y%m%d-%H%M%S}-{p.key}.log"
    cmd = ["bash", str(REPO / "profiles" / p.script), *flags]
    env = {**os.environ, "DOTFILES_DIR": str(REPO)}
    start = time.monotonic()
    if shutil.which("script") and sys.stdout.isatty():
        # -e: propagate the child's exit code; -q: no "Script started" banner.
        argv = ["script", "-qefc", shlex.join(cmd), str(log)]
    else:
        argv = cmd
    try:
        code = subprocess.call(argv, env=env)
    except KeyboardInterrupt:
        code = 130
    seconds = time.monotonic() - start
    try:
        with log.open("a") as f:
            f.write(f"\n# dotfiles: exit={code} seconds={seconds:.1f}\n")
    except OSError:
        pass
    result = _parse_log(log)
    result.code, result.seconds = code, seconds
    return result


def summary_panel(p: Profile, r: RunResult) -> Panel:
    ok = r.code == 0
    if r.code is None:
        status = "[yellow]Unknown[/] [dim](run did not finish recording)[/]"
    elif ok:
        status = "[green]Complete[/]"
    elif r.code == 130:
        status = "[yellow]Interrupted[/]"
    else:
        status = f"[red]Failed[/] [dim](exit {r.code})[/]"
    mins, secs = divmod(int(r.seconds), 60)
    lines = [f"[dim]Status:[/]   {status}",
             f"[dim]Duration:[/] [cyan dim]{mins}m {secs:02d}s[/]"]
    if r.step_total:
        lines.append(f"[dim]Steps:[/]    [cyan dim]{len(r.steps)}/{r.step_total}[/]"
                     + (f" [dim]· stopped at[/] {r.steps[-1]}" if not ok and r.steps else ""))
    if r.warnings:
        lines.append(f"[dim]Warnings:[/] [yellow]{len(r.warnings)}[/]")
        lines += [f"  [yellow dim]•[/] [dim]{w[:90]}[/]" for w in r.warnings[:5]]
        if len(r.warnings) > 5:
            lines.append(f"  [dim]… {len(r.warnings) - 5} more in the log[/]")
    if r.errors:
        lines.append(f"[dim]Errors:[/]   [red]{len(r.errors)}[/]")
        lines += [f"  [red dim]•[/] [dim]{e[:90]}[/]" for e in r.errors[:5]]
    if r.log.exists():
        lines.append(f"[dim]Log:[/]      [magenta dim]{tilde(r.log)}[/]")
    return Panel("\n".join(lines), title=f"[bold]{p.title.upper()}[/]", title_align="left",
                 border_style="green dim" if ok else "red dim", padding=(0, 1), box=box.ROUNDED)


def choose_shell() -> str:
    t = Table(title=Align.left("[bold]Interactive shell[/]"), box=box.ROUNDED, padding=(0, 2), show_header=True,
              header_style="bold")
    t.add_column("#", style="dim", justify="right")
    t.add_column("Shell", style="cyan")
    t.add_column("Use for", style="white")
    t.add_row("1", "bash", "robot-env (robot workstations) — already the login shell, no chsh")
    t.add_row("2", "zsh", "everything else — oh-my-zsh + plugins, chsh at the end")
    console.print(t)
    pick = IntPrompt.ask("Enter selection \\[#]", choices=["1", "2"], show_choices=False, default=1, console=console)
    return "zsh" if pick == 2 else "bash"


def do_install(p: Profile, shell: str | None, dry_run: bool, yes: bool) -> int:
    s = detect_system()
    if blocker := profile_blocker(p, s):
        console.print(f"[red]Cannot run[/] [cyan]{p.key}[/]: {blocker}")
        return 1

    console.print(Panel(f"{p.summary}\n[dim]{'Requires sudo · ' if p.sudo else ''}existing configs are backed up "
                        f"with a timestamp{' · DRY RUN, nothing will change' if dry_run else ''}[/]",
                        title=f"[bold]{p.title}[/]", title_align="left", border_style="dim", box=box.ROUNDED,
                        padding=(0, 1)))
    if not yes and not Confirm.ask("Continue?", default=False, console=console):
        console.print("[dim]Cancelled.[/]")
        return 0

    flags: list[str] = []
    if dry_run:
        flags.append("--dry-run")
    if yes:
        flags.append("--non-interactive")
    if p.asks_shell:
        if shell is None:
            shell = "bash" if yes else choose_shell()
        flags.append(f"--shell={shell}")

    console.rule(f"[dim]{p.script} {' '.join(flags)}[/]", style="dim")
    result = run_profile(p, flags)
    console.rule(style="dim")
    console.print(summary_panel(p, result))
    return result.code


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------
@click.group(invoke_without_command=True, context_settings=dict(help_option_names=["-h", "--help"]))
@click.option("--dry-run", is_flag=True, help="Preview: profiles print what they would do.")
@click.pass_context
def cli(ctx: click.Context, dry_run: bool) -> None:
    """Install and inspect this machine's dotfiles."""
    ctx.obj = {"dry_run": dry_run}
    if ctx.invoked_subcommand is not None:
        return
    # Bare `dotfiles`: the overview, then a rai-ledger style numbered menu.
    s = detect_system()
    table = profiles_table(s, numbered=True)
    width = console.measure(table).maximum
    console.print(Group(table, footer(s, "DOTFILES", width)))
    if not sys.stdin.isatty():
        return
    valid = [str(i) for i, p in enumerate(PROFILES, 1) if not profile_blocker(p, s)]
    try:
        n = IntPrompt.ask("Enter selection \\[#] [dim](Ctrl+C to quit)[/]", choices=valid, show_choices=False,
                          console=console)
    except (KeyboardInterrupt, EOFError):
        console.print()
        return
    ctx.exit(do_install(PROFILES[n - 1], None, dry_run, yes=False))


@cli.command()
@click.option("--links/--no-links", default=True, help="Show config symlinks.")
@click.option("--tools/--no-tools", default=True, help="Show tool availability.")
def status(links: bool, tools: bool) -> None:
    """Show what is linked, what is installed, and system info."""
    s = detect_system()
    parts = []
    if links:
        parts.append(links_table(s))
    if tools:
        parts.append(tools_table())
    width = max((console.measure(p).maximum for p in parts), default=60)
    console.print(Group(*parts, footer(s, "DOTFILES", width)))


@cli.command("profiles")
def profiles_cmd() -> None:
    """List install profiles and what they need."""
    console.print(profiles_table(detect_system()))


@cli.command()
@click.argument("profile", type=click.Choice([p.key for p in PROFILES], case_sensitive=False))
@click.option("--shell", type=click.Choice(["bash", "zsh"]), help="Interactive shell (asked if omitted).")
@click.option("--dry-run", is_flag=True, help="Show what would change without changing it.")
@click.option("-y", "--yes", is_flag=True, help="No prompts: accept defaults (bash, no optional extras).")
@click.pass_context
def install(ctx: click.Context, profile: str, shell: str | None, dry_run: bool, yes: bool) -> None:
    """Run an install PROFILE (terminal, desktop, vm, bar)."""
    ctx.exit(do_install(BY_KEY[profile.lower()], shell, dry_run or ctx.obj["dry_run"], yes))


@cli.command()
@click.option("-n", "--count", default=10, show_default=True, help="How many logs to list.")
@click.option("--show", "show", is_flag=True, help="Print the summary of the most recent run.")
def logs(count: int, show: bool) -> None:
    """List recent install logs."""
    # Only files this CLI wrote ("YYYYmmdd-HHMMSS-<profile>.log"); anything
    # else dropped in the directory is ignored rather than crashing the table.
    files = sorted((f for f in LOG_DIR.glob("*.log") if LOG_NAME_RE.match(f.stem)), reverse=True)
    if not files:
        console.print(f"[dim]No install logs yet in[/] {tilde(LOG_DIR)}")
        return
    if show:
        latest = files[0]
        key = LOG_NAME_RE.match(latest.stem).group(2)
        console.print(summary_panel(BY_KEY.get(key, PROFILES[0]), _parse_log(latest)))
        return
    t = Table(title=Align.left("[bold]Install logs[/]"), box=box.ROUNDED, padding=(0, 1), header_style="bold")
    t.add_column("When", style="cyan", no_wrap=True)
    t.add_column("Profile", style="white")
    t.add_column("Result", no_wrap=True)
    t.add_column("Steps", justify="right", style="dim")
    t.add_column("Warn", justify="right")
    t.add_column("Err", justify="right")
    t.add_column("Log", style="dim", overflow="fold")
    for f in files[:count]:
        stamp, key = LOG_NAME_RE.match(f.stem).groups()
        r = _parse_log(f)
        when = datetime.strptime(stamp, "%Y%m%d-%H%M%S").strftime("%Y-%m-%d %H:%M")
        if r.code is None:
            result = Text("unknown", style="yellow dim")
        elif r.code == 0:
            result = Text("ok", style="green")
        else:
            result = Text(f"exit {r.code}", style="red")
        t.add_row(when, key, result, f"{len(r.steps)}/{r.step_total}" if r.step_total else "—",
                  Text(str(len(r.warnings)), style="yellow" if r.warnings else "dim"),
                  Text(str(len(r.errors)), style="red" if r.errors else "dim"), f.name)
    console.print(t)
    console.print(f"[dim]in {tilde(LOG_DIR)} · `dotfiles logs --show` for the latest summary[/]")


def main() -> None:
    cli(prog_name="dotfiles")


if __name__ == "__main__":
    main()
