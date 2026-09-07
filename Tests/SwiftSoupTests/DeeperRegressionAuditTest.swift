import XCTest
@testable import SwiftSoup

final class DeeperRegressionAuditTest: XCTestCase {
    func testAttributeEdgeCasesAgreeBetweenIndexesAndEvaluators() throws {
        let values = ["", " ", "x", " X ", "É", "é", "İ", "i", "e\u{301}", "\u{00a0}", "\t\n"]
        for key in ["href", "class", "data-edge"] {
            let doc = try SwiftSoup.parse("<main></main>")
            let root = try XCTUnwrap(doc.select("main").first())
            for value in values {
                try root.appendElement("a").attr(key, value)
            }
            _ = try root.appendElement("a")
            for value in values {
                let query = "[\(key)='\(value)']"
                let evaluator = try QueryParser.parse(query)
                let expected = try ([root] + root.children().array()).filter { try evaluator.matches(root, $0) }
                let actual = try root.select(query).array()
                XCTAssertEqual(actual.map(ObjectIdentifier.init), expected.map(ObjectIdentifier.init), query)
            }
        }
    }

    func testTextSelectorFastPathsMatchExtractedText() throws {
        let fixtures = ["<div>K İ K I</div>", "<div>K<span>İ</span>K</div>",
            "<pre>A  B\n C<span>D</span>  E</pre>", "<div><pre>A  B\n C</pre>tail</div>",
            "<div>before<p>block</p>after</div>", "<div><p>block</p><span>after</span></div>",
            "<div> a <span>b</span> c </div>", "<div>x<br> y</div>", "<div> </div>",
            "<div>a&nbsp;b</div>", "<div><span></span> tail </div>"]
        for fixture in fixtures {
            let doc = try SwiftSoup.parse(fixture)
            let element = try XCTUnwrap(doc.body()?.children().first())
            let text = try element.text().lowercased()
            let own = element.ownText().lowercased()
            var needles = ["k", "i", "a  b", "b\n c", "blockafter", "block after", "before block", " ", "tail ", "a b"]
            needles += [text, own]
            for needle in needles {
                XCTAssertEqual(try Evaluator.ContainsText(needle).matches(element, element), text.contains(needle), "text: \(fixture), needle \(needle.debugDescription)")
                XCTAssertEqual(try Evaluator.ContainsOwnText(needle).matches(element, element), own.contains(needle), "own: \(fixture), needle \(needle.debugDescription)")
            }
        }
    }

    func testExplicitEmptyAttributeEqualityAndRegex() throws {
        let doc = try SwiftSoup.parse("<a id='empty' href=''></a><a id='missing'></a>")
        let empty = try XCTUnwrap(doc.getElementById("empty"))
        XCTAssertTrue(try empty.iS("[href='']"))
        XCTAssertFalse(try empty.iS("[href!='']"))
        XCTAssertEqual(try doc.select("[href~=^$]").array().map { $0.id() }, ["empty"])
    }

    func testPreservedCaseAttributeSelectorsAndDuplicateNames() throws {
        let parser = Parser.htmlParser().settings(ParseSettings.preserveCase)
        let doc = try SwiftSoup.parse("<a HREF='one' href='two' CLASS='first' class='second'></a>", "", parser)
        let element = try XCTUnwrap(doc.select("a").first())
        for query in ["[href]", "a[href]", "[href='one']", "[href='two']", "a[href='one']", "[class]", ".first", ".second"] {
            let evaluator = try QueryParser.parse(query)
            let expected = try evaluator.matches(doc, element) ? [ObjectIdentifier(element)] : []
            XCTAssertEqual(try doc.select(query).array().map(ObjectIdentifier.init), expected, query)
        }
        XCTAssertTrue(try element.iS("[href='one']"))
        XCTAssertEqual(try doc.select("[href]").size(), 1)
        XCTAssertEqual(try doc.select("[href='two']").size(), 0)
    }

    func testDuplicateClassTokensNeverDuplicateMatches() throws {
        let doc = try SwiftSoup.parse("<p class='x X x'>one</p><p class='x'>two</p>")
        for query in [".x", "p.x", ".x.x", "p.x:contains(one)"] {
            let result = try doc.select(query).array()
            XCTAssertEqual(result.count, Set(result.map(ObjectIdentifier.init)).count, query)
        }
        XCTAssertEqual(try doc.getElementsByClass("x").size(), 2)
    }

    func testMalformedParsingAgreesWithSourceTrackingDisabled() throws {
        let atoms = ["<p>", "</p>", "<b>", "</b>", "<table>", "<tr><td>", "</table>", "<select><option>",
            "</select>", "<ruby><rt>", "</ruby>", "<script>x<y</script>", "<!--x-->", "&amp;", "text", "<div a='x' b='y'>", "</div>"]
        var state: UInt64 = 0x5eed
        for iteration in 0..<250 {
            var html = ""
            for _ in 0..<12 {
                state = state &* 6364136223846793005 &+ 1
                html += atoms[Int((state >> 32) % UInt64(atoms.count))]
            }
            let tracked = try SwiftSoup.parse(html, "", Parser.htmlParser().settings(ParseSettings(false, false, true)))
            let untracked = try SwiftSoup.parse(html, "", Parser.htmlParser().settings(ParseSettings(false, false, false)))
            tracked.outputSettings().prettyPrint(pretty: false)
            untracked.outputSettings().prettyPrint(pretty: false)
            XCTAssertEqual(try tracked.outerHtmlUTF8WithoutSourceReuse(), try untracked.outerHtmlUTF8WithoutSourceReuse(), "case \(iteration): \(html)")
        }
    }

    func testSourceReuseHonorsChangedOutputSettings() throws {
        for variant in 0..<3 {
            let doc = try SwiftSoup.parse("<html><head><title>日本語</title></head><body><input disabled><p title='日本語'>日本語&nbsp;&copy;</p></body></html>")
            doc.outputSettings().prettyPrint(pretty: false)
            switch variant {
            case 0: doc.outputSettings().charset(.ascii)
            case 1: doc.outputSettings().syntax(syntax: .xml)
            default: doc.outputSettings().escapeMode(.xhtml)
            }
            let expected = try doc.outerHtmlUTF8WithoutSourceReuse()
            XCTAssertEqual(try doc.outerHtmlUTF8(), expected, "variant \(variant)")
            XCTAssertEqual(try doc.outerHtmlUTF8ReusingSourceOutsideBody(), expected, "body variant \(variant)")
        }
    }

    func testUnicodeAttributeEqualityAndInequalityAgree() throws {
        let doc = try SwiftSoup.parse("<p data-x='É'></p>")
        let p = try XCTUnwrap(doc.select("p").first())
        XCTAssertTrue(try p.iS("[data-x='é']"))
        XCTAssertFalse(try p.iS("[data-x!='é']"))
    }

    func testSourceReuseMatchesCurrentTreeAfterMutationSequences() throws {
        let fixtures = [
            "<!doctype html><html><head><title>x</title></head><body><main><p id='a'>one <b>bold</b></p><p id='b'>two</p></main></body></html>",
            "<main><p id=a>one<p id=b>two</main>",
            "<html><head></head><body><main><p id=a>日本語&amp;字</p><!--x--><p id=b>two</p></main></body></html>",
            "<main><table><tr><td>cell</table><p id=a>one</p><p id=b>two</p></main>"
        ]
        func canonical(_ bytes: [UInt8]) throws -> String {
            let parsed = try SwiftSoup.parse(String(decoding: bytes, as: UTF8.self))
            parsed.outputSettings().prettyPrint(pretty: false)
            return String(decoding: try parsed.outerHtmlUTF8WithoutSourceReuse(), as: UTF8.self)
        }
        for (fixtureIndex, fixture) in fixtures.enumerated() {
            let doc = try SwiftSoup.parse(fixture)
            doc.outputSettings().prettyPrint(pretty: false)
            let a = try XCTUnwrap(doc.getElementById("a"))
            let b = try XCTUnwrap(doc.getElementById("b"))
            for step in 0..<16 {
                switch step {
                case 0: try a.attr("data-test", "new")
                case 1: try a.appendText("<&追加")
                case 2: try b.before("<aside>new</aside>")
                case 3: try b.appendChild(a)
                case 4: try a.tagName("article")
                case 5: try a.text("replacement")
                case 6: try a.wrap("<section class='wrapped'></section>")
                case 7: try b.attr("class", "updated")
                case 8: try a.removeAttr("data-test")
                case 9: try b.prependText("prefix")
                case 10: try a.after("<em>after</em>")
                case 11: try a.remove()
                case 12: try b.appendChild(a)
                case 13: b.empty()
                case 14: try b.append("<span>final</span>")
                default: try doc.head()?.append("<meta name='changed' content='yes'>")
                }
                let expected = try canonical(doc.outerHtmlUTF8WithoutSourceReuse())
                XCTAssertEqual(try canonical(doc.outerHtmlUTF8()), expected, "fixture \(fixtureIndex), step \(step), patches")
                XCTAssertEqual(try canonical(doc.outerHtmlUTF8ReusingSourceOutsideBody()), expected, "fixture \(fixtureIndex), step \(step), body")
            }
        }
    }
}
