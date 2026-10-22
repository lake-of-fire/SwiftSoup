import Foundation
import XCTest
@testable import SwiftSoup

final class DocumentLookupStackSafetyTest: XCTestCase {
    func testDeepMissingAndPresentLookupsOnSmallStack() {
        let done = DispatchSemaphore(value: 0)
        let thread = Thread {
            defer { done.signal() }
            do {
                // Build bottom-up using public mutation APIs so the reproducer
                // does not depend on parser recursion or quadratic setup work.
                let doc = Document("")
                var root = try Element(Tag.valueOf("n"), "")
                let head = try root.appendElement("head")
                let body = try root.appendElement("body")
                for _ in 0..<4_000 {
                    let parent = try Element(Tag.valueOf("n"), "")
                    try parent.appendChild(root)
                    root = parent
                }
                try doc.appendChild(root)
                XCTAssertTrue(doc.head() === head)
                XCTAssertTrue(doc.body() === body)
                try head.remove()
                try body.remove()
                XCTAssertNil(doc.head())
                XCTAssertNil(doc.body())
            } catch {
                XCTFail("Unexpected lookup failure: \(error)")
            }
        }
        thread.stackSize = 512 * 1024
        thread.start()
        XCTAssertEqual(done.wait(timeout: .now() + 60), .success)
    }

    func testPreorderAndCaseSensitiveNameMatchingArePreserved() throws {
        let doc = try Parser.xmlParser().parseInput(
            "<root><Head/><Body/><container><head id='nested'/><body id='nested'/></container><head id='later'/><body id='later'/></root>", "")
        XCTAssertEqual(doc.head()?.id(), "nested")
        XCTAssertEqual(doc.body()?.id(), "nested")
        try doc.head()?.remove()
        try doc.body()?.remove()
        XCTAssertEqual(doc.head()?.id(), "later")
        XCTAssertEqual(doc.body()?.id(), "later")
    }

    func testRepeatedLookupsTrackMutationsAndNormalization() throws {
        let doc = Document("")
        XCTAssertNil(doc.head())
        XCTAssertNil(doc.body())
        try doc.normalise()
        let originalHead = try XCTUnwrap(doc.head())
        let originalBody = try XCTUnwrap(doc.body())
        for _ in 0..<4 {
            XCTAssertTrue(doc.head() === originalHead)
            XCTAssertTrue(doc.body() === originalBody)
        }
        try originalHead.remove()
        try originalBody.remove()
        XCTAssertNil(doc.head())
        XCTAssertNil(doc.body())
        try doc.normalise()
        XCTAssertNotNil(doc.head())
        XCTAssertNotNil(doc.body())
        XCTAssertFalse(doc.head() === originalHead)
        XCTAssertFalse(doc.body() === originalBody)
    }
}
