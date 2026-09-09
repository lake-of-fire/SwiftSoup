import XCTest
import SwiftSoup

final class TokenQueueEmptyIgnoreCaseDelimiterTest: XCTestCase {
    func testConsumeToIgnoreCaseEmptyDelimiterIsNoOp() {
        let queue = TokenQueue("AbC")
        XCTAssertEqual(queue.consumeToIgnoreCase(""), "")
        XCTAssertEqual(queue.remainder(), "AbC")
    }

    func testChompToIgnoreCaseEmptyDelimiterIsNoOp() {
        let queue = TokenQueue("AbC")
        XCTAssertEqual(queue.chompToIgnoreCase(""), "")
        XCTAssertEqual(queue.remainder(), "AbC")
    }

    func testEmptyDelimiterAfterPriorConsumptionPreservesPosition() {
        let queue = TokenQueue("AbC")
        XCTAssertTrue(queue.matchChomp("A"))
        XCTAssertEqual(queue.consumeToIgnoreCase(""), "")
        XCTAssertEqual(queue.remainder(), "bC")
    }

    func testEmptyDelimiterMatchesCaseSensitiveContract() {
        let sensitive = TokenQueue("AbC")
        let insensitive = TokenQueue("AbC")
        XCTAssertEqual(sensitive.consumeTo(""), insensitive.consumeToIgnoreCase(""))
        XCTAssertEqual(sensitive.remainder(), insensitive.remainder())
    }

    func testEmptyQueueAlsoAcceptsEmptyDelimiter() {
        let queue = TokenQueue("")
        XCTAssertEqual(queue.consumeToIgnoreCase(""), "")
        XCTAssertEqual(queue.chompToIgnoreCase(""), "")
        XCTAssertTrue(queue.isEmpty())
    }
}
