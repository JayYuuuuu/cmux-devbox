/// Identifies one plain-SSH upload transport by its full connection arguments.
/// Session-only environment and interactive commands are removed by the caller.
public struct SSHUploadEndpoint: Hashable, Sendable {
    /// Noninteractive SSH arguments, including the destination as the last item.
    public let arguments: [String]

    /// Creates an endpoint without conflating different credentials or routes.
    /// - Parameter arguments: SSH transport arguments and destination.
    public init(arguments: [String]) { self.arguments = arguments }
}
