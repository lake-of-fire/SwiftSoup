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
            func mark(_ stage: String) {
                FileHandle.standardError.write(Data("ReaderDocumentOutput deep stage: \(stage)\n".utf8))
            }
            defer {
                mark("thread-defer")
                done.signal()
            }
            do {
                mark("parse-original-begin")
                let document = try SwiftSoup.parse(html)
                mark("parse-original-end")
                document.outputSettings().prettyPrint(pretty: true).indentAmount(indentAmount: 0)
                mark("pretty-serialize-begin")
                let pretty = try document.outerHtml()
                mark("pretty-serialize-end")
                let prettyDocument = try SwiftSoup.parse(pretty)
                mark("pretty-reparse-end")
                XCTAssertEqual(try prettyDocument.body()?.text(), "original")
                mark("pretty-text-end")

                document.outputSettings().prettyPrint(pretty: false)
                mark("clean-utf8-begin")
                XCTAssertEqual(String(decoding: try document.outerHtmlUTF8(), as: UTF8.self), html)
                mark("clean-utf8-end")
                var deepest: Node = try XCTUnwrap(document.body())
                while let child = deepest.getChildNodes().first { deepest = child }
                mark("deepest-end")
                let text = try XCTUnwrap(deepest as? TextNode)
                XCTAssertTrue(text.ownerDocument() === document)
                mark("owner-document-end")
                text.text("updated")
                mark("mutation-end")
                let sourceReuse = try document.outerHtmlUTF8()
                mark("dirty-source-reuse-serialize-end")
                let noSourceReuse = try document.outerHtmlUTF8WithoutSourceReuse()
                mark("dirty-no-source-reuse-serialize-end")
                for bytes in [sourceReuse, noSourceReuse] {
                    let reparsed = try SwiftSoup.parse(String(decoding: bytes, as: UTF8.self))
                    mark("dirty-reparse-end")
                    XCTAssertEqual(try reparsed.body()?.text(), "updated")
                    mark("dirty-text-end")
                    XCTAssertEqual(try reparsed.select("span").count, depth)
                    mark("dirty-select-end")
                }
                mark("body-end")
            } catch {
                XCTFail("Deep serialization failed: \(error)")
            }
        }
        thread.stackSize = 512 * 1024
        thread.start()
        XCTAssertEqual(done.wait(timeout: .now() + 60), .success)
    }
}
