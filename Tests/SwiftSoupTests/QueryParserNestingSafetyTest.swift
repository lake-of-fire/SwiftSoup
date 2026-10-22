import Foundation
import XCTest
@testable import SwiftSoup

private func nestedNotSelector(_ depth: Int, atom: String = ".missing") -> String {
    String(repeating: ":not(", count: depth) + atom + String(repeating: ")", count: depth)
}

private func nestedHasSelector(_ depth: Int, atom: String = "span") -> String {
    String(repeating: ":has(", count: depth) + atom + String(repeating: ")", count: depth)
}

final class QueryParserNestingSafetyTest: XCTestCase {
    func testExcessiveNotNestingThrowsInsteadOfOverflowOnSmallStack() {
        let done = DispatchSemaphore(value: 0)
        let query = nestedNotSelector(800)
        let thread = Thread {
            defer { done.signal() }
            do {
                _ = try QueryParser.parse(query)
                XCTFail("Expected excessive selector nesting to be rejected")
            } catch Exception.Error(type: .SelectorParseException, Message: let message) {
                XCTAssertTrue(message.contains("nesting"), message)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
        thread.stackSize = 512 * 1024
        thread.start()
        XCTAssertEqual(done.wait(timeout: .now() + 60), .success)
    }

    func testSupportedNestingBoundaryStillParsesAndMatchesOnSmallStack() {
        let done = DispatchSemaphore(value: 0)
        let query = nestedNotSelector(64)
        let thread = Thread {
            defer { done.signal() }
            do {
                let evaluator = try QueryParser.parse(query)
                let element = try Element(Tag.valueOf("div"), "")
                XCTAssertFalse(try evaluator.matches(element, element))
                XCTAssertFalse(evaluator.toString().isEmpty)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
        thread.stackSize = 512 * 1024
        thread.start()
        XCTAssertEqual(done.wait(timeout: .now() + 60), .success)
    }

    func testHasAndCachedNestedSubqueriesCannotBypassLimit() throws {
        XCTAssertThrowsError(try QueryParser.parse(nestedHasSelector(800)))

        let previous = QueryParser.cache
        QueryParser.cache = QueryParser.DefaultCache(limit: .count(512))
        defer { QueryParser.cache = previous }

        let inner = nestedNotSelector(64)
        _ = try QueryParser.parse(inner)
        XCTAssertThrowsError(try QueryParser.parse(":not(" + inner + ")")) { error in
            guard case Exception.Error(type: .SelectorParseException, Message: _) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }
}
