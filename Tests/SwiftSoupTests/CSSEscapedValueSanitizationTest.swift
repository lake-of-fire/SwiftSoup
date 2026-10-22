import Foundation
import XCTest
@testable import SwiftSoup

final class CSSEscapedValueSanitizationTest: XCTestCase {
    private func whitelist() throws -> Whitelist {
        try Whitelist().addTags("p").addAttributes("p", "style")
            .addCSSProperties("p", "color", "background-image", "width", "content", "font-family", "transform")
    }

    private func cleanStyle(_ style: String, with whitelist: Whitelist) throws -> String {
        let doc = Document.createShell("")
        let p = try XCTUnwrap(doc.body()).appendElement("p")
        try p.attr("style", style)
        let original = try p.attr("style")
        let cleaner = Cleaner(headWhitelist: nil, bodyWhitelist: whitelist)
        let result = try cleaner.clean(doc)
        XCTAssertEqual(try p.attr("style"), original, "Cleaning must not modify input")
        return try result.select("p").attr("style")
    }

    func testEscapedURLFunctionNamesCannotBypassValueFiltering() throws {
        let policy = try whitelist()
        let names = [#"u\72l"#, #"\75rl"#, #"ur\6c"#, #"\75\72\6c"#,
                     #"\000075 rl"#, #"u\r\l"#, #"\URL"#, #"u\000052l"#]
        for name in names {
            for operand in ["https://example.invalid/a.png", "'https://example.invalid/a.png'"] {
                let style = "color:red; background-image:\(name)(\(operand)); width:2px"
                XCTAssertEqual(try cleanStyle(style, with: policy), "color:red; width:2px", style)
            }
        }
    }

    func testOneToSixHexDigitsAndWhitespaceTerminators() throws {
        let policy = try whitelist()
        for count in 2...6 {
            let digits = String(repeating: "0", count: count - 2) + "72"
            for terminator in ["", " ", "\t", "\n", "\r", "\r\n", "\u{c}"] {
                let style = "color:red; background-image:u\\\(digits)\(terminator)l(https://example.invalid/a)"
                XCTAssertEqual(try cleanStyle(style, with: policy), "color:red", style.debugDescription)
            }
        }
    }

    func testEscapedBlockedTokensInsideOtherFunctionsAndAfterComments() throws {
        let policy = try whitelist()
        for declaration in [#"width:ex\70ression(1)"#, #"width:\65 xpression(1)"#,
                            #"background-image:image-set(u\72l(https://example.invalid/a) 1x)"#,
                            #"background-image:u/*comment*/\72l(https://example.invalid/a)"#,
                            #"content:'\40import'"#] {
            XCTAssertEqual(try cleanStyle("color:red; " + declaration, with: policy), "color:red", declaration)
        }
    }

    func testSafeEscapedValuesRetainTheirSourceSpelling() throws {
        let policy = try whitelist()
        for declaration in [#"font-family:Open\ Sans"#, #"content:'\65\301 日本😀'"#,
                            #"content:'a\;b\:c'"#, #"content:'\\75rl'"#,
                            #"color:r\65 d"#, #"transform:translate(1px, calc(50% - 2px))"#] {
            XCTAssertEqual(try cleanStyle(declaration, with: policy), declaration, declaration)
        }
        // Decode only for validation. Emitting decoded punctuation could create
        // new declarations or change quote boundaries in otherwise safe content.
        let punctuation = #"content:'\27\3b background-image:example'"#
        XCTAssertEqual(try cleanStyle(punctuation, with: policy), punctuation)
    }

    func testPublicStringCleaningAndAllTagPolicy() throws {
        let policy = try Whitelist().addTags("p").addAttributes(":all", "style")
            .addCSSProperties(":all", "color", "background-image")
        let input = #"<p style="background-image:u\72l(https://example.invalid/a); color:blue">x</p>"#
        XCTAssertEqual(try SwiftSoup.clean(input, policy), #"<p style="color:blue">x</p>"#)
        // With no property-level CSS policy, style retains the pre-existing
        // opt-in behavior; this repair does not invent a policy for callers.
        let unfiltered = try Whitelist().addTags("p").addAttributes("p", "style")
        XCTAssertTrue(try XCTUnwrap(SwiftSoup.clean(input, unfiltered)).contains(#"u\72l"#))
    }
    func testMalformedAndContinuedEscapesDoNotTrapOrLeakUnsafeTokens() throws {
        let policy = try whitelist()
        XCTAssertEqual(try cleanStyle("color:red; content:trailing\\", with: policy), "color:red")
        for newline in ["\n", "\r", "\r\n", "\u{c}"] {
            let style = "color:red; content:'u\\" + newline + "rl(example)'"
            XCTAssertEqual(try cleanStyle(style, with: policy), "color:red")
        }
        for escaped in [#"\0"#, #"\D800"#, #"\110000"#, #"\FFFFFF"#, #"\1F600"#, #"\0000720"#] {
            let declaration = "content:'" + escaped + "'"
            XCTAssertEqual(try cleanStyle(declaration, with: policy), declaration)
        }
    }

}
