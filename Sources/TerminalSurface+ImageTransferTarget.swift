import CmuxSettings
import CmuxTerminal
import Foundation

extension TerminalSurface {
    @MainActor
    func resolvedImageTransferTarget(
        mode: TerminalImageTransferMode = .paste,
        in workspace: Workspace? = nil
    ) -> TerminalImageTransferTarget {
        // The bound session remains authoritative even during reconnect, before
        // its local workspace or a fresh remote numeric surface can be resolved.
        let workspace = workspace ?? owningWorkspace()
        if mode == .paste, isManagedCloudImageTarget(in: workspace) { return .cloud }
        guard let workspace else {
            DevBoxPasteDiagnostics.recordLocalTarget(mode: mode, surfaceId: id, ttyName: nil)
            return .local
        }
        if workspace.isRemoteTerminalSurface(id) {
            return .remote(.workspaceRemote)
        }
        // Manual tmux mirrors have no local TTY for the SSH process detector.
        if let target = AppDelegate.shared?.remoteTmuxController.remoteUploadTarget(forSurfaceId: id) {
            return .remote(target)
        }
        if let ttyName = workspace.surfaceTTYNames[id],
           let session = TerminalSSHSessionDetector.detect(forTTY: ttyName) {
            return .remote(.detectedSSH(session))
        }
        DevBoxPasteDiagnostics.recordLocalTarget(
            mode: mode,
            surfaceId: id,
            ttyName: workspace.surfaceTTYNames[id]
        )
        return .local
    }

    @MainActor
    private func isManagedCloudImageTarget(in workspace: Workspace?) -> Bool {
        if hostedView.cloudTerminalOverlay.session != nil { return true }
        guard let workspace else { return false }
        if workspace.cloudProjectedResource(forPanel: id)?.id.machine.cloudMachineID != nil { return true }
        if (workspace.panels[id] as? TerminalPanel)?.cloudAttachment != nil { return true }
        // A VM label alone also describes legacy SSH workspaces. Their existing
        // SSH upload path remains authoritative until a native Cloud view exists.
        return false
    }
}

/// DevBox edition: one log line whenever an image transfer resolves to the
/// local Mac, so a paste that inserted a local path instead of uploading can be
/// traced afterwards (`~/Library/Logs/cmux-devbox-paste.log`, kept under
/// 256 KB). Local-only sessions log too; the line shows what was seen.
enum DevBoxPasteDiagnostics {
    private static let maxBytes = 256 * 1024

    static func recordLocalTarget(mode: TerminalImageTransferMode, surfaceId: UUID?, ttyName: String?) {
        guard CmuxDevBoxEdition.isActive, mode != .plainText else { return }
        let seen = ttyName.map(TerminalSSHSessionDetector.diagnosticSummary(forTTY:)) ?? "tty=none"
        let line = "\(ISO8601DateFormatter().string(from: Date())) local mode=\(mode) surface=\(surfaceId.map { String($0.uuidString.prefix(8)) } ?? "none") \(seen)\n"
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/cmux-devbox-paste.log")
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maxBytes {
            try? FileManager.default.removeItem(at: url)
        }
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}
