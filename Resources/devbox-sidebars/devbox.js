// cmux-devbox-panel rev=2026110902 min-build=112.41
// cmux DevBox team panel: the edition's built-in left sidebar (provider
// `cmux.sidebar.custom.devbox`). Edit it here, not in ~/.config/cmux/sidebars
// (a user file with this name is ignored). The app ships a copy, and also
// fetches the copy published on the devbox (scripts/devbox/
// publish-team-panel.sh), so panel-only changes need no app release.
// Line 1 is required: bump `rev` on every change; raise `min-build` to the
// app's CFBundleVersion when the script needs data only newer apps provide.
//
// What it answers at a glance:
//   - which remote sessions need me (permission prompt, or a finished turn I
//     have not looked at), which are working and for how long, and which
//     agent (Claude Code / Codex) runs there with how many background shells;
//   - how much five-hour / weekly Claude quota each account has left, and
//     the shared Codex account's quota (Pro: weekly only; Plus: both) and
//     its reset cards with the earliest expiry;
//   - one click to jump to a session, or to open it if it is not open yet.
//
// Data:
//   - `data.devboxSessions()`: the user's cmux.json quick-entry actions tagged
//     with the `devbox` keyword, as [{ action, title, group, command }] in shortcut
//     order; `group` is the title without its trailing number.
//   - `workspaces[i].devbox.activity` from the agent hooks and
//     `.devbox.usage` from the statusline usage reporter, `.devbox.codexUsage`
//     from the agent hooks (all sent by the remote scripts in scripts/devbox/,
//     see docs/devbox-edition.md).

const ENTRIES = () => data.devboxSessions() ?? [];

// The app reports whether the terminal theme (and so this sidebar) is light
// or dark; accents are deepened on light themes so they stay legible.
const isLight = () => data.devboxScheme?.() === "light";
const tone = (dark, light) => (isLight() ? light : dark);

const COLORS = {
  get waiting() { return tone("#E5484D", "#C62F35"); },
  get unseen() { return tone("#F5A524", "#A86A00"); },
  get working() { return tone("#3E9BFF", "#1F6FD1"); },
  get ok() { return tone("#30A46C", "#2B8A57"); },
  idle: "#7f7f7f99",
  closed: "#7f7f7f44",
};

// The workspace the window is showing: a solid outline in the text tone plus
// a stronger fill, distinct from every status color and from hover.
const SELECTED = {
  get border() { return tone("#ECE6DF", "#4A423B"); },
  fill: "#7f7f7f38",
};

const now = () => data.clock()?.epoch ?? 0;
const workspaces = () => data.workspaces() ?? [];

function elapsed(secs) {
  const s = Math.max(0, Math.floor(secs));
  if (s < 60) return s + "秒";
  const m = Math.floor(s / 60);
  if (m < 60) return m + "分";
  const h = Math.floor(m / 60);
  return h < 24 ? h + "小时" + (m % 60 ? (m % 60) + "分" : "") : Math.floor(h / 24) + "天";
}

// "35分后重置 · 10:40", "1天3小时后重置 · 明天13:20",
// "5天10小时后重置 · 14号09:00": the countdown plus the Mac-local clock time.
function untilReset(epoch) {
  if (!epoch) return "";
  const s = epoch - now();
  if (s <= 0) return "";
  const m = Math.ceil(s / 60);
  const h = Math.floor(m / 60);
  const left = m < 60 ? m + "分"
    : h < 24 ? h + "小时" + (m % 60 ? (m % 60) + "分" : "")
    : Math.floor(h / 24) + "天" + (h % 24 ? (h % 24) + "小时" : "");
  return left + "后重置 · " + resetAt(epoch);
}

// Local clock time of a reset, prefixed with 明天/后天/day of month when it is
// not today ("10:40", "明天13:20", "14号09:00", "12月1号09:00").
function resetAt(epoch) {
  const off = localOffset();
  const t = epoch + off;
  const days = Math.floor(t / 86400);
  const secs = t - days * 86400;
  const pad = (n) => (n < 10 ? "0" : "") + n;
  const clock = pad(Math.floor(secs / 3600)) + ":" + pad(Math.floor((secs % 3600) / 60));
  const gap = days - Math.floor((now() + off) / 86400);
  if (gap <= 0) return clock;
  if (gap === 1) return "明天" + clock;
  if (gap === 2) return "后天" + clock;
  const [month, day] = civil(days);
  return (gap < 7 ? "" : month + "月") + day + "号" + clock;
}

function levelColor(pct) {
  if (pct >= 85) return COLORS.waiting;
  if (pct >= 60) return COLORS.unseen;
  return COLORS.ok;
}

// One status for a session row, from its workspace (or null when not open).
function sessionStatus(ws) {
  if (!ws) return { key: "closed", label: "未打开", color: COLORS.closed, since: 0 };
  const act = ws.devbox?.activity;
  const unread = (ws.unread ?? 0) > 0;
  if (act?.state === "waiting") {
    return { key: "waiting", label: "等你批准", color: COLORS.waiting, since: act.since };
  }
  if (act?.state === "working") {
    return { key: "working", label: "干活中", color: COLORS.working, since: act.since };
  }
  if (unread) {
    return { key: "unseen", label: act?.state === "done" ? "干完了" : "有新消息", color: COLORS.unseen, since: act?.since ?? 0 };
  }
  if (act?.state === "ended") return { key: "idle", label: "已退出", color: COLORS.idle, since: 0 };
  return { key: "idle", label: "空闲", color: COLORS.idle, since: 0 };
}

const workspaceFor = (entry) => workspaces().find((w) => w.title === entry.title) ?? null;

function open(entry) {
  const ws = workspaceFor(entry);
  if (ws) {
    cmux("workspace.select", { workspace_id: ws.id });
  } else {
    // Run the cmux.json entry itself: the same path as its keyboard
    // shortcut. `cmux()` is fire-and-forget, so there is no fallback; the
    // panel ships with the app that implements the method.
    cmux("devbox.session.open", { action_id: entry.action });
  }
}

// ---------------------------------------------------------------- summary

const counts = computed(() => {
  const out = { waiting: 0, unseen: 0, working: 0 };
  for (const entry of ENTRIES()) {
    const key = sessionStatus(workspaceFor(entry)).key;
    if (key in out) out[key] += 1;
  }
  return out;
});

function summary() {
  // Only the categories that have sessions, so the row never truncates.
  const items = computed(() => {
    const c = counts();
    const out = [];
    for (const [key, label] of [["waiting", "等你"], ["unseen", "干完了"], ["working", "干活中"]]) {
      if (c[key]) out.push({ key, label: c[key] + " " + label });
    }
    return out.length ? out : [{ key: "idle", label: "都空闲" }];
  });
  return HStack({ spacing: 12 }, [
    ForEach({ items, key: (i) => i.key, spacing: 12 }, (item) =>
      HStack({ spacing: 4 }, [
        Circle({ size: 6 }).fill(() => COLORS[item().key] ?? COLORS.closed),
        Text(() => item().label)
          .font(12)
          .color(() => (item().key === "idle" ? "tertiary" : "primary")),
      ])
    ).layoutPriority(1),
    Spacer(),
  ]).paddingHorizontal(10);
}

// ---------------------------------------------------------------- accounts

// Latest usage report per account label, from whichever workspace sent it last.
const usageByWho = computed(() => {
  const latest = {};
  for (const w of workspaces()) {
    const u = w.devbox?.usage;
    if (!u || !u.who) continue;
    if (!latest[u.who] || (u.at ?? 0) > (latest[u.who].at ?? 0)) latest[u.who] = u;
  }
  return latest;
});

// A quota window as two lines: name, reset countdown and percent on top, a
// full-width meter of 20 cells (5% each) below. Cells share the row width
// equally, so the meter stretches with the sidebar without measuring it.
const CELLS = 20;
const CELL_INDEX = [...Array(CELLS).keys()];

const WINDOW_5H = 5 * 3600;
const WINDOW_7D = 7 * 86400;

// Pacing: the share of the window already gone is the share of quota it
// can afford to have used. `mark` is that share (0–1); when the usage so far
// projects past 100% by the reset, `out` is when it runs out at this rate
// and, for the weekly window, `perDay` is what each remaining day can use.
// No verdict in the first tenth of a window: too little to extrapolate.
function pace(pct, reset, window) {
  if (pct === null || pct === undefined || !reset) return null;
  const left = reset - now();
  if (left <= 0 || left > window) return null;
  const used = window - left;
  const mark = used / window;
  if (mark < 0.1 || pct <= 0) return { mark };
  const rate = pct / used;
  if (pct < 100 && pct + rate * left <= 100) return { mark };
  return {
    mark,
    out: pct >= 100 ? 0 : now() + (100 - pct) / rate,
    perDay: window > 86400 ? Math.max(0, (100 - pct) / (left / 86400)) : null,
  };
}

function paceWarning(p) {
  if (!p?.out && p?.out !== 0) return "";
  if (p.out === 0) return "已用完";
  return "偏快 · 照这速度 " + resetAt(p.out) + " 用完" +
    (p.perDay !== null ? "，每天别超 " + Math.floor(p.perDay) + "%" : "");
}

function quota(label, pct, reset, window) {
  // pct() is null when the account has not reported yet.
  const has = () => pct() !== null && pct() !== undefined;
  const lit = () => (has() && pct() > 0 ? Math.max(1, Math.round(pct() / (100 / CELLS))) : 0);
  const p = computed(() => (has() ? pace(pct(), reset(), window) : null));
  const behind = () => p()?.out !== undefined;
  // Color by the worse of absolute level and pace.
  const color = () => (behind() && pct() < 60 ? COLORS.unseen : levelColor(pct()));
  // Cell where usage would sit if spread evenly over the window.
  const paceCell = () => (p() ? Math.min(CELLS - 1, Math.floor(p().mark * CELLS)) : -1);
  const warning = computed(() => {
    const w = paceWarning(p());
    return w ? [w] : [];
  });
  return VStack({ spacing: 5 }, [
    HStack({ spacing: 6 }, [
      Text(label).font(11).color("secondary").lineLimit(1),
      Text(() => (has() ? untilReset(reset()) : "")).font(10).color("tertiary").lineLimit(1),
      Spacer({ minLength: 4 }),
      Text(() => (has() ? pct() + "%" : "—"))
        .font(14).weight("semibold").monospaced()
        .color(() => (has() && (pct() >= 60 || behind()) ? color() : "primary"))
        .layoutPriority(2),
    ]),
    HStack({ spacing: 2 }, CELL_INDEX.map((i) =>
      RoundedRectangle({ cornerRadius: 1.5 })
        .fill(() => (i < lit() ? color() : i === paceCell() ? "#7f7f7f66" : "#7f7f7f2e"))
        .frame({ maxWidth: "infinity", height: 6 })
    )),
    ForEach({ items: warning, key: () => "pace" }, (t) =>
      Text(() => t()).font(10).color(() => color()).lineLimit(2)
    ),
  ]);
}

// Shown in place of the reset times until an account has reported.
function noUsageLine(usage, text) {
  const line = computed(() => (usage() ? [] : [text]));
  return ForEach({ items: line, key: () => "no-usage" }, (t) =>
    Text(() => t()).font(10).color("tertiary").lineLimit(2)
  );
}

// Which agent runs in the session, the Codex runs it started ("指挥 Codex"),
// and its other background shells. Empty when the agent exited.
const AGENTS = {
  claude: {
    label: "Claude",
    get fg() { return tone("#F0A07E", "#B4532F"); },
    get bg() { return tone("#D977573a", "#D9775726"); },
  },
  codex: {
    label: "Codex",
    get fg() { return tone("#6FD3B8", "#0E7A5F"); },
    get bg() { return tone("#10A37F3a", "#10A37F24"); },
  },
};
const SHELL_BADGE = {
  get fg() { return tone("#C9B8FF", "#6A4FD0"); },
  get bg() { return tone("#8E7CFF33", "#8E7CFF24"); },
};

function sessionBadges(act, nowEpoch) {
  if (!act || act.state === "ended") return [];
  const out = [];
  const agent = AGENTS[act.agent];
  if (agent) out.push({ key: "agent", label: agent.label, fg: agent.fg, bg: agent.bg });
  const codex = act.codex ?? 0;
  if (codex > 0) {
    const count = codex > 1 ? " ×" + codex : "";
    const time = act.codexSince ? " " + elapsed(nowEpoch - act.codexSince) : "";
    out.push({
      key: "codex", label: "指挥 Codex" + count + time, fg: AGENTS.codex.fg, bg: AGENTS.codex.bg,
      help: "这个会话派出去的 Codex 还在干活，切过去在分屏里能看到进度",
    });
  }
  // A Codex run lives in one of the background shells; it has its own badge.
  const shells = Math.max(0, (act.bg ?? 0) - codex);
  if (shells > 0) {
    out.push({
      key: "shell", label: "⚙ " + shells + " shell", fg: SHELL_BADGE.fg, bg: SHELL_BADGE.bg,
      help: "这个会话里还在后台跑的 shell",
    });
  }
  return out;
}

function openRow(entry) {
  const ws = () => workspaceFor(entry());
  const status = () => sessionStatus(ws());
  const strong = () => status().key === "waiting" || status().key === "unseen";
  // Lines 2 and 3 exist only when they have content, so idle rows stay one line.
  const badges = computed(() => sessionBadges(ws()?.devbox?.activity, now()));
  const badgeLine = computed(() => (badges().length ? [1] : []));
  const detailLine = computed(() => {
    const act = ws()?.devbox?.activity;
    return act && act.title && act.state !== "ended"
      ? [(act.dir ? act.dir + " · " : "") + act.title] : [];
  });
  return VStack({ spacing: 4 }, [
      HStack({ spacing: 7 }, [
        Circle({ size: 8 }).fill(() => status().color),
        Text(() => entry().title)
          .font(13)
          .weight(() => (strong() ? "semibold" : "regular"))
          .lineLimit(1),
        Spacer({ minLength: 4 }),
        Text(() => {
          const st = status();
          const time = st.since && st.key !== "idle" ? " " + elapsed(now() - st.since) : "";
          return st.label + time;
        })
          .font(11)
          .color(() => (strong() || status().key === "working" ? status().color : "tertiary"))
          .layoutPriority(2)
          .lineLimit(1),
      ]),
      ForEach({ items: badgeLine, key: () => "badges" }, () =>
        HStack({ spacing: 4 }, [
          ForEach({ items: badges, key: (b) => b.key, spacing: 4 }, (b) =>
            Text(() => b().label)
              .font(10).weight("semibold")
              .color(() => b().fg)
              .paddingHorizontal(5).paddingVertical(2)
              .background(() => b().bg)
              .cornerRadius(4)
              .help(() => b().help ?? "")
              .lineLimit(1)
          // The list renders as one view; without priority it splits the
          // row with the Spacer and truncates badges at half the width.
          ).layoutPriority(1),
          Spacer({ minLength: 0 }),
        ])
          .paddingLeading(10) // 15 minus the pill inset, so badge text lines up with the name
      ),
      ForEach({ items: detailLine, key: () => "detail" }, (line) =>
        Text(() => line())
          .font(11).color("tertiary").lineLimit(1).truncation("tail")
          .paddingLeading(15)
      ),
  ])
    .paddingHorizontal(9).paddingVertical(7)
    .cornerRadius(8)
    .background(() =>
      ws()?.selected ? SELECTED.fill
        : status().key === "waiting" ? COLORS.waiting + "24"
        : status().key === "unseen" ? COLORS.unseen + "1f"
        : "#7f7f7f12"
    )
    .borderColor(() => (ws()?.selected ? SELECTED.border : "clear"))
    .borderWidth(1.5)
    .hoverBackground(() => (ws()?.selected ? SELECTED.fill : "#7f7f7f2a"))
    .frame({ maxWidth: "infinity" })
    .onTap(() => open(entry()))
    .contextMenu([
      Button("切过去", () => open(entry())),
      Button("标为已读", () => {
        const w = workspaceFor(entry());
        if (w) cmux("workspace.action", { workspace_id: w.id, action: "mark_read" });
      }),
    ]);
}

function closedChip(entry) {
  return HStack({ spacing: 3 }, [
    Image("plus").font(9).color("secondary"),
    Text(() => entry().title).font(11).color("secondary").lineLimit(1),
  ])
    .paddingHorizontal(8).paddingVertical(4)
    .cornerRadius(11)
    .borderColor("#7f7f7f40").borderWidth(1)
    .hoverBackground("#7f7f7f24")
    .help("点一下打开这个 devbox 会话")
    .onTap(() => open(entry()));
}

// Who pays for the account and when it renews: a "付款" pill, the paying
// account, and the next renewal date. The reporter forwards what the user
// wrote in the devbox subscription list; the renewal date is computed here
// from the start date and cycle against the Mac's local today.
const PAYER_BADGE = {
  get fg() { return tone("#E6C07B", "#8A6408"); },
  get bg() { return tone("#E6C07B2e", "#C9A0402a"); },
};

// Days since 1970-01-01 of a calendar date (Hinnant's days_from_civil).
function civilDays(y, m, d) {
  y -= m <= 2 ? 1 : 0;
  const era = Math.floor(y / 400);
  const yoe = y - era * 400;
  const doy = Math.floor((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1;
  const doe = yoe * 365 + Math.floor(yoe / 4) - Math.floor(yoe / 100) + doy;
  return era * 146097 + doe - 719468;
}

// The first renewal on or after today, as [daysSinceEpoch, month, day]; a
// start on the 31st renews on the last day of shorter months.
function nextRenewal(start, cycle) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(start ?? "");
  if (!m) return null;
  const [y0, m0, d0] = [+m[1], +m[2], +m[3]];
  if (m0 < 1 || m0 > 12 || d0 < 1 || d0 > 31) return null;
  const today = Math.floor((now() + localOffset()) / 86400);
  const step = cycle === "y" ? 12 : 1;
  for (let k = 0; k < 1200; k += step) {
    const mi = m0 - 1 + k;
    const y = y0 + Math.floor(mi / 12);
    const mo = (mi % 12) + 1;
    const last = civilDays(mo === 12 ? y + 1 : y, mo === 12 ? 1 : mo + 1, 1) - civilDays(y, mo, 1);
    const days = civilDays(y, mo, Math.min(d0, last));
    if (days >= today) return [days, mo, Math.min(d0, last), days - today];
  }
  return null;
}

function payerLine(usage) {
  const line = computed(() => {
    const u = usage();
    return u && (u.payer || u.subscribed) ? [1] : [];
  });
  const renewal = () => {
    const r = nextRenewal(usage()?.subscribed, usage()?.cycle);
    if (!r) return "";
    const [, mo, d, left] = r;
    if (left === 0) return "今天续费";
    if (left <= 7) return left + "天后续费";
    return mo + "月" + d + "号续费";
  };
  const help = () => {
    const u = usage();
    if (!u) return "";
    const cycle = u.cycle === "y" ? "每年" : "每月";
    return "付款账号：" + (u.payer || "没写") +
      (u.subscribed ? "\n" + u.subscribed + " 订阅，" + cycle + "续费" : "") +
      "\n在 devbox 的 ~/.config/claude-as/subscriptions.csv 里改";
  };
  return ForEach({ items: line, key: () => "payer" }, () =>
    HStack({ spacing: 6 }, [
      Text("付款")
        .font(10).weight("semibold").color(() => PAYER_BADGE.fg)
        .paddingHorizontal(5).paddingVertical(2)
        .background(() => PAYER_BADGE.bg)
        .cornerRadius(4)
        .lineLimit(1)
        .layoutPriority(2),
      Text(() => usage()?.payer || "—")
        .font(11).color("secondary").lineLimit(1).truncation("middle"),
      Spacer({ minLength: 4 }),
      Text(() => renewal())
        .font(11).color(() => (nextRenewal(usage()?.subscribed, usage()?.cycle)?.[3] <= 3 ? COLORS.unseen : "tertiary"))
        .lineLimit(1)
        .layoutPriority(1),
    ]).help(() => help())
  );
}

function accountCard(group) {
  const items = () => ENTRIES().filter((e) => (e.group || "会话") === group);
  // The account label the group's sessions report (the newest one wins).
  const who = () => {
    let best = null;
    for (const e of items()) {
      const d = workspaceFor(e)?.devbox;
      // Codex sessions have no account label of their own (the reporter
      // falls back to the login user), so only usage and Claude reports count.
      const act = d?.activity?.agent === "claude" ? d.activity : null;
      for (const r of [d?.usage, act]) {
        const at = r?.at ?? r?.since ?? 0;
        if (r?.who && (!best || at > best.at)) best = { who: r.who, at };
      }
    }
    return best?.who ?? "";
  };
  const usage = () => usageByWho()[who()] ?? null;
  const openItems = () => items().filter((e) => workspaceFor(e));
  const closedItems = () => items().filter((e) => !workspaceFor(e));
  return VStack({ spacing: 9 }, [
    HStack({ spacing: 6 }, [
      // The reporter's display label and login email win; before the first
      // report the card falls back to the shortcut group and account name.
      Text(() => usage()?.label || group).font(15).weight("semibold").lineLimit(1).layoutPriority(1),
      Text(() => usage()?.email || (who() && who() !== group ? who() : ""))
        .font(11).color("tertiary").lineLimit(1).truncation("middle"),
      Spacer({ minLength: 0 }),
      Text(() => {
        const n = openItems().length;
        return n ? n + " 个开着" : "都没开";
      }).font(11).color("tertiary").lineLimit(1).layoutPriority(1),
    ]),
    payerLine(usage),
    quota("5小时", () => usage()?.h5 ?? null, () => usage()?.h5Reset, WINDOW_5H),
    quota("本周", () => usage()?.d7 ?? null, () => usage()?.d7Reset, WINDOW_7D),
    noUsageLine(usage, "还没收到用量：在这个账号的会话里用一次 Claude 就有"),
    ForEach({ items: openItems, key: (e) => e.title }, (entry) => openRow(entry)),
    HStack({ spacing: 5 }, [
      ForEach({ items: closedItems, key: (e) => e.title }, (entry) => closedChip(entry)),
      Spacer({ minLength: 0 }),
    ]),
  ])
    .padding(12)
    .cornerRadius(12)
    .background("#7f7f7f14")
    .borderColor(() => {
      const keys = openItems().map((e) => sessionStatus(workspaceFor(e)).key);
      if (keys.includes("waiting")) return COLORS.waiting + "88";
      if (keys.includes("unseen")) return COLORS.unseen + "77";
      return "#7f7f7f22";
    })
    .borderWidth(1)
    .frame({ maxWidth: "infinity" });
}

// ---------------------------------------------------------------- codex

// One Codex account serves every session; the report Codex observed last wins,
// whichever workspace carried it.
const codexUsage = computed(() => {
  let best = null;
  for (const w of workspaces()) {
    const u = w.devbox?.codexUsage;
    if (u && (!best || (u.at ?? 0) > (best.at ?? 0))) best = u;
  }
  return best;
});

const PLAN_NAMES = { pro: "Pro", prolite: "Pro Lite", plus: "Plus", team: "Team", business: "Business", enterprise: "Enterprise" };

function codexCard() {
  const plan = () => {
    const id = codexUsage()?.plan ?? "";
    return PLAN_NAMES[id] ?? (id ? id[0].toUpperCase() + id.slice(1) : "");
  };
  // Pro has no five-hour window; show it only when Codex reports one.
  const fiveHour = computed(() => (codexUsage()?.h5 !== undefined ? [1] : []));
  return VStack({ spacing: 9 }, [
    HStack({ spacing: 6 }, [
      Text("Codex").font(15).weight("semibold"),
      Text(() => plan())
        .font(10).weight("semibold").color(() => AGENTS.codex.fg)
        .paddingHorizontal(5).paddingVertical(2)
        .background(() => (plan() ? AGENTS.codex.bg : "clear"))
        .cornerRadius(4)
        .lineLimit(1)
        .layoutPriority(1),
      Spacer({ minLength: 0 }),
    ]).help("一个 Codex 账号，所有会话共用这份额度"),
    ForEach({ items: fiveHour, key: () => "h5" }, () =>
      quota("5小时", () => codexUsage()?.h5 ?? null, () => codexUsage()?.h5Reset, WINDOW_5H)
    ),
    quota("本周", () => codexUsage()?.d7 ?? null, () => codexUsage()?.d7Reset, WINDOW_7D),
    resetCardLine(),
    noUsageLine(codexUsage, "还没收到用量：在任一会话里用一次 Codex 就有"),
  ])
    .padding(12)
    .cornerRadius(12)
    .background("#7f7f7f14")
    .borderColor("#7f7f7f22")
    .borderWidth(1)
    .frame({ maxWidth: "infinity" });
}

// When a reset card expires, in the Mac's local time: "7号 07:00" within a
// week, "12月1号 04:25" further out. The sidebar clock gives local
// hour/minute/second next to the epoch, so the zone offset is their gap.
function localOffset() {
  const c = data.clock?.();
  if (!c || c.hour == null) return 0;
  const local = c.hour * 3600 + c.minute * 60 + c.second;
  let off = local - (((c.epoch % 86400) + 86400) % 86400);
  if (off > 14 * 3600) off -= 86400;
  if (off < -12 * 3600) off += 86400;
  return Math.round(off / 60) * 60;
}

// [month, day] of a day count since 1970-01-01 (Hinnant's civil_from_days).
function civil(days) {
  const z = days + 719468;
  const era = Math.floor(z / 146097);
  const doe = z - era * 146097;
  const yoe = Math.floor((doe - Math.floor(doe / 1460) + Math.floor(doe / 36524) - Math.floor(doe / 146096)) / 365);
  const doy = doe - (365 * yoe + Math.floor(yoe / 4) - Math.floor(yoe / 100));
  const mp = Math.floor((5 * doy + 2) / 153);
  const d = doy - Math.floor((153 * mp + 2) / 5) + 1;
  return [mp < 10 ? mp + 3 : mp - 9, d];
}

function expiryAt(epoch) {
  const t = epoch + localOffset();
  const days = Math.floor(t / 86400);
  const secs = t - days * 86400;
  const pad = (n) => (n < 10 ? "0" : "") + n;
  const clock = pad(Math.floor(secs / 3600)) + ":" + pad(Math.floor((secs % 3600) / 60));
  const [month, day] = civil(days);
  const near = epoch - now() < 7 * 86400;
  return (near ? "" : month + "月") + day + "号 " + clock;
}

// Outcome of the last "使用" press, from the app (`data.devboxCodexReset`):
// { state, at, expiresAt? }; see DevBoxCodexReset.swift.
const resetRun = () => data.devboxCodexReset?.() ?? null;
const RESET_RESULT_SECONDS = 120;
const RESET_RUN_LIMIT = 90;

function resetRunText(run, nowEpoch) {
  const card = run.expiresAt ? " " + expiryAt(run.expiresAt) + " 过期那张" : "一张";
  switch (run.state) {
    case "running":
      return nowEpoch - run.at > RESET_RUN_LIMIT ? "没等到结果，稍后看张数有没有变" : "正在用重置卡…";
    case "reset": return "已用掉" + card + "，额度已重置";
    case "nothingToReset": return "现在没有能重置的额度，卡没用掉";
    case "noCredit": return "没有可用的重置卡";
    case "alreadyRedeemed": return "这次已经用过了，没再扣卡";
    case "noSession": return "先打开一个 devbox 会话再用";
    case "unavailable": return "devbox 上没装上报脚本，用不了";
    default: return "没用成，稍后再试";
  }
}

// Usage limit resets ("reset cards") the Codex account holds: one line under
// the weekly meter, shown once the reporter has asked. The count drops a card
// as soon as it expires; the note turns amber within a day of the earliest
// expiry and red within three hours, since an unused card is simply lost.
// "使用" redeems the card that expires first after an inline confirmation
// (it lapses after 15 seconds); the app runs it on the devbox over SSH.
function resetCardLine() {
  const known = computed(() => (codexUsage()?.resets !== undefined ? [1] : []));
  const count = () => codexUsage()?.resets ?? 0;
  const next = () => (codexUsage()?.resetExpiries ?? []).find((e) => e > now());
  const [confirmAt, setConfirmAt] = signal(0);
  const running = () => resetRun()?.state === "running" && now() - resetRun().at <= RESET_RUN_LIMIT;
  const confirming = computed(() =>
    count() > 0 && !running() && confirmAt() && now() - confirmAt() <= 15 ? [1] : []);
  const result = computed(() => {
    const run = resetRun();
    return run && now() - run.at <= RESET_RESULT_SECONDS ? [resetRunText(run, now())] : [];
  });
  const canUse = computed(() => (count() > 0 && !running() && !confirming().length ? [1] : []));
  const urgency = () => {
    const e = next();
    if (!e || count() === 0) return "tertiary";
    const left = e - now();
    if (left <= 3 * 3600) return COLORS.waiting;
    if (left <= 24 * 3600) return COLORS.unseen;
    return "tertiary";
  };
  const note = () => {
    if (count() === 0) return "";
    const e = next();
    if (!e) return "";
    return (count() > 1 ? "最早 " : "") + expiryAt(e) + " 过期";
  };
  const tip = () => {
    const list = (codexUsage()?.resetExpiries ?? []).filter((e) => e > now());
    if (count() === 0) return "没有可用的重置卡";
    const each = list.length ? "，分别 " + list.map(expiryAt).join(" / ") + " 过期" : "";
    return "Codex 重置卡 " + count() + " 张" + each + "。用一张会把额度重置满，过期不用就作废；点「使用」用掉最早过期的那张";
  };
  const pill = (label, fg, bg) =>
    Text(label)
      .font(10).weight("semibold").color(fg)
      .paddingHorizontal(6).paddingVertical(2)
      .background(bg)
      .cornerRadius(4)
      .lineLimit(1);
  return ForEach({ items: known, key: () => "resets" }, () =>
    VStack({ spacing: 6 }, [
      HStack({ spacing: 6 }, [
        Text("重置卡").font(11).color("secondary").lineLimit(1),
        Text(() => note()).font(10).color(() => urgency()).lineLimit(1),
        Spacer({ minLength: 4 }),
        HStack({ spacing: 2 }, [
          Text(() => String(count()))
            .font(14).weight("semibold").monospaced()
            .color(() => (count() > 0 ? "primary" : "tertiary")),
          Text("张").font(11).color("secondary"),
        ]).layoutPriority(2),
        ForEach({ items: canUse, key: () => "use" }, () =>
          pill("使用", () => AGENTS.codex.fg, () => AGENTS.codex.bg)
            .help("用掉最早过期的那张，点了还要再确认一次")
            .onTap(() => setConfirmAt(now()))
        ),
      ]).help(() => tip()),
      ForEach({ items: confirming, key: () => "confirm" }, () =>
        HStack({ spacing: 6 }, [
          Text(() => {
            const e = next();
            const used = codexUsage()?.d7;
            return "用掉" + (e ? " " + expiryAt(e) + " 过期那张" : "一张") +
              (used !== undefined ? "？本周已用 " + used + "%" : "？");
          }).font(11).color("secondary").lineLimit(2),
          Spacer({ minLength: 4 }),
          pill("确认", () => COLORS.waiting, () => COLORS.waiting + "2e")
            .onTap(() => {
              setConfirmAt(0);
              cmux("devbox.codex.reset.use", {});
            }),
          pill("取消", "secondary", "#7f7f7f24").onTap(() => setConfirmAt(0)),
        ])
      ),
      ForEach({ items: result, key: () => "result" }, (line) =>
        Text(() => line())
          .font(11)
          .color(() => (resetRun()?.state === "reset" ? COLORS.ok
            : resetRun()?.state === "running" ? "secondary" : COLORS.unseen))
          .lineLimit(2)
      ),
    ])
  );
}

const GROUPS = computed(() => [...new Set(ENTRIES().map((e) => e.group || "会话"))]);

// Open workspaces that are not one of the entries (local shells and such).
const others = computed(() => {
  const known = new Set(ENTRIES().map((e) => e.title));
  return workspaces().filter((w) => !known.has(w.title));
});

// Shown until cmux.json has quick entries tagged "devbox".
function hint() {
  return Text(() =>
    ENTRIES().length
      ? ""
      : "在 cmux.json 里给常用会话加带 devbox 关键词的快捷入口，这里就会按账号列出来"
  )
    .font(10).color("tertiary").paddingHorizontal(10);
}

function otherSection() {
  return VStack({ spacing: 1 }, [
    Text(() => (others().length ? "其他窗口" : ""))
      .font(10).weight("semibold").color("secondary").paddingHorizontal(10),
    ForEach({ items: others, key: (w) => w.id }, (w) =>
      HStack({ spacing: 8 }, [
        Circle({ size: 6 }).fill(() => ((w().unread ?? 0) > 0 ? COLORS.unseen : COLORS.closed)),
        Text(() => w().title).font(11).color("secondary").lineLimit(1).truncation("tail"),
        Spacer({ minLength: 0 }),
      ])
        .paddingHorizontal(10).paddingVertical(3)
        .cornerRadius(6)
        .background(() => (w().selected ? SELECTED.fill : null))
        .borderColor(() => (w().selected ? SELECTED.border : "clear"))
        .borderWidth(1.5)
        .hoverBackground(() => (w().selected ? SELECTED.fill : "#7f7f7f24"))
        .frame({ maxWidth: "infinity" })
        .onTap(() => cmux("workspace.select", { workspace_id: w().id }))
    ),
  ]);
}

sidebar(() =>
  VStack({ spacing: 12 }, [
    summary(),
    ForEach({ items: GROUPS, key: (g) => g, spacing: 12 }, (_g, key) => accountCard(key)),
    codexCard(),
    hint(),
    otherSection(),
    Spacer(),
  ]).paddingHorizontal(6).paddingVertical(8)
);
