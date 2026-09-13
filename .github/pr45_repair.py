from pathlib import Path

node_path = Path('Sources/Node.swift')
s = node_path.read_text()

old_owner = '''    @inline(__always)
open func ownerDocument() -> Document? {
    var node: Node? = self
    while let current = node {
        if let document = current as? Document {
  return document
        }
        node = current.parentNode
    }
    return nil
}

/// A token that changes when text content in this node's tree mutates.
'''
new_owner = '''    @inline(__always)
    open func ownerDocument() -> Document? {
        if let document = self as? Document {
            return document
        }
        return parentNode?.ownerDocument()
    }

    /// Internal stack-safe lookup for source tracking and deep serialization.
    /// This deliberately follows stored parent links rather than changing the
    /// open `ownerDocument()` dispatch contract for subclasses.
    @inline(__always)
    @usableFromInline
    internal func ownerDocumentDirect() -> Document? {
        var node: Node? = self
        while let current = node {
            if let document = current as? Document {
                return document
            }
            node = current.parentNode
        }
        return nil
    }

    /// A token that changes when text content in this node's tree mutates.
'''
if s.count(old_owner) != 1:
    raise SystemExit(f'owner block count={s.count(old_owner)}')
s = s.replace(old_owner, new_owner)

dirty_old = 'current.ownerDocument()?.registerDirtySourceRoot(current)'
if s.count(dirty_old) != 2:
    raise SystemExit(f'dirty owner call count={s.count(dirty_old)}')
s = s.replace(dirty_old, 'current.ownerDocumentDirect()?.registerDirtySourceRoot(current)')

raw_old = '              let doc = ownerDocument(),\n'
if s.count(raw_old) != 1:
    raise SystemExit(f'raw owner call count={s.count(raw_old)}')
s = s.replace(raw_old, '              let doc = ownerDocumentDirect(),\n')

old_outer = '''    @inline(__always)
    internal func outerHtmlFast(_ accum: StringBuilder, _ depth: Int, _ out: OutputSettings, allowRawSource: Bool) throws {
        // Walk head/children/tail without consuming a stack frame per element.
        // A reused subtree is already complete and can advance straight to its
        // sibling, while the ancestors still receive their closing tags.
        var node: Node = self
        var nodeDepth = depth
        while true {
            if let raw = node.rawSourceSlice(out, allowRawSource: allowRawSource) {
                accum.append(raw)
            } else {
                try node.outerHtmlHead(accum, nodeDepth, out)
                if let child = node.childNodes.first {
                    node = child
                    nodeDepth += 1
                    continue
                }
                try node.outerHtmlTail(accum, nodeDepth, out)
            }
            while node !== self {
                if let sibling = node.nextSibling() {
                    node = sibling
                    break
                }
                guard let parent = node.parentNode else { return }
                node = parent
                nodeDepth -= 1
                try node.outerHtmlTail(accum, nodeDepth, out)
            }
            if node === self { return }
        }
    }
'''
new_outer = '''    @inline(__always)
    internal func outerHtmlFast(_ accum: StringBuilder, _ depth: Int, _ out: OutputSettings, allowRawSource: Bool) throws {
        // Preserve the historical authority of the stored childNodes arrays
        // while avoiding one Swift call frame per nesting level. Public sibling
        // accessors are overridable and therefore must not drive serialization.
        var stack: [(node: Node, depth: Int, emitTail: Bool)] = [(self, depth, false)]
        while let frame = stack.popLast() {
            if frame.emitTail {
                try frame.node.outerHtmlTail(accum, frame.depth, out)
                continue
            }
            if let raw = frame.node.rawSourceSlice(out, allowRawSource: allowRawSource) {
                accum.append(raw)
                continue
            }
            try frame.node.outerHtmlHead(accum, frame.depth, out)
            stack.append((frame.node, frame.depth, true))
            if !frame.node.childNodes.isEmpty {
                for child in frame.node.childNodes.reversed() {
                    stack.append((child, frame.depth + 1, false))
                }
            }
        }
    }
'''
if s.count(old_outer) != 1:
    raise SystemExit(f'outer block count={s.count(old_outer)}')
s = s.replace(old_outer, new_outer)
node_path.write_text(s)

test_path = Path('Tests/SwiftSoupTests/ReaderDocumentOutputTests.swift')
t = test_path.read_text()
t = t.replace('                XCTAssertTrue(text.ownerDocument() === document)\n', '')

header = '@testable import SwiftSoup\n\n'
helpers = '''@testable import SwiftSoup

private final class OwnerDocumentOverrideElement: Element {
    private let forcedOwner: Document

    init(owner: Document) throws {
        self.forcedOwner = owner
        super.init(try Tag.valueOf("div"), [UInt8]())
    }

    override func ownerDocument() -> Document? {
        return forcedOwner
    }
}

private final class NilNextSiblingElement: Element {
    init() throws {
        super.init(try Tag.valueOf("span"), [UInt8]())
    }

    override func nextSibling() -> Node? {
        return nil
    }
}

'''
if t.count(header) != 1:
    raise SystemExit('test import anchor mismatch')
t = t.replace(header, helpers)

marker = '    func testDeepSerializationPreservesCleanAndMutatedTreesOnSmallStack() {\n'
additions = '''    func testOwnerDocumentPreservesAncestorOverrideDispatch() throws {
        let forcedOwner = try SwiftSoup.parse("<p>forced</p>")
        let parent = try OwnerDocumentOverrideElement(owner: forcedOwner)
        let child = TextNode("child", nil)
        child.parentNode = parent
        XCTAssertTrue(child.ownerDocument() === forcedOwner)
    }

    func testIterativeSerializerUsesStoredChildOrder() throws {
        let document = try SwiftSoup.parse("<html><head></head><body></body></html>")
        document.outputSettings().prettyPrint(pretty: false)
        let body = try XCTUnwrap(document.body())

        let first = try NilNextSiblingElement()
        try first.addChildren(TextNode("first", nil))
        let second = Element(try Tag.valueOf("span"), [UInt8]())
        try second.addChildren(TextNode("second", nil))
        try body.addChildren(first, second)

        let html = String(decoding: try document.outerHtmlUTF8WithoutSourceReuse(), as: UTF8.self)
        let reparsed = try SwiftSoup.parse(html)
        XCTAssertEqual(try reparsed.select("span").array().map { try $0.text() }, ["first", "second"])
    }

''' + marker
if t.count(marker) != 1:
    raise SystemExit('deep test marker mismatch')
t = t.replace(marker, additions)
test_path.write_text(t)
