import XCTest
import SwiftSoup

final class TextNodeOriginalHTMLTests: XCTestCase {
    func testParsedTextOriginalHTMLKeepsEntitiesAndWhitespace() throws {
        let source = " 前&amp;&#xff5c;猫&#x300a;ねこ&#x300b; 後 "
        let document = try SwiftSoup.parse("<p>" + source + "</p>")
        let paragraph = try XCTUnwrap(document.select("p").first())
        let text = try XCTUnwrap(paragraph.getChildNodes().first as? TextNode)
        XCTAssertEqual(text.getWholeText(), " 前&｜猫《ねこ》 後 ")
        XCTAssertEqual(text.originalHTML(), source)
    }

    func testEditedAndProgrammaticTextHaveNoOriginalHTML() throws {
        XCTAssertNil(TextNode("｜猫《ねこ》", nil).originalHTML())
        let document = try SwiftSoup.parse("<p>&#xff5c;猫</p>")
        let paragraph = try XCTUnwrap(document.select("p").first())
        let text = try XCTUnwrap(paragraph.getChildNodes().first as? TextNode)
        XCTAssertEqual(text.originalHTML(), "&#xff5c;猫")
        text.text("｜犬《いぬ》")
        XCTAssertNil(text.originalHTML())
        XCTAssertEqual(text.getWholeText(), "｜犬《いぬ》")
    }

    func testSiblingEditDoesNotInvalidateUnchangedTextSource() throws {
        let document = try SwiftSoup.parse("<p>&#xff5c;猫<span>犬</span></p>")
        let paragraph = try XCTUnwrap(document.select("p").first())
        let text = try XCTUnwrap(paragraph.getChildNodes().first as? TextNode)
        try document.select("span").first()?.text("更新")
        XCTAssertEqual(text.originalHTML(), "&#xff5c;猫")
    }
    func testFragmentSourceIsExactOrDeclinedBeforeEdits() throws {
        let document = try SwiftSoup.parseBodyFragment("<p>&#xff5c;猫</p>")
        let paragraph = try XCTUnwrap(document.select("p").first())
        let text = try XCTUnwrap(paragraph.getChildNodes().first as? TextNode)
        XCTAssertEqual(text.getWholeText(), "｜猫")
        if let source = text.originalHTML() {
            XCTAssertEqual(try Parser.unescapeEntities(source, false), text.getWholeText())
        }
        text.text("｜犬《いぬ》")
        XCTAssertNil(text.originalHTML(), "Edited data cannot introduce authored markup")
    }

    func testEntityRangesStayIndependentAcrossMarkup() throws {
        let document = try SwiftSoup.parse("<p>前&amp;<b>内</b>&#xff5c;後</p>")
        let paragraph = try XCTUnwrap(document.select("p").first())
        let texts = paragraph.getChildNodes().compactMap { $0 as? TextNode }
        XCTAssertEqual(texts.map { $0.getWholeText() }, ["前&", "｜後"])
        XCTAssertEqual(texts.map { $0.originalHTML() }, ["前&amp;", "&#xff5c;後"])
    }

    func testSourceRangesOnlyCoverMappedInput() throws {
        for (source, decoded, original) in [
            ("A&amp;B", "A&B", Optional("A&amp;B")),
            ("A&#0;B", "A\u{FFFD}B", Optional("A&#0;B")),
            ("A\0B", "A\0B", nil),
        ] {
            let document = try SwiftSoup.parse("<p>" + source + "</p>")
            let paragraph = try XCTUnwrap(document.select("p").first())
            let text = try XCTUnwrap(paragraph.getChildNodes().first as? TextNode)
            XCTAssertEqual(text.getWholeText(), decoded)
            XCTAssertEqual(text.originalHTML(), original)
        }
    }

    func testXMLDecodedTextAndOriginalSpellingRemainIndependent() throws {
        let source = "猫&#128;&amp;"
        let document = try SwiftSoup.parse("<?xml version='1.0'?><root>" + source + "</root>")
        let root = try XCTUnwrap(document.select("root").first())
        let text = try XCTUnwrap(root.getChildNodes().first as? TextNode)
        XCTAssertEqual(text.getWholeText(), "猫\u{80}&")
        XCTAssertEqual(text.originalHTML(), source)
    }

    func testRCDATATextRetainsCharacterReferenceSpelling() throws {
        for tag in ["textarea", "title"] {
            for source in ["前&amp;｜猫《ねこ》後", "｜猫《ね&#12371;》&amp;後",
                           "&#xff5c;猫《ねこ》", "A& B", "&unknown;猫", "&NotEqualTilde;猫"] {
                let document = try SwiftSoup.parse("<\(tag)>" + source + "</\(tag)>")
                let element = try XCTUnwrap(document.select(tag).first())
                let text = try XCTUnwrap(element.getChildNodes().first as? TextNode)
                XCTAssertEqual(text.getWholeText(), try Parser.unescapeEntities(source, false), source)
                XCTAssertEqual(text.originalHTML(), source, "\(tag): \(source)")
                text.text("更新")
                XCTAssertNil(text.originalHTML())
            }
        }
    }

}
