import CmuxSidebar
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
}
