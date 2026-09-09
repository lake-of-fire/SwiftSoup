import Foundation
import SwiftSoup

struct Workload {
    let elements: Elements
    let operation: String
    let trim: Bool
    let html: String?
    func run() throws -> String {
        if let html {
            let doc = try SwiftSoup.parse(html)
            if operation == "control" { return try doc.body()!.text() }
            return try doc.select("p").text()
        }
        switch operation {
        case "text": return try elements.text(trimAndNormaliseWhitespace: trim)
        case "html": return try elements.html()
        case "outer": return try elements.outerHtml()
        default: preconditionFailure("Unknown operation")
        }
    }
}

func fixture(_ name: String) throws -> Workload {
    let short = "日本語を読もう👩🏽‍💻 e\u{301}"
    func items(_ count: Int, _ content: (Int) -> String, operation: String = "text", trim: Bool = true) throws -> Workload {
        let nodes = try (0..<count).map { i -> Element in
            let el = try Element(Tag.valueOf("p"), "")
            try el.appendChild(TextNode(content(i), ""))
            return el
        }
        return Workload(elements: Elements(nodes), operation: operation, trim: trim, html: nil)
    }
    switch name {
    case "empty-html": return Workload(elements: Elements(), operation: "html", trim: true, html: nil)
    case "empty-outer": return Workload(elements: Elements(), operation: "outer", trim: true, html: nil)
    case "single-short": return try items(1, { _ in short })
    case "single-html": return try items(1, { _ in short }, operation: "html")
    case "single-outer": return try items(1, { _ in short }, operation: "outer")
    case "empty": return Workload(elements: Elements(), operation: "text", trim: true, html: nil)
    case "single-long": return try items(1, { _ in String(repeating: short, count: 256) })
    case "text-8": return try items(8, { _ in short })
    case "text-256": return try items(256, { _ in short })
    case "text-long": return try items(128, { _ in String(repeating: short, count: 64) })
    case "text-raw": return try items(256, { _ in " \t\n" + short + "\r\n " }, trim: false)
    case "text-blank": return try items(256, { _ in " \n\t " })
    case "text-mixed": return try items(256, { $0 % 3 == 0 ? "" : short })
    case "html-128", "outer-128":
        let html = "<main>" + (0..<128).map { "<p id='n\($0)'>日本語<b>e&#x301;</b><!--gap-->👩🏽‍💻</p>" }.joined() + "</main>"
        let doc = try SwiftSoup.parse(html)
        return Workload(elements: try doc.select("p"), operation: name == "html-128" ? "html" : "outer", trim: true, html: nil)
    case "parse-text":
        let html = "<main>" + (0..<128).map { "<p id='n\($0)'>日本語<b>e&#x301;</b><!--gap-->👩🏽‍💻</p>" }.joined() + "</main>"
        return Workload(elements: Elements(), operation: "text", trim: true, html: html)
    case "parse-control":
        return Workload(elements: Elements(), operation: "control", trim: true, html: "<main>" + String(repeating: "<div class='entry'>日本語<b>文章</b></div>", count: 128) + "</main>")
    default: throw NSError(domain: "Benchmark", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown case \(name)"])
    }
}

// Preserve the baseline's separator rule; it is NOT joined(separator:).
func reference(_ elements: Elements, _ operation: String, _ trim: Bool) throws -> String {
    let out = StringBuilder()
    for el in elements.array() {
        if !out.isEmpty { out.append(operation == "text" ? " " : "\n") }
        switch operation {
        case "text": out.append(try el.text(trimAndNormaliseWhitespace: trim))
        case "html": out.append(try el.html())
        default: out.append(try el.outerHtml())
        }
    }
    return out.toString()
}

func verify() throws {
    var records = [[String: Any]]()
    for name in ["empty", "empty-html", "empty-outer", "single-short", "single-html", "single-outer", "single-long", "text-8", "text-256", "text-long", "text-raw", "text-blank", "text-mixed", "html-128", "outer-128"] {
        let work = try fixture(name), output = try work.run()
        let expected = try reference(work.elements, work.operation, work.trim)
        precondition(Array(output.utf8) == Array(expected.utf8), "Incorrect \(name)")
        records.append(["case": name, "utf8": Array(output.utf8)])
    }
    for name in ["parse-text", "parse-control"] {
        let work = try fixture(name), doc = try SwiftSoup.parse(work.html!)
        let actual = try work.run()
        let expected = name == "parse-control" ? try doc.body()!.text() : try reference(doc.select("p"), "text", true)
        precondition(Array(actual.utf8) == Array(expected.utf8))
        records.append(["case": name, "utf8": Array(actual.utf8), "html": try doc.outerHtml()])
    }
    let values: [[UInt8]] = [[], [0x61], [0xCC,0x81], [0xE3], [0x81,0x82], [0xFF], [0xED,0xA0,0x80], [0], [13,10], [32], [0xF0,0x9F], [0x87,0xAF]]
    for i in values.indices {
        for j in values.indices {
            let a = try Element(Tag.valueOf("p"), ""), b = try Element(Tag.valueOf("p"), "")
            try a.appendChild(TextNode(values[i], [])); try b.appendChild(TextNode(values[j], []))
            let elements = Elements([a, b, a])
            for trim in [false,true] {
                let output = try elements.text(trimAndNormaliseWhitespace: trim)
                let expected = try reference(elements,"text",trim)
                precondition(Array(output.utf8) == Array(expected.utf8))
                records.append(["i": i,"j": j,"trim": trim,"utf8": Array(output.utf8)])
            }
        }
    }
    let data = try JSONSerialization.data(withJSONObject: records, options: [.sortedKeys])
    FileHandle.standardOutput.write(data)
}

let args = CommandLine.arguments
if args.count == 2 && args[1] == "--verify" {
    try verify()
} else {
    guard args.count == 3, let count = Int(args[2]), count > 0 else {
        fatalError("Usage: benchmark CASE ITERATIONS | --verify")
    }
    let work = try fixture(args[1])
    let expected = try work.run().utf8.count
    for _ in 0..<3 { let n = try work.run().utf8.count; precondition(n == expected) }
    var checksum = 0
    let begin = DispatchTime.now().uptimeNanoseconds
    for _ in 0..<count { checksum &+= try work.run().utf8.count }
    let ns = DispatchTime.now().uptimeNanoseconds - begin
    precondition(checksum == expected * count)
    let data = try JSONSerialization.data(withJSONObject: ["case": args[1], "iterations": count, "ns": ns, "checksum": checksum, "expected": expected], options: [.sortedKeys])
    FileHandle.standardOutput.write(data)
    print("")
}
