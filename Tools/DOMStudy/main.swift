import Foundation
import SwiftSoup

// Standalone public-API replay. No testing-enabled library or app dependencies.
let args = CommandLine.arguments
func argument(_ name: String, _ fallback: String) -> String {
    guard let index = args.firstIndex(of: name), index + 1 < args.count else { return fallback }
    return args[index + 1]
}
let count = Int(argument("--count", "96"))!
let iterations = Int(argument("--iterations", "20"))!
let kind = argument("--workload", "parse")
precondition(count > 0 && count <= 4096 && iterations > 0 && iterations <= 100000)
let observe = args.contains("--observe")
let paragraphs = (0..<count).map { i in
    "<p id='p\(i)' class='entry'><b>日本語の文章</b>を<em>読む</em>。<a href='/\(i)'>リンク</a>と<ruby>漢字<rt>かんじ</rt></ruby>です。</p>\n"
}.joined()
let plain = (0..<count).map { "<p id='p\($0)'>日本語の文章を読みます。今日もよい天気です。</p>\n" }.joined()
let annotated = (0..<count).map { i in
    "<p id='p\(i)'><m-s><m-m data-id='\(i)'><m-t>日本語</m-t></m-m>の<m-m><m-t>文章</m-t></m-m>を読む。</m-s><ruby>漢字<rt>かんじ</rt></ruby></p>\n"
}.joined()
let article = "<!doctype html><html><head><title>日本語</title><style>.entry{color:inherit}</style></head><body><article id='reader-content'>\(paragraphs)</article><script>let a = 1;</script></body></html>"
let source = Array((kind == "parse-plain" ? "<html><body>\(plain)</body></html>" : kind == "parse-injected" ? "<html><body>\(annotated)</body></html>" : article).utf8)
func parse() throws -> Document {
    let document = try SwiftSoup.parse(source, "", Parser.htmlParser())
    document.outputSettings().prettyPrint(pretty: false)
    return document
}
let prepared = ["copy", "publish"].contains(kind) ? try parse() : nil
let stagingDocument = kind == "publish" ? try SwiftSoup.parseBodyFragment(annotated) : nil
if let prepared {
    for element in try prepared.select("*") { _ = element.getAttributes()?.asList() }
}
@inline(never)
func operation() throws -> String {
    if kind == "copy" {
        let copied = prepared!.copy() as! Document
        return observe ? String(decoding: try copied.outerHtmlUTF8WithoutSourceReuse(), as: UTF8.self) : String(copied.childNodeSize())
    }
    let document = kind == "publish" ? prepared! : try parse()
    if kind == "publish" {
        let root = document.body()!
        let children = stagingDocument!.body()!.childNodesCopy()
        let rollback = root.childNodesCopy()
        root.empty()
        try root.insertChildren(0, children)
        withExtendedLifetime(rollback) {}
        return String(decoding: try document.outerHtmlUTF8ReusingSourceOutsideBody(), as: UTF8.self)
    }
    if kind.hasPrefix("parse") {
        return observe ? String(decoding: try document.outerHtmlUTF8WithoutSourceReuse(), as: UTF8.self) : String(document.body()!.childNodeSize())
    }
    if kind == "select" {
        var output = ""
        for query in ["b", "p", "#reader-content", "a[href]", "script, style", "ruby rt", "article > p"] {
            let matches = try document.select(query)
            output += observe ? try matches.outerHtml() : String(matches.size())
        }
        return output
    }
    if kind == "injection" {
        let root = document.body()!
        let input = try root.html()
        let staging = root.copy() as! Element
        try staging.html(annotated)
        let children = staging.getChildNodes().map { $0.copy() as! Node }
        let rollback = root.getChildNodes().map { $0.copy() as! Node }
        root.empty()
        try root.insertChildren(0, children)
        withExtendedLifetime(rollback) {}
        let result = String(decoding: try document.outerHtmlUTF8ReusingSourceOutsideBody(), as: UTF8.self)
        return observe ? input + "\n---\n" + result : result
    }
    // Cleanup path exercises mutations, cold indexes, text, and serialization.
    try document.select("script, style").remove()
    for link in try document.select("a[href]") { try link.attr("data-visited", "true") }
    for ruby in try document.select("ruby") { try ruby.getElementsByTag("rt").remove() }
    let text = try document.text()
    let result = String(decoding: try document.outerHtmlUTF8ReusingSourceOutsideBody(), as: UTF8.self)
    return text + result
}
if observe {
    print(String(decoding: try JSONSerialization.data(withJSONObject: ["output": try operation()], options: [.sortedKeys]), as: UTF8.self))
} else {
    var checksum: UInt64 = 0
    for _ in 0..<3 { checksum &+= UInt64(try operation().utf8.count) }
    let start = DispatchTime.now().uptimeNanoseconds
    for _ in 0..<iterations { checksum &+= UInt64(try operation().utf8.count) }
    let elapsed = DispatchTime.now().uptimeNanoseconds - start
    let result: [String: Any] = ["workload": kind, "count": count, "iterations": iterations, "warmups": 3, "elapsed_ms": Double(elapsed) / 1e6, "checksum": String(checksum)]
    print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
}
