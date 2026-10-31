import XCTest
@testable import NashiCore

/// Matches Windows WebDownload.Validate: a pasted, dragged or redirected link
/// may not point at this Mac (loopback) or a .local name. Every URLSession
/// redirect is checked with the same `link` function.
final class WebDownloadLocalHostTests: XCTestCase {
    func testLoopbackAndLocalNamesAreRejected() {
        for address in ["http://localhost/a.mp4", "http://LOCALHOST.:8080/a.mp4", "http://api.localhost/a.mp4",
                        "http://127.0.0.1/a.mp4", "https://127.8.9.10/a.mp4", "http://127.1/a.mp4", "http://2130706433/a.mp4",
                        "http://0x7f.0.0.1/a.mp4", "http://0.0.0.0:3000/a.mp4", "http://[::1]/a.mp4", "http://[::]/a.mp4",
                        "http://[::ffff:127.0.0.1]/a.mp4", "http://printer.local/scan.jpg", "http://NAS.Local./v.mp4"] {
            XCTAssertThrowsError(try WebDownloadEngine.link(address), address)
        }
    }

    func testPublicLinksStillWork() throws {
        for address in ["https://www.youtube.com/watch?v=abc", "https://example.com/photo.jpg", "http://93.184.216.34/a.mp4",
                        "https://localhost.example.com/a.mp4", "https://local.example/a.mp4", "http://[2606:4700::1111]/a.mp4"] {
            XCTAssertEqual(try WebDownloadEngine.link(address).absoluteString, address)
        }
    }
}
