// cmux DevBox team panel (right sidebar). Installed per Mac with the
// session list filled in, then selected with:
//   cmux right-sidebar set custom devbox
//
// What it answers at a glance:
//   - which remote sessions need me (permission prompt, or a finished turn I
//     have not looked at), which are working and for how long;
//   - how much five-hour / weekly Claude quota each account has left;
//   - one click to jump to a session, or to open it if it is not open yet.
//
// Data: `workspaces[i].devbox.activity` comes from the agent hooks
// (scripts/devbox/agent-activity-report.py), `workspaces[i].devbox.usage`
// from the statusline (scripts/devbox/claude-usage-report.mjs). Both need
// DevBox 0.64.25-devbox.20 or newer; older builds just show the list.

// Filled in by the installer: [{ title, group, who, command }]. `title` must
// equal the workspace title the entry opens; `who` is the account label the
// remote reports carry (used to order the quota rows).
const ENTRIES = /*ENTRIES*/[]/*END*/;

const COLORS = {
  waiting: "#E5484D",
  unseen: "#F5A524",
  working: "#3E9BFF",
  idle: "#7f7f7f99",
  closed: "#7f7f7f44",
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

function untilReset(epoch) {
  if (!epoch) return "";
  const s = epoch - now();
  if (s <= 0) return "";
  const m = Math.ceil(s / 60);
  if (m < 60) return m + "分后重置";
  const h = Math.floor(m / 60);
  if (h < 48) return h + "小时后重置";
  return Math.floor(h / 24) + "天后重置";
}

function levelColor(pct) {
  if (pct >= 85) return COLORS.waiting;
  if (pct >= 60) return COLORS.unseen;
  return "#30A46C";
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
    cmux("workspace.create", { title: entry.title, initial_command: entry.command });
  }
}

// ---------------------------------------------------------------- summary

const counts = computed(() => {
  const out = { waiting: 0, unseen: 0, working: 0 };
  for (const entry of ENTRIES) {
    const key = sessionStatus(workspaceFor(entry)).key;
    if (key in out) out[key] += 1;
  }
  return out;
});

function summary() {
  const chip = (key, label) =>
    HStack({ spacing: 4 }, [
      Circle({ size: 6 }).fill(() => (counts()[key] ? COLORS[key] : COLORS.closed)),
      Text(() => counts()[key] + " " + label)
        .font(11)
        .color(() => (counts()[key] ? "primary" : "tertiary")),
    ]);
  return HStack({ spacing: 12 }, [
    chip("waiting", "等你"),
    chip("unseen", "干完了"),
    chip("working", "干活中"),
    Spacer(),
  ]).paddingHorizontal(10);
}

// ---------------------------------------------------------------- quota

const ACCOUNT_ORDER = [...new Set(ENTRIES.map((e) => e.who).filter(Boolean))];

const accounts = computed(() => {
  const latest = {};
  for (const w of workspaces()) {
    const u = w.devbox?.usage;
    if (!u || !u.who) continue;
    if (!latest[u.who] || (u.at ?? 0) > (latest[u.who].at ?? 0)) latest[u.who] = u;
  }
  const rank = (who) => {
    const i = ACCOUNT_ORDER.indexOf(who);
    return i < 0 ? 999 : i;
  };
  return Object.values(latest).sort((a, b) => rank(a.who) - rank(b.who) || (a.who < b.who ? -1 : 1));
});

function gauge(pct, reset) {
  const BAR = 54;
  return HStack({ spacing: 5 }, [
    ZStack({ alignment: "leading" }, [
      Capsule({ width: BAR, height: 5 }).fill("#7f7f7f33"),
      Capsule({ width: () => Math.max(3, Math.round((BAR * Math.min(100, pct())) / 100)), height: 5 })
        .fill(() => levelColor(pct())),
    ]),
    Text(() => pct() + "%").font(10).monospaced().frame({ width: 30, alignment: "trailing" }),
    Text(() => untilReset(reset())).font(9).color("tertiary").lineLimit(1),
  ]);
}

function accountRow(acc) {
  return VStack({ spacing: 3 }, [
    Text(() => acc().who).font(11).weight("semibold").lineLimit(1),
    HStack({ spacing: 6 }, [
      Text("5小时").font(9).color("secondary").frame({ width: 28, alignment: "leading" }),
      gauge(() => acc().h5 ?? 0, () => acc().h5Reset),
    ]),
    HStack({ spacing: 6 }, [
      Text("本周").font(9).color("secondary").frame({ width: 28, alignment: "leading" }),
      gauge(() => acc().d7 ?? 0, () => acc().d7Reset),
    ]),
  ])
    .paddingHorizontal(10).paddingVertical(5)
    .frame({ maxWidth: "infinity", alignment: "leading" });
}

function quotaSection() {
  return VStack({ spacing: 2 }, [
    sectionHeader("账号额度"),
    ForEach({ items: accounts, key: (a) => a.who }, (acc) => accountRow(acc)),
    Text(() => (accounts().length ? "" : "还没收到用量（在任一会话里用一次 Claude 就有）"))
      .font(10).color("tertiary").paddingHorizontal(10),
  ]);
}

// ---------------------------------------------------------------- sessions

function sessionRow(entry) {
  const ws = () => workspaceFor(entry);
  const status = () => sessionStatus(ws());
  const strong = () => status().key === "waiting" || status().key === "unseen";
  return HStack({ spacing: 8 }, [
    Circle({ size: 8 }).fill(() => status().color),
    VStack({ spacing: 1 }, [
      HStack({ spacing: 6 }, [
        Text(entry.title)
          .font(12)
          .weight(() => (strong() ? "semibold" : "regular"))
          .color(() => (ws() ? "primary" : "tertiary"))
          .lineLimit(1),
        Spacer({ minLength: 0 }),
        Text(() => {
          const st = status();
          const time = st.since && st.key !== "idle" ? " " + elapsed(now() - st.since) : "";
          return st.label + time;
        })
          .font(10)
          .color(() => (strong() || status().key === "working" ? status().color : "tertiary"))
          .lineLimit(1),
      ]),
      Text(() => {
        const act = ws()?.devbox?.activity;
        if (!act || !act.title || act.state === "ended") return ws() ? "" : "点一下打开";
        return (act.dir ? act.dir + " · " : "") + act.title;
      })
        .font(10).color("tertiary").lineLimit(1).truncation("tail"),
    ]),
  ])
    .paddingHorizontal(10).paddingVertical(5)
    .cornerRadius(8)
    .background(() => (status().key === "waiting" ? "#E5484D1f" : status().key === "unseen" ? "#F5A5241a" : null))
    .hoverBackground("#7f7f7f24")
    .frame({ maxWidth: "infinity" })
    .onTap(() => open(entry))
    .contextMenu([
      Button("切过去 / 打开", () => open(entry)),
      Button("标为已读", () => {
        const w = workspaceFor(entry);
        if (w) cmux("workspace.action", { workspace_id: w.id, action: "mark_read" });
      }),
    ]);
}

function sectionHeader(label) {
  return Text(label).font(10).weight("semibold").color("secondary").paddingHorizontal(10).paddingVertical(2);
}

const GROUPS = [...new Set(ENTRIES.map((e) => e.group || "会话"))];

function groupSection(group) {
  const items = ENTRIES.filter((e) => (e.group || "会话") === group);
  return VStack({ spacing: 1 }, [
    sectionHeader(group),
    ...items.map(sessionRow),
  ]);
}

// Open workspaces that are not one of the entries (local shells and such).
const others = computed(() => {
  const known = new Set(ENTRIES.map((e) => e.title));
  return workspaces().filter((w) => !known.has(w.title));
});

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
        .hoverBackground("#7f7f7f24")
        .frame({ maxWidth: "infinity" })
        .onTap(() => cmux("workspace.select", { workspace_id: w().id }))
    ),
  ]);
}

sidebar(() =>
  VStack({ spacing: 10 }, [
    summary(),
    Divider(),
    ...GROUPS.map(groupSection),
    otherSection(),
    Divider(),
    quotaSection(),
    Spacer(),
  ]).paddingHorizontal(4).paddingVertical(6)
);
