public import CmuxSwiftRender
public import Foundation

/// Projects the DevBox edition's remote reports into the custom-sidebar
/// `workspaces[i].devbox` object, so an interpreted sidebar can show what the
/// remote agent is doing and how much of each account's quota is left.
///
/// Shape (every key optional, omitted when unknown):
///
///     devbox: {
///       usage:      { who, h5, h5Reset, d7, d7Reset, at },
///       codexUsage: { plan, h5, h5Reset, d7, d7Reset, at },
///       activity:   { state, since, agent, who, dir, title, bg, codex, codexSince }
///     }
///
/// `h5`/`d7` are already zeroed when their window has reset by `now`; times are
/// epoch seconds. `codexUsage.at` is when Codex observed the numbers (falling
/// back to when the report arrived), so the newest one wins across workspaces.
public enum SidebarDevBoxCustomSidebarValue {
    /// Key under `workspaces[i]`.
    public static let key = "devbox"

    /// Returns nil when there is nothing to report.
    public static func value(
        usage: SidebarClaudeUsage?,
        usageReportedAt: Date?,
        activity: SidebarAgentActivity?,
        codexUsage: SidebarCodexUsage? = nil,
        codexUsageReportedAt: Date? = nil,
        now: Date
    ) -> SwiftValue? {
        var fields: [String: SwiftValue] = [:]
        if let usage {
            var usageFields = windowFields(fiveHour: usage.fiveHour, sevenDay: usage.sevenDay, now: now)
            if !usage.who.isEmpty { usageFields["who"] = .string(usage.who) }
            if let usageReportedAt {
                usageFields["at"] = .int(Int(usageReportedAt.timeIntervalSince1970))
            }
            fields["usage"] = .object(usageFields)
        }
        if let codexUsage {
            var codexFields = windowFields(fiveHour: codexUsage.fiveHour, sevenDay: codexUsage.sevenDay, now: now)
            if !codexUsage.plan.isEmpty { codexFields["plan"] = .string(codexUsage.plan) }
            if let at = codexUsage.observedAt ?? codexUsageReportedAt {
                codexFields["at"] = .int(Int(at.timeIntervalSince1970))
            }
            fields["codexUsage"] = .object(codexFields)
        }
        if let activity {
            var activityFields: [String: SwiftValue] = [
                "state": .string(activity.state.rawValue),
                "since": .int(Int(activity.since.timeIntervalSince1970)),
            ]
            if !activity.agent.isEmpty { activityFields["agent"] = .string(activity.agent) }
            if !activity.who.isEmpty { activityFields["who"] = .string(activity.who) }
            if !activity.directory.isEmpty { activityFields["dir"] = .string(activity.directory) }
            if !activity.title.isEmpty { activityFields["title"] = .string(activity.title) }
            activityFields["bg"] = .int(activity.backgroundShells)
            activityFields["codex"] = .int(activity.codexRuns)
            if let since = activity.codexSince {
                activityFields["codexSince"] = .int(Int(since.timeIntervalSince1970))
            }
            fields["activity"] = .object(activityFields)
        }
        return fields.isEmpty ? nil : .object(fields)
    }

    private static func windowFields(
        fiveHour: SidebarClaudeUsage.Window?,
        sevenDay: SidebarClaudeUsage.Window?,
        now: Date
    ) -> [String: SwiftValue] {
        var out: [String: SwiftValue] = [:]
        for (window, pctKey, resetKey) in [(fiveHour, "h5", "h5Reset"), (sevenDay, "d7", "d7Reset")] {
            guard let window else { continue }
            out[pctKey] = .int(window.effectivePercent(now: now))
            if let reset = window.resetsAt, reset > now {
                out[resetKey] = .int(Int(reset.timeIntervalSince1970))
            }
        }
        return out
    }
}
