import CmuxTerminal
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// The full paste worker re-executes the app binary, and on a loaded machine
/// that exec alone can outlast the paste deadline (#18819). These tests drive
/// the real worker client and process supervision with a scripted worker.
@Suite("Paste worker startup and the preparation deadline", .serialized, .timeLimit(.minutes(1)))
struct TerminalPasteWorkerStartupDeadlineTests {
    @Test("a worker whose startup outlasts the deadline still completes")
    func slowWorkerStartupDoesNotConsumePreparationDeadline() async throws {
        let worker = try ScriptedPasteWorker(
            startupDelay: "3",
            afterReady: "cp \"$RESPONSE\" \"$3/response.json\"",
            response: .terminal(.insertText("pasted after a slow start"))
        )
        defer { worker.remove() }
        let service = worker.service(deadline: .seconds(2))

        let content = await service.prepare(
            request: TerminalPasteboardReadRequest(
                pasteboardName: "cmux-slow-worker-start-\(UUID())",
                changeCount: 0
            ),
            mode: .paste
        )

        #expect(content == .insertText("pasted after a slow start"))
    }

}

/// A shell script standing in for `cmux --cmux-paste-preparation-worker`.
/// It sleeps to simulate exec and app-image load, prints the startup byte the
/// real worker prints once it is running, then runs `afterReady`.
struct ScriptedPasteWorker {
    let directory: URL
    let executableURL: URL

    init(
        startupDelay: String,
        afterReady: String,
        response: TerminalPastePreparationResult
    ) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-scripted-paste-worker-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        let responseURL = directory.appendingPathComponent("response.json")
        try JSONEncoder().encode(
            TerminalPastePreparationWorkerResponse(
                result: response,
                textPayload: nil,
                ownedTemporaryImageNames: []
            )
        ).write(to: responseURL)
        executableURL = directory.appendingPathComponent("worker.sh")
        let script = """
        #!/bin/sh
        RESPONSE='\(responseURL.path)'
        sleep \(startupDelay)
        printf r
        exec >/dev/null
        \(afterReady)
        """
        try Data(script.utf8).write(to: executableURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )
    }

    func service(
        deadline: Duration
    ) -> TerminalImageTransferPreparationService {
        let pasteboardService = TerminalPasteboardService()
        let client = TerminalPastePreparationWorkerClient(
            executableURL: executableURL,
            pasteboardService: pasteboardService
        )
        return TerminalImageTransferPreparationService(
            deadline: deadline,
            operation: { request in try await client.prepare(request) },
            cleanup: { result in
                result.cleanupTransferredTemporaryFiles(using: pasteboardService)
            },
            failureSignal: { _ in }
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
