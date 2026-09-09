import Foundation
import XCTest
@testable import SwiftSoup

final class TokenScratchBufferTest: XCTestCase {
    func testDoctypeBuffersGrowAndRetainedSlicesSurviveReset() {
        let token = Token.Doctype()
        for count in [0, 1, 7, 16, 1024, 4097] {
            let value = String(repeating: "日本語-ab", count: count)
            token.name.append(value)
            token.publicIdentifier.append(value + "-public")
            token.systemIdentifier.append(value + "-system")
            let snapshots = [token.name.buffer, token.publicIdentifier.buffer, token.systemIdentifier.buffer]
            token.reset()
            XCTAssertTrue(token.name.isEmpty)
            XCTAssertTrue(token.publicIdentifier.isEmpty)
            XCTAssertTrue(token.systemIdentifier.isEmpty)
            token.name.append("next")
            XCTAssertEqual(Array(snapshots[0]), Array(value.utf8))
            XCTAssertEqual(Array(snapshots[1]), Array((value + "-public").utf8))
            XCTAssertEqual(Array(snapshots[2]), Array((value + "-system").utf8))
            token.reset()
        }
    }

    func testCommentBufferGrowthResetAndSnapshots() {
        let token = Token.Comment()
        for count in [0, 1, 15, 256, 4097] {
            let text = String(repeating: "comment-日本😀", count: count)
            token.data.append(text)
            let snapshot = token.data.buffer
            token.reset()
            token.data.append("replacement")
            XCTAssertEqual(Array(snapshot), Array(text.utf8))
            XCTAssertEqual(token.data.toString(), "replacement")
            token.reset()
        }
    }

    func testPublicScriptAndEntityAttributesAcrossGrowthBoundaries() throws {
        for count in [0, 1, 16, 257, 4097] {
            let script = String(repeating: "if(a<b){s='<x';}<!--c-->\n", count: count)
            let encoded = String(repeating: "日&amp;本&#x8a9e;", count: count)
            let value = String(repeating: "日&本語", count: count)
            let document = try SwiftSoup.parse("<!doctype html><html><body><script>\(script)</script><p title='\(encoded)'>\(encoded)</p></body></html>")
            let p = try XCTUnwrap(document.getElementsByTag("p").first())
            XCTAssertEqual(try document.getElementsByTag("script").first()?.data(), script)
            XCTAssertEqual(try p.attr("title"), value)
            XCTAssertEqual(try p.text(trimAndNormaliseWhitespace: false), value)
        }
    }

    func testScriptEscapeScratchStateAndLongXMLComments() throws {
        for count in [1, 17, 1025] {
            let script = String(repeating: "<!--<script>日本語</script>-->", count: count)
            let document = try SwiftSoup.parse("<script>\(script)</script><p>after</p>")
            XCTAssertEqual(try document.getElementsByTag("script").first()?.data(), script)
            XCTAssertEqual(try document.getElementsByTag("p").text(), "after")
            let comment = String(repeating: "日本語 note ", count: count)
            let xml = try SwiftSoup.parse("<root><!--\(comment)--><p>value</p></root>", "", Parser.xmlParser())
            let root = try XCTUnwrap(xml.getElementsByTag("root").first())
            let parsed = try XCTUnwrap(root.childNode(0) as? Comment)
            XCTAssertEqual(parsed.getData(), comment)
            XCTAssertEqual(try root.text(), "value")
        }
    }
}
