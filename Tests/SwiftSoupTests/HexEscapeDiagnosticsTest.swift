import XCTest
@testable import SwiftSoup

final class HexEscapeDiagnosticsTest: XCTestCase {
    func testUnicodeIdentifierDiagnostics() throws {
        for (query, value) in [(#"#\65e5\672c"#, "日本"), ("#e\u{301}", "e\u{301}"), ("#é", "é"), ("#e\u{301}", "e\u{301}"), (#"#\61"# + "\u{20DD}", "a\u{20DD}")] {
            let doc = try SwiftSoup.parse("<main><p>hit</p><p>miss</p></main>")
            let target = try XCTUnwrap(doc.select("p").first())
            try target.attr("id", value)
            let decoded = TokenQueue(String(query.dropFirst())).consumeCssIdentifier()
            let parsed = try QueryParser.parse(query)
            let storedCache = QueryParser.cache
            QueryParser.cache = nil
            let fresh: Evaluator
            do {
                fresh = try QueryParser.parse(query)
                QueryParser.cache = storedCache
            } catch {
                QueryParser.cache = storedCache
                throw error
            }
            let selected = try doc.select(query)
            let collected = try Collector.collect(parsed, doc)
            let freshCollected = try Collector.collect(fresh, doc)
            print("HEX-DIAG query=\(query.debugDescription) input=\(Array(value.utf8)) id=\(target.idUTF8()) decoded=\(Array(decoded.utf8)) cached=\((parsed as? Evaluator.Id)?.idBytes ?? []) fresh=\((fresh as? Evaluator.Id)?.idBytes ?? []) selected=\(selected.size()) collected=\(collected.size()) freshCollected=\(freshCollected.size())")
        }
    }
}
