import XCTest
import PDFKit
@testable import NashiCore

/// OCR, slide export and raster compression sized their page thumbnails from the
/// PDF page box without a limit. A 1e20-point page must be refused with an
/// error, not allocated, trapped on, or silently written as an empty PDF.
final class PDFHugePageRasterLimitTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws { root = try OutputFiles.temporaryDirectory() }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testOCRRejectsHugePage() throws {
        let page = try XCTUnwrap(HugeMediaBoxPDF.document(in: root).page(at: 0))
        XCTAssertThrowsError(try PDFOfficeCodec.recognizedCells(page, token: .init()))
    }

    func testSlideExportRejectsHugePage() throws {
        let input = try HugeMediaBoxPDF.write(in: root)
        let work = root.appendingPathComponent("work"); try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        XCTAssertThrowsError(try PDFOfficeCodec.prepare(input, to: "pptx", at: work, options: .init(), token: .init()))
    }

    func testRasterCompressionRejectsHugePageInsteadOfWritingAnEmptyPDF() throws {
        let input = try HugeMediaBoxPDF.write(in: root)
        let output = root.appendingPathComponent("out"); try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var options = OperationOptions(); options.outputDirectory = output
        XCTAssertThrowsError(try PDFEngine.tool(.compress, inputs: [input], options: options, token: .init()))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: output.path), [], "no partial output remains")
    }
}
