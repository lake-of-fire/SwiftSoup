import XCTest
@testable import SwiftSoup

final class FixReevaluationTest: XCTestCase {
    func testHasRelativeSiblingQueries() throws {
        let doc = try SwiftSoup.parse("<main><p id='before'>first</p><aside></aside><p id='target'>second</p><p id='last'>last</p></main>")
        XCTAssertEqual(try doc.select("p:has(+ p)").array().map { $0.id() }, ["target"])
        XCTAssertEqual(try doc.select("p:has(~ #target)").array().map { $0.id() }, ["before"])
        XCTAssertEqual(try doc.select("p:has(+ aside + p)").array().map { $0.id() }, ["before"])
        XCTAssertEqual(try doc.select(":has(+ #target)").array().map { $0.tagName() }, ["aside"])
    }

    func testOrdinaryHasKeepsHistoricalOuterScope() throws {
        let doc = try SwiftSoup.parse("<div id='x'><p>text</p></div>")
        XCTAssertEqual(try doc.select("div:has(body p)").array().map { $0.id() }, ["x"])
        XCTAssertEqual(try doc.select("div:has(> p)").array().map { $0.id() }, ["x"])
    }

    func testHasMixedListsAndSiblingDescendants() throws {
        let doc = try SwiftSoup.parse("<main><section id='first'><b></b></section><section id='second'><i class='hit'></i></section><section id='third'><p></p></section></main>")
        let cases: [(String, [String])] = [
            ("section:has(> b, + section > i.hit)", ["first"]),
            ("section:has(+ section > i.hit, > p)", ["first", "third"]),
            ("section:has(> b, body p)", ["first", "third"]),
            ("section:has(~ section > p)", ["first", "second"]),
            ("section:has(> p, ~ section > p)", ["first", "second", "third"])
        ]
        for (query, expected) in cases {
            XCTAssertEqual(try doc.select(query).array().map { $0.id() }, expected, query)
        }
    }

    func testCloneSettingsAndFormControlsAreIndependentThroughCopyEntrypoints() throws {
        let doc = try SwiftSoup.parse("<form><input value='old'></form>")
        doc.outputSettings().prettyPrint(pretty: false).charset(.ascii).escapeMode(.xhtml)
        let clone = try XCTUnwrap(doc.copy(clone: Document("")).copy() as? Document)
        XCTAssertEqual(clone.outputSettings().encoder(), .ascii)
        XCTAssertEqual(clone.outputSettings().escapeMode(), .xhtml)
        let form = try XCTUnwrap(clone.select("form").first() as? FormElement)
        try form.elements().first()?.attr("value", "new")
        XCTAssertEqual(try doc.select("input").first()?.attr("value"), "old")
        clone.outputSettings().charset(.utf8)
        XCTAssertEqual(doc.outputSettings().encoder(), .ascii)
    }

    func testSharedOwnersSurviveRemovalRenameAndOwnerChurn() throws {
        let attrs = Attributes()
        try attrs.put("class", "old")
        let tag = try Tag.valueOf("p")
        let owners = (0..<3).map { _ in Element(tag, "", attrs) }
        for node in owners {
            for _ in 0..<3 { _ = try node.select(".old, [data-x], .new") }
        }
        for _ in 0..<20 { _ = Element(tag, "", attrs) }
        try attrs.asList().first?.setKey(key: "data-x")
        for node in owners {
            XCTAssertEqual(try node.select(".old").size(), 0)
            XCTAssertEqual(try node.select("[data-x]").size(), 1)
        }
        attrs.removeAll(keys: [Array("data-x".utf8)])
        try attrs.put("class", "new")
        for node in owners {
            XCTAssertEqual(try node.select("[data-x]").size(), 0)
            XCTAssertEqual(try node.select(".new").size(), 1)
        }
    }

    func testByteSplitsPreserveEveryUnicodeScalarBoundary() throws {
        for value in ["", "日本", "e\u{301}x", "\r\nx", "👩‍👩‍👧‍👦end"] {
            let bytes = Array(value.utf8)
            for offset in 0...bytes.count {
                let node = TextNode(value, "")
                if offset == bytes.count || bytes[offset] & 0xc0 != 0x80 {
                    let tail = try node.splitText(utf8Offset: offset)
                    XCTAssertEqual(node.getWholeTextUTF8(), Array(bytes[..<offset]))
                    XCTAssertEqual(tail.getWholeTextUTF8(), Array(bytes[offset...]))
                } else {
                    XCTAssertThrowsError(try node.splitText(utf8Offset: offset))
                    XCTAssertEqual(node.getWholeTextUTF8(), bytes)
                }
            }
        }
    }

    func testHasListsPreserveEscapedAndNestedCommas() throws {
        let doc = try SwiftSoup.parse("<main><p data-x='a,b'>a,b</p><i></i></main>")
        for query in ["main:has(> p[data-x='a,b'], > aside)",
                      "main:has(> p:contains(a,b), > aside)",
                      "main:has(> p:not(.a, .b), > aside)"] {
            XCTAssertEqual(try doc.select(query).size(), 1, query)
        }
        XCTAssertThrowsError(try doc.select("main:has(> p, )"))
    }

    func testInvalidSplitLeavesTreeUntouched() throws {
        let doc = try SwiftSoup.parse("<p>e&#x301;tail</p>")
        let p = try XCTUnwrap(doc.select("p").first())
        let text = try XCTUnwrap(p.childNode(0) as? TextNode)
        let whole = text.getWholeText()
        for offset in [-1, 2, 100] {
            XCTAssertThrowsError(try text.splitText(utf8Offset: offset))
            XCTAssertEqual(text.getWholeText(), whole)
            XCTAssertEqual(p.getChildNodes().count, 1)
        }
    }
}
