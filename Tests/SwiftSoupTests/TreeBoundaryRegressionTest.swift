import XCTest
@testable import SwiftSoup

final class TreeBoundaryRegressionTest: XCTestCase {
    func testEmptyDetachesRetainedChildrenBeforeReuse() throws {
        let doc = try SwiftSoup.parse("<main><p>one</p>tail</main><aside></aside>")
        let main = try XCTUnwrap(doc.select("main").first())
        let aside = try XCTUnwrap(doc.select("aside").first())
        let children = main.getChildNodes()
        main.empty()
        for child in children {
            XCTAssertNil(child.parent())
            XCTAssertNil(child.ownerDocument())
            // Avoid triggering the old stale-parent remove(at:) trap on failure.
            if child.parent() == nil { try aside.appendChild(child) }
        }
        XCTAssertEqual(try aside.text(), "onetail")
    }

    func testHasRelativeChildSelectorUsesCandidateAsScope() throws {
        let doc = try SwiftSoup.parse("<section id='direct'><p>x</p></section><section id='nested'><div><p>x</p></div></section>")
        XCTAssertEqual(try doc.select("section:has(> p)").array().map { $0.id() }, ["direct"])
        XCTAssertEqual(try doc.select("section:has(> div > p)").array().map { $0.id() }, ["nested"])
        XCTAssertEqual(try doc.select("section:not(:has(> p))").array().map { $0.id() }, ["nested"])
        // Ordinary inner queries retain SwiftSoup's historical outer scope.
        XCTAssertEqual(try doc.select("section:has(body p)").size(), 2)
    }

    func testInvalidUnicodeSplitOffsetsThrowWithoutMutating() throws {
        let text = TextNode("日本", "")
        XCTAssertThrowsError(try text.splitText(utf8Offset: 1))
        XCTAssertEqual(text.getWholeText(), "日本")
        XCTAssertThrowsError(try TextNode("日本", "").splitText(3))
    }

    func testUnicodeSplitBoundariesPreserveText() throws {
        for value in ["", "abc", "日本", "e\u{301}x", "👩‍👩‍👧‍👦end"] {
            var byteOffset = 0
            for offset in 0...value.count {
                let text = TextNode(value, "")
                let tail = try text.splitText(utf8Offset: byteOffset)
                XCTAssertEqual(text.getWholeText() + tail.getWholeText(), value)
                XCTAssertEqual(text.getWholeText().count, offset)
                if offset < value.count {
                    byteOffset += String(value[value.index(value.startIndex, offsetBy: offset)]).utf8.count
                }
            }
        }
    }

    func testParentEvaluatorTerminatesForDetachedCandidate() throws {
        let root = try SwiftSoup.parse("<main></main>")
        let detached = try Element(Tag.valueOf("p"), "")
        XCTAssertFalse(StructuralEvaluator.Parent(Evaluator.Tag("missing")).matches(root, detached))
    }

    func testChangingBaseUriInvalidatesAbsoluteUrlSelectors() throws {
        let doc = try SwiftSoup.parse("<main><a href='page'>link</a></main>", "https://old.example/")
        let main = try XCTUnwrap(doc.select("main").first())
        let old = "a[abs:href='https://old.example/page']"
        let new = "a[abs:href='https://new.example/page']"
        for _ in 0..<3 {
            XCTAssertEqual(try doc.select(old).size(), 1)
            XCTAssertEqual(try main.select(old).size(), 1)
            XCTAssertEqual(try doc.select(new).size(), 0)
        }
        try main.setBaseUri("https://new.example/")
        XCTAssertEqual(try main.select("a").first()?.absUrl("href"), "https://new.example/page")
        XCTAssertEqual(try doc.select(old).size(), 0)
        XCTAssertEqual(try main.select(old).size(), 0)
        XCTAssertEqual(try doc.select(new).size(), 1)
    }
}
