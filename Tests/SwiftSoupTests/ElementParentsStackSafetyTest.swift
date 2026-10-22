import Foundation
import XCTest
@testable import SwiftSoup

final class ElementParentsStackSafetyTest: XCTestCase {
    func testDeepParentsOnSmallStack() {
        let done = DispatchSemaphore(value: 0)
        let thread = Thread {
            defer { done.signal() }
            do {
                let doc = Document("")
                var root = try Element(Tag.valueOf("n"), "")
                var leaf = root
                for _ in 0..<4_000 {
                    let child = try Element(Tag.valueOf("n"), "")
                    try leaf.appendChild(child)
                    leaf = child
                }
                try doc.appendChild(root)
                let parents = leaf.parents()
                XCTAssertEqual(parents.size(), 4_000)
                XCTAssertTrue(parents.first() === leaf.parent())
                XCTAssertTrue(parents.last() === root)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
        thread.stackSize = 512 * 1024
        thread.start()
        XCTAssertEqual(done.wait(timeout: .now() + 60), .success)
    }

    func testParentOrderAndRootSentinelSemanticsArePreserved() throws {
        let doc = Document("")
        let html = try doc.appendElement("html")
        let body = try html.appendElement("body")
        let section = try body.appendElement("section")
        let leaf = try section.appendElement("span")
        let parents = leaf.parents().array()
        XCTAssertEqual(parents.count, 3)
        XCTAssertTrue(parents[0] === section)
        XCTAssertTrue(parents[1] === body)
        XCTAssertTrue(parents[2] === html)
        XCTAssertFalse(parents.contains { $0 === doc })
        try section.remove()
        XCTAssertEqual(leaf.parents().array().map { $0.tagName() }, ["section"])
    }

    func testCustomParentOverrideStillParticipatesInTraversal() throws {
        final class RedirectElement: Element {
            var redirectedParent: Element?
            override func parent() -> Element? { redirectedParent ?? super.parent() }
        }
        let synthetic = try Element(Tag.valueOf("synthetic"), "")
        let actual = try Element(Tag.valueOf("actual"), "")
        let leaf = RedirectElement(try Tag.valueOf("leaf"), "")
        try actual.appendChild(leaf)
        leaf.redirectedParent = synthetic
        let parents = leaf.parents()
        XCTAssertEqual(parents.size(), 1)
        XCTAssertTrue(parents.first() === synthetic)
    }
}
