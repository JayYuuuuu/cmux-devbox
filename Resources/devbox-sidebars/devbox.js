// cmux DevBox team panel: the edition's built-in left sidebar (provider
// `cmux.sidebar.custom.devbox`). Shipped inside the app; edit it here, not in
// ~/.config/cmux/sidebars (a user file with this name is ignored).
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

// "35分后重置", "1小时10分后重置", "5天10小时后重置".
function untilReset(epoch) {
  if (!epoch) return "";
  const s = epoch - now();
  if (s <= 0) return "";
  const m = Math.ceil(s / 60);
  if (m < 60) return m + "分后重置";
  const h = Math.floor(m / 60);
  if (h < 24) return h + "小时" + (m % 60 ? (m % 60) + "分" : "") + "后重置";
  return Math.floor(h / 24) + "天" + (h % 24 ? (h % 24) + "小时" : "") + "后重置";
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

function quota(label, pct, reset) {
  // pct() is null when the account has not reported yet.
  const has = () => pct() !== null && pct() !== undefined;
  const lit = () => (has() && pct() > 0 ? Math.max(1, Math.round(pct() / (100 / CELLS))) : 0);
  return VStack({ spacing: 5 }, [
    HStack({ spacing: 6 }, [
      Text(label).font(11).color("secondary").lineLimit(1),
      Text(() => (has() ? untilReset(reset()) : "")).font(10).color("tertiary").lineLimit(1),
      Spacer({ minLength: 4 }),
      Text(() => (has() ? pct() + "%" : "—"))
        .font(14).weight("semibold").monospaced()
        .color(() => (has() && pct() >= 60 ? levelColor(pct()) : "primary"))
        .layoutPriority(2),
    ]),
    HStack({ spacing: 2 }, CELL_INDEX.map((i) =>
      RoundedRectangle({ cornerRadius: 1.5 })
        .fill(() => (i < lit() ? levelColor(pct()) : "#7f7f7f2e"))
        .frame({ maxWidth: "infinity", height: 6 })
    )),
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
      Text(group).font(15).weight("semibold"),
      Text(() => (who() && who() !== group ? who() : "")).font(11).color("tertiary"),
      Spacer({ minLength: 0 }),
      Text(() => {
        const n = openItems().length;
        return n ? n + " 个开着" : "都没开";
      }).font(11).color("tertiary"),
    ]),
    quota("5小时", () => usage()?.h5 ?? null, () => usage()?.h5Reset),
    quota("本周", () => usage()?.d7 ?? null, () => usage()?.d7Reset),
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
      quota("5小时", () => codexUsage()?.h5 ?? null, () => codexUsage()?.h5Reset)
    ),
    quota("本周", () => codexUsage()?.d7 ?? null, () => codexUsage()?.d7Reset),
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

// "1天15小时", "3小时20分", "40分": how long until a reset card expires.
function untilExpiry(epoch) {
  const m = Math.ceil(Math.max(0, epoch - now()) / 60);
  if (m < 60) return m + "分";
  const h = Math.floor(m / 60);
  if (h < 24) return h + "小时" + (m % 60 ? (m % 60) + "分" : "");
  return Math.floor(h / 24) + "天" + (h % 24 ? (h % 24) + "小时" : "");
}

// Usage limit resets ("reset cards") the Codex account holds: one line under
// the weekly meter, shown once the reporter has asked. The count drops a card
// as soon as it expires; the note turns amber within a day of the earliest
// expiry and red within three hours, since an unused card is simply lost.
function resetCardLine() {
  const known = computed(() => (codexUsage()?.resets !== undefined ? [1] : []));
  const count = () => codexUsage()?.resets ?? 0;
  const next = () => (codexUsage()?.resetExpiries ?? []).find((e) => e > now());
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
    return (count() > 1 ? "最早一张 " : "") + untilExpiry(e) + "后过期";
  };
  const tip = () => {
    const list = (codexUsage()?.resetExpiries ?? []).filter((e) => e > now());
    if (count() === 0) return "没有可用的重置卡";
    const each = list.length ? "，分别 " + list.map(untilExpiry).join(" / ") + " 后过期" : "";
    return "Codex 重置卡 " + count() + " 张" + each + "。用一张会把额度重置满，过期不用就作废；在 Codex 的用量菜单里使用";
  };
  return ForEach({ items: known, key: () => "resets" }, () =>
    HStack({ spacing: 6 }, [
      Text("重置卡").font(11).color("secondary").lineLimit(1),
      Text(() => note()).font(10).color(() => urgency()).lineLimit(1),
      Spacer({ minLength: 4 }),
      Text(() => count() + " 张")
        .font(14).weight("semibold").monospaced()
        .color(() => (count() > 0 ? "primary" : "tertiary"))
        .layoutPriority(2),
    ]).help(() => tip())
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
