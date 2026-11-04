#!/usr/bin/env -S python3 -I -S
"""cmux DevBox: report what a coding agent is doing to the cmux sidebar.

Install as a Claude Code / Codex hook for UserPromptSubmit, PostToolUse,
PermissionRequest, Notification, Stop, SessionStart and SessionEnd. The hook
JSON arrives on stdin; the optional first argument names the agent
(`claude`, `codex`).

It writes an OSC 777 notification titled `cmux-devbox-claude-usage` (the
DevBox report channel) straight to the terminal the agent is drawing on:

    v1 ev=agent st=<working|waiting|done|ended> at=<epoch> agent=<kind>
       who=<account> d=<dir> t=<prompt>          (d and t percent-encoded)

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

PERMISSION_NOTIFICATIONS = {"permission_prompt", "elicitation_dialog"}


def state_for(event, payload):
    """Maps a hook event to (state, title-or-None); None to skip."""
    if event == "UserPromptSubmit":
        return "working", str(payload.get("prompt") or "")
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
    if event == "Stop":
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


def build_body(state, at, agent, who, directory, title):
    parts = ["v1", "ev=agent", f"st={state}", f"at={int(at)}"]
    if clean_name(agent):
        parts.append(f"agent={clean_name(agent)}")
    if clean_name(who):
        parts.append(f"who={clean_name(who)}")
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
    since = previous.get("since", now) if previous.get("state") == state else now
    if (previous.get("state") == state and previous.get("title") == title
            and now - int(previous.get("sent", 0)) < RESEND_SECONDS):
        return

    who = os.environ.get("CLAUDE_AS_NAME") or os.environ.get("CMUX_DEVBOX_WHO") or os.environ.get("USER", "")
    directory = os.path.basename(str(payload.get("cwd") or os.getcwd()).rstrip("/"))
    body = build_body(state, since, agent, who, directory, title)
    try:
        with open(tty, "a", encoding="utf-8") as handle:
            handle.write(build_sequence(body, bool(os.environ.get("TMUX"))))
    except OSError:
        return
    try:
        os.makedirs(base, mode=0o700, exist_ok=True)
        with open(path, "w", encoding="utf-8") as handle:
            json.dump({"state": state, "title": title, "since": since, "sent": now}, handle)
    except OSError:
        pass


if __name__ == "__main__":
    try:
        main()
    except Exception:  # a hook must never break the agent
        pass
