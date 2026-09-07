import XCTest
@testable import SwiftSoup
final class SelectorSeedBoundaryTest: XCTestCase {
    func testPresenceSeedsDoNotSkipValuePredicates() throws {
        let doc = try SwiftSoup.parse("<p data-x='yes'>text</p><p data-x='bad'>text</p>")
        for clause in ["[data-x^=yes]", "[data-x$=yes]", "[data-x*=yes]", "[data-x~=^yes$]"] {
            XCTAssertEqual(try doc.select(clause + ":contains(text)").size(), 1, clause)
            let evaluator = try QueryParser.parse(clause)
            XCTAssertEqual(try Collector.collect(CombiningEvaluator.And([evaluator]), doc).size(), 1, clause)
        }
    }
    func testUnicodeQueryCacheKeysPreserveByteDistinctIds() throws {
        let ids = ["é", "e\u{301}"]
        let doc = try SwiftSoup.parse("<p id='é'>first</p><p id='e\u{301}'>second</p>")
        for _ in 0..<3 {
            for (index, id) in ids.enumerated() {
                let expected = index == 0 ? "first" : "second"
                XCTAssertEqual(try doc.select("#" + id).text(), expected)
                XCTAssertEqual(try doc.select("p#" + id + ":not(.none)").text(), expected)
            }
        }
    }
    func testAbsoluteAttributePresenceAndPatternSelectors() throws {
        let doc = try SwiftSoup.parse("<a href='page'>text</a><a>text</a>", "https://example.com/")
        for query in ["[abs:href]", "a[abs:href]", "[abs:href]:contains(text)",
                      "[abs:href^=https]:contains(text)", "[abs:href~=example]:contains(text)"] {
            XCTAssertEqual(try doc.select(query).size(), 1, query)
        }
    }

    func testStandaloneHasRelativeChildUsesCandidateScope() throws {
        let doc = try SwiftSoup.parse("<section id=direct><p>x</p></section><section id=nested><div id=inner><p>x</p></div></section>")
        XCTAssertEqual(try doc.select(":has(> p)").array().map { $0.id() }, ["direct", "inner"])
    }
}
