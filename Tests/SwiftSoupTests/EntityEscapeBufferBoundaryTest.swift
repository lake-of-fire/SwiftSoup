import Foundation
import XCTest
@testable import SwiftSoup

final class EntityEscapeBufferBoundaryTest: XCTestCase {
    private let truncated: [[UInt8]] = [[0xC2], [0xE2], [0xE2, 0x82], [0xF0], [0xF0, 0x9F], [0xF0, 0x9F, 0x98]]

    func testArraySliceNeverSerializesBytesBeyondItsEnd() {
        let out = OutputSettings().prettyPrint(pretty: true)
        for suffix in truncated {
            let input: [UInt8] = [0x20] + suffix
            let storage: [UInt8] = [0x23] + input + Array("NOT-INPUT".utf8)
            let slice = storage[1..<(1 + input.count)]
            let accum = StringBuilder()
            Entities.escape(accum, slice, out, false, true, false)
            XCTAssertEqual(Array(accum.buffer), input, "suffix=\(suffix)")
        }
    }

    func testAllByteSliceBackingsRespectTheSliceBoundary() {
        let out = OutputSettings()
        for suffix in truncated {
            let input: [UInt8] = [0x20] + suffix
            let bytes = [UInt8(0x23)] + input + Array("NOT-INPUT".utf8)
            func verify(_ storage: ByteStorage) {
                for inAttribute in [false, true] {
                    for strip in [false, true] {
                        let slice = ByteSlice(storage: storage, start: 1, end: 1 + input.count)
                        let accum = StringBuilder()
                        Entities.escape(accum, slice, out, inAttribute, true, strip)
                        XCTAssertEqual(Array(accum.buffer), strip ? suffix : input)
                    }
                }
            }
            verify(ByteStorage(array: bytes))
            verify(ByteStorage(data: Data(bytes)))
            bytes.withUnsafeBufferPointer { buffer in
                verify(ByteStorage(buffer: buffer.baseAddress!, count: buffer.count, owner: nil))
            }
        }
    }

    func testOwnedArrayAndPublicTextNodeDoNotOverreadTruncatedInput() throws {
        let doc = Document.createShell("")
        let p = try XCTUnwrap(doc.body()).appendElement("p")
        for suffix in truncated {
            let input: [UInt8] = [0x20] + suffix
            let direct = StringBuilder()
            Entities.escape(direct, input, doc.outputSettings(), false, true, false)
            XCTAssertEqual(Array(direct.buffer), input)
            let node = TextNode(input, [])
            p.empty()
            try p.appendChild(node)
            let serialized = StringBuilder()
            try node.outerHtml(serialized)
            XCTAssertEqual(Array(serialized.buffer), input)
        }
    }

    func testCompleteScalarsAndEscapingRemainUnchanged() {
        let out = OutputSettings()
        for text in [" ©", " €", " 😀", " 日本", " <&>"] {
            let expected = text.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            let accum = StringBuilder()
            Entities.escape(accum, Array(text.utf8), out, false, true, false)
            XCTAssertEqual(accum.toString(), expected)
        }
    }
}
