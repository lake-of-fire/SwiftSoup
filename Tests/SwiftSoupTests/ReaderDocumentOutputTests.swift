import Foundation
import XCTest
@testable import SwiftSoup

private final class OwnerDocumentOverrideElement: Element {
    private let forcedOwner: Document

    init(owner: Document) throws {
        self.forcedOwner = owner
        super.init(try Tag.valueOf("div"), [UInt8]())
    }

    override func ownerDocument() -> Document? {
        return forcedOwner
    }
}

private final class NilNextSiblingElement: Element {
    init() throws {
        super.init(try Tag.valueOf("span"), [UInt8]())
    }

    override func nextSibling() -> Node? {
        return nil
    }
}

private final class CallbackSerializationNode: Node {
    let label: String
    var onHead: ((CallbackSerializationNode, Int) throws -> Void)?
    var onTail: ((CallbackSerializationNode, Int) throws -> Void)?

    init(_ label: String) {
        self.label = label
        super.init()
    }

    override func outerHtmlHead(_ accum: StringBuilder, _ depth: Int, _ out: OutputSettings) throws {
        accum.append("H(\(label),\(depth));")
        try onHead?(self, depth)
    }

    override func outerHtmlTail(_ accum: StringBuilder, _ depth: Int, _ out: OutputSettings) throws {
        accum.append("T(\(label),\(depth));")
        try onTail?(self, depth)
    }
}

private enum SerializationCallbackFailure: Error {
    case stopped
}

/// Reader regressions reconciled onto upstream without replacing its newer
/// attribute-ownership or deep-clone implementation.
final class ReaderDocumentOutputTests: XCTestCase {
    func testCompactUTF8PreservesFragmentInsertionsAndRemovals() throws {
        let document = try SwiftSoup.parse("<p>Before</p>")
        document.outputSettings().prettyPrint(pretty: false)
        try document.body()?.appendElement("p").text("After")
        let appended = String(decoding: try document.outerHtmlUTF8(), as: UTF8.self)
        XCTAssertEqual(
            try SwiftSoup.parse(appended).select("p").array().map { try $0.text() },
            ["Before", "After"]
        )
        try document.select("p").remove()
        let removed = String(decoding: try document.outerHtmlUTF8(), as: UTF8.self)
        XCTAssertTrue(try SwiftSoup.parse(removed).select("p").isEmpty)
    }

    func testCompactUTF8HonorsXMLSyntaxAfterHTMLParse() throws {
        let document = try SwiftSoup.parse("<html><head></head><body><br><input disabled></body></html>")
        document.outputSettings().prettyPrint(pretty: false).syntax(syntax: .xml)
        XCTAssertEqual(try document.outerHtmlUTF8(), try document.outerHtmlUTF8WithoutSourceReuse())
    }

    func testCompactUTF8HonorsHTMLSyntaxAfterXMLParse() throws {
        let document = try SwiftSoup.parse("<html><head/><body><br/></body></html>", "", Parser.xmlParser())
        document.outputSettings().prettyPrint(pretty: false).syntax(syntax: .html)
        XCTAssertEqual(try document.outerHtmlUTF8(), try document.outerHtmlUTF8WithoutSourceReuse())
    }

    func testOwnerDocumentPreservesAncestorOverrideDispatch() throws {
        let forcedOwner = try SwiftSoup.parse("<p>forced</p>")
        let parent = try OwnerDocumentOverrideElement(owner: forcedOwner)
        let child = TextNode("child", nil)
        child.parentNode = parent
        XCTAssertTrue(child.ownerDocument() === forcedOwner)
    }

    func testIterativeSerializerUsesStoredChildOrder() throws {
        let document = try SwiftSoup.parse("<html><head></head><body></body></html>")
        document.outputSettings().prettyPrint(pretty: false)
        let body = try XCTUnwrap(document.body())

        let first = try NilNextSiblingElement()
        try first.addChildren(TextNode("first", nil))
        let second = Element(try Tag.valueOf("span"), [UInt8]())
        try second.addChildren(TextNode("second", nil))
        try body.addChildren(first, second)

        let html = String(decoding: try document.outerHtmlUTF8WithoutSourceReuse(), as: UTF8.self)
        let reparsed = try SwiftSoup.parse(html)
        XCTAssertEqual(try reparsed.select("span").array().map { try $0.text() }, ["first", "second"])
    }

    func testSerializerPreservesVirtualCallbacksAndChildSnapshots() throws {
        for allowRawSource in [true, false] {
            let root = CallbackSerializationNode("root")
            let first = CallbackSerializationNode("first")
            let second = CallbackSerializationNode("second")
            let headAdded = CallbackSerializationNode("head-added")
            let lateAdded = CallbackSerializationNode("late-added")
            let tailAdded = CallbackSerializationNode("tail-added")
            try root.addChildren(first, second)
            root.onHead = { node, _ in try node.addChildren(headAdded) }
            first.onHead = { node, _ in
                try second.remove()
                try XCTUnwrap(node.parentNode).addChildren(lateAdded)
            }
            root.onTail = { node, _ in try node.addChildren(tailAdded) }

            let accum = StringBuilder()
            let out = OutputSettings().prettyPrint(pretty: false)
            if allowRawSource {
                try root.outerHtmlFast(accum, 5, out, allowRawSource: true)
            } else {
                try root.outerHtmlFastWithoutSourceReuse(accum, 5, out)
            }
            XCTAssertEqual(accum.toString(),
                "H(root,5);H(first,6);T(first,6);H(second,6);T(second,6);" +
                "H(head-added,6);T(head-added,6);T(root,5);")
            XCTAssertNil(second.parentNode)
            XCTAssertEqual(root.getChildNodes().count, 4)
            XCTAssertTrue(root.childNode(0) === first)
            XCTAssertTrue(root.childNode(1) === headAdded)
            XCTAssertTrue(root.childNode(2) === lateAdded)
            XCTAssertTrue(root.childNode(3) === tailAdded)
        }
    }

    func testSerializerPropagatesCallbackErrorsWithoutRemainingCallbacks() throws {
        for allowRawSource in [true, false] {
            for throwsInHead in [true, false] {
                let root = CallbackSerializationNode("root")
                let first = CallbackSerializationNode("first")
                let second = CallbackSerializationNode("second")
                try root.addChildren(first, second)
                if throwsInHead {
                    first.onHead = { _, _ in throw SerializationCallbackFailure.stopped }
                } else {
                    first.onTail = { _, _ in throw SerializationCallbackFailure.stopped }
                }
                let accum = StringBuilder()
                let out = OutputSettings().prettyPrint(pretty: false)
                XCTAssertThrowsError(try {
                    if allowRawSource {
                        try root.outerHtmlFast(accum, 0, out, allowRawSource: true)
                    } else {
                        try root.outerHtmlFastWithoutSourceReuse(accum, 0, out)
                    }
                }()) { error in
                    guard case SerializationCallbackFailure.stopped = error else {
                        return XCTFail("Unexpected serialization error: \(error)")
                    }
                }
                XCTAssertEqual(accum.toString(), throwsInHead
                    ? "H(root,0);H(first,1);"
                    : "H(root,0);H(first,1);T(first,1);")
            }
        }
    }

    func testDeepSerializationPreservesCleanAndMutatedTreesOnSmallStack() {
        let depth = 3_000
        let html = "<html><head></head><body>" + String(repeating: "<span>", count: depth)
            + "original" + String(repeating: "</span>", count: depth) + "</body></html>"
        let done = DispatchSemaphore(value: 0)
        let thread = Thread {
            defer { done.signal() }
            do {
                let document = try SwiftSoup.parse(html)
                document.outputSettings().prettyPrint(pretty: true).indentAmount(indentAmount: 0)
                let pretty = try document.outerHtml()
                let prettyDocument = try SwiftSoup.parse(pretty)
                XCTAssertEqual(try prettyDocument.body()?.text(), "original")

                document.outputSettings().prettyPrint(pretty: false)
                XCTAssertEqual(String(decoding: try document.outerHtmlUTF8(), as: UTF8.self), html)
                var deepest: Node = try XCTUnwrap(document.body())
                while let child = deepest.getChildNodes().first { deepest = child }
                let text = try XCTUnwrap(deepest as? TextNode)
                text.text("updated")
                let sourceReuse = try document.outerHtmlUTF8()
                let noSourceReuse = try document.outerHtmlUTF8WithoutSourceReuse()
                for bytes in [sourceReuse, noSourceReuse] {
                    let reparsed = try SwiftSoup.parse(String(decoding: bytes, as: UTF8.self))
                    XCTAssertEqual(try reparsed.body()?.text(), "updated")
                    XCTAssertEqual(try reparsed.select("span").count, depth)
                }
            } catch {
                XCTFail("Deep serialization failed: \(error)")
            }
        }
        thread.stackSize = 512 * 1024
        thread.start()
        XCTAssertEqual(done.wait(timeout: .now() + 60), .success)
    }
}
