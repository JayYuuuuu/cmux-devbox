import CmuxFoundation
import CmuxSettings
import CmuxSidebar
import CmuxSwiftRender
import Foundation

/// DevBox team panel: redeems one Codex usage limit reset ("reset card") on
/// the devbox the panel's sessions connect to.
///
/// The Codex sign-in lives on the remote host, so the app does not call any
/// OpenAI endpoint itself. It finds an open panel session whose terminal runs
/// plain `ssh`, opens a separate non-interactive connection with the same
/// route and options, and runs the agent reporter's `--use-reset-card` mode
/// (scripts/devbox/agent-activity-report.py). That mode asks Codex's own
/// app-server to consume the available card that expires first and prints
/// one JSON line with the outcome and a fresh `cx1` usage report, which is
/// applied to the workspace right away.
///
/// The outcome is exposed to the panel as the ``dataKey`` object
/// `{ state, at, expiresAt? }`; `state` is `running`, Codex's answer
/// (`reset`, `nothingToReset`, `noCredit`, `alreadyRedeemed`), or one of
/// `noSession` (no open devbox session over ssh), `unavailable` (reporter not
/// installed) and `failed`. The panel words it; nothing here is user-facing.
@MainActor
enum DevBoxCodexReset {
    /// Top-level custom-sidebar data key.
    static let dataKey = "devboxCodexReset"
    /// Reporter entry point, relative to the remote home directory.
    static let remoteCommand =
        #"sh -c 'f="$HOME/.local/bin/cmux-agent-activity-report.py"; [ -x "$f" ] || exit 127; exec "$f" --use-reset-card'"#
    private static let timeout: TimeInterval = 60

    private struct Outcome {
        let state: String
        let at: Date
        let expiresAt: Date?
    }

    private static var last: Outcome?

    static var isRunning: Bool { last?.state == "running" }

    /// Starts one redemption; ignored while another is in flight.
    static func start(tabManager: TabManager, actions: [CmuxResolvedConfigAction]) {
        guard CmuxDevBoxEdition.isActive, !isRunning else { return }
        let candidates = DevBoxTeamPanel.sessionForegroundProcesses(tabManager: tabManager, actions: actions)
        last = Outcome(state: "running", at: Date(), expiresAt: nil)
        let command = remoteCommand
        let limit = timeout
        Task {
            guard let (workspace, session) = await DevBoxTeamPanel.firstSSHSession(in: candidates) else {
                finish(state: "noSession")
                return
            }
            let run = await Task.detached(priority: .userInitiated) {
                try? session.runRemoteCommandSync(command, timeout: limit)
            }.value
            guard let run else {
                finish(state: "failed")
                return
            }
            guard run.status == 0 else {
                finish(state: run.status == 127 ? "unavailable" : "failed")
                return
            }
            let reply = run.stdout
                .split(separator: "\n")
                .last
                .flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] } ?? [:]
            if let body = reply["report"] as? String, let usage = SidebarCodexUsage.parse(body) {
                workspace.applyCodexUsageReport(usage)
            }
            let expiry = (reply["expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            finish(state: (reply["outcome"] as? String) ?? "failed", expiresAt: expiry)
        }
    }

    private static func finish(state: String, expiresAt: Date? = nil) {
        let known: Set<String> = ["reset", "nothingToReset", "noCredit", "alreadyRedeemed", "noSession", "unavailable"]
        last = Outcome(state: known.contains(state) ? state : "failed", at: Date(), expiresAt: expiresAt)
    }

    /// Adds ``dataKey`` to a custom-sidebar data context once a redemption ran.
    static func add(to context: inout [String: SwiftValue]) {
        guard let last else { return }
        var fields: [String: SwiftValue] = [
            "state": .string(last.state),
            "at": .int(Int(last.at.timeIntervalSince1970)),
        ]
        if let expiresAt = last.expiresAt {
            fields["expiresAt"] = .int(Int(expiresAt.timeIntervalSince1970))
        }
        context[dataKey] = .object(fields)
    }
}
