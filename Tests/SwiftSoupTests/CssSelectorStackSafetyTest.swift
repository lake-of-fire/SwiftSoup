import Foundation
import XCTest
@testable import SwiftSoup

final class CssSelectorStackSafetyTest: XCTestCase {
    private final class CountingParentElement: Element {
        var parentCalls = 0
        override func parent() -> Element? {
            parentCalls += 1
            return super.parent()
        }
    }

    func testDeepCssSelectorOnSmallStack() {
        let done = DispatchSemaphore(value: 0)
        let thread = Thread {
            defer { done.signal() }
            do {
                let root = try Element(Tag.valueOf("n"), "")
                var leaf = root
                for _ in 0..<1_500 {
                    let child = try Element(Tag.valueOf("n"), "")
                    try leaf.appendChild(child)
                    leaf = child
                }
                let selector = try leaf.cssSelector()
                XCTAssertFalse(selector.isEmpty)
                XCTAssertEqual(selector.split(separator: ">", omittingEmptySubsequences: true).count, 1_501)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
        thread.stackSize = 512 * 1024
        thread.start()
        XCTAssertEqual(done.wait(timeout: .now() + 60), .success)
    }

    func testIdAncestorStillTerminatesPathAndRoundTrips() throws {
        let doc = try SwiftSoup.parse("<main id='anchor'><section class='x'><span></span><span class='target'></span></section></main>")
        let target = try XCTUnwrap(doc.select("span.target").first())
        let selector = try target.cssSelector()
        XCTAssertEqual(selector, "#anchor > section.x > span.target")
        XCTAssertTrue(try doc.select(selector).first() === target)
    }

    func testVirtualParentCallSequenceAtLeafIsPreserved() throws {
        let doc = Document.createShell("")
        let body = try XCTUnwrap(doc.body())
        let leaf = CountingParentElement(try Tag.valueOf("span"), [])
        try body.appendChild(leaf)

        XCTAssertEqual(try leaf.cssSelector(), "html > body > span")
        XCTAssertEqual(leaf.parentCalls, 5)
    }
}
