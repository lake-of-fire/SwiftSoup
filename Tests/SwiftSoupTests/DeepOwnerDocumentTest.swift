import Foundation
import XCTest
@testable import SwiftSoup

final class DeepOwnerDocumentTest: XCTestCase {
    func testDeepBuiltInAncestorLookupUsesBoundedStack() throws {
        let chain = try DeepChain(count: 20_000)
        defer { chain.dispose() }
        let outcome = onSmallStack { chain.leaf.ownerDocument() }
        XCTAssertTrue(outcome === chain.document)
    }

    func testDeepDetachedAncestorLookupUsesBoundedStack() throws {
        let chain = try DeepChain(count: 20_000)
        defer { chain.dispose() }
        chain.nodes[0].parentNode = nil
        let outcome = onSmallStack { chain.leaf.ownerDocument() }
        XCTAssertNil(outcome)
    }

    func testDeepLookupRetainsAncestorOverrideAndItsNilAnswer() throws {
        let physical = Document("")
        let logical = Document("")
        let boundary = RedirectElement(try Tag.valueOf("section"), "")
        boundary.result = logical
        try physical.appendChild(boundary)
        let chain = try DeepChain(count: 12_000, parent: boundary)
        defer { chain.dispose() }
        boundary.calls = 0
        XCTAssertTrue(onSmallStack { chain.leaf.ownerDocument() } === logical)
        XCTAssertEqual(boundary.calls, 1)
        boundary.result = nil
        XCTAssertNil(onSmallStack { chain.leaf.ownerDocument() })
        XCTAssertEqual(boundary.calls, 2)
    }

    func testOverrideCanCallSuperWithoutRedispatchingToItself() throws {
        let document = Document("")
        let boundary = ObservingElement(try Tag.valueOf("div"), "")
        try document.appendChild(boundary)
        let child = try boundary.appendElement("span")
        boundary.calls = 0
        XCTAssertTrue(child.ownerDocument() === document)
        XCTAssertEqual(boundary.calls, 1)
        XCTAssertTrue(boundary.ownerDocument() === document)
        XCTAssertEqual(boundary.calls, 2)
    }

    func testDocumentOverrideRemainsVisibleFromDescendants() throws {
        let logical = Document("")
        let document = RedirectDocument("")
        document.result = logical
        let child = try document.appendElement("div").appendElement("span")
        document.calls = 0
        XCTAssertTrue(child.ownerDocument() === logical)
        XCTAssertEqual(document.calls, 1)
        document.result = nil
        XCTAssertNil(child.ownerDocument())
        XCTAssertEqual(document.calls, 2)
    }

    func testInheritedImplementationOnACustomElementStartsAboveSelf() throws {
        let document = Document("")
        let child = PlainCustomElement(try Tag.valueOf("span"), "")
        try document.appendChild(child)
        let text = try child.appendElement("b")
        XCTAssertTrue(child.ownerDocument() === document)
        XCTAssertTrue(text.ownerDocument() === document)
        try child.remove()
        XCTAssertNil(child.ownerDocument())
        XCTAssertNil(text.ownerDocument())
    }

    func testReparentingAndDetachmentDoNotCacheTheOldOwner() throws {
        let first = try SwiftSoup.parse("<main><p>text</p></main>")
        let second = try SwiftSoup.parse("<section></section>")
        let paragraph = try XCTUnwrap(first.getElementsByTag("p").first())
        let text = paragraph.childNode(0)
        XCTAssertTrue(text.ownerDocument() === first)
        try XCTUnwrap(second.body()).appendChild(paragraph)
        XCTAssertTrue(text.ownerDocument() === second)
        try paragraph.remove()
        XCTAssertNil(text.ownerDocument())
        try XCTUnwrap(first.body()).appendChild(paragraph)
        XCTAssertTrue(text.ownerDocument() === first)
    }

    func testLiveOutputSettingsUseTheCustomOwner() throws {
        let physical = Document("")
        let logical = Document("")
        let boundary = RedirectElement(try Tag.valueOf("section"), "")
        boundary.result = logical
        try physical.appendChild(boundary)
        let text = try boundary.appendElement("p")
        XCTAssertTrue(text.getOutputSettings() === logical.outputSettings())
        let replacement = OutputSettings().prettyPrint(pretty: false).syntax(syntax: .xml)
        logical.outputSettings(replacement)
        XCTAssertTrue(text.getOutputSettings() === replacement)
        boundary.result = nil
        XCTAssertFalse(text.getOutputSettings() === replacement)
    }

    func testDocumentCallingSuperStillReturnsItself() throws {
        let document = ObservingDocument("")
        XCTAssertTrue(document.ownerDocument() === document)
        XCTAssertEqual(document.calls, 1)
        let child = try document.appendElement("p")
        document.calls = 0
        XCTAssertTrue(child.ownerDocument() === document)
        XCTAssertEqual(document.calls, 1)
    }

    func testStoredParentChainNotOverriddenParentGetterDefinesTheOwner() throws {
        let physical = Document("")
        let unrelated = Document("")
        let boundary = ParentRedirectElement(try Tag.valueOf("section"), "")
        boundary.alternateParent = unrelated
        try physical.appendChild(boundary)
        let child = try boundary.appendElement("p")
        XCTAssertTrue(boundary.parent() === unrelated)
        XCTAssertTrue(child.ownerDocument() === physical)
    }

    // Construct links without quadratic parser/index work. All ancestors remain
    // strongly retained; only ownerDocument executes on the small worker stack.
    // Iterative teardown avoids turning an ARC deallocation chain into the test.
    private final class DeepChain: @unchecked Sendable {
        let document = Document("")
        let nodes: [Element]
        var leaf: Element { nodes[nodes.count - 1] }
        init(count: Int, parent: Node? = nil) throws {
            let tag = try Tag.valueOf("div")
            nodes = (0..<count).map { _ in Element(tag, "") }
            var previous: Node = parent ?? document
            for element in nodes {
                element.suppressQueryIndexDirty = true
                element.parentNode = previous
                previous.childNodes.append(element)
                previous = element
            }
        }
        func dispose() {
            for node in nodes {
                node.childNodes.removeAll()
                node.parentNode = nil
            }
            document.childNodes.removeAll()
        }
    }

    private final class Result: @unchecked Sendable { var value: Document? }
    private func onSmallStack(
        file: StaticString = #filePath, line: UInt = #line,
        _ operation: @escaping @Sendable () -> Document?
    ) -> Document? {
        let result = Result()
        let done = DispatchSemaphore(value: 0)
        let thread = Thread {
            result.value = operation()
            done.signal()
        }
        thread.stackSize = 512 * 1024
        thread.start()
        guard done.wait(timeout: .now() + 20) == .success else {
            fatalError("ownerDocument worker did not complete at \(file):\(line)")
        }
        return result.value
    }

    private final class RedirectElement: Element {
        var result: Document?
        var calls = 0
        override func ownerDocument() -> Document? { calls += 1; return result }
    }
    private final class ObservingElement: Element {
        var calls = 0
        override func ownerDocument() -> Document? { calls += 1; return super.ownerDocument() }
    }
    private final class PlainCustomElement: Element {}
    private final class ParentRedirectElement: Element {
        var alternateParent: Element?
        override func parent() -> Element? { alternateParent }
    }
    private final class RedirectDocument: Document {
        var result: Document?
        var calls = 0
        override func ownerDocument() -> Document? { calls += 1; return result }
    }
    private final class ObservingDocument: Document {
        var calls = 0
        override func ownerDocument() -> Document? { calls += 1; return super.ownerDocument() }
    }
}
