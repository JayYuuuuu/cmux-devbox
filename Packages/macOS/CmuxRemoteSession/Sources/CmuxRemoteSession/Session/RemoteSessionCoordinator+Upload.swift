internal import CmuxCore
public import Foundation

// File upload onto the remote host over scp, with rollback of already-uploaded
// files on failure or cancellation. DevBox: one scp per file straight to the
// absolute /tmp path from RemotePasteFileTransferPolicy, no extra ssh hops.
extension RemoteSessionCoordinator {
    /// Uploads local files to per-session /tmp paths on the remote host,
    /// completing on the main queue with the remote paths.
    public func uploadDroppedFiles(
        _ fileURLs: [URL],
        operation: any RemoteTransferCancelling,
        completion: @escaping @Sendable (Result<[String], any Error>) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async {
                    completion(.failure(RemoteDropUploadError.unavailable))
                }
                return
            }

            do {
                try operation.throwIfCancelled()
                let remotePaths = try self.uploadDroppedFilesLocked(fileURLs, operation: operation)
                try operation.throwIfCancelled()
                DispatchQueue.main.async { [weak self] in
                    if operation.isCancelled {
                        guard let self else {
                            completion(.failure(operation.cancellationError))
                            return
                        }
                        self.queue.async { [weak self] in
                            self?.cleanupUploadedRemotePaths(remotePaths)
                            DispatchQueue.main.async {
                                completion(.failure(operation.cancellationError))
                            }
                        }
                    } else {
                        completion(.success(remotePaths))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    private func uploadDroppedFilesLocked(
        _ fileURLs: [URL],
        operation: any RemoteTransferCancelling
    ) throws -> [String] {
        guard !fileURLs.isEmpty else { return [] }

        let scpSSHOptions = backgroundSSHOptions(configuration.sshOptions)
        var uploadedRemotePaths: [String] = []
        do {
            try operation.throwIfCancelled()
            // Mark before copying: a failed scp may still leave a partial file.
            hasTouchedRemotePasteDirectory = true
            for localURL in fileURLs {
                try operation.throwIfCancelled()
                let normalizedLocalURL = localURL.standardizedFileURL
                guard normalizedLocalURL.isFileURL else {
                    throw RemoteDropUploadError.invalidFileURL
                }

                let remotePath = remotePastePolicy.remotePath(for: normalizedLocalURL)
                uploadedRemotePaths.append(remotePath)
                // SCP's stream is a batch protocol; a remote PTY would corrupt
                // its framing even when an interactive workspace requested one.
                var scpArgs: [String] = [
                    "-q",
                    "-o", "ControlMaster=no",
                    "-o", "RequestTTY=no",
                ]
                if !hasSSHOptionKey(scpSSHOptions, key: "StrictHostKeyChecking") {
                    scpArgs += ["-o", "StrictHostKeyChecking=accept-new"]
                }
                if let port = configuration.port {
                    scpArgs += ["-P", String(port)]
                }
                if let identityFile = configuration.identityFile,
                   !identityFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    scpArgs += ["-i", identityFile]
                }
                for option in scpSSHOptions {
                    scpArgs += ["-o", option]
                }
                scpArgs += ["--", normalizedLocalURL.path, "\(configuration.destination):\(remotePath)"]

                // DevBox: a paste once finished on the server in 0.2 s while
                // the local scp lingered until a fixed 45 s timeout. Scale the
                // timeout with the file and retry a timed-out copy once.
                let fileSize = (try? normalizedLocalURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                let timeout = Self.uploadTimeout(forFileSize: fileSize)
                let scpResult: RemoteCommandResult
                do {
                    scpResult = try scpExec(arguments: scpArgs, timeout: timeout, operation: operation)
                } catch let error as NSError where Self.isProcessTimeout(error) {
                    try operation.throwIfCancelled()
                    scpResult = try scpExec(arguments: scpArgs, timeout: timeout, operation: operation)
                }
                guard scpResult.status == 0 else {
                    let detail = Self.bestErrorLine(stderr: scpResult.stderr, stdout: scpResult.stdout) ??
                        "scp exited \(scpResult.status)"
                    throw RemoteDropUploadError.uploadFailed(detail)
                }
            }
            return uploadedRemotePaths
        } catch {
            cleanupUploadedRemotePaths(uploadedRemotePaths)
            throw error
        }
    }

    /// 10 s plus 1 s per 100 KB, capped at the former fixed 45 s.
    static func uploadTimeout(forFileSize bytes: Int) -> TimeInterval {
        min(45, 10 + TimeInterval(max(0, bytes)) / 100_000)
    }

    /// Whether `error` is the process runner's timeout.
    static func isProcessTimeout(_ error: NSError) -> Bool {
        error.domain == "cmux.remote.process" && error.code == 2
    }

    /// The private remote path a dropped or pasted local file uploads to.
    /// Kept as a compatibility entry point for callers that only need a
    /// path-shaped fixture; production uploads use the coordinator's session
    /// policy so teardown can remove only its own files.
    public static func remoteDropPath(for fileURL: URL, uuid: UUID = UUID()) -> String {
        RemotePasteFileTransferPolicy(
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        ).remotePath(for: fileURL, uuid: uuid)
    }

    func cleanupUploadedRemotePaths(_ remotePaths: [String]) {
        guard !remotePaths.isEmpty else { return }
        let cleanupScript = remotePastePolicy.cleanupScript(for: remotePaths)
        let cleanupCommand = "sh -c \(cleanupScript.shellSingleQuoted)"
        _ = try? sshExec(
            arguments: sshCommonArguments(batchMode: true) + ["--", configuration.destination, cleanupCommand],
            timeout: 8
        )
    }

    func cleanupRemotePasteDirectoryLocked() {
        let command = "sh -c \(remotePastePolicy.teardownCleanupScript().shellSingleQuoted)"
        _ = try? sshExec(
            arguments: sshCommonArguments(batchMode: true) + ["--", configuration.destination, command],
            timeout: 8
        )
    }
}
