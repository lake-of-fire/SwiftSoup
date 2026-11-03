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

}
