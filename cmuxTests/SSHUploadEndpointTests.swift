import Foundation
import CmuxRemoteSession
import CmuxSettings
import Testing
#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite(.serialized)
struct SSHUploadEndpointTests {
    private func session(_ extra: [String] = []) throws -> DetectedSSHSession {
        try #require(TerminalSSHSessionDetector.detectForTesting(
            ttyName: "ttys004",
            processes: [.init(pid: 42, pgid: 42, tpgid: 42, tty: "ttys004", executableName: "ssh")],
            argumentsByPID: [42: ["ssh"] + extra + ["user@host.example"]]
        ))
    }

    @Test func sharesDifferentTerminalSessionEnvironment() throws {
        let first = try session(["-o", "SetEnv=LC_TMUX_SESSION=1"])
        let second = try session(["-o", "SetEnv=LC_TMUX_SESSION=2"])
        #expect(first.uploadEndpoint != nil)
        #expect(first.uploadEndpoint == second.uploadEndpoint)
        #expect(first.uploadEndpoint != (try session(["-p", "2222"])).uploadEndpoint)
        #expect(first.uploadEndpoint != (try session(["-i", "/tmp/other-key"])).uploadEndpoint)
    }

    @Test func leavesExplicitUserMastersAlone() throws {
        #expect(try session(["-S", "/tmp/custom-master"]).uploadEndpoint == nil)
        #expect(try session(["-o", "ControlMaster=no"]).uploadEndpoint == nil)
    }

    @Test(arguments: [false, true])
    func failedSharedTransferFallsBackOnce(includingTimeout: Bool) throws {
        let session = try session()
        var invocations: [[String]] = []
        DetectedSSHSession.runProcessOverrideForTesting = { _, args, _, _ in
            invocations.append(args)
            if invocations.count == 1 {
                if includingTimeout { throw NSError(domain: "cmux.detected-ssh.drop", code: 3) }
                return (255, "", "broken master")
            }
            return (0, "", "")
        }
        defer { DetectedSSHSession.runProcessOverrideForTesting = nil }
        let paths = try session.uploadDroppedFilesSync(
            [URL(fileURLWithPath: "/tmp/sample.png")], operation: TerminalImageTransferOperation(),
            usingControlPath: "/tmp/test-owned-master.sock"
        )
        #expect(paths.count == 1)
        #expect(invocations.count == 2)
        #expect(invocations.first?.contains("ControlPath=/tmp/test-owned-master.sock") == true)
        #expect(invocations.last?.contains("ControlPath=/tmp/test-owned-master.sock") == false)
    }

    @Test func cancellationDoesNotRetry() throws {
        let session = try session()
        let operation = TerminalImageTransferOperation()
        var invocations = 0
        DetectedSSHSession.runProcessOverrideForTesting = { _, _, _, _ in
            invocations += 1
            operation.cancel()
            throw TerminalImageTransferExecutionError.cancelled
        }
        defer { DetectedSSHSession.runProcessOverrideForTesting = nil }
        #expect(throws: (any Error).self) {
            try session.uploadDroppedFilesSync(
                [URL(fileURLWithPath: "/tmp/sample.png")], operation: operation,
                usingControlPath: "/tmp/test-owned-master.sock"
            )
        }
        #expect(invocations == 1)
    }

    @Test(arguments: [nil, "DisableFileTransfer", "DisableRemoteConnections"] as [String?])
    @MainActor
    func prewarmRespectsManagedPolicies(deniedKey: String?) async throws {
        let policy = ManagedDevicePolicy(
            releaseDomainDefaults: nil,
            forcedObject: { _, key in key == deniedKey ? true : nil },
            editionEnforcesKeys: false
        )
        var inspectedForeground = false
        let coordinator = PlainSSHUploadCoordinator(
            broker: NativeSSHConnectionBroker(), policy: policy,
            foregroundPIDs: { inspectedForeground = true; return [] }
        )
        defer { coordinator.stop() }
        await coordinator.refresh()
        #expect(inspectedForeground == (deniedKey == nil))
        #expect(coordinator.controlPath(for: try session()) == nil)
    }


    @Test(arguments: [true, false])
    func wrapperChildrenMustBelongToTheForegroundJob(sameGroup: Bool) throws {
        let detected = TerminalSSHSessionDetector.detect(
            foregroundPID: 100,
            argumentsForPID: { pid in
                pid == 100 ? ["ghostty", "+ssh", "--", "user@host.example"] : ["ssh", "user@host.example"]
            },
            processGroup: { pid in pid == 100 || sameGroup ? 100 : 200 },
            childPIDs: { $0 == 100 ? [101] : [] }
        )
        #expect((detected?.destination == "user@host.example") == sameGroup)
    }

}
