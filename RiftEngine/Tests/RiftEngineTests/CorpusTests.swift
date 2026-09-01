import Foundation
import XCTest
@testable import RiftEngine

/// the golden corpus is the engine's executable specification (sdd §10):
/// every folder under Corpus/ holds left.txt, right.txt, and the expected.json
/// the engine must reproduce. adding a regression test = adding a folder
private struct ExpectedReport: Codable, Equatable {
    let profile: String
    let verdict: String
    let convergenceLevel: String?
    let contentChanges: Int
    let formattingOnly: Int
    let hunkKinds: [String]
}

final class CorpusTests: XCTestCase {
    private func observed(_ report: DiffReport) -> ExpectedReport {
        let verdictName: String
        var convergence: String?
        var contentChanges = 0
        var formattingOnly = 0
        switch report.verdict {
        case .identical:
            verdictName = "identical"
            convergence = "L0"
        case let .formattingOnly(level, count):
            verdictName = "formattingOnly"
            convergence = level.label
            formattingOnly = count
        case let .changed(k, m):
            verdictName = "changed"
            contentChanges = k
            formattingOnly = m
        }
        let kinds = report.document.hunks.filter { $0.kind != .equal }.map(\.kind.rawValue)
        return ExpectedReport(profile: report.profile.profile.rawValue,
                              verdict: verdictName,
                              convergenceLevel: convergence,
                              contentChanges: contentChanges,
                              formattingOnly: formattingOnly,
                              hunkKinds: kinds)
    }

    func testGoldenCorpus() throws {
        let corpusURL = try XCTUnwrap(Bundle.module.url(forResource: "Corpus", withExtension: nil),
                                      "Corpus resource directory missing from test bundle")
        let fileManager = FileManager.default
        let entries = try fileManager
            .contentsOfDirectory(at: corpusURL, includingPropertiesForKeys: nil)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var caseCount = 0
        for entry in entries {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: entry.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                continue  // e.g. the corpus README
            }
            let name = entry.lastPathComponent
            let left = String(decoding: try Data(contentsOf: entry.appendingPathComponent("left.txt")),
                              as: UTF8.self)
            let right = String(decoding: try Data(contentsOf: entry.appendingPathComponent("right.txt")),
                               as: UTF8.self)
            let expectedData = try Data(contentsOf: entry.appendingPathComponent("expected.json"))
            let expected = try JSONDecoder().decode(ExpectedReport.self, from: expectedData)
            let got = observed(RiftEngine.compare(left, right))
            XCTAssertEqual(got, expected, "corpus case '\(name)'")
            caseCount += 1
        }
        XCTAssertGreaterThanOrEqual(caseCount, 20, "golden corpus looks incomplete")
    }
}
