public import Foundation

/// Owns the private remote directory and cleanup contract for pasted files.
public struct RemotePasteFileTransferPolicy: Equatable, Sendable {
    /// The maximum number of bytes retained in one session's paste directory.
    public let maximumByteCount: Int64

    /// The age after which an uploaded paste file is eligible for cleanup.
    public let maximumAge: TimeInterval

    /// The random directory identity for one remote session.
    public let sessionID: UUID

    /// Creates a policy for one remote session.
    public init(
        sessionID: UUID = UUID(),
        maximumByteCount: Int64 = 200 * 1024 * 1024,
        maximumAge: TimeInterval = 24 * 60 * 60
    ) {
        self.sessionID = sessionID
        self.maximumByteCount = max(1, maximumByteCount)
        self.maximumAge = max(60, maximumAge)
    }

    /// Returns the shell path used by SCP for an uploaded file.
    public func remotePath(for fileURL: URL, uuid: UUID = UUID()) -> String {
        let suffix = sanitizedExtension(fileURL.pathExtension)
        let extensionSuffix = suffix.isEmpty ? "" : "." + suffix
        let fileName = "cmux-paste-" + uuid.uuidString.lowercased() + extensionSuffix
        return "~/" + relativeDirectoryPath + "/" + fileName
    }

    /// Returns a shell script that creates the private directory and removes stale or oversized files.
    public func maintenanceScript() -> String {
        let directory = shellDirectoryExpression
        let ageMinutes = max(1, Int(maximumAge / 60))
        return [
            "set -eu",
            "dir=" + directory,
            "umask 077",
            "mkdir -p \"$dir\"",
            "chmod 700 \"$dir\"",
            "find \"$dir\" -type f -name 'cmux-paste-*' -mmin +" + String(ageMinutes) + " -delete",
            "total=0",
            "for file in \"$dir\"/cmux-paste-*; do",
            "  [ -f \"$file\" ] || continue",
            "  bytes=$(wc -c < \"$file\" 2>/dev/null || printf '0')",
            "  total=$((total + bytes))",
            "done",
            "while [ \"$total\" -gt " + String(maximumByteCount) + " ]; do",
            "  oldest=''",
            "  oldest_mtime=9223372036854775807",
            "  for file in \"$dir\"/cmux-paste-*; do",
            "    [ -f \"$file\" ] || continue",
            "    mtime=$(stat -c %Y \"$file\" 2>/dev/null || stat -f %m \"$file\" 2>/dev/null || printf '0')",
            "    if [ \"$mtime\" -lt \"$oldest_mtime\" ]; then",
            "      oldest=\"$file\"",
            "      oldest_mtime=\"$mtime\"",
            "    fi",
            "  done",
            "  [ -n \"$oldest\" ] || break",
            "  bytes=$(wc -c < \"$oldest\" 2>/dev/null || printf '0')",
            "  rm -f -- \"$oldest\"",
            "  total=$((total - bytes))",
            "done",
        ].joined(separator: "\n")
    }

    /// Returns a shell script that enforces mode `0600` after SCP creates a file
    /// and prints the file's absolute remote path on its last stdout line.
    public func finalizeScript(for remotePath: String) -> String {
        guard let fileName = ownedFileName(in: remotePath) else {
            return "false"
        }
        let path = "\"$HOME/" + relativeDirectoryPath + "/" + fileName + "\""
        // No `--` for chmod: macOS chmod rejects it as a file operand, and
        // "$HOME/..." already starts with "/" so it cannot read as an option.
        return "chmod 600 \(path) && test -f \(path) && printf '%s\\n' \(path)"
    }

    /// Returns the absolute remote path reported by ``finalizeScript(for:)``.
    ///
    /// Agents such as Claude Code only attach a pasted image when the pasted
    /// text names a file that exists as written; they do not expand `~`, so the
    /// home-relative SCP path must not reach the terminal. Falls back to
    /// `remotePath` when the output does not name this exact file (for example
    /// a remote shell that predates the printf, or rc-file noise only).
    public func resolvedRemotePath(finalizeStdout: String, remotePath: String) -> String {
        guard let fileName = ownedFileName(in: remotePath) else { return remotePath }
        let suffix = "/" + relativeDirectoryPath + "/" + fileName
        let lastLine = finalizeStdout
            .split(whereSeparator: \.isNewline)
            .last
            .map(String.init) ?? ""
        guard lastLine.hasPrefix("/"),
              lastLine.hasSuffix(suffix),
              lastLine.count > suffix.count else {
            return remotePath
        }
        return lastLine
    }

    /// Returns a shell script that removes only files owned by this policy.
    public func cleanupScript(for remotePaths: [String]) -> String {
        let fileNames = remotePaths.compactMap(ownedFileName(in:))
        guard fileNames.count == remotePaths.count, !fileNames.isEmpty else {
            return "true"
        }
        let paths = fileNames.map {
            "\"$HOME/" + relativeDirectoryPath + "/" + $0 + "\""
        }.joined(separator: " ")
        return "rm -f -- " + paths
    }

    /// Returns a shell script that removes this session's paste files after relay teardown.
    public func teardownCleanupScript() -> String {
        let directory = shellDirectoryExpression
        return [
            "set -eu",
            "dir=" + directory,
            "if [ -d \"$dir\" ]; then",
            "  find \"$dir\" -type f -name 'cmux-paste-*' -delete",
            "  rmdir \"$dir\" 2>/dev/null || true",
            "fi",
        ].joined(separator: "\n")
    }

    /// Returns the paste file name when `remotePath` points into this
    /// session's directory, either home-relative (`~/…`, as handed to SCP) or
    /// absolute (as resolved by ``resolvedRemotePath(finalizeStdout:remotePath:)``).
    private func ownedFileName(in remotePath: String) -> String? {
        let directorySuffix = relativeDirectoryPath + "/"
        let fileName: Substring
        if remotePath.hasPrefix("~/" + directorySuffix) {
            fileName = remotePath.dropFirst(2 + directorySuffix.count)
        } else if remotePath.hasPrefix("/"),
                  let range = remotePath.range(of: "/" + directorySuffix, options: .backwards),
                  range.upperBound < remotePath.endIndex {
            fileName = remotePath[range.upperBound...]
        } else {
            return nil
        }
        guard fileName.hasPrefix("cmux-paste-"), !fileName.contains("/") else { return nil }
        return String(fileName)
    }

    private var relativeDirectoryPath: String {
        ".cache/cmux/paste/" + sessionID.uuidString.lowercased()
    }

    private var shellDirectoryExpression: String {
        "\"$HOME/" + relativeDirectoryPath + "\""
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
