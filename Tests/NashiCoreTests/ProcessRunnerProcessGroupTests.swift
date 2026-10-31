import XCTest
import Darwin
@testable import NashiCore

/// A tool's own children (LibreOffice helpers, ffmpeg under yt-dlp) inherit its
/// output pipes. Cancel, app termination and a normal exit must stop the whole
/// process group, and waiting for the pipes must be bounded.
final class ProcessRunnerProcessGroupTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws { root = try OutputFiles.temporaryDirectory() }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private let shell = URL(fileURLWithPath: "/bin/sh")

    func testExitedToolDoesNotWaitForItsBackgroundChild() throws {
        let pidFile = root.appendingPathComponent("child.pid")
        let started = Date()
        let result = try ProcessRunner.run(shell, ["-c", "sleep 30 & echo $! > \"$1\"; echo done", "sh", pidFile.path])
        XCTAssertLessThan(Date().timeIntervalSince(started), 6, "a leftover child holding stdout must not block the run")
        XCTAssertEqual(result.text.trimmingCharacters(in: .whitespacesAndNewlines), "done")
        try assertStopped(pidFile)
    }

    func testCancelStopsTheWholeProcessGroup() throws {
        let pidFile = root.appendingPathComponent("child.pid")
        let token = CancellationToken()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { token.cancel() }
        let started = Date()
        XCTAssertThrowsError(try ProcessRunner.run(shell, ["-c", "trap '' TERM; sleep 30 & echo $! > \"$1\"; wait", "sh", pidFile.path], token: token)) { error in
            guard case .cancelled? = error as? NashiError else { return XCTFail("expected cancellation, got \(error)") }
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 8, "cancel must stop a child that ignores SIGTERM, not wait for it")
        try assertStopped(pidFile)
    }

    func testTerminateAllStopsChildrenAndWaitsBoundedly() throws {
        let pidFile = root.appendingPathComponent("child.pid")
        let finished = expectation(description: "run returned")
        DispatchQueue.global().async {
            _ = try? ProcessRunner.run(self.shell, ["-c", "trap '' TERM; sleep 30 & echo $! > \"$1\"; wait", "sh", pidFile.path])
            finished.fulfill()
        }
        let ready = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: pidFile.path) && Date() < ready { Thread.sleep(forTimeInterval: 0.05) }
        Thread.sleep(forTimeInterval: 0.2)
        let started = Date()
        ProcessRunner.terminateAll()
        XCTAssertLessThan(Date().timeIntervalSince(started), 6, "terminateAll must be bounded even when SIGTERM is ignored")
        wait(for: [finished], timeout: 8)
        try assertStopped(pidFile)
    }

    func testWorkingDirectoryEnvironmentAndFailureAreKept() throws {
        let result = try ProcessRunner.run(shell, ["-c", "pwd -P; printf %s \"$NASHI_PROCESS_TEST\""], directory: root, environment: ["NASHI_PROCESS_TEST": "value"])
        let lines = result.text.split(separator: "\n").map(String.init)
        let resolved = try XCTUnwrap(realpath(root.path, nil)); defer { free(resolved) }
        XCTAssertEqual(lines.first, String(cString: resolved))
        XCTAssertEqual(lines.last, "value")
        XCTAssertThrowsError(try ProcessRunner.run(shell, ["-c", "echo broken >&2; exit 3"])) { error in
            guard case .failed(let message)? = error as? NashiError else { return XCTFail("expected failure, got \(error)") }
            XCTAssertEqual(message, "broken")
        }
        XCTAssertThrowsError(try ProcessRunner.run(root.appendingPathComponent("missing-tool"), []))
    }

    private func assertStopped(_ pidFile: URL, file: StaticString = #filePath, line: UInt = #line) throws {
        let text = try String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let pid = try XCTUnwrap(pid_t(text), file: file, line: line)
        let deadline = Date().addingTimeInterval(3)
        while kill(pid, 0) == 0 && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        XCTAssertNotEqual(kill(pid, 0), 0, "child \(pid) must not outlive the run", file: file, line: line)
        if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
    }
}
