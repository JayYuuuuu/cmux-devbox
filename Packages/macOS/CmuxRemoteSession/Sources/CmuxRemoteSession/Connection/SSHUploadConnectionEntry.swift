internal import Foundation

/// One broker-owned transport; no interactive shell or workspace owns its PID.
struct SSHUploadConnectionEntry {
    var process: (any RemoteReverseRelayProcess)?
    var controlPath: String
    var lastAttempt: TimeInterval
    var idleSince: TimeInterval?
}
