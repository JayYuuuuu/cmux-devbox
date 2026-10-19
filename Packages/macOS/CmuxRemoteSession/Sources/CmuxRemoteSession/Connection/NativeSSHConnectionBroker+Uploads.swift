public import Foundation

extension NativeSSHConnectionBroker {
    /// Prewarms one upload master per active endpoint and retires idle masters.
    /// - Parameters:
    ///   - endpoints: Complete set of locally owned foreground SSH endpoints.
    ///   - now: Observation time used for the ten-minute last-owner grace period.
    public func reconcileUploadConnections(_ endpoints: Set<SSHUploadEndpoint>, now: Date = Date()) {
        reconcileUploadConnections(endpoints, now: now, launch: { _ in fatalError("unimplemented upload master") })
    }

    func reconcileUploadConnections(
        _ endpoints: Set<SSHUploadEndpoint>, now: Date,
        launch: ([String]) throws -> any RemoteReverseRelayProcess
    ) {}

    /// Returns a ready socket, or nil so ordinary SCP remains the fallback.
    /// - Parameter endpoint: Exact transport whose connection may be reused.
    public func uploadControlPath(for endpoint: SSHUploadEndpoint) -> String? { nil }

    /// Closes only upload masters owned by this broker when the application exits.
    public func stopUploadConnections() {}
}
