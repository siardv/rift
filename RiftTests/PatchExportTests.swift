import CoreTransferable
import Foundation
import RiftEngine
import UniformTypeIdentifiers
import XCTest

/// materialize the real transferable so its type, filename and bytes are checked
final class PatchExportTests: XCTestCase {
    func testPartialLineHunksKeepActualLineCountsAndBytes() {
        let cases: [(String, String, String)] = [
            ("Before.\n", "After.\n", "-Before.\n+After.\n"),
            ("hello old\n", "hello new\n", "-hello old\n+hello new\n"),
            ("é\n", "e\u{301}\n", "-é\n+e\u{301}\n"),
            ("Before.\r\n", "After.\r\n", "-Before.\r\n+After.\r\n"),
            ("Before.\r\n", "After.\n", "-Before.\r\n+After.\n"),
            ("Before.", "After.", "-Before.\n\\ No newline at end of file\n+After.\n\\ No newline at end of file\n"),
        ]
        for (a, b, body) in cases {
            let patch = Export.unifiedPatch(a: a, b: b, document: RiftEngine.compare(a, b).document)
            XCTAssertEqual(Data(patch.utf8), Data(("--- a\n+++ b\n@@ -1,1 +1,1 @@\n" + body).utf8), patch)
        }
    }

    func testAdvertisedTypePreservesPatchExtensionAndTextCompatibility() throws {
        guard #available(iOS 18.2, *) else {
            throw XCTSkip("transfer inspection requires iOS 18.2")
        }
        let types = PatchExport.exportedContentTypes()
        let type = try XCTUnwrap(types.first)
        XCTAssertEqual(types.count, 1)
        XCTAssertEqual(type.preferredFilenameExtension, "patch")
        XCTAssertTrue(type.conforms(to: .plainText))
    }

    func testMaterializedExportHasExactFilenameAndUnifiedPatchBytes() async throws {
        guard #available(iOS 18.2, *) else {
            throw XCTSkip("transfer materialization requires iOS 18.2")
        }
        let a = "Before.\n"
        let b = "After.\n"
        let item = PatchExport(a: a, b: b, document: RiftEngine.compare(a, b).document)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rift_patch_export_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = try await item.export(to: directory, contentType: nil)
        XCTAssertEqual(file.lastPathComponent, "rift-comparison.patch")
        XCTAssertEqual(try Data(contentsOf: file),
                       Data("--- a\n+++ b\n@@ -1,1 +1,1 @@\n-Before.\n+After.\n".utf8))
    }
}
