import XCTest
@testable import SwiftSoup

final class ClassTokenByteIdentityTest: XCTestCase {
    private let composed = "\u{00E9}"
    private let decomposed = "e\u{0301}"

    private func element(className: String) throws -> Element {
        let element = Element(try Tag.valueOf("div"), "")
        try element.attr("class", className)
        return element
    }

    private func tokens(_ element: Element) throws -> [[UInt8]] {
        Array(try element.classNamesUTF8())
    }

    func testFixtureUsesCanonicallyEquivalentButByteDistinctSpellings() {
        XCTAssertEqual(composed, decomposed)
        XCTAssertNotEqual(Array(composed.utf8), Array(decomposed.utf8))
    }

    func testAddClassPreservesBothExistingCanonicalSpellings() throws {
        let element = try element(className: "\(composed) \(decomposed) keep")

        try element.addClass("fresh")

        XCTAssertEqual(try tokens(element), [
            Array(composed.utf8), Array(decomposed.utf8),
            Array("keep".utf8), Array("fresh".utf8),
        ])
    }

    func testAddClassCanAddCanonicallyEquivalentDistinctToken() throws {
        let element = try element(className: composed)

        try element.addClass(decomposed)

        XCTAssertEqual(try tokens(element), [
            Array(composed.utf8), Array(decomposed.utf8),
        ])
    }

    func testRemoveClassRemovesOnlyExactUTF8Token() throws {
        let element = try element(className: "\(composed) \(decomposed) keep")

        try element.removeClass(composed)

        XCTAssertEqual(try tokens(element), [
            Array(decomposed.utf8), Array("keep".utf8),
        ])
    }

    func testToggleClassRemovesOnlyExactUTF8Token() throws {
        let element = try element(className: "\(composed) \(decomposed)")

        try element.toggleClass(decomposed)

        XCTAssertEqual(try tokens(element), [Array(composed.utf8)])
    }

    func testToggleClassAddsDistinctCanonicalVariant() throws {
        let element = try element(className: composed)

        try element.toggleClass(decomposed)

        XCTAssertEqual(try tokens(element), [
            Array(composed.utf8), Array(decomposed.utf8),
        ])
    }

    func testMutationPreservesMalformedExistingClassBytes() throws {
        let element = Element(try Tag.valueOf("div"), "")
        let malformed: [UInt8] = [0x66, 0x6f, 0x80, 0x6f]
        try element.attr(UTF8Arrays.class_, malformed)

        try element.addClass("fresh")

        XCTAssertEqual(try element.attr(UTF8Arrays.class_),
            malformed + [UInt8(ascii: " ")] + Array("fresh".utf8))
    }

    func testMutationRetainsHTMLASCIIWhitespaceNormalization() throws {
        let element = try element(className: "  a\tb\r\nc\u{0C}d  ")

        try element.addClass("e")

        XCTAssertEqual(try element.attr("class"), "a b c d e")
    }

    func testExistingExactTokenIsNotDuplicated() throws {
        let element = try element(className: "\(composed) keep")

        try element.addClass(composed)

        XCTAssertEqual(try tokens(element), [
            Array(composed.utf8), Array("keep".utf8),
        ])
    }

    func testASCIICaseVariantsRemainDistinctTokens() throws {
        let element = try element(className: "foo")

        try element.addClass("FOO")

        XCTAssertEqual(try tokens(element), [
            Array("foo".utf8), Array("FOO".utf8),
        ])
    }
}
