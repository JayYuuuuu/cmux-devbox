#!/usr/bin/env -S python3 -I -S
"""cmux DevBox: report what a coding agent is doing to the cmux sidebar.

Install as a Claude Code / Codex hook for UserPromptSubmit, PostToolUse,
PermissionRequest, Notification, Stop, StopFailure, SessionStart and
SessionEnd. The hook
JSON arrives on stdin; the optional first argument names the agent
(`claude`, `codex`).

It writes an OSC 777 notification titled `cmux-devbox-claude-usage` (the
DevBox report channel) straight to the terminal the agent is drawing on:

    v1 ev=agent st=<working|waiting|done|ended> at=<epoch> agent=<kind>
       who=<account> bg=<n> d=<dir> t=<prompt>   (d and t percent-encoded)

`bg` counts the Claude Code background shells still running (omitted at 0);
`cx` counts the Codex runs Claude started and `cxs` is when the earliest
began (both omitted at 0).

cmux DevBox 0.64.25-devbox.20+ stores it for custom sidebars; older DevBox
builds drop it silently. Other terminals would show it as a notification, so
only enable this where everyone runs DevBox.

Inside tmux the sequence is wrapped for passthrough (`allow-passthrough on`).
The account label is $CLAUDE_AS_NAME, falling back to $CMUX_DEVBOX_WHO, then
$USER. A report is written only when the state or prompt changes, or every
RESEND_SECONDS, so tool-heavy turns stay quiet. Never fails the hook.
"""
import json
import os
import re
import sys
import time
import urllib.parse

TITLE = "cmux-devbox-claude-usage"
RESEND_SECONDS = 600
MAX_TEXT = 120
# Ghostty hands notification bodies to the app in a 255-byte buffer and cuts
# the rest; a cut percent-escape would not decode, so stay under it.
MAX_BODY_BYTES = 250

PERMISSION_NOTIFICATIONS = {"permission_prompt", "elicitation_dialog"}


def state_for(event, payload):
    """Maps a hook event to (state, title-or-None); None to skip."""
    if event == "UserPromptSubmit":
        prompt = str(payload.get("prompt") or "")
        # Claude Code injects background-task results as a prompt; keep the
        # user's own prompt as the title.
        if prompt.lstrip().startswith("<task-notification"):
            return "working", None
        return "working", prompt
    if event == "PostToolUse":
        return "working", None
    if event == "PermissionRequest":
        return "waiting", None
    if event == "Notification":
        kind = str(payload.get("notification_type") or "")
        message = str(payload.get("message") or "").lower()
        if kind in PERMISSION_NOTIFICATIONS or (not kind and "permission" in message):
            return "waiting", None
        return None
    if event in ("Stop", "StopFailure"):
        return "done", None
    if event == "SessionStart":
        return "done", ""
    if event == "SessionEnd":
        return "ended", None
    return None


def clean(text):
    text = re.sub(r"[\x00-\x1f\x7f]+", " ", str(text))
    text = re.sub(r"\s+", " ", text).strip()
    return text[:MAX_TEXT]


def clean_name(raw):
    return re.sub(r"[\s=;\x00-\x1f\x7f]", "", str(raw or ""))[:24]


def build_body(state, at, agent, who, directory, title, bg=0, cx=0, cxs=0):
    """Body that fits MAX_BODY_BYTES: the prompt is shortened first, then the directory."""
    title = clean(title)
    directory = clean(directory)
    while True:
        body = _body(state, at, agent, who, directory, title, bg, cx, cxs)
        if len(body.encode("utf-8")) <= MAX_BODY_BYTES:
            return body
        if title:
            title = title[:-1]
        elif directory:
            directory = directory[:-1]
        else:
            return body


def _body(state, at, agent, who, directory, title, bg=0, cx=0, cxs=0):
    parts = ["v1", "ev=agent", f"st={state}", f"at={int(at)}"]
    if clean_name(agent):
        parts.append(f"agent={clean_name(agent)}")
    if clean_name(who):
        parts.append(f"who={clean_name(who)}")
    if bg > 0:
        parts.append(f"bg={int(bg)}")
    if cx > 0:
        parts.append(f"cx={int(cx)}")
        if cxs > 0:
            parts.append(f"cxs={int(cxs)}")
    if directory:
        parts.append("d=" + urllib.parse.quote(clean(directory), safe="-._~"))
    if title:
        parts.append("t=" + urllib.parse.quote(clean(title), safe="-._~"))
    return " ".join(parts)


def build_sequence(body, in_tmux):
    osc = f"\x1b]777;notify;{TITLE};{body}\x07"
    if not in_tmux:
        return osc
    return "\x1bPtmux;" + osc.replace("\x1b", "\x1b\x1b") + "\x1b\\"


def parent_of(pid):
    with open(f"/proc/{pid}/stat", encoding="utf-8") as handle:
        stat = handle.read()
    return int(stat[stat.rindex(")") + 2:].split(" ")[1])


def find_agent_pid(agent):
    """The agent process this hook runs under (nearest ancestor named like it)."""
    pid = os.getppid()
    for _ in range(16):
        if pid <= 1:
            return None
        try:
            with open(f"/proc/{pid}/comm", encoding="utf-8") as handle:
                if handle.read().strip() == agent:
                    return pid
            pid = parent_of(pid)
        except (OSError, ValueError, IndexError):
            return None
    return None


def count_background_shells(agent_pid, own_ancestors):
    """Claude Code runs Bash tool calls as `<shell> -c source …/shell-snapshots/…`
    children. Hooks fire when no foreground tool call is running, so the ones
    still alive are background shells."""
    if not agent_pid:
        return 0
    count = 0
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        pid = int(entry)
        if pid in own_ancestors:
            continue
        try:
            if parent_of(pid) != agent_pid:
                continue
            with open(f"/proc/{pid}/cmdline", "rb") as handle:
                cmdline = handle.read()
        except (OSError, ValueError, IndexError):
            continue
        if b"shell-snapshots" in cmdline:
            count += 1
    return count


def _proc_table():
    """pid -> (ppid, comm, start epoch) for every visible process."""
    table = {}
    try:
        with open("/proc/stat", encoding="utf-8") as handle:
            btime = next(int(line.split()[1]) for line in handle if line.startswith("btime "))
        ticks = os.sysconf("SC_CLK_TCK")
    except (OSError, StopIteration, ValueError):
        btime, ticks = 0, 100
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/stat", encoding="utf-8") as handle:
                stat = handle.read()
        except OSError:
            continue
        comm = stat[stat.index("(") + 1:stat.rindex(")")]
        fields = stat[stat.rindex(")") + 2:].split(" ")
        try:
            table[int(entry)] = (int(fields[1]), comm, btime + int(fields[19]) // ticks)
        except (IndexError, ValueError):
            continue
    return table


def count_codex_runs(agent_pid):
    """Codex runs Claude Code started (`codex exec` from a Bash call): the
    outermost `codex` processes below the Claude process. Returns the count
    and the earliest start time (epoch seconds, 0 when none)."""
    if not agent_pid:
        return 0, 0
    table = _proc_table()
    count, earliest = 0, 0
    for pid, (_ppid, comm, started) in table.items():
        if comm != "codex":
            continue
        cursor, outermost = table[pid][0], True
        for _ in range(32):
            if cursor == agent_pid or cursor <= 1 or cursor not in table:
                break
            if table[cursor][1] == "codex":
                outermost = False
                break
            cursor = table[cursor][0]
        if outermost and cursor == agent_pid:
            count += 1
            earliest = started if not earliest else min(earliest, started)
    return count, earliest


def ancestors():
    out = set()
    pid = os.getpid()
    for _ in range(32):
        out.add(pid)
        if pid <= 1:
            break
        try:
            pid = parent_of(pid)
        except (OSError, ValueError, IndexError):
            break
    return out


def find_terminal():
    """The terminal the agent renders on: the first ancestor whose stdin is a pty."""
    pid = os.getppid()
    for _ in range(16):
        if pid <= 1:
            return None
        try:
            target = os.readlink(f"/proc/{pid}/fd/0")
            if re.match(r"^/dev/(pts/\d+|tty\w*)$", target):
                return target
            with open(f"/proc/{pid}/stat", encoding="utf-8") as handle:
                stat = handle.read()
            pid = int(stat[stat.rindex(")") + 2:].split(" ")[1])
        except (OSError, ValueError, IndexError):
            return None
    return None


def state_path(tty, session):
    base = os.path.join("/tmp", f"cmux-agent-activity-{os.getuid()}")
    key = re.sub(r"[^A-Za-z0-9_.-]", "_", f"{tty}-{session}") or "default"
    return base, os.path.join(base, key)


def main():
    agent = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except ValueError:
        return
    if not isinstance(payload, dict):
        return
    mapped = state_for(str(payload.get("hook_event_name") or ""), payload)
    if not mapped:
        return
    state, title = mapped
    # A Codex run that Claude Code started (`codex exec` from a Bash tool
    # call) shares Claude's terminal; reporting it would overwrite the Claude
    # session's own status with the helper's.
    if agent != "claude" and find_agent_pid("claude"):
        return
    tty = find_terminal()
    if not tty:
        return

    base, path = state_path(tty, payload.get("session_id") or "")
    now = int(time.time())
    previous = {}
    try:
        with open(path, encoding="utf-8") as handle:
            previous = json.load(handle)
    except (OSError, ValueError):
        pass
    if title is None:
        title = previous.get("title", "")
    title = clean(title)
    agent_pid = find_agent_pid(agent) if agent == "claude" else None
    bg = count_background_shells(agent_pid, ancestors()) if agent_pid else 0
    cx, cxs = count_codex_runs(agent_pid) if agent_pid else (0, 0)
    since = previous.get("since", now) if previous.get("state") == state else now
    if (previous.get("state") == state and previous.get("title") == title
            and previous.get("bg", 0) == bg
            and previous.get("cx", 0) == cx
            and now - int(previous.get("sent", 0)) < RESEND_SECONDS):
        return

    who = os.environ.get("CLAUDE_AS_NAME") or os.environ.get("CMUX_DEVBOX_WHO") or os.environ.get("USER", "")
    directory = os.path.basename(str(payload.get("cwd") or os.getcwd()).rstrip("/"))
    body = build_body(state, since, agent, who, directory, title, bg, cx, cxs)
    try:
        with open(tty, "a", encoding="utf-8") as handle:
            handle.write(build_sequence(body, bool(os.environ.get("TMUX"))))
    except OSError:
        return
    try:
        os.makedirs(base, mode=0o700, exist_ok=True)
        with open(path, "w", encoding="utf-8") as handle:
            json.dump({"state": state, "title": title, "since": since, "bg": bg, "cx": cx, "sent": now}, handle)
    except OSError:
        pass


if __name__ == "__main__":
    try:
        main()
    except Exception:  # a hook must never break the agent
        pass
