import Foundation
import XCTest
@testable import SwiftSoup

final class OwnerDocumentStackSafetyTest: XCTestCase {
    func testDeepOwnerDocumentLookupOnSmallStack() {
        let done = DispatchSemaphore(value: 0)
        let thread = Thread {
            defer { done.signal() }
            do {
                let doc = Document("")
                let leaf = try Element(Tag.valueOf("n"), "")
                var root = leaf
                for _ in 0..<8_000 {
                    let parent = try Element(Tag.valueOf("n"), "")
                    try parent.appendChild(root)
                    root = parent
                }
                try doc.appendChild(root)
                XCTAssertTrue(leaf.ownerDocument() === doc)
                XCTAssertTrue(root.ownerDocument() === doc)
                XCTAssertTrue(doc.ownerDocument() === doc)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
        thread.stackSize = 512 * 1024
        thread.start()
        XCTAssertEqual(done.wait(timeout: .now() + 60), .success)
    }

    func testDetachedNodesReturnNil() throws {
        let root = try Element(Tag.valueOf("root"), "")
        let child = try root.appendElement("child")
        XCTAssertNil(root.ownerDocument())
        XCTAssertNil(child.ownerDocument())
    }

    func testCustomAncestorOwnerOverrideIsPreserved() throws {
        final class RedirectNode: Element {
            let redirected: Document
            init(_ redirected: Document) throws {
                self.redirected = redirected
                try super.init(Tag.valueOf("redirect"), [])
            }
            override func ownerDocument() -> Document? { redirected }
        }
        let redirected = Document("redirected")
        let custom = try RedirectNode(redirected)
        let leaf = try custom.appendElement("leaf")
        XCTAssertTrue(leaf.ownerDocument() === redirected)
    }
}
