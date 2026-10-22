import XCTest
@testable import SwiftSoup

final class SerializationStackSafetyTest: XCTestCase {
    func testEveryUTF8SerializationPolicySurvivesDeepTreesOnSmallStack() {
        let done = DispatchSemaphore(value: 0)
        let thread = Thread {
            defer { done.signal() }
            do {
                let depth = 3_000
                let inner = String(repeating: "<span>", count: depth) + "text &amp; more"
                    + String(repeating: "</span>", count: depth)
                let html = "<html><head></head><body>" + inner + "</body></html>"
                let doc = try SwiftSoup.parse(html)
                doc.outputSettings().prettyPrint(pretty: false)
                let body = try XCTUnwrap(doc.body())
                XCTAssertEqual(try doc.outerHtmlUTF8WithoutSourceReuse(), Array(html.utf8))
                XCTAssertEqual(try doc.outerHtmlUTF8ReusingSourceOutsideBody(), Array(html.utf8))
                XCTAssertEqual(try body.htmlUTF8WithoutSourceReuse(), Array(inner.utf8))
                // Dirty the deep path so the ordinary serializer cannot bypass it
                // by reusing the complete clean ancestor's source range.
                var leaf: Node = body
                while let child = leaf.getChildNodes().first { leaf = child }
                try XCTUnwrap(leaf as? TextNode).text("updated & more")
                let updated = html.replacingOccurrences(of: "text &amp; more", with: "updated &amp; more")
                XCTAssertEqual(try doc.outerHtmlUTF8(), Array(updated.utf8))
                XCTAssertEqual(try doc.outerHtml(), updated)
            } catch {
                XCTFail("Deep serialization failed: \(error)")
            }
        }
        thread.stackSize = 512 * 1024
        thread.start()
        XCTAssertEqual(done.wait(timeout: .now() + 60), .success)
    }

    func testTraversalKeepsHeadTailDepthAndSiblingOrder() throws {
        let root = try RecordingElement("root")
        let left = try RecordingElement("left")
        let right = try RecordingElement("right")
        try root.appendChild(left)
        try root.appendChild(right)
        try left.appendChild(RecordingElement("leaf"))
        let output = StringBuilder()
        try root.outerHtmlFastWithoutSourceReuse(output, 7, OutputSettings())
        XCTAssertEqual(output.toString(), "<root:7><left:8><leaf:9></leaf:9></left:8><right:8></right:8></root:7>")
    }

    private final class RecordingElement: Element {
        init(_ name: String) throws { super.init(try Tag.valueOf(name), []) }
        override func outerHtmlHead(_ accum: StringBuilder, _ depth: Int, _ out: OutputSettings) throws {
            accum.append("<\(tagName()):\(depth)>")
        }
        override func outerHtmlTail(_ accum: StringBuilder, _ depth: Int, _ out: OutputSettings) {
            accum.append("</\(tagName()):\(depth)>")
        }
    }
}
