import XCTest
import PDFKit
@testable import NashiCore

/// A page whose MediaBox is 1e20 points wide, with one image drawn across it.
/// Rasterizing it converted the scaled size to Int before any limit, which
/// trapped the whole app instead of reporting an oversized page.
final class PDFHugeMediaBoxTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws { root = try OutputFiles.temporaryDirectory() }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testPreservePagesRejectsHugeMediaBoxInsteadOfTrapping() throws {
        let pdf = try HugeMediaBoxPDF.document(in: root)
        XCTAssertThrowsError(try PDFDocumentReconstruction.preservePages(pdf, at: root.appendingPathComponent("pages.fodt"), options: .init(), token: .init()))
    }

    func testEditableReconstructionRejectsHugePlacedImageInsteadOfTrapping() throws {
        let pdf = try HugeMediaBoxPDF.document(in: root)
        let page = try XCTUnwrap(pdf.page(at: 0))
        XCTAssertFalse(try PDFPlacedImages.regions(page, token: .init()).isEmpty, "the editable path must reach the image raster")
        XCTAssertThrowsError(try PDFDocumentReconstruction.document(pdf, at: root.appendingPathComponent("editable.fodt"), options: .init(), token: .init()))
    }
}

/// Hand-written so the 1e20 box is stored exactly as PDF number syntax.
enum HugeMediaBoxPDF {
    static func write(in root: URL) throws -> URL {
        let huge = "100000000000000000000"
        let content = "q \(huge) 0 0 \(huge) 0 0 cm /Im0 Do Q\n"
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 \(huge) \(huge)] /Resources << /XObject << /Im0 5 0 R >> >> /Contents 4 0 R >>",
            "<< /Length \(content.utf8.count) >>\nstream\n\(content)endstream",
            "<< /Type /XObject /Subtype /Image /Width 1 /Height 1 /ColorSpace /DeviceGray /BitsPerComponent 8 /Length 1 >>\nstream\n\u{40}\nendstream"
        ]
        var data = "%PDF-1.4\n"
        var offsets: [Int] = []
        for (index, object) in objects.enumerated() {
            offsets.append(data.utf8.count)
            data += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xref = data.utf8.count
        data += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets { data += String(format: "%010d 00000 n \n", offset) }
        data += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        let url = root.appendingPathComponent("huge.pdf")
        try Data(data.utf8).write(to: url)
        return url
    }

    static func document(in root: URL) throws -> PDFDocument {
        let pdf = try XCTUnwrap(PDFDocument(url: write(in: root)))
        let bounds = try XCTUnwrap(pdf.page(at: 0)).bounds(for: .cropBox)
        XCTAssertGreaterThan(bounds.width, 1e15, "the fixture must keep its huge page size")
        return pdf
    }
}
