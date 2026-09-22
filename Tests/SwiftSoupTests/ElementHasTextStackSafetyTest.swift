import Foundation
import XCTest
@testable import SwiftSoup

final class ElementHasTextStackSafetyTest: XCTestCase {
    private final class CallLog {
        var values: [String] = []
    }

    private final class SpyTextNode: TextNode {
        let label: String
        let callLog: CallLog

        init(_ label: String, text: String, callLog: CallLog) {
            self.label = label
            self.callLog = callLog
            super.init(Array(text.utf8), [])
        }

        override func isBlank() -> Bool {
            callLog.values.append(label)
            return super.isBlank()
        }
    }

    func testDeepHasTextOnSmallStack() {
        let done = DispatchSemaphore(value: 0)
        let thread = Thread {
            defer { done.signal() }
            do {
                let root = try Element(Tag.valueOf("n"), "")
                var leaf = root
                for _ in 0..<5_000 {
                    let child = try Element(Tag.valueOf("n"), "")
                    try leaf.appendChild(child)
                    leaf = child
                }
                try leaf.appendChild(TextNode("x", ""))
                XCTAssertTrue(root.hasText())
                leaf.empty()
                XCTAssertFalse(root.hasText())
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
        thread.stackSize = 512 * 1024
        thread.start()
        XCTAssertEqual(done.wait(timeout: .now() + 60), .success)
    }

    func testDepthFirstShortCircuitOrderIsPreserved() throws {
        let log = CallLog()
        let root = try Element(Tag.valueOf("root"), "")
        try root.appendChild(SpyTextNode("a", text: " ", callLog: log))
        let nested = try root.appendElement("nested")
        try nested.appendChild(SpyTextNode("b", text: "\n", callLog: log))
        try nested.appendChild(SpyTextNode("c", text: "text", callLog: log))
        try root.appendChild(SpyTextNode("d", text: "later", callLog: log))

        XCTAssertTrue(root.hasText())
        XCTAssertEqual(log.values, ["a", "b", "c"])
    }

    func testNonTextNonElementNodesRemainIgnored() throws {
        let root = try Element(Tag.valueOf("root"), "")
        try root.appendChild(DataNode(Array("visible-data".utf8), []))
        try root.appendChild(Comment(Array("visible-comment".utf8), []))
        XCTAssertFalse(root.hasText())
        try root.appendChild(TextNode("\t", ""))
        XCTAssertFalse(root.hasText())
        try root.appendChild(TextNode("x", ""))
        XCTAssertTrue(root.hasText())
    }
}
