@testable import CmuxRemoteSession

/// Main-actor test mutations never overlap a process callback.
final class UploadMasterTestProcess: RemoteReverseRelayProcess, @unchecked Sendable {
    var isRunning = true
    var terminations = 0
    let terminationStatus: Int32 = 0
    func terminate() { terminations += 1; isRunning = false }
}
