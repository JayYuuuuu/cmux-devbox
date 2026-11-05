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

Every hook run (from either agent) also forwards the Codex account's quota,
read from the newest Codex session log, on the same channel:

    cx1 plan=<plan> h5=<pct> h5r=<epoch> d7=<pct> d7r=<epoch> ob=<epoch>

Codex says how long each window is: 300 minutes maps to `h5`, a week to `d7`
(Pro plans only have the weekly one). DevBox 0.64.25-devbox.29+ shows it;
older builds drop it silently.

The same report carries the account's usage limit resets ("reset cards"):
`rs=<n> rx=<expiry epoch>,...`. The session log does not record them, so a
detached child asks Codex's own app-server (`account/rateLimits/read`, the
same read-only call as Codex's usage menu) at most every RESETS_REFRESH
seconds and caches the answer; the hook itself never waits for it.
DevBox 0.64.25-devbox.34+ shows them; older builds ignore the fields.

cmux DevBox 0.64.25-devbox.20+ stores it for custom sidebars; older DevBox
builds drop it silently. Other terminals would show it as a notification, so
only enable this where everyone runs DevBox.

Inside tmux the sequence is wrapped for passthrough (`allow-passthrough on`).
The account label is $CLAUDE_AS_NAME, falling back to $CMUX_DEVBOX_WHO, then
$USER. A report is written only when the state or prompt changes, or every
RESEND_SECONDS, so tool-heavy turns stay quiet. Never fails the hook.
"""
import calendar
import json
import os
import re
import subprocess
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


def _claude_pid_env(pid):
    """CLAUDE_PID from a process environment (Claude Code exports it to every
    Bash call), or 0. Detached runs (`nohup … &`, `setsid`) are re-parented to
    init, so this is the only link back to the Claude that started them."""
    try:
        with open(f"/proc/{pid}/environ", "rb") as handle:
            for item in handle.read().split(b"\0"):
                if item.startswith(b"CLAUDE_PID="):
                    return int(item[11:] or 0)
    except (OSError, ValueError):
        pass
    return 0


def count_codex_runs(agent_pid):
    """Codex runs Claude Code started (`codex exec` from a Bash call): the
    outermost `codex` processes below the Claude process, or detached ones
    whose environment names it. Returns the count and the earliest start time
    (epoch seconds, 0 when none)."""
    if not agent_pid:
        return 0, 0
    table = _proc_table()
    count, earliest = 0, 0
    for pid, (ppid, comm, started) in table.items():
        if comm != "codex" or table.get(ppid, (0, ""))[1] == "codex":
            continue
        cursor = ppid
        for _ in range(32):
            if cursor == agent_pid or cursor <= 1 or cursor not in table:
                break
            if table[cursor][1] == "codex":
                break
            cursor = table[cursor][0]
        if cursor in table and table[cursor][1] == "codex":
            continue  # nested below another Codex
        if cursor == agent_pid or _claude_pid_env(pid) == agent_pid:
            count += 1
            earliest = started if not earliest else min(earliest, started)
    return count, earliest


CODEX_WINDOWS = {300: "h5", 10080: "d7"}
CODEX_TAIL_BYTES = 256 * 1024
RESETS_REFRESH = 1800        # ask for reset cards at most this often
RESETS_RETRY = 300           # after a failed ask
RESETS_MAX_AGE = 12 * 3600   # older answers are not forwarded
RESETS_TIMEOUT = 20
RESETS_MAX = 16


def newest_codex_log(root):
    """Newest rollout log in the two latest day folders of ~/.codex/sessions."""
    days = []
    try:
        for year in sorted(os.listdir(root), reverse=True):
            for month in sorted(os.listdir(os.path.join(root, year)), reverse=True):
                for day in sorted(os.listdir(os.path.join(root, year, month)), reverse=True):
                    days.append(os.path.join(root, year, month, day))
                    if len(days) >= 2:
                        raise StopIteration
    except StopIteration:
        pass
    except OSError:
        return None
    best = None
    for folder in days:
        try:
            names = os.listdir(folder)
        except OSError:
            continue
        for name in names:
            if not name.endswith(".jsonl"):
                continue
            full = os.path.join(folder, name)
            try:
                mtime = os.path.getmtime(full)
            except OSError:
                continue
            if best is None or mtime > best[0]:
                best = (mtime, full)
    return best[1] if best else None


def codex_usage_body(rate_limits, observed):
    """`cx1` report from a Codex `rate_limits` object, or None without windows."""
    if not isinstance(rate_limits, dict):
        return None
    windows = {}
    for slot in ("primary", "secondary"):
        win = rate_limits.get(slot)
        if not isinstance(win, dict):
            continue
        key = CODEX_WINDOWS.get(win.get("window_minutes"))
        pct = win.get("used_percent")
        if not key or not isinstance(pct, (int, float)) or key in windows:
            continue
        windows[key] = (max(0, min(100, round(pct))), win.get("resets_at"))
    if not windows:
        return None
    parts = ["cx1"]
    plan = re.sub(r"[^A-Za-z0-9_-]", "", str(rate_limits.get("plan_type") or ""))[:16]
    if plan:
        parts.append(f"plan={plan}")
    for key in ("h5", "d7"):
        if key in windows:
            pct, reset = windows[key]
            parts.append(f"{key}={pct}")
            if isinstance(reset, (int, float)) and reset > 0:
                parts.append(f"{key}r={int(reset)}")
    if observed:
        parts.append(f"ob={int(observed)}")
    return " ".join(parts)


def latest_codex_usage(path):
    """(rate_limits, observed epoch) from the last quota line of a rollout log."""
    try:
        with open(path, "rb") as handle:
            handle.seek(0, os.SEEK_END)
            size = handle.tell()
            handle.seek(max(0, size - CODEX_TAIL_BYTES))
            chunk = handle.read().decode("utf-8", "replace")
    except OSError:
        return None
    lines = chunk.splitlines()
    if size > CODEX_TAIL_BYTES:
        lines = lines[1:]  # the first line is cut
    for line in reversed(lines):
        if '"rate_limits"' not in line:
            continue
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        limits = (entry.get("payload") or {}).get("rate_limits")
        if not isinstance(limits, dict) or not (limits.get("primary") or limits.get("secondary")):
            continue
        observed = 0
        stamp = str(entry.get("timestamp") or "")
        try:
            observed = calendar.timegm(time.strptime(stamp[:19], "%Y-%m-%dT%H:%M:%S"))
        except ValueError:
            observed = int(os.path.getmtime(path))
        return limits, observed
    return None


def codex_binary():
    """The vendor Codex CLI (wrappers pass `app-server` straight through)."""
    for name in (os.environ.get("CMUX_DEVBOX_CODEX"), os.path.expanduser("~/.npm-global/bin/codex"),
                 os.path.expanduser("~/.local/bin/codex"), "/usr/local/bin/codex", "/usr/bin/codex"):
        if name and os.access(name, os.X_OK):
            return name
    return None


def parse_reset_credits(result):
    """(count, sorted expiries) from an `account/rateLimits/read` result, or None."""
    if not isinstance(result, dict):
        return None
    credits = result.get("rateLimitResetCredits")
    if not isinstance(credits, dict):
        return None
    listed = [c for c in credits.get("credits") or [] if isinstance(c, dict)]
    usable = [c for c in listed if c.get("status") in (None, "available")]
    count = credits.get("availableCount")
    if not isinstance(count, int) or count < 0:
        count = len(usable)
    expiries = sorted(int(c["expiresAt"]) for c in usable
                      if isinstance(c.get("expiresAt"), (int, float)) and c["expiresAt"] > 0)
    count = min(count, RESETS_MAX)
    return count, expiries[:count]


def ask_reset_credits():
    """Runs `codex app-server` once and returns parse_reset_credits() of its answer."""
    binary = codex_binary()
    if not binary:
        return None
    requests = [
        {"jsonrpc": "2.0", "id": 1, "method": "initialize",
         "params": {"clientInfo": {"name": "cmux-devbox-panel", "version": "1"}}},
        {"jsonrpc": "2.0", "method": "initialized"},
        {"jsonrpc": "2.0", "id": 2, "method": "account/rateLimits/read"},
    ]
    proc = subprocess.Popen([binary, "app-server"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=subprocess.DEVNULL, cwd="/tmp")
    try:
        proc.stdin.write("".join(json.dumps(r) + "\n" for r in requests).encode())
        proc.stdin.flush()
        deadline = time.time() + RESETS_TIMEOUT
        while time.time() < deadline:
            line = proc.stdout.readline()
            if not line:
                return None
            try:
                message = json.loads(line)
            except ValueError:
                continue
            if isinstance(message, dict) and message.get("id") == 2:
                return parse_reset_credits(message.get("result"))
        return None
    finally:
        try:
            proc.kill()
            proc.wait(timeout=5)
        except Exception:
            pass


def refresh_reset_credits(base):
    """Child entry point: asks once and caches the answer; keeps the last good one on failure."""
    path = os.path.join(base, "codex-resets.json")
    cached = {}
    try:
        with open(path, encoding="utf-8") as handle:
            cached = json.load(handle)
    except (OSError, ValueError):
        pass
    now = int(time.time())
    found = None
    try:
        found = ask_reset_credits()
    except Exception:
        found = None
    if found:
        cached = {"asked": now, "ok": now, "count": found[0], "expiries": found[1]}
    else:
        cached["asked"] = now
        cached["failed"] = True
    os.makedirs(base, mode=0o700, exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as handle:
        json.dump(cached, handle)
    os.replace(tmp, path)


def cached_reset_credits(base):
    """The cached reset cards (count, expiries), starting a refresh in the background when due."""
    path = os.path.join(base, "codex-resets.json")
    cached = {}
    try:
        with open(path, encoding="utf-8") as handle:
            cached = json.load(handle)
    except (OSError, ValueError):
        pass
    now = int(time.time())
    asked = int(cached.get("asked") or 0)
    due = now - asked >= (RESETS_RETRY if cached.get("failed") else RESETS_REFRESH)
    if due:
        lock = os.path.join(base, "codex-resets.lock")
        try:
            os.makedirs(base, mode=0o700, exist_ok=True)
            if os.path.exists(lock) and now - os.path.getmtime(lock) > RESETS_TIMEOUT * 3:
                os.unlink(lock)  # a child that died without cleaning up
            fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
            os.close(fd)
            subprocess.Popen([sys.executable, "-I", "-S", os.path.abspath(__file__), "--refresh-resets"],
                             stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL, start_new_session=True, close_fds=True)
        except OSError:
            pass
    ok = int(cached.get("ok") or 0)
    if not ok or now - ok > RESETS_MAX_AGE or not isinstance(cached.get("count"), int):
        return None
    expiries = [int(e) for e in cached.get("expiries") or [] if isinstance(e, (int, float)) and e > now]
    gone = len([e for e in cached.get("expiries") or [] if isinstance(e, (int, float)) and 0 < e <= now])
    return max(0, cached["count"] - gone), expiries


def reset_credits_fields(credits):
    if not credits:
        return ""
    count, expiries = credits
    out = f" rs={count}"
    if expiries:
        out += " rx=" + ",".join(str(e) for e in expiries[:count])
    return out


def report_codex_usage(tty, base):
    """Forwards the Codex quota when it changed, or every RESEND_SECONDS."""
    root = os.path.join(os.environ.get("CODEX_HOME") or os.path.expanduser("~/.codex"), "sessions")
    log = newest_codex_log(root)
    found = latest_codex_usage(log) if log else None
    body = codex_usage_body(*found) if found else None
    if not body:
        return
    body += reset_credits_fields(cached_reset_credits(base))
    path = os.path.join(base, "codex-usage-" + (re.sub(r"[^A-Za-z0-9_.-]", "_", tty) or "default"))
    now = int(time.time())
    # Compare without the observed time, which moves on every Codex turn.
    stable = re.sub(r" ob=\d+", "", body)
    try:
        with open(path, encoding="utf-8") as handle:
            sent_at, previous = handle.read().split("\n", 1)
        if previous == stable and now - int(sent_at) < RESEND_SECONDS:
            return
    except (OSError, ValueError):
        pass
    try:
        with open(tty, "a", encoding="utf-8") as handle:
            handle.write(build_sequence(body, bool(os.environ.get("TMUX"))))
    except OSError:
        return
    try:
        os.makedirs(base, mode=0o700, exist_ok=True)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(f"{now}\n{stable}")
    except OSError:
        pass


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
    tty = find_terminal()
    if not tty:
        return
    base, path = state_path(tty, payload.get("session_id") or "")
    try:
        report_codex_usage(tty, base)
    except Exception:  # the activity report below must still go out
        pass
    # A Codex run that Claude Code started (`codex exec` from a Bash tool
    # call) shares Claude's terminal; reporting it would overwrite the Claude
    # session's own status with the helper's.
    if agent != "claude" and find_agent_pid("claude"):
        return
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
    if sys.argv[1:] == ["--refresh-resets"]:
        base = os.path.join("/tmp", f"cmux-agent-activity-{os.getuid()}")
        try:
            refresh_reset_credits(base)
        finally:
            try:
                os.unlink(os.path.join(base, "codex-resets.lock"))
            except OSError:
                pass
        sys.exit(0)
    try:
        main()
    except Exception:  # a hook must never break the agent
        pass
