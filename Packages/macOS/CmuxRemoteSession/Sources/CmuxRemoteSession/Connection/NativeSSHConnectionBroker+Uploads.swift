public import Foundation
internal import Darwin

extension NativeSSHConnectionBroker {
    /// Prewarms one upload master per active endpoint and retires idle masters.
    /// - Parameters:
    ///   - endpoints: Complete set of locally owned foreground SSH endpoints.
    ///   - now: Observation time used for the ten-minute last-owner grace period.
    public func reconcileUploadConnections(_ endpoints: Set<SSHUploadEndpoint>, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        reconcileUploadConnections(endpoints, now: now, launch: Self.launchUploadMaster)
    }

    func reconcileUploadConnections(
        _ endpoints: Set<SSHUploadEndpoint>, now: TimeInterval,
        launch: ([String]) throws -> any RemoteReverseRelayProcess
    ) {
        for endpoint in Array(uploadConnections.keys) where !endpoints.contains(endpoint) {
            guard var entry = uploadConnections[endpoint] else { continue }
            if entry.idleSince == nil { entry.idleSince = now }
            if now - (entry.idleSince ?? now) >= 600 {
                entry.process?.terminate()
                try? FileManager.default.removeItem(atPath: entry.controlPath)
                uploadConnections.removeValue(forKey: endpoint)
            } else {
                uploadConnections[endpoint] = entry
            }
        }
        for endpoint in endpoints {
            var entry = uploadConnections[endpoint]
            entry?.idleSince = nil
            if let existing = entry, existing.process?.isRunning == true {
                uploadConnections[endpoint] = existing
                continue
            }
            // Failed authentication or an unavailable network must not trigger
            // one new login per pane or per observation tick.
            if let existing = entry, now - existing.lastAttempt < 15 {
                uploadConnections[endpoint] = existing
                continue
            }
            if let oldPath = entry?.controlPath { try? FileManager.default.removeItem(atPath: oldPath) }
            guard let directory = prepareUploadDirectory() else { continue }
            let path = directory.appendingPathComponent(UUID().uuidString.prefix(12) + ".sock").path
            let arguments = [
                "-N", "-T",
                "-o", "ControlMaster=yes", "-o", "ControlPersist=no",
                "-o", "ControlPath=\(path)",
                "-o", "ClearAllForwardings=yes", "-o", "ExitOnForwardFailure=yes",
                "-o", "ForwardAgent=no", "-o", "ForwardX11=no", "-o", "PermitLocalCommand=no",
                "-o", "ServerAliveInterval=5", "-o", "ServerAliveCountMax=1",
                "-o", "BatchMode=yes", "-o", "ConnectTimeout=6",
            ] + endpoint.arguments
            let process = try? launch(arguments)
            uploadConnections[endpoint] = SSHUploadConnectionEntry(
                process: process, controlPath: path, lastAttempt: now, idleSince: nil
            )
        }
    }

    /// Returns a ready socket, or nil so ordinary SCP remains the fallback.
    /// - Parameter endpoint: Exact transport whose connection may be reused.
    public func uploadControlPath(for endpoint: SSHUploadEndpoint) -> String? {
        guard let entry = uploadConnections[endpoint], entry.process?.isRunning == true else { return nil }
        var info = stat()
        guard lstat(entry.controlPath, &info) == 0, (info.st_mode & S_IFMT) == S_IFSOCK else { return nil }
        return entry.controlPath
    }

    /// Closes only upload masters owned by this broker when the application exits.
    public func stopUploadConnections() {
        for entry in uploadConnections.values { entry.process?.terminate() }
        uploadConnections.removeAll()
        if let directory = uploadConnectionDirectory { try? FileManager.default.removeItem(at: directory) }
        uploadConnectionDirectory = nil
    }

    private func prepareUploadDirectory() -> URL? {
        if let directory = uploadConnectionDirectory { return directory }
        // A short, app-private directory keeps Unix socket paths below the
        // platform limit and prevents another local user substituting a socket.
        let directory = URL(fileURLWithPath: "/tmp/cmux-upload-" + UUID().uuidString.prefix(16))
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            uploadConnectionDirectory = directory
            return directory
        } catch { return nil }
    }

    private static func launchUploadMaster(_ arguments: [String]) throws -> any RemoteReverseRelayProcess {
        let process = Process()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderr
        let handle = FoundationRemoteReverseRelayProcess(process: process, stderrPipe: stderr)
        try process.run()
        // Reuse the event-driven process handle and its bounded SIGTERM/SIGKILL
        // cleanup. A master has no remote-forward startup marker to wait for.
        handle.captureTermination { _ in }
        return handle
    }
}
