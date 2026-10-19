import CmuxRemoteSession
import CmuxSettings
import Foundation

/// Prewarms uploads from the same live foreground-process ownership used by
/// the app's pane guardrail. The shared native SSH broker owns every transport.
@MainActor
final class PlainSSHUploadCoordinator {
    private let broker: NativeSSHConnectionBroker
    private let foregroundPIDs: @MainActor () -> [Int32]
    private let policy: ManagedDevicePolicy
    private var task: Task<Void, Never>?

    init(
        broker: NativeSSHConnectionBroker,
        policy: ManagedDevicePolicy = ManagedDevicePolicy(),
        foregroundPIDs: @escaping @MainActor () -> [Int32]
    ) {
        self.broker = broker
        self.policy = policy
        self.foregroundPIDs = foregroundPIDs
    }

    private var isAllowed: Bool {
        !policy.isEnforced(.disableFileTransfer) && !policy.isEnforced(.disableRemoteConnections)
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }

    func refresh() async {
        guard isAllowed else { broker.stopUploadConnections(); return }
        let pids = Set(foregroundPIDs())
        let endpoints = await Task.detached(priority: .utility) {
            Set(pids.compactMap { TerminalSSHSessionDetector.detect(foregroundPID: $0)?.uploadEndpoint })
        }.value
        guard !Task.isCancelled else { return }
        // Policy can change while the process arguments are read off-main.
        guard isAllowed else { broker.stopUploadConnections(); return }
        broker.reconcileUploadConnections(endpoints)
    }

    func controlPath(for session: DetectedSSHSession) -> String? {
        guard isAllowed, let endpoint = session.uploadEndpoint else { return nil }
        return broker.uploadControlPath(for: endpoint)
    }

    func stop() {
        task?.cancel()
        task = nil
        broker.stopUploadConnections()
    }
}
