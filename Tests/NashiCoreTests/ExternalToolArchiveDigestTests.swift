import XCTest
@testable import NashiCore

/// Every downloaded archive is checked against a pinned SHA-256 before libarchive
/// parses it; a "binary" zip also pins the executable it contains.
final class ExternalToolArchiveDigestTests: XCTestCase {
    func testEveryArchiveHasAPinnedDigestBeforeExtraction() {
        let hex = "^[0-9a-f]{64}$"
        for package in ExternalToolSetup.mediaPackages {
            XCTAssertNotNil(package.2.range(of: hex, options: .regularExpression), package.0)
            if package.3 == "binary" {
                XCTAssertNotNil(package.4?.range(of: hex, options: .regularExpression), "\(package.0) zip must be pinned")
                XCTAssertNotEqual(package.4, package.2, package.0)
            } else {
                XCTAssertNil(package.4, package.0)
            }
        }
    }

    func testMismatchedArchiveIsRejected() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("Nashi-digest-\(UUID().uuidString).zip")
        try Data("not the pinned archive".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertThrowsError(try ExternalToolSetup.verify(file, digest: ExternalToolSetup.mediaPackages[0].4 ?? ""))
        XCTAssertThrowsError(try ExternalToolSetup.verify(file, digest: ""))
    }
}
