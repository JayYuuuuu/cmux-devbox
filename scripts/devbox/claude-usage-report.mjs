#!/usr/bin/env node
// cmux DevBox: report Claude Code subscription usage to the cmux sidebar.
//
// Run from a Claude Code statusLine command with the statusline JSON on
// stdin. Reads `rate_limits.five_hour` / `rate_limits.seven_day`, then writes
// an OSC 777 notification titled `cmux-devbox-claude-usage` straight to the
// terminal Claude Code is drawing on. cmux DevBox turns it into a usage
// badge under the workspace; other terminals ignore or never see it.
//
//   statusline:  input=$(cat)
//                printf '%s' "$input" | node claude-usage-report.mjs &
//
// Inside tmux the sequence is wrapped for passthrough, which requires
// `set -g allow-passthrough on`. The account label is $CLAUDE_USAGE_WHO,
// falling back to $CLAUDE_AS_NAME, then $USER. $CLAUDE_USAGE_LABEL is an
// optional display name (spaces allowed) shown as the sidebar card title; the
// email is the one Claude Code logged in with (`.claude.json` in
// $CLAUDE_CONFIG_DIR, else the home directory), falling back to
// $CLAUDE_USAGE_EMAIL. $CLAUDE_USAGE_PAYER (the account paying for the
// subscription, spaces allowed), $CLAUDE_USAGE_SUBSCRIBED (yyyy-mm-dd) and
// $CLAUDE_USAGE_CYCLE (m / y, also 月 / 年) feed the card's payment line.
// Identical reports are sent at
// most every RESEND_SECONDS per Claude session so the terminal stays quiet.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const TITLE = 'cmux-devbox-claude-usage';
const RESEND_SECONDS = 300;

function readStdin() {
  try { return fs.readFileSync(0, 'utf8'); } catch { return ''; }
}

function pct(win) {
  const v = win?.used_percentage;
  return typeof v === 'number' && Number.isFinite(v) ? Math.max(0, Math.min(100, Math.round(v))) : null;
}

function reset(win) {
  const v = win?.resets_at;
  return typeof v === 'number' && Number.isFinite(v) && v > 0 ? Math.floor(v) : null;
}

function cleanName(raw) {
  return String(raw ?? '').replace(/[\s=;\x00-\x1f\x7f]/g, '').slice(0, 24);
}

function cleanLabel(raw) {
  const s = String(raw ?? '').replace(/[\x00-\x1f\x7f]/g, ' ').replace(/\s+/g, ' ').trim();
  return [...s].slice(0, 24).join('').trim();
}

function cleanEmail(raw) {
  return String(raw ?? '').replace(/[\s=;\x00-\x1f\x7f]/g, '').slice(0, 64);
}

// The email of the account this Claude Code session is logged in with.
function loginEmail() {
  const dir = process.env.CLAUDE_CONFIG_DIR;
  const file = dir ? path.join(dir, '.claude.json') : path.join(os.homedir(), '.claude.json');
  try {
    const email = JSON.parse(fs.readFileSync(file, 'utf8'))?.oauthAccount?.emailAddress;
    return typeof email === 'string' ? email : '';
  } catch { return ''; }
}

const MAX_BODY = 250; // Ghostty caps a notification body at 255 bytes

function encodedText(raw, maxEncoded) {
  let chars = [...cleanLabel(raw)];
  while (chars.length && encodeURIComponent(chars.join('')).length > maxEncoded) chars.pop();
  const text = chars.join('').trim();
  return text ? encodeURIComponent(text) : '';
}

function cleanCycle(raw) {
  const v = String(raw ?? '').trim().toLowerCase();
  if (['y', 'year', 'yearly', 'annual', '年', '每年', '年付'].includes(v)) return 'y';
  if (['m', 'month', 'monthly', '月', '每月', '月付'].includes(v)) return 'm';
  return '';
}

export function buildBody(input, who, label = '', email = '', sub = {}) {
  const limits = input?.rate_limits;
  const h5 = pct(limits?.five_hour);
  const d7 = pct(limits?.seven_day);
  if (h5 === null && d7 === null) return null;
  const parts = ['v1'];
  const name = cleanName(who);
  if (name) parts.push(`who=${name}`);
  // Optional fields, dropped from the end of this list if the body runs long.
  const optional = [];
  const lb = encodedText(label, 72);
  if (lb) optional.push(`lb=${lb}`);
  const em = cleanEmail(email);
  if (em) optional.push(`em=${em}`);
  const pe = encodedText(sub.payer, 72);
  if (pe) optional.push(`pe=${pe}`);
  const ps = String(sub.subscribed ?? '').trim();
  if (/^\d{4}-\d{2}-\d{2}$/.test(ps)) optional.push(`ps=${ps}`);
  const pc = cleanCycle(sub.cycle);
  if (pc) optional.push(`pc=${pc}`);
  const windows = [];
  if (h5 !== null) {
    windows.push(`h5=${h5}`);
    const r = reset(limits.five_hour);
    if (r) windows.push(`h5r=${r}`);
  }
  if (d7 !== null) {
    windows.push(`d7=${d7}`);
    const r = reset(limits.seven_day);
    if (r) windows.push(`d7r=${r}`);
  }
  const join = () => [...parts, ...optional, ...windows].join(' ');
  // Drop the payment note first, then the email, then the label.
  for (const key of ['pc=', 'ps=', 'pe=', 'em=', 'lb=']) {
    if (join().length <= MAX_BODY) break;
    const i = optional.findIndex((f) => f.startsWith(key));
    if (i >= 0) optional.splice(i, 1);
  }
  return join();
}

export function buildSequence(body, inTmux) {
  const osc = `\x1b]777;notify;${TITLE};${body}\x07`;
  if (!inTmux) return osc;
  return `\x1bPtmux;${osc.replaceAll('\x1b', '\x1b\x1b')}\x1b\\`;
}

// The terminal Claude Code renders on: the first ancestor whose stdin is a pty.
function findTerminal() {
  let pid = process.ppid;
  for (let depth = 0; pid > 1 && depth < 16; depth += 1) {
    try {
      const target = fs.readlinkSync(`/proc/${pid}/fd/0`);
      if (/^\/dev\/(pts\/\d+|tty\w*)$/.test(target)) return target;
      const stat = fs.readFileSync(`/proc/${pid}/stat`, 'utf8');
      pid = Number(stat.slice(stat.lastIndexOf(')') + 2).split(' ')[1]);
    } catch {
      return null;
    }
  }
  return null;
}

function shouldSend(key, body) {
  const dir = path.join(os.tmpdir(), `cmux-claude-usage-${process.getuid?.() ?? 'u'}`);
  const file = path.join(dir, key.replace(/[^A-Za-z0-9_.-]/g, '_') || 'default');
  const now = Math.floor(Date.now() / 1000);
  try {
    const [at, ...rest] = fs.readFileSync(file, 'utf8').split('\n');
    if (rest.join('\n') === body && now - Number(at) < RESEND_SECONDS) return false;
  } catch { /* first report */ }
  try {
    fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
    fs.writeFileSync(file, `${now}\n${body}`);
  } catch { /* still send */ }
  return true;
}

function main() {
  let input;
  try { input = JSON.parse(readStdin()); } catch { return; }
  const who = process.env.CLAUDE_USAGE_WHO || process.env.CLAUDE_AS_NAME || process.env.USER;
  const email = loginEmail() || process.env.CLAUDE_USAGE_EMAIL;
  const body = buildBody(input, who, process.env.CLAUDE_USAGE_LABEL, email, {
    payer: process.env.CLAUDE_USAGE_PAYER,
    subscribed: process.env.CLAUDE_USAGE_SUBSCRIBED,
    cycle: process.env.CLAUDE_USAGE_CYCLE,
  });
  if (!body) return;
  const tty = findTerminal();
  if (!tty) return;
  if (!shouldSend(`${tty}-${input.session_id ?? ''}`, body)) return;
  try {
    fs.writeFileSync(tty, buildSequence(body, Boolean(process.env.TMUX)), { flag: 'a' });
  } catch { /* terminal gone */ }
}

if (!process.env.CLAUDE_USAGE_REPORT_NO_MAIN) main();
