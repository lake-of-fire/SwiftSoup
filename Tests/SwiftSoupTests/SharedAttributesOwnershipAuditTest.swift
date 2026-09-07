import XCTest
@testable import SwiftSoup

final class SharedAttributesOwnershipAuditTest: XCTestCase {
    func testDocumentCopyPreservesOutputSettings() throws {
        let document = try SwiftSoup.parse("<p>text</p>")
        document.outputSettings().prettyPrint(pretty: false)
        document.quirksMode(.quirks)
        document.updateMetaCharsetElement(true)
        let clone = document.copy() as! Document
        XCTAssertFalse(clone.outputSettings().prettyPrint())
        XCTAssertEqual(clone.quirksMode(), .quirks)
        XCTAssertTrue(clone.updateMetaCharsetElement())
        XCTAssertEqual(try clone.outerHtml(), try document.outerHtml())
        clone.outputSettings().prettyPrint(pretty: true)
        XCTAssertFalse(document.outputSettings().prettyPrint())
    }

    func testCopiedXmlDocumentPreservesParsingAndSerializationMode() throws {
        let document = try SwiftSoup.parse("<Root><Child /></Root>", "", Parser.xmlParser())
        let clone = document.copy() as! Document
        XCTAssertTrue(clone.parsedAsXml)
        XCTAssertEqual(clone.outputSettings().syntax(), .xml)
        XCTAssertEqual(try clone.outerHtml(), try document.outerHtml())
    }

    func testStandaloneFormCopyMapsDescendantsAndDropsExternalControls() throws {
        let document = try SwiftSoup.parse("<form><input name='q'></form><input name='external'>")
        let original = try XCTUnwrap(document.select("form").first() as? FormElement)
        let external = try XCTUnwrap(document.select("input[name=external]").first())
        original.addElement(external)
        let clone = original.copy() as! FormElement
        XCTAssertEqual(clone.elements().size(), 1)
        XCTAssertTrue(clone.elements().first() === (try clone.select("input").first()))

        let documentClone = document.copy() as! Document
        let documentClonedForm = try XCTUnwrap(documentClone.select("form").first() as? FormElement)
        XCTAssertEqual(documentClonedForm.elements().size(), 2)
        XCTAssertTrue(documentClonedForm.elements().last() === (try documentClone.select("input[name=external]").first()))
    }

    func testCopiedFormControlsBelongToCopiedDocument() throws {
        let document = try SwiftSoup.parse("<form><input name='q' value='original'></form>")
        let clone = document.copy() as! Document
        let originalForm = try XCTUnwrap(document.select("form").first() as? FormElement)
        let clonedForm = try XCTUnwrap(clone.select("form").first() as? FormElement)
        let clonedInput = try XCTUnwrap(clone.select("input").first())
        XCTAssertTrue(clonedForm.elements().first() === clonedInput)
        try clonedForm.elements().first()?.attr("value", "changed")
        XCTAssertEqual(try originalForm.elements().first()?.attr("value"), "original")
    }

    func testSharedAttributeCollectionInvalidatesEveryElementRoot() throws {
        let attributes = Attributes()
        try attributes.put("class", "before")
        let first = Element(try Tag.valueOf("p"), "", attributes)
        let second = Element(try Tag.valueOf("p"), "", attributes)
        for element in [first, second] {
            for _ in 0..<3 {
                XCTAssertEqual(try element.select(".before").size(), 1)
                XCTAssertEqual(try element.select(".after").size(), 0)
            }
        }
        try attributes.put("class", "after")
        for element in [first, second] {
            XCTAssertEqual(try element.attr("class"), "after")
            XCTAssertEqual(try element.select(".before").size(), 0)
            XCTAssertEqual(try element.select(".after").size(), 1)
        }
    }

    func testSharedAttributesDirtyEverySourceDocument() throws {
        let doc = try SwiftSoup.parse("<p class='old'>text</p>")
        doc.outputSettings().prettyPrint(pretty: false)
        let p = try XCTUnwrap(doc.select("p").first())
        let attributes = try XCTUnwrap(p.getAttributes())
        let other = Element(try Tag.valueOf("span"), "", attributes)
        try other.attr("class", "new")
        XCTAssertTrue(String(decoding: try doc.outerHtmlUTF8(), as: UTF8.self).contains("class=\"new\""))
    }

    func testSharedAttributeCollectionStillInvalidatesAfterNewestOwnerDies() throws {
        let attributes = Attributes()
        try attributes.put("class", "before")
        let first = Element(try Tag.valueOf("p"), "", attributes)
        do {
            let second = Element(try Tag.valueOf("p"), "", attributes)
            XCTAssertEqual(try second.attr("class"), "before")
        }
        for _ in 0..<3 { XCTAssertEqual(try first.select(".before").size(), 1) }
        try attributes.put("class", "after")
        XCTAssertEqual(try first.select(".before").size(), 0)
        XCTAssertEqual(try first.select(".after").size(), 1)
    }
}
