import Foundation
import Testing
@testable import CmuxRemoteSession

@Suite("Remote paste file transfer policy")
struct RemotePasteFileTransferPolicyTests {
    private let policy = RemotePasteFileTransferPolicy(
        sessionID: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
    )

    @Test("remote paths are absolute /tmp paths with a sanitized extension")
    func remotePathIsAbsoluteTmpPath() {
        let path = policy.remotePath(
            for: URL(fileURLWithPath: "/tmp/clipboard image.PnG;touch"),
            uuid: UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!
        )

        #expect(path == "/tmp/cmux-paste-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee-01234567-89ab-cdef-0123-456789abcdef.pngtouch")
        #expect(!path.contains("~"))
        #expect(!path.contains(";"))
    }

    @Test("cleanup only names this session's files")
    func cleanupOnlyNamesOwnedFiles() {
        let owned = policy.remotePath(for: URL(fileURLWithPath: "/x/a.png"))
        let other = RemotePasteFileTransferPolicy().remotePath(for: URL(fileURLWithPath: "/x/a.png"))

        #expect(policy.cleanupScript(for: [owned]) == "rm -f -- '\(owned)'")
        #expect(policy.cleanupScript(for: [owned, other]) == "true")
        #expect(policy.cleanupScript(for: ["/etc/passwd"]) == "true")
        #expect(policy.cleanupScript(for: [owned + "'; rm -rf /"]) == "true")
        #expect(policy.cleanupScript(for: []) == "true")
    }

    @Test("teardown removes this session's files and keeps others")
    func teardownRemovesOnlyThisSession() throws {
        let owned = policy.remotePath(for: URL(fileURLWithPath: "/x/a.png"))
        let other = RemotePasteFileTransferPolicy().remotePath(for: URL(fileURLWithPath: "/x/b.png"))
        try Data("a".utf8).write(to: URL(fileURLWithPath: owned))
        try Data("b".utf8).write(to: URL(fileURLWithPath: other))
        defer {
            try? FileManager.default.removeItem(atPath: owned)
            try? FileManager.default.removeItem(atPath: other)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", policy.teardownCleanupScript()]
        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
        #expect(!FileManager.default.fileExists(atPath: owned))
        #expect(FileManager.default.fileExists(atPath: other))
    }
}
