import XCTest
@testable import SwiftSoup

final class TemplateTreeBuilderTest: XCTestCase {
    private func parse(_ body: String) throws -> Document {
        let document = try SwiftSoup.parse("<!doctype html>" + body)
        document.outputSettings().prettyPrint(pretty: false)
        return document
    }

    func testParagraphAndListScopesDoNotEscapeTemplate() throws {
        for (outer, inner) in [("p", "p"), ("li", "li"), ("dd", "dt"), ("button", "button")] {
            for close in ["</\(inner)>", ""] {
                let doc = try parse("<\(outer) id=outer>visible<template><\(inner) id=draft>draft\(close)</template>tail</\(outer)><p id=after>after</p>")
                let template = try XCTUnwrap(doc.select("template").first())
                XCTAssertEqual(try template.select("#draft").size(), 1)
                XCTAssertEqual(try doc.getElementById("outer")?.parent(), doc.body())
                XCTAssertEqual(try doc.getElementById("after")?.parent(), doc.body())
                XCTAssertTrue(try doc.getElementById("outer")!.ownText().contains("tail"))
            }
        }
    }

    func testStrayOuterEndTagsCannotRetireTemplate() throws {
        for end in ["p", "div", "body", "html", "table", "form", "li", "button"] {
            let doc = try parse("<div id=outer><template></\(end)><p id=draft>draft</template><p id=after>after</div>")
            XCTAssertEqual(try doc.select("template #draft").size(), 1, end)
            XCTAssertEqual(try doc.select("#outer > #after").size(), 1, end)
        }
    }

    func testTableInsertionModesAndFosteringStayInsideTemplate() throws {
        for content in ["<tr><td id=draft>draft", "<td id=draft>draft", "<colgroup><col id=draft>", "<table>foster<tr><td id=draft>draft"] {
            let doc = try parse("<p id=outer>before<template>\(content)</template>tail</p><p id=after>after</p>")
            XCTAssertEqual(try doc.select("template #draft").size(), 1, content)
            XCTAssertEqual(try doc.select("#after").first()?.parent(), doc.body())
            XCTAssertEqual(try doc.getElementById("outer")?.ownText(), "beforetail")
        }
        let doc = try parse("<table><template>draft<div id=draft>text</div></template><tr><td>live</table><p id=after>after")
        XCTAssertEqual(try doc.select("table > template > #draft").size(), 1)
        XCTAssertEqual(try doc.select("table > template").first()?.ownText(), "draft")
        XCTAssertEqual(try doc.getElementById("after")?.parent(), doc.body())
    }

    func testFormattingAndFormsDoNotLeakAcrossTemplateClose() throws {
        let doc = try parse("<form id=outer><template><form id=inner><b id=draft>draft</template><p id=after>after</p><input name=live></form>")
        XCTAssertEqual(try doc.select("template #inner #draft").size(), 1)
        XCTAssertEqual(try doc.select("#after b").size(), 0)
        XCTAssertEqual(try doc.select("#outer > #after").size(), 1)
        let form = try XCTUnwrap(doc.getElementById("outer") as? FormElement)
        XCTAssertEqual(form.elements().size(), 1)
    }

    func testNestedTemplatesAndSelfClosingSyntaxPreserveLiveTail() throws {
        let doc = try parse("<p>before<template/><template><p id=draft>draft</template>inner</template>tail</p><p id=after>after")
        XCTAssertEqual(try doc.select("template template #draft").size(), 1)
        XCTAssertEqual(try doc.select("body > p").size(), 2)
        XCTAssertEqual(try doc.select("body > p").first()?.ownText(), "beforetail")
        XCTAssertEqual(try doc.select("body > #after").size(), 1)
    }

    func testTemplateFragmentUsesTemplateInsertionMode() throws {
        let context = try Element(Tag.valueOf("template"), [])
        let nodes = try Parser.parseFragment("<tr><td>cell</td></tr>", context, [])
        XCTAssertEqual((nodes.first as? Element)?.tagNameNormal(), "tr")
        XCTAssertEqual(try (nodes.first as? Element)?.text(), "cell")
    }

    func testTemplateInHeadRestoresHeadModeBeforeCreatingBody() throws {
        let doc = try parse("<template><p id='draft'>draft</template><title>Title</title><p id='live'>live")
        XCTAssertEqual(try doc.select("head > template #draft").size(), 1)
        XCTAssertEqual(try doc.select("head > title").text(), "Title")
        XCTAssertEqual(try doc.getElementById("live")?.parent(), doc.body())
    }

    func testUnclosedTemplatesStopAtEOFWithoutFormattingEscape() throws {
        let doc = try parse("<p>before<template><b>draft<template><p>nested")
        XCTAssertEqual(try doc.select("template template p").size(), 1)
        XCTAssertEqual(try doc.select("body > p > template").size(), 1)
    }

    func testForeignIntegrationScopeDoesNotCloseOuterParagraph() throws {
        let doc = try parse("<p id='outer'>before<svg><title><p id='inner'>inside</p></title></svg>after</p><p id='next'>next")
        XCTAssertEqual(try doc.getElementById("outer")?.ownText(), "beforeafter")
        XCTAssertEqual(try doc.select("#outer > svg > title > #inner").size(), 1)
        XCTAssertEqual(try doc.getElementById("next")?.parent(), doc.body())
    }

    func testForeignTemplateNamesRemainForeignAndTitlesIntegrateHTML() throws {
        for foreign in ["svg", "math"] {
            let doc = try parse("<\(foreign)><template id=foreign>visible</template></\(foreign)><p id=after>after")
            XCTAssertEqual(try doc.getElementById("foreign")?.namespace(), foreign == "svg" ? .svg : .mathml)
            XCTAssertEqual(try doc.getElementById("after")?.namespace(), .html)
        }
        let doc = try parse("<svg><title><template id=inert><p>draft</template>live</title><foreignObject><template id=other>draft</template><p id=live>live</p></foreignObject></svg>")
        XCTAssertEqual(try doc.getElementById("inert")?.namespace(), .html)
        XCTAssertEqual(try doc.getElementById("other")?.namespace(), .html)
        XCTAssertEqual(try doc.select("svg > title > template > p").size(), 1)
        XCTAssertEqual(try doc.getElementById("live")?.namespace(), .html)
        XCTAssertFalse(try doc.outerHtml().contains("&lt;template"))
    }

    func testMathMLIntegrationAndForeignBreakouts() throws {
        let doc = try parse("<math><mtext><template id=inert>draft</template><mglyph id='glyph'/></mtext><annotation-xml encoding='text/html'><template id=encoded>draft</template></annotation-xml></math><svg><g><p id=after>live</p>")
        XCTAssertEqual(try doc.getElementById("inert")?.namespace(), .html)
        XCTAssertEqual(try doc.getElementById("encoded")?.namespace(), .html)
        XCTAssertEqual(try doc.getElementById("glyph")?.namespace(), .mathml)
        XCTAssertEqual(try doc.select("body > #after").size(), 1)
    }

    func testForeignNamesAttributesSerializationAndCloneRetainNamespace() throws {
        let doc = try parse("<svg viewbox='0 0 10 10'><lineargradient/><foreignobject><p>live</p></foreignobject><source></source></svg>")
        let svg = try XCTUnwrap(doc.select("svg").first())
        XCTAssertEqual(try svg.attr("viewBox"), "0 0 10 10")
        XCTAssertEqual(try doc.select("foreignObject").first()?.tagName(), "foreignObject")
        XCTAssertEqual(try doc.select("linearGradient").first()?.tagName(), "linearGradient")
        XCTAssertTrue(try doc.outerHtml().contains("<source></source>"))
        XCTAssertEqual((svg.copy() as? Element)?.namespace(), .svg)
        let reparse = try SwiftSoup.parse(doc.outerHtml())
        XCTAssertEqual(try reparse.select("svg source").size(), 1)
    }

    func testSVGTitleFragmentUsesHTMLIntegrationWithoutRCDATA() throws {
        let doc = try parse("<svg><title id='title'></title></svg>")
        let title = try XCTUnwrap(doc.getElementById("title"))
        let nodes = try Parser.parseFragment("<template><p>draft</template>live", title, [])
        let template = try XCTUnwrap(nodes.first as? Element)
        XCTAssertEqual(template.tagNameNormal(), "template")
        XCTAssertEqual(template.namespace(), .html)
        XCTAssertEqual(try template.select("p").text(), "draft")
    }

    func testCDATAIsTextOnlyInForeignNamespace() throws {
        let doc = try parse("<div><![CDATA[hidden]]></div><svg><![CDATA[visible]]></svg>")
        XCTAssertEqual(try doc.select("div").text(), "")
        XCTAssertEqual(try doc.select("svg").text(), "visible")
    }

    func testXMLNamespacesPreserveXHTMLAndForeignTemplateIdentity() throws {
        let doc = try SwiftSoup.parse("<html xmlns='http://www.w3.org/1999/xhtml'>"
            + "<template id='html'>draft</template><svg xmlns='http://www.w3.org/2000/svg'>"
            + "<template id='foreign'>visible</template></svg><div xmlns='urn:other'>"
            + "<template id='other'>visible</template></div></html>", "", Parser.xmlParser())
        XCTAssertEqual(try doc.getElementById("html")?.namespace(), .html)
        XCTAssertEqual(try doc.getElementById("foreign")?.namespace(), .svg)
        XCTAssertEqual(try doc.getElementById("other")?.namespace(), .other)
    }
}
