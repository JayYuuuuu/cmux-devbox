public import Foundation

/// Names the remote files a paste uploads and the scripts that remove them.
///
/// DevBox: pastes go straight to an absolute `/tmp` path in one scp, as on
/// 0.64.x. Upstream's private `~/.cache` directory needed an ssh round trip
/// before the copy (create and prune it) and one after (chmod and resolve the
/// absolute path for agents that do not expand `~`), and each round trip is a
/// full SSH handshake. The session ID in the file name lets teardown remove
/// exactly this session's files.
public struct RemotePasteFileTransferPolicy: Equatable, Sendable {
    /// The random identity for one remote session.
    public let sessionID: UUID

    /// Creates a policy for one remote session.
    public init(sessionID: UUID = UUID()) {
        self.sessionID = sessionID
    }

    /// Returns the absolute remote path SCP writes and the terminal receives.
    public func remotePath(for fileURL: URL, uuid: UUID = UUID()) -> String {
        let suffix = sanitizedExtension(fileURL.pathExtension)
        let extensionSuffix = suffix.isEmpty ? "" : "." + suffix
        return "/tmp/" + fileNamePrefix + uuid.uuidString.lowercased() + extensionSuffix
    }

    /// Returns a shell script that removes only files owned by this policy.
    public func cleanupScript(for remotePaths: [String]) -> String {
        guard !remotePaths.isEmpty, remotePaths.allSatisfy(isOwnedPath) else {
            return "true"
        }
        return "rm -f -- " + remotePaths.map { "'" + $0 + "'" }.joined(separator: " ")
    }

    /// Returns a shell script that removes this session's paste files after relay teardown.
    public func teardownCleanupScript() -> String {
        "rm -f -- /tmp/" + fileNamePrefix + "*"
    }

    /// Owned paths contain only the fixed prefix, a UUID and a sanitized
    /// extension, so they are safe inside single quotes.
    private func isOwnedPath(_ remotePath: String) -> Bool {
        let prefix = "/tmp/" + fileNamePrefix
        guard remotePath.hasPrefix(prefix) else { return false }
        let rest = remotePath.dropFirst(prefix.count)
        return !rest.isEmpty && rest.unicodeScalars.allSatisfy {
            ($0.value >= 48 && $0.value <= 57) || ($0.value >= 97 && $0.value <= 122) ||
                $0 == "-" || $0 == "."
        }
    }

    private var fileNamePrefix: String {
        "cmux-paste-" + sessionID.uuidString.lowercased() + "-"
    }

    private func sanitizedExtension(_ value: String) -> String {
        let lowered = value.lowercased()
        let scalars = lowered.unicodeScalars.prefix(16)
        var result = ""
        for scalar in scalars where
            (scalar.value >= 48 && scalar.value <= 57) ||
            (scalar.value >= 97 && scalar.value <= 122) {
            result.unicodeScalars.append(scalar)
        }
        return result
    }
}
