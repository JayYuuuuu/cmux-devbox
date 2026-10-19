import Foundation
import Testing
@testable import CmuxRemoteSession

@MainActor
@Suite("Plain SSH upload master lifecycle")
struct SSHUploadConnectionsTests {
    @Test func sharesAcrossOwnersAndWaitsTenMinutesAfterLastOwner() {
        let broker = NativeSSHConnectionBroker()
        let endpoint = SSHUploadEndpoint(arguments: ["user@host.example"])
        let process = UploadMasterTestProcess()
        var launches = 0
        func update(_ active: Set<SSHUploadEndpoint>, _ seconds: Double) {
            broker.reconcileUploadConnections(active, now: Date(timeIntervalSince1970: seconds)) { _ in
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
        let first = SSHUploadEndpoint(arguments: ["first@host.example"])
        let second = SSHUploadEndpoint(arguments: ["second@host.example"])
        let process = UploadMasterTestProcess()
        var launches = 0
        broker.reconcileUploadConnections([first, second], now: Date()) { _ in
            launches += 1
            return process
        }
        #expect(launches == 2)
        broker.stopUploadConnections()
        #expect(process.terminations == 2)
    }

    @Test func reconnectsDeadMasterWithoutRepeatedAuthenticationAttempts() {
        let broker = NativeSSHConnectionBroker()
        let endpoint = SSHUploadEndpoint(arguments: ["host.example"])
        let process = UploadMasterTestProcess()
        var launches = 0
        for seconds in [0.0, 1.0, 16.0] {
            broker.reconcileUploadConnections([endpoint], now: Date(timeIntervalSince1970: seconds)) { _ in
                launches += 1
                return process
            }
            process.isRunning = false
        }
        #expect(launches == 2)
    }
}
