import XCTest
@testable import SwiftSoup

final class MutationBoundaryAuditTest: XCTestCase {
    func testRenamedDuplicateKeysKeepFirstLookupAcrossIndexThreshold() throws {
        for count in 0...6 {
            let doc = try SwiftSoup.parse("<a href='first' other='second'></a>")
            let a = try XCTUnwrap(doc.select("a").first())
            let attrs = try XCTUnwrap(a.getAttributes())
            for i in 0..<count { try attrs.put("padding\(i)", "x") }
            let other = try XCTUnwrap(attrs.asList().first { $0.getKey() == "other" })
            try other.setKey(key: "href")
            XCTAssertEqual(attrs.get(key: "href"), "first", "padding \(count)")
            XCTAssertEqual(try doc.select("[href]").size(), 1)
            XCTAssertEqual(try doc.select("[href=second]").size(), 0)
            XCTAssertEqual(try doc.select("[href=first]").size(), 1)
        }
    }

    func testLiveLeafAttributesInvalidateSourceReuse() throws {
        for live in [false, true] {
            let doc = try SwiftSoup.parse("<div><!--old--><p>old</p></div>")
            doc.outputSettings().prettyPrint(pretty: false)
            let div = try XCTUnwrap(doc.select("div").first())
            let comment = try XCTUnwrap(div.getChildNodes().first as? Comment)
            let attrs = try XCTUnwrap(comment.getAttributes())
            if live { try XCTUnwrap(attrs.asList().first).setValue(value: Array("new".utf8)) }
            else { try attrs.put("comment", "new") }
            XCTAssertEqual(comment.getData(), "new")
            XCTAssertTrue(String(decoding: try doc.outerHtmlUTF8(), as: UTF8.self).contains("<!--new-->"))
        }
    }

    func testTextAttributesInvalidateWarmSelectors() throws {
        for live in [false, true] {
            let doc = try SwiftSoup.parse("<p>old</p>")
            let p = try XCTUnwrap(doc.select("p").first())
            let text = try XCTUnwrap(p.getChildNodes().first as? TextNode)
            let attrs = text.getAttributes()
            for _ in 0..<5 { XCTAssertEqual(try doc.select("p:contains(old)").size(), 1) }
            if live { try XCTUnwrap(attrs.asList().first).setValue(value: Array("new".utf8)) }
            else { try text.attr("text", "new") }
            XCTAssertEqual(try p.text(), "new")
            XCTAssertEqual(try doc.select("p:contains(old)").size(), 0)
            XCTAssertEqual(try doc.select("p:contains(new)").size(), 1)
        }
    }

    func testLazyLeafAttributeAccessPreservesAndUpdatesContent() throws {
        let doc = try SwiftSoup.parse("<p>one&amp;two&#65;three</p><script>old</script>")
        let p = try XCTUnwrap(doc.select("p").first())
        let text = try XCTUnwrap(p.getChildNodes().first as? TextNode)
        _ = text.getAttributes()
        try text.attr("text", "replacement")
        XCTAssertEqual(text.getWholeText(), "replacement")
        let script = try XCTUnwrap(doc.select("script").first())
        let data = try XCTUnwrap(script.getChildNodes().first as? DataNode)
        XCTAssertEqual(try data.attr("data"), "old")
        try data.attr("data", "replacement")
        XCTAssertEqual(data.getWholeData(), "replacement")
    }

    func testLeafReadsPreserveSourceAndPresenceForBothKeyOverloads() throws {
        let html = "<html><head><script >old</script></head><body><p >old&amp;text</p></body></html>"
        let doc = try SwiftSoup.parse(html)
        doc.outputSettings().prettyPrint(pretty: false)
        let script = try XCTUnwrap(doc.select("script").first())
        let data = try XCTUnwrap(script.getChildNodes().first as? DataNode)
        let p = try XCTUnwrap(doc.select("p").first())
        let text = try XCTUnwrap(p.getChildNodes().first as? TextNode)
        let version = doc.textMutationVersionToken()
        XCTAssertTrue(data.hasAttr(Array("data".utf8)))
        XCTAssertTrue(text.hasAttr(Array("text".utf8)))
        XCTAssertTrue(data.hasAttr("data"))
        XCTAssertTrue(text.hasAttr("text"))
        XCTAssertEqual(data.getWholeData(), "old")
        XCTAssertEqual(text.getWholeText(), "old&text")
        XCTAssertEqual(doc.textMutationVersionToken(), version)
        XCTAssertEqual(String(decoding: try doc.outerHtmlUTF8(), as: UTF8.self), html)
    }

    func testMultipleTextSlicesMaterializeBeforeAttributeMutation() throws {
        let text = TextNode(slice: ByteSlice.fromArray(Array("first".utf8)), baseUri: [])
        text.appendSlice(.fromArray(Array("second".utf8)))
        XCTAssertEqual(text.getAttributes().get(key: "text"), "firstsecond")
        try text.attr("text", "new")
        XCTAssertEqual(text.getWholeText(), "new")
    }

    func testClonedLeafAttributesNotifyOnlyClone() throws {
        let original = try SwiftSoup.parse("<p>old<!--old--></p>")
        let clone = try XCTUnwrap(original.copy() as? Document)
        original.outputSettings().prettyPrint(pretty: false)
        clone.outputSettings().prettyPrint(pretty: false)
        let p = try XCTUnwrap(clone.select("p").first())
        let comment = try XCTUnwrap(p.getChildNodes().last as? Comment)
        let originalVersion = original.textMutationVersionToken()
        try comment.getAttributes()?.put("comment", "new")
        XCTAssertEqual(original.textMutationVersionToken(), originalVersion)
        XCTAssertTrue(String(decoding: try clone.outerHtmlUTF8(), as: UTF8.self).contains("<!--new-->"))
        XCTAssertTrue(String(decoding: try original.outerHtmlUTF8(), as: UTF8.self).contains("<!--old-->"))
    }

    func testDataNodePreservesOptionalAttributeOverrideContract() throws {
        final class CustomDataNode: DataNode {
            override func getAttributes() -> Attributes? { super.getAttributes() }
        }
        let node = CustomDataNode(Array("old".utf8), [])
        XCTAssertEqual(node.getAttributes()?.get(key: "data"), "old")
    }

    func testParsedAndConstructedDataNodesAgreeThroughPublicAttributes() throws {
        for operation in 0..<4 {
            let doc = try SwiftSoup.parse("<script>old</script>")
            let script = try XCTUnwrap(doc.select("script").first())
            let parsed = try XCTUnwrap(script.getChildNodes().first as? DataNode)
            let constructed = DataNode(Array("old".utf8), [])
            for node in [parsed, constructed] {
                switch operation {
                case 0: try node.attr("data", "new")
                case 1: try node.removeAttr("data")
                case 2: try node.getAttributes()?.put("data", "new")
                default:
                    let attribute = try XCTUnwrap(node.getAttributes()?.asList().first)
                    _ = attribute.setValue(value: Array("new".utf8))
                }
            }
            XCTAssertEqual(parsed.getWholeData(), constructed.getWholeData(), "operation \(operation)")
            XCTAssertEqual(try parsed.attr("data"), try constructed.attr("data"))
        }
    }

    func testDataSetterInvalidatesWarmSelectors() throws {
        let doc = try SwiftSoup.parse("<script>old</script>")
        let script = try XCTUnwrap(doc.select("script").first())
        let data = try XCTUnwrap(script.getChildNodes().first as? DataNode)
        for _ in 0..<5 { XCTAssertEqual(try doc.select("script:containsData(old)").size(), 1) }
        data.setWholeData("new")
        XCTAssertEqual(try doc.select("script:containsData(old)").size(), 0)
        XCTAssertEqual(try doc.select("script:containsData(new)").size(), 1)
    }
}
