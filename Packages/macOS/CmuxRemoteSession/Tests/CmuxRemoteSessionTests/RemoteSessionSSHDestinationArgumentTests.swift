import Foundation
import Testing
import CmuxCore
import CmuxRemoteDaemon
import CmuxRemoteWorkspace
@testable import CmuxRemoteSession

// The coordinator's background ssh and scp runs must read the destination as
// a host operand only, and batch execs must not carry the user's agent, X11
// or port forwards into sessions that only run a helper command.
@Suite("Coordinator background ssh argv passes the destination as an operand")
struct RemoteSessionSSHDestinationArgumentTests {
    @Test("Port-scan exec ends option parsing and turns off forwarding")
    func portScanExecEndsOptionParsingAndTurnsOffForwarding() throws {
        let runner = RecordingProcessRunner()
        let configured = ["ForwardAgent=yes", "ForwardX11=yes", "ClearAllForwardings=no"]
        let coordinator = Self.makeCoordinator(runner: runner, sshOptions: configured)
        let panelId = UUID()

        coordinator.queue.sync {
            coordinator.daemonReady = true
            coordinator.updateRemotePortScanTTYsLocked([panelId: "ttys010"])
            coordinator.performRemotePortScanLocked()
        }
        defer { coordinator.stop() }

        let request = try #require(runner.requests.first)
        #expect(request.executable == "/usr/bin/ssh")
        let destinationIndex = try #require(request.arguments.firstIndex(of: "user@example.test"))
        #expect(destinationIndex > 0 && request.arguments[destinationIndex - 1] == "--")
        for (override, option) in zip(
            ["ForwardAgent=no", "ForwardX11=no", "ClearAllForwardings=yes"],
            configured
        ) {
            let overrideIndex = try #require(Self.pairIndex(request.arguments, "-o", override))
            let configuredIndex = try #require(Self.pairIndex(request.arguments, "-o", option))
            #expect(overrideIndex < configuredIndex)
        }
    }

    @Test("Daemon bootstrap execs turn off forwarding")
    func daemonBootstrapTurnsOffForwarding() throws {
        let coordinator = Self.makeCoordinator(
            runner: RecordingProcessRunner(),
            sshOptions: ["ForwardAgent=yes"]
        )
        defer { coordinator.stop() }

        let arguments = coordinator.daemonBootstrapSSHArguments()
        let overrideIndex = try #require(Self.pairIndex(arguments, "-o", "ForwardAgent=no"))
        let configuredIndex = try #require(Self.pairIndex(arguments, "-o", "ForwardAgent=yes"))
        #expect(overrideIndex < configuredIndex)
    }

    @Test("Dropped-file SCP ends option parsing before its operands")
    func droppedFileUploadEndsOptionParsing() async throws {
        let localFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-drop-operand-regression-" + UUID().uuidString)
        try Data("payload".utf8).write(to: localFile)
        defer { try? FileManager.default.removeItem(at: localFile) }

        let runner = RecordingProcessRunner()
        let coordinator = Self.makeCoordinator(runner: runner)
        defer { coordinator.stop() }

        let succeeded = await withCheckedContinuation { continuation in
            coordinator.uploadDroppedFiles(
                [localFile],
                operation: RemoteProcessCancellationOperation()
            ) { result in
                switch result {
                case .success:
                    continuation.resume(returning: true)
                case .failure:
                    continuation.resume(returning: false)
                }
            }
        }
        #expect(succeeded)

        let scpRequest = try #require(
            runner.requests.first { $0.executable == "/usr/bin/scp" }
        )
        let arguments = scpRequest.arguments
        #expect(arguments.count >= 3)
        #expect(arguments.dropLast(2).last == "--")
        #expect(arguments.last?.hasPrefix("user@example.test:") == true)
        #expect(arguments.last?.contains(":/home/test user/.cache/cmux/paste/") == true)
    }

    // Exercise a timed-out copy after the directory preparation has succeeded.
    @Test("Dropped-file upload retries once after a timeout")
    func droppedFileUploadRetriesOnceAfterTimeout() async throws {
        let localFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-drop-retry-" + UUID().uuidString + ".png")
        try Data(count: 500_000).write(to: localFile)
        defer { try? FileManager.default.removeItem(at: localFile) }

        let scpAttempts = Counter()
        let runner = RecordingProcessRunner { request in
            if request.executable == "/usr/bin/scp", scpAttempts.increment() == 1 {
                throw NSError(domain: "cmux.remote.process", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "scp timed out after \(Int(request.timeout))s",
                ])
            }
            let stdout = request.arguments.contains {
                $0.contains("__CMUX_REMOTE_PASTE_HOME__")
            } ? "__CMUX_REMOTE_PASTE_HOME__/home/test user\n" : ""
            return RemoteCommandResult(status: 0, stdout: stdout, stderr: "")
        }
        let coordinator = Self.makeCoordinator(runner: runner)
        defer { coordinator.stop() }

        let paths = try await withCheckedThrowingContinuation { continuation in
            coordinator.uploadDroppedFiles(
                [localFile],
                operation: RemoteProcessCancellationOperation()
            ) { result in
                continuation.resume(with: result)
            }
        }

        let scps = runner.requests.filter { $0.executable == "/usr/bin/scp" }
        #expect(paths.count == 1)
        #expect(scps.count == 2)
        #expect(scps.first?.timeout ?? 0 < 20)
        #expect(scps.first?.arguments.last == scps.last?.arguments.last)
    }

    @Test("Reverse relay fallback ends option parsing and keeps its forward")
    func reverseRelayFallbackEndsOptionParsingAndKeepsItsForward() throws {
        let coordinator = Self.makeCoordinator(
            runner: RecordingProcessRunner(),
            sshOptions: ["ForwardAgent=yes"]
        )
        defer { coordinator.stop() }

        let arguments = coordinator.reverseRelayArguments(
            relayPort: 64_007,
            localRelayPort: 54_321
        )

        #expect(arguments.suffix(2) == ["--", "user@example.test"])
        // ClearAllForwardings would also drop the relay's own -R.
        #expect(!arguments.contains("ClearAllForwardings=yes"))
        #expect(Self.pairIndex(arguments, "-R", "127.0.0.1:64007:127.0.0.1:54321") != nil)
    }

    // MARK: - Helpers

    private static func pairIndex(_ args: [String], _ a: String, _ b: String) -> Int? {
        for i in args.indices.dropLast() where args[i] == a && args[i + 1] == b {
            return i
        }
        return nil
    }

    private static func makeCoordinator(
        runner: RecordingProcessRunner,
        sshOptions: [String] = []
    ) -> RemoteSessionCoordinator {
        let configuration = WorkspaceRemoteConfiguration(
            destination: "user@example.test",
            port: nil,
            identityFile: nil,
            sshOptions: sshOptions,
            localProxyPort: nil,
            relayPort: nil,
            relayID: nil,
            relayToken: nil,
            localSocketPath: nil,
            terminalStartupCommand: nil,
            preserveAfterTerminalExit: false,
            persistentDaemonSlot: nil
        )
        return RemoteSessionCoordinator(
            host: NoopRemoteSessionHost(),
            configuration: configuration,
            proxyBroker: SSHOverrideUnusedRemoteProxyBroker(),
            connectionBroker: NativeSSHConnectionBroker(),
            manifestRepository: RemoteDaemonManifestRepository(
                homeDirectory: FileManager.default.temporaryDirectory
            ),
            processRunner: runner,
            reachabilityProbe: SSHOverrideNoopReachabilityProbe(),
            relayCommandRewriter: SSHOverridePassthroughRelayCommandRewriter(),
            buildInfo: SSHOverrideStubBuildInfo(),
            daemonStrings: RemoteDaemonStrings(
                missingPersistentPTYCapability: "",
                missingRequiredFunctionality: "",
                cloudNotificationClearWorkspaceInvalid: "",
                cloudNotificationClearWorkspaceDenied: "",
                cloudNotificationClearSurfaceInvalid: ""
            ),
            strings: RemoteSessionStrings(
                connectedVMNoProxyFormat: "%@",
                suspendedDetailFormat: "%@",
                reverseRelayUnavailableRetrying: "",
                reverseRelayPortUnavailableRetrying: "",
                controlMasterOwnershipUnavailable: ""
            )
        )
    }
}

/// Thread-safe call counter for scripted process runners.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    /// Increments and returns the new count.
    func increment() -> Int { lock.withLock { value += 1; return value } }
}
