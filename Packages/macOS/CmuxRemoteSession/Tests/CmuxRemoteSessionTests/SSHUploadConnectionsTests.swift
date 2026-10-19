import Foundation
import Testing
@testable import CmuxRemoteSession

@MainActor
@Suite("Plain SSH upload master lifecycle")
struct SSHUploadConnectionsTests {
    @Test func sharesAcrossOwnersAndWaitsTenMinutesAfterLastOwner() {
        let broker = NativeSSHConnectionBroker()
        defer { broker.stopUploadConnections() }
        let endpoint = SSHUploadEndpoint(arguments: ["user@host.example"])
        let process = UploadMasterTestProcess()
        var launches = 0
        func update(_ active: Set<SSHUploadEndpoint>, _ seconds: Double) {
            broker.reconcileUploadConnections(active, now: seconds) { _ in
                launches += 1
                return process
            }
        }
        update([endpoint, endpoint], 0)
        update([endpoint], 1000) // one owner is still present, even after ten minutes
        #expect(launches == 1)
        update([], 1001)
        update([], 1599)
        #expect(process.terminations == 0)
        update([], 1601)
        #expect(process.terminations == 1)
    }

    @Test func separatesCredentialsAndReapsAllOnQuit() {
        let broker = NativeSSHConnectionBroker()
        defer { broker.stopUploadConnections() }
        let first = SSHUploadEndpoint(arguments: ["first@host.example"])
        let second = SSHUploadEndpoint(arguments: ["second@host.example"])
        let process = UploadMasterTestProcess()
        var launches = 0
        broker.reconcileUploadConnections([first, second], now: 0) { _ in
            launches += 1
            return process
        }
        #expect(launches == 2)
        broker.stopUploadConnections()
        #expect(process.terminations == 2)
    }

    @Test func distinctClientsNeverCloseEachOthersMaster() {
        let first = NativeSSHConnectionBroker()
        let second = NativeSSHConnectionBroker()
        defer { first.stopUploadConnections(); second.stopUploadConnections() }
        let endpoint = SSHUploadEndpoint(arguments: ["user@host.example"])
        let firstProcess = UploadMasterTestProcess()
        let secondProcess = UploadMasterTestProcess()
        var paths: [String] = []
        first.reconcileUploadConnections([endpoint], now: 0) { args in
            paths.append(try #require(args.first(where: { $0.hasPrefix("ControlPath=") })))
            return firstProcess
        }
        second.reconcileUploadConnections([endpoint], now: 0) { args in
            paths.append(try #require(args.first(where: { $0.hasPrefix("ControlPath=") })))
            return secondProcess
        }
        #expect(paths.count == 2)
        #expect(Set(paths).count == 2)
        first.stopUploadConnections()
        #expect(firstProcess.terminations == 1)
        #expect(secondProcess.terminations == 0)
    }

    @Test func returningOwnerCancelsTheOldExpiry() {
        let broker = NativeSSHConnectionBroker()
        defer { broker.stopUploadConnections() }
        let endpoint = SSHUploadEndpoint(arguments: ["user@host.example"])
        let process = UploadMasterTestProcess()
        for (active, time) in [(true, 0.0), (false, 10.0), (true, 500.0), (false, 700.0), (false, 1299.0)] {
            broker.reconcileUploadConnections(active ? [endpoint] : [], now: time) { _ in process }
        }
        #expect(process.terminations == 0)
        broker.reconcileUploadConnections([], now: 1300) { _ in process }
        #expect(process.terminations == 1)
    }

    @Test func reconnectsDeadMasterWithoutRepeatedAuthenticationAttempts() {
        let broker = NativeSSHConnectionBroker()
        defer { broker.stopUploadConnections() }
        let endpoint = SSHUploadEndpoint(arguments: ["host.example"])
        let process = UploadMasterTestProcess()
        var launches = 0
        for seconds in [0.0, 1.0, 16.0] {
            broker.reconcileUploadConnections([endpoint], now: seconds) { _ in
                launches += 1
                return process
            }
            process.isRunning = false
        }
        #expect(launches == 2)
    }
}
