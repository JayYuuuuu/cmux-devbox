import CmuxSettings
import CmuxSidebar
import CmuxSwiftRender
import Foundation

/// DevBox: Claude Code usage reported by a remote statusline (see
/// `SidebarClaudeUsage`). Stored as a regular status entry so it persists with
/// the session and refreshes the sidebar through the existing observation path.
extension Workspace {
    /// The latest usage report for this workspace, if any.
    var claudeUsage: SidebarClaudeUsage? {
        statusEntries[SidebarClaudeUsage.statusKey].flatMap { SidebarClaudeUsage.parse($0.value) }
    }

    /// Records a report; identical repeats are dropped so a chatty statusline
    /// does not churn the sidebar.
    func applyClaudeUsageReport(_ usage: SidebarClaudeUsage) {
        let encoded = usage.encoded
        guard statusEntries[SidebarClaudeUsage.statusKey]?.value != encoded else { return }
        statusEntries[SidebarClaudeUsage.statusKey] = SidebarStatusEntry(
            key: SidebarClaudeUsage.statusKey,
            value: encoded
        )
    }

    /// The latest remote agent activity report, if any.
    var agentActivity: SidebarAgentActivity? {
        statusEntries[SidebarAgentActivity.statusKey].flatMap { SidebarAgentActivity.parse($0.value) }
    }

    /// Records an agent activity report; identical repeats are dropped.
    func applyAgentActivityReport(_ activity: SidebarAgentActivity) {
        let encoded = activity.encoded
        guard statusEntries[SidebarAgentActivity.statusKey]?.value != encoded else { return }
        statusEntries[SidebarAgentActivity.statusKey] = SidebarStatusEntry(
            key: SidebarAgentActivity.statusKey,
            value: encoded
        )
    }

    /// DevBox: the `workspaces[i].devbox` custom-sidebar object, nil outside
    /// the edition or when no report has arrived.
    func devBoxCustomSidebarExtraFields(now: Date = Date()) -> [String: SwiftValue] {
        guard CmuxDevBoxEdition.isActive,
              let value = SidebarDevBoxCustomSidebarValue.value(
                usage: claudeUsage,
                usageReportedAt: statusEntries[SidebarClaudeUsage.statusKey]?.timestamp,
                activity: agentActivity,
                now: now
              ) else {
            return [:]
        }
        return [SidebarDevBoxCustomSidebarValue.key: value]
    }

    /// DevBox: the remote report entries a session restore brings back. Usage
    /// carries its own reset times, so it stays meaningful across a restart;
    /// agent activity is dropped because a turn that ended while the app was
    /// closed would otherwise show as working forever. Nothing outside the
    /// edition.
    func devBoxStatusEntriesSurvivingRestore(
        _ snapshots: [SessionStatusEntrySnapshot]
    ) -> [String: SidebarStatusEntry] {
        guard CmuxDevBoxEdition.isActive else { return [:] }
        var kept: [String: SidebarStatusEntry] = [:]
        // Only the usage report survives; see above.
        for snapshot in snapshots
        where snapshot.key == SidebarClaudeUsage.statusKey {
            kept[snapshot.key] = SidebarStatusEntry(
                key: snapshot.key,
                value: snapshot.value,
                timestamp: Date(timeIntervalSince1970: snapshot.timestamp)
            )
        }
        return kept
    }
}
