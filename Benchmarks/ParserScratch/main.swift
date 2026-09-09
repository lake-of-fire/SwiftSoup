// Portable release replay. Synthetic fixtures; excludes dictionaries, morphology and UI.
import Foundation
import SwiftSoup

let arguments = Array(CommandLine.arguments.dropFirst())
func option(_ name: String, _ fallback: String) -> String {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return fallback }
    return arguments[index + 1]
}
func fail(_ text: String) -> Never {
    FileHandle.standardError.write(Data((text + "\n").utf8))
    exit(1)
}
let workload = option("--workload", "highlight")
guard let iterations = Int(option("--iterations", "100")), (1...1_000_000).contains(iterations),
      let warmups = Int(option("--warmup", "3")), (0...100).contains(warmups) else { fail("Invalid iteration count") }
let baseURI = "https://example.invalid/"
let paragraphs = (0..<96).map { index in
    "<p id='p\(index)' class='entry'>日本語の文章です。<b>重要</b>な言葉と<a href='/\(index)'>説明</a>。</p>"
}.joined(separator: "\n")
let article = "<!doctype html><html><head><title>Reader</title></head><body>\(paragraphs)</body></html>"
let segments = (0..<24).map { index in
    "<m-m data-id='\(index)'><m-t><ruby>漢字<rp>(</rp><rt>かんじ</rt><rp>)</rp></ruby></m-t></m-m>を読む。"
}.joined()
let sentence = "<m-s>\(segments)</m-s>"
let snippets = ["<p>日本語</p>", "<b>重要</b>な言葉", "<ruby>漢字<rt>かんじ</rt></ruby>",
                "<span title='a &amp; b'>one &amp; two</span>", "<m-m><m-t>文章</m-t></m-m>",
                "<!--note--><p>😀 &lt; &gt;</p>"]
let script = String(repeating: "if(a<b){s='<x';}<!--c-->\n", count: 512)
let growing = "<!doctype html><html><body><!--" + String(repeating: "comment-日本語 ", count: 512)
    + "--><script>\(script)</script><p title='" + String(repeating: "日&amp;本&#x8a9e;", count: 512) + "'>after</p></body></html>"

@discardableResult
func configured(_ document: Document) -> Document {
    document.outputSettings().prettyPrint(pretty: false).charset(.utf8)
    return document
}
func stripRuby(_ html: String) throws -> String {
    guard html.contains("<") else { return html }
    let document = configured(try SwiftSoup.parse(html))
    for ruby in try (document.body() ?? document).getElementsByTag("ruby") {
        for tag in ["rp", "rt", "rtc"] { try ruby.getElementsByTag(tag).remove() }
        let surface = try ruby.text(trimAndNormaliseWhitespace: false)
        try ruby.before(surface)
        try ruby.remove()
    }
    return try document.text()
}
@inline(never)
func exercise() throws -> [String] {
    switch workload {
    case "highlight":
        let plain = try stripRuby(sentence)
        let document = configured(try SwiftSoup.parseBodyFragment(sentence))
        guard let body = document.body() else { fail("Missing body") }
        var text: [String] = []
        for (index, segment) in try body.select("m-m").array().enumerated() {
            text.append(try stripRuby(segment.html()))
            if index % 4 == 0 { try segment.wrap("<b></b>") }
        }
        for tag in ["m-m", "m-t", "m-s", "m-c"] { try body.select(tag).unwrap() }
        return try [plain, text.joined(separator: "|"), body.html()]
    case "snippets":
        return try snippets.map(stripRuby)
    case "document", "growth":
        let document = configured(try SwiftSoup.parse(workload == "document" ? article : growing, baseURI))
        return try [document.text(), String(decoding: document.outerHtmlUTF8WithoutSourceReuse(), as: UTF8.self)]
    default:
        fail("Expected highlight, snippets, document or growth")
    }
}
let expected = try exercise()
let expectedBytes = expected.reduce(0) { $0 + $1.utf8.count }
if arguments.contains("--observations") {
    let payload: [String: Any] = ["workload": workload, "output": expected]
    let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    try data.write(to: URL(fileURLWithPath: option("--output", "observations.json")))
    exit(0)
}
var checksum: UInt64 = 0
for _ in 0..<warmups { checksum &+= UInt64(try exercise().reduce(0) { $0 + $1.utf8.count }) }
let start = DispatchTime.now().uptimeNanoseconds
for _ in 0..<iterations { checksum &+= UInt64(try exercise().reduce(0) { $0 + $1.utf8.count }) }
let elapsed = DispatchTime.now().uptimeNanoseconds - start
guard checksum == UInt64(expectedBytes) * UInt64(iterations + warmups), try exercise() == expected else {
    fail("Inconsistent output")
}
let result: [String: Any] = ["workload": workload, "iterations": iterations, "warmups": warmups,
                           "elapsed_ms": Double(elapsed) / 1_000_000, "checksum": String(checksum),
                           "output_bytes": expectedBytes]
print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
