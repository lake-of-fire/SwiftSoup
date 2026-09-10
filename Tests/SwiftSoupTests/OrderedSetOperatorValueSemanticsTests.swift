import XCTest
@testable import SwiftSoup

final class OrderedSetOperatorValueSemanticsTests: XCTestCase {
    func testPlusDoesNotMutateLeftOperandAndReturnsIndependentContainer() {
        let lhs = OrderedSet(sequence: [1, 2])
        let result = lhs + [2, 3]
        XCTAssertEqual(Array(lhs), [1, 2])
        XCTAssertEqual(Array(result), [1, 2, 3])
        XCTAssertFalse(lhs === result)
        result.append(4)
        XCTAssertEqual(Array(lhs), [1, 2])
        XCTAssertEqual(Array(result), [1, 2, 3, 4])
    }

    func testMinusDoesNotMutateLeftOperandAndReturnsIndependentContainer() {
        let lhs = OrderedSet(sequence: [1, 2, 3])
        let result = lhs - [2]
        XCTAssertEqual(Array(lhs), [1, 2, 3])
        XCTAssertEqual(Array(result), [1, 3])
        XCTAssertFalse(lhs === result)
        result.remove(1)
        XCTAssertEqual(Array(lhs), [1, 2, 3])
        XCTAssertEqual(Array(result), [3])
    }

    func testEmptyRightHandSideStillProducesIndependentValue() {
        let lhs = OrderedSet(sequence: [1, 2])
        let plus = lhs + [Int]()
        let minus = lhs - [Int]()
        XCTAssertFalse(lhs === plus)
        XCTAssertFalse(lhs === minus)
        plus.append(3)
        minus.remove(1)
        XCTAssertEqual(Array(lhs), [1, 2])
        XCTAssertEqual(Array(plus), [1, 2, 3])
        XCTAssertEqual(Array(minus), [2])
    }

    func testMutatingAssignmentOperatorsRemainMutating() {
        var plus = OrderedSet(sequence: [1, 2])
        plus += [3]
        XCTAssertEqual(Array(plus), [1, 2, 3])
        var minus = OrderedSet(sequence: [1, 2, 3])
        minus -= [2]
        XCTAssertEqual(Array(minus), [1, 3])
    }
}
