import Foundation
import XCTest
@testable import SwiftSoup

/// DOM-only workloads modeled on ReaderSentenceIdentityFinalizer,
/// ReaderModeContentProcessor+CacheRestoration, and the fresh EPUB DataNode path.
/// This deliberately excludes dictionary, sidecar, and WebView processing.
enum ReaderPipelineBenchmark {
    static let baseURI = "https://example.test/book/chapter.xhtml"

    static func withPool(_ body: () throws -> Void) rethrows {
        #if canImport(ObjectiveC)
        try autoreleasepool(invoking: body)
        #else
        try body()
        #endif
    }

    static func fixture(paragraphs: Int) -> (document: String, body: String) {
        let classCount = max(1, Int(ProcessInfo.processInfo.environment["SWIFTSOUP_BENCHMARK_READER_CLASS_COUNT"] ?? "1") ?? 1)
        let classes = (["mnb-seg"] + (1..<classCount).map { "existing-\($0)" }).joined(separator: " ")
        let body = (0..<paragraphs).map { p in
            let sentences = (0..<3).map { s in
                let segments = (0..<4).map { m in
                    "<m-m id='seg-\(p)-\(s)-\(m)' class='\(classes)'><ruby>日本語<rt>にほんご</rt></ruby>を読む。</m-m>"
                }.joined()
                return "<m-s h='hash-\(p)-\(s)' sid='local-\(s)'>\(segments)</m-s>"
            }.joined()
            return "<section class='chapter'><p id='p-\(p)'>\(sentences)</p></section>"
        }.joined()
        return ("<!doctype html><html><head><title>日本語</title><style>ruby{display:ruby}</style></head><body>\(body)</body></html>", body)
    }

    @inline(never)
    static func parse(_ html: String, xml: Bool) throws -> Document {
        let doc = try SwiftSoup.parse(html, baseURI, xml ? Parser.xmlParser() : Parser.htmlParser())
        doc.outputSettings().prettyPrint(pretty: false).syntax(syntax: xml ? .xml : .html)
        return doc
    }

    @inline(never)
    static func cloneAndRestore(_ body: Element) throws {
        // The Reader cache path serializes a fingerprint and stages a deep clone,
        // then retains shallow child snapshots for rollback before insertion.
        let html = try body.html()
        let stagedRoot = body.copy() as! Element
        try stagedRoot.html(html)
        let staged = stagedRoot.getChildNodes().map { $0.copy(parent: nil) }
        let original = body.getChildNodes().map { $0.copy(parent: nil) }
        body.empty()
        try body.insertChildren(0, staged)
        withExtendedLifetime(original) {}
    }

    @inline(never)
    static func finalize(_ doc: Document) throws -> Int {
        var stack = doc.getChildNodes()
        var count = 0
        while let node = stack.popLast() {
            if let element = node as? Element {
                switch element.tagNameNormal() {
                case "m-s":
                    let hash = try element.attr("h")
                    try element.attr("sid", "sentence-\(hash)")
                    try element.attr("o", "true")
                    count += 1
                case "m-m":
                    _ = try element.attr("id")
                    try element.addClass("mnb-known")
                default: break
                }
            }
            stack.append(contentsOf: node.getChildNodes())
        }
        return count
    }

    @inline(never)
    static func serialize(_ doc: Document) throws -> [UInt8] {
        try doc.outerHtmlUTF8ReusingSourceOutsideBody()
    }

    static func run() throws {
        let env = ProcessInfo.processInfo.environment
        let iterations = max(1, Int(env["SWIFTSOUP_BENCHMARK_ITERATIONS"] ?? "30") ?? 30)
        let warmup = max(0, Int(env["SWIFTSOUP_BENCHMARK_WARMUP"] ?? "2") ?? 2)
        let paragraphs = max(1, Int(env["SWIFTSOUP_BENCHMARK_READER_PARAGRAPHS"] ?? "160") ?? 160)
        let mode = env["SWIFTSOUP_BENCHMARK_READER_MODE"] ?? "structured"
        let xml = env["SWIFTSOUP_BENCHMARK_READER_XML"] == "1"
        guard ["structured", "cache", "raw"].contains(mode) else {
            XCTFail("Unknown Reader mode: \(mode)"); return
        }
        let fixture = fixture(paragraphs: paragraphs)
        let input = mode == "raw" ? fixture.document.replacingOccurrences(of: fixture.body, with: "") : fixture.document
        var totals = [String: UInt64]()
        var elapsed: UInt64 = 0
        var lastOutput = [UInt8]()
        var count = 0
        for iteration in 0..<(warmup + iterations) {
            let measured = iteration >= warmup
            let begin = DispatchTime.now().uptimeNanoseconds
            try withPool {
                func measure<T>(_ name: String, _ body: () throws -> T) rethrows -> T {
                    let start = DispatchTime.now().uptimeNanoseconds
                    let value = try body()
                    if measured { totals[name, default: 0] += DispatchTime.now().uptimeNanoseconds - start }
                    return value
                }
                let doc = try measure("parse") { try parse(input, xml: xml) }
                let body = try XCTUnwrap(doc.body())
                if mode == "cache" {
                    try measure("clone-restore") { try cloneAndRestore(body) }
                }
                if mode == "raw" {
                    try measure("raw-insert") { try body.appendChild(DataNode(Array(fixture.body.utf8), Array(baseURI.utf8))) }
                    count = 0
                } else {
                    count = try measure("finalize") { try finalize(doc) }
                }
                lastOutput = try measure("serialize") { try serialize(doc) }
            }
            if measured { elapsed += DispatchTime.now().uptimeNanoseconds - begin }
        }
        XCTAssertEqual(count, mode == "raw" ? 0 : paragraphs * 3)
        XCTAssertFalse(lastOutput.isEmpty)
        var digest: UInt64 = 14695981039346656037
        for byte in lastOutput { digest = (digest ^ UInt64(byte)) &* 1099511628211 }
        print("Reader workload: mode=\(mode) xml=\(xml) paragraphs=\(paragraphs) input=\(fixture.document.utf8.count) output=\(lastOutput.count) digest=\(String(digest, radix: 16))")
        for stage in totals.keys.sorted() {
            print("Reader stage \(stage): \(String(format: "%.2f", Double(totals[stage]!) / 1_000_000)) ms")
        }
        print("Benchmark elapsed: \(String(format: "%.2f", Double(elapsed) / 1_000_000)) ms over \(iterations) iterations")
        if let path = env["SWIFTSOUP_BENCHMARK_READER_OUTPUT"] {
            try Data(lastOutput).write(to: URL(fileURLWithPath: path))
        }
    }
}
