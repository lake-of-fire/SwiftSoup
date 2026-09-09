import Foundation
import XCTest
@testable import SwiftSoup

final class ElementsOutputAggregationTest: XCTestCase {
    private func element(_ text: String) throws -> Element {
        let element = try Element(Tag.valueOf("p"), "")
        try element.appendChild(TextNode(text, ""))
        return element
    }

    // Leading empty pieces never start a separator in the existing API.
    private func expected(_ pieces: [String], separator: String) -> String {
        guard let first = pieces.firstIndex(where: { !$0.isEmpty }) else { return "" }
        return pieces[first...].joined(separator: separator)
    }

    private func assertBytes(_ a: String, _ b: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Array(a.utf8), Array(b.utf8), file: file, line: line)
    }

    func testSingletonOutputAndMutationStaySinglePass() throws {
        let node = try element("日本語 e\u{301}")
        let single = Elements([node])
        for trim in [false,true] { assertBytes(try single.text(trimAndNormaliseWhitespace: trim), try node.text(trimAndNormaliseWhitespace: trim)) }
        assertBytes(try single.html(), try node.html())
        assertBytes(try single.outerHtml(), try node.outerHtml())
        let log = Log()
        let first = try OutputElement("first", "", log)
        let second = try OutputElement("second", "added", log)
        let mutating = Elements([first])
        first.callback = { mutating.add(second) }
        assertBytes(try mutating.outerHtml(), "")
        XCTAssertEqual(log.events, ["first"])
        XCTAssertEqual(mutating.size(), 2)
        first.callback = nil
        first.callback = { throw TestError.stop }
        XCTAssertThrowsError(try Elements([first]).outerHtml())
        first.callback = nil
    }

    func testTextSeparatorRulesIncludingAllEmptyAndTrailingEmptyElements() throws {
        for pieces in [[], [""], ["", ""], ["a"], ["", "a"], ["a", ""], ["", "a", "", "b", ""], [" ", "", "日本語", "\t"]] {
            let nodes = try pieces.map(element)
            let elements = Elements(nodes)
            for trim in [false, true] {
                let values = try nodes.map { try $0.text(trimAndNormaliseWhitespace: trim) }
                assertBytes(try elements.text(trimAndNormaliseWhitespace: trim), expected(values, separator: " "))
            }
        }
    }

    func testHtmlSeparatorsAndWhitespaceSettings() throws {
        for pretty in [false,true] {
            let doc = try SwiftSoup.parse("<main><p></p><p>日本語<b>かな</b><!--c--></p><p></p><p>e&#x301;</p><p></p></main>")
            doc.outputSettings().prettyPrint(pretty: pretty)
            let nodes = try doc.select("p").array(), elements = Elements(nodes)
            assertBytes(try elements.html(), expected(try nodes.map { try $0.html() }, separator: "\n"))
            assertBytes(try elements.outerHtml(), expected(try nodes.map { try $0.outerHtml() }, separator: "\n"))
            assertBytes(try elements.toString(), try elements.outerHtml())
        }
        assertBytes(try Elements().html(), "")
        assertBytes(try Elements().outerHtml(), "")
    }

    func testMalformedUTF8IsRepairedWithinEachElementBeforeJoining() throws {
        let values: [[UInt8]] = [[], [0xE3], [0x81,0x82], [0xF0,0x9F], [0x87,0xAF], [0xFF], [0xED,0xA0,0x80], [0xC0,0x80], [0], [13,10]]
        for a in values {
            for b in values {
                let first = try Element(Tag.valueOf("p"), ""), second = try Element(Tag.valueOf("p"), "")
                try first.appendChild(TextNode(a, [])); try second.appendChild(TextNode(b, []))
                let nodes = [first,second,first], elements = Elements(nodes)
                for trim in [false,true] {
                    assertBytes(try elements.text(trimAndNormaliseWhitespace: trim), expected(try nodes.map { try $0.text(trimAndNormaliseWhitespace: trim) }, separator: " "))
                }
            }
        }
    }

    func testUnicodeSpellingAndLongSourceStringsRemainByteExact() throws {
        let values = ["e\u{301}", "é", "\u{301}", "👩🏽‍💻", "🇯🇵", "\r\n", "\0", String(repeating: "日本語\u{00A0}𠮷\u{200D}", count: 2048)]
        let nodes = try values.map(element), elements = Elements(nodes)
        for trim in [false,true] {
            assertBytes(try elements.text(trimAndNormaliseWhitespace: trim), expected(try nodes.map { try $0.text(trimAndNormaliseWhitespace: trim) }, separator: " "))
        }
        assertBytes(try elements.html(), expected(try nodes.map { try $0.html() }, separator: "\n"))
        assertBytes(try elements.outerHtml(), expected(try nodes.map { try $0.outerHtml() }, separator: "\n"))
    }

    private final class Log { var events: [String] = [] }
    private enum TestError: Error { case stop }
    private final class OutputElement: Element, @unchecked Sendable {
        var value: String
        var callback: (() throws -> Void)?
        let label: String
        let log: Log
        init(_ label: String, _ value: String, _ log: Log) throws {
            self.label = label; self.value = value; self.log = log
            try super.init(Tag.valueOf("p"), [])
        }
        override func outerHtml() throws -> String {
            log.events.append(label)
            try callback?()
            return value
        }
    }

    func testOverriddenOuterHtmlCallsOnceInOrderWithoutPrecomputingValues() throws {
        let log = Log()
        let first = try OutputElement("first", "", log)
        let second = try OutputElement("second", "e\u{301}", log)
        let third = try OutputElement("third", "old", log)
        second.callback = { third.value = "日本語" }
        let elements = Elements([first,second,third,first])
        assertBytes(try elements.outerHtml(), "e\u{301}\n日本語\n")
        XCTAssertEqual(log.events, ["first","second","third","first"])
    }

    func testThrowingOuterHtmlStopsBeforeLaterGetters() throws {
        let log = Log()
        let first = try OutputElement("first", "a", log)
        let second = try OutputElement("second", "b", log)
        let third = try OutputElement("third", "c", log)
        second.callback = { throw TestError.stop }
        XCTAssertThrowsError(try Elements([first,second,third]).outerHtml()) { error in
            guard case TestError.stop = error else { return XCTFail("Wrong error \(error)") }
        }
        XCTAssertEqual(log.events, ["first","second"])
    }

    func testOuterHtmlRetainsCollectionIterationSnapshotDuringGetterMutation() throws {
        let log = Log()
        let first = try OutputElement("first", "a", log)
        let second = try OutputElement("second", "b", log)
        let added = try OutputElement("added", "c", log)
        let elements = Elements([first,second])
        first.callback = { elements.add(added) }
        assertBytes(try elements.outerHtml(), "a\nb")
        XCTAssertEqual(log.events, ["first","second"])
        XCTAssertEqual(elements.size(), 3)
        first.callback = nil
    }

    func testResultSnapshotsSourceStateAndSubsequentMutations() throws {
        let doc = try SwiftSoup.parse("<main><p>日本語</p><p>e&#x301;<b>文章</b></p></main>")
        let elements = try doc.select("p")
        let old = try elements.outerHtml(), oldText = try elements.text()
        let source = try doc.outerHtml(), version = doc.textMutationVersionToken()
        for _ in 0..<4 { _ = try elements.text(); _ = try elements.html(); _ = try elements.outerHtml() }
        assertBytes(try doc.outerHtml(), source)
        XCTAssertEqual(doc.textMutationVersionToken(), version)
        try elements.first()!.text("変更後")
        XCTAssertNotEqual(try elements.text(), oldText)
        XCTAssertNotEqual(try elements.outerHtml(), old)
        assertBytes(oldText, "日本語 e\u{301}文章")
        assertBytes(try elements.outerHtml(), expected(try elements.array().map { try $0.outerHtml() }, separator: "\n"))
    }

    func testDocumentsAndForeignFoundationStringsRetainPublicOutput() throws {
        let a = try SwiftSoup.parse("<title>題</title><p>内容</p>")
        let b = try SwiftSoup.parse("<p>二番</p>")
        let docSet = Elements([a,b,a])
        assertBytes(try docSet.outerHtml(), expected(try [a,b,a].map { try $0.outerHtml() }, separator: "\n"))
        let log = Log()
        let foreign: NSString = NSString(string: String(repeating: "e\u{301}🇯🇵", count: 2048))
        let first = try OutputElement("foreign", foreign as String, log)
        let second = try OutputElement("end", "\u{301}\0", log)
        assertBytes(try Elements([first,second]).outerHtml(), (foreign as String) + "\n\u{301}\0")
    }

    func testSeededOutputCasesIncludingDuplicateElements() throws {
        let alphabet = ["", " ", "\r\n", "日本語", "e\u{301}", "é", "👩🏽‍💻", "&<>\"", "\0"]
        var seed: UInt64 = 0x3BD593
        func next(_ count: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int(seed >> 32) % count }
        for _ in 0..<384 {
            var nodes = [Element]()
            for _ in 0..<next(20) {
                if !nodes.isEmpty && next(4) == 0 { nodes.append(nodes[next(nodes.count)]) }
                else { nodes.append(try element(alphabet[next(alphabet.count)])) }
            }
            let elements = Elements(nodes)
            for trim in [false,true] {
                assertBytes(try elements.text(trimAndNormaliseWhitespace: trim), expected(try nodes.map { try $0.text(trimAndNormaliseWhitespace: trim) }, separator: " "))
            }
            assertBytes(try elements.html(), expected(try nodes.map { try $0.html() }, separator: "\n"))
            assertBytes(try elements.outerHtml(), expected(try nodes.map { try $0.outerHtml() }, separator: "\n"))
        }
    }
}
