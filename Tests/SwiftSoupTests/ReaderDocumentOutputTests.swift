import Foundation
import XCTest
@testable import SwiftSoup

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
                XCTAssertEqual(try SwiftSoup.parse(pretty).body()?.text(), "original")

                document.outputSettings().prettyPrint(pretty: false)
                XCTAssertEqual(String(decoding: try document.outerHtmlUTF8(), as: UTF8.self), html)
                var deepest: Node = try XCTUnwrap(document.body())
                while let child = deepest.getChildNodes().first { deepest = child }
                let text = try XCTUnwrap(deepest as? TextNode)
                XCTAssertTrue(text.ownerDocument() === document)
                text.text("updated")
                for bytes in [try document.outerHtmlUTF8(), try document.outerHtmlUTF8WithoutSourceReuse()] {
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
