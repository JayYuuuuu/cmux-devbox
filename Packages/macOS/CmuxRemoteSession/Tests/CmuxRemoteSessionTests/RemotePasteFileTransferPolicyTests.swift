import Foundation
import Testing
@testable import CmuxRemoteSession

@Suite("Remote paste file transfer policy")
struct RemotePasteFileTransferPolicyTests {
    @Test("remote paths use a private random directory and sanitized extension")
    func remotePathUsesPrivateRandomName() {
        let policy = RemotePasteFileTransferPolicy(
            sessionID: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
        )
        let path = policy.remotePath(
            for: URL(fileURLWithPath: "/tmp/clipboard image.PnG;touch") ,
            uuid: UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!
        )

        #expect(path == "~/.cache/cmux/paste/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee/cmux-paste-01234567-89ab-cdef-0123-456789abcdef.pngtouch")
        #expect(!path.contains("/tmp"))
        #expect(!path.contains(";"))
    }

    @Test("maintenance removes old files and trims oldest files over the cap")
    func maintenanceCleansByAgeAndSize() throws {
        let policy = RemotePasteFileTransferPolicy(
            sessionID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            maximumByteCount: 10
        )
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-remote-paste-\(UUID().uuidString)", isDirectory: true)
        let directory = home.appendingPathComponent(
            ".cache/cmux/paste/11111111-2222-3333-4444-555555555555",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let stale = directory.appendingPathComponent("cmux-paste-stale.png")
        let old = directory.appendingPathComponent("cmux-paste-old.png")
        let newest = directory.appendingPathComponent("cmux-paste-new.png")
        try Data(repeating: 0, count: 1).write(to: stale)
        try Data(repeating: 1, count: 8).write(to: old)
        try Data(repeating: 2, count: 8).write(to: newest)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -(policy.maximumAge + 60))],
            ofItemAtPath: stale.path
        )
        // Shell mtimes have one-second resolution; give the size-capped files
        // distinct ages so "oldest" does not fall back to glob order.
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -120)],
            ofItemAtPath: old.path
        )

        try runShell(policy.maintenanceScript(), home: home)

        #expect(!FileManager.default.fileExists(atPath: stale.path))
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: newest.path))
        #expect(try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber == 0o700)
    }

    @Test("teardown cleanup removes only cmux paste files")
    func teardownCleanupRemovesPasteFiles() throws {
        let policy = RemotePasteFileTransferPolicy(
            sessionID: UUID(uuidString: "66666666-7777-8888-9999-aaaaaaaaaaaa")!
        )
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-remote-paste-teardown-\(UUID().uuidString)", isDirectory: true)
        let directory = home.appendingPathComponent(
            ".cache/cmux/paste/66666666-7777-8888-9999-aaaaaaaaaaaa",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let pasteFile = directory.appendingPathComponent("cmux-paste-one.png")
        let otherFile = directory.appendingPathComponent("keep.txt")
        try Data("paste".utf8).write(to: pasteFile)
        try Data("keep".utf8).write(to: otherFile)

        try runShell(policy.teardownCleanupScript(), home: home)

        #expect(!FileManager.default.fileExists(atPath: pasteFile.path))
        #expect(FileManager.default.fileExists(atPath: otherFile.path))
    }

    @Test("finalize reports the absolute remote path so agents need no ~ expansion")
    func finalizeReportsAbsolutePath() throws {
        let policy = RemotePasteFileTransferPolicy(
            sessionID: UUID(uuidString: "77777777-8888-9999-aaaa-bbbbbbbbbbbb")!
        )
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-remote-paste-finalize-\(UUID().uuidString)", isDirectory: true)
        let directory = home.appendingPathComponent(
            ".cache/cmux/paste/77777777-8888-9999-aaaa-bbbbbbbbbbbb",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let remotePath = policy.remotePath(
            for: URL(fileURLWithPath: "/tmp/shot.png"),
            uuid: UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!
        )
        let file = directory.appendingPathComponent("cmux-paste-01234567-89ab-cdef-0123-456789abcdef.png")
        try Data("png".utf8).write(to: file)

        let stdout = try runShell(policy.finalizeScript(for: remotePath), home: home)
        let resolved = policy.resolvedRemotePath(finalizeStdout: stdout, remotePath: remotePath)

        #expect(resolved == file.path)
        #expect(!resolved.contains("~"))
        #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber == 0o600)
        // The resolved path still belongs to this session, so cleanup removes it.
        try runShell(policy.cleanupScript(for: [resolved]), home: home)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test("resolved path ignores rc-file noise and falls back when the output is foreign")
    func resolvedPathParsing() {
        let policy = RemotePasteFileTransferPolicy(
            sessionID: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
        )
        let remotePath = "~/.cache/cmux/paste/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee/cmux-paste-1.png"
        let absolute = "/home/dev user/.cache/cmux/paste/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee/cmux-paste-1.png"

        #expect(policy.resolvedRemotePath(finalizeStdout: "welcome!\r\n" + absolute + "\n", remotePath: remotePath) == absolute)
        #expect(policy.resolvedRemotePath(finalizeStdout: "", remotePath: remotePath) == remotePath)
        #expect(policy.resolvedRemotePath(finalizeStdout: "/etc/passwd\n", remotePath: remotePath) == remotePath)
        #expect(policy.resolvedRemotePath(
            finalizeStdout: "/home/u/.cache/cmux/paste/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee/cmux-paste-2.png",
            remotePath: remotePath
        ) == remotePath)
        #expect(policy.cleanupScript(for: [absolute]).hasPrefix("rm -f -- "))
        #expect(policy.cleanupScript(for: ["/etc/passwd"]) == "true")
    }

    @discardableResult
    private func runShell(_ script: String, home: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        process.environment = ["HOME": home.path]
        let stdout = Pipe()
        process.standardOutput = stdout
        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        return String(decoding: data, as: UTF8.self)
    }
}
