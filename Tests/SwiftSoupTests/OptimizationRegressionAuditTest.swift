import XCTest
@testable import SwiftSoup

final class OptimizationRegressionAuditTest: XCTestCase {
    func testCachedSelectionTracksSiblingTypeChanges() throws {
        let doc = try SwiftSoup.parse("<main><aside></aside><section>text</section></main>")
        let aside = try XCTUnwrap(doc.select("aside").first())
        let section = try XCTUnwrap(doc.select("section").first())
        for _ in 0..<3 { XCTAssertEqual(try section.select("section:nth-of-type(1)").size(), 1) }
        try aside.tagName("section")
        XCTAssertEqual(try section.select("section:nth-of-type(1)").size(), 0)
        XCTAssertEqual(try section.select("section:nth-of-type(2)").size(), 1)
    }

    func testCloneAttributeCompactionDoesNotMutateOriginal() throws {
        let doc = try SwiftSoup.parse("<div class='before'>text</div>")
        let original = try XCTUnwrap(doc.select("div").first())
        let clone = original.copy() as! Element
        clone.getAttributes()?.compactAndMutate { _ in AttributeMutation(keep: true, newValue: Array("after".utf8)) }
        XCTAssertEqual(try original.attr("class"), "before")
        XCTAssertEqual(try clone.attr("class"), "after")
    }

    func testCloningWhitespaceKeyDoesNotRevalidateNormalizedEmptyKey() throws {
        let attribute = try Attribute(key: " ", value: "value")
        XCTAssertEqual(attribute.getKey(), "")
        let clone = attribute.clone()
        XCTAssertEqual(clone.getKey(), "")
        XCTAssertEqual(clone.getValue(), "value")
        XCTAssertFalse(clone === attribute)
    }

    func testBooleanClonesPreserveSerializationBehavior() throws {
        let boolean = try BooleanAttribute(key: Array("custom-flag".utf8))
        let attrs = Attributes()
        attrs.put(attribute: boolean)
        let copied = attrs.clone()
        XCTAssertTrue(try XCTUnwrap(copied.asList().first) is BooleanAttribute)
        XCTAssertEqual(try attrs.html(), try copied.html())
    }

    func testSharedAttributeNotifiesBothOwnersAndRemovedViewsAreHarmless() throws {
        let first = try SwiftSoup.parse("<a href='/before'></a>")
        let second = try SwiftSoup.parse("<a title='other'></a>")
        let a = try XCTUnwrap(first.select("a").first())
        let b = try XCTUnwrap(second.select("a").first())
        let attribute = try XCTUnwrap(a.getAttributes()?.makeIterator().next())
        b.getAttributes()?.put(attribute: attribute)
        for doc in [first, second] { XCTAssertEqual(try doc.select("[href='/before']").size(), 1) }
        attribute.setValue(value: Array("/after".utf8))
        for doc in [first, second] {
            XCTAssertEqual(try doc.select("[href='/before']").size(), 0)
            XCTAssertEqual(try doc.select("[href='/after']").size(), 1)
        }
        try b.removeAttr("href")
        attribute.setValue(value: Array("/latest".utf8))
        XCTAssertEqual(try first.select("[href='/latest']").size(), 1)
        XCTAssertEqual(try second.select("[href]").size(), 0)
    }

    func testAttributeObserversDoNotRetainDocument() throws {
        weak var released: Document?
        var retained: Attribute?
        do {
            let doc = try SwiftSoup.parse("<p class='before'>x</p>")
            released = doc
            retained = try doc.select("p").first()?.getAttributes()?.asList().first
        }
        XCTAssertNil(released)
        retained?.setValue(value: Array("after".utf8))
        XCTAssertEqual(retained?.getValue(), "after")
    }

    func testCloneSupportsAttributeSubclassState() throws {
        final class CustomAttribute: Attribute {
            var extra = "custom"
            override func clone() -> Attribute {
                let copy = CustomAttribute(copying: self)
                copy.extra = extra
                return copy
            }
        }
        let attribute = try CustomAttribute(key: "data-custom", value: "original")
        attribute.extra = "preserved"
        let attributes = Attributes()
        attributes.put(attribute: attribute)
        let clone = try XCTUnwrap(attributes.clone().asList().first as? CustomAttribute)
        XCTAssertEqual(clone.extra, "preserved")
        clone.setValue(value: Array("changed".utf8))
        XCTAssertEqual(attribute.getValue(), "original")
    }

    func testAttributeRetainedFromCompactionRemainsObservable() throws {
        let doc = try SwiftSoup.parse("<p class='before'>x</p>")
        let p = try XCTUnwrap(doc.select("p").first())
        var retained: Attribute?
        p.getAttributes()?.compactAndMutate { attribute in
            retained = attribute
            return AttributeMutation(keep: true)
        }
        XCTAssertEqual(try doc.select(".before").size(), 1)
        retained?.setValue(value: Array("after".utf8))
        XCTAssertEqual(try doc.select(".before").size(), 0)
        XCTAssertEqual(try doc.select(".after").size(), 1)
    }

    func testCopyDoesNotEraseUncustomizedAttributeSubclass() throws {
        final class CustomAttribute: Attribute {}
        let attribute = try CustomAttribute(key: "data-custom", value: "value")
        let attrs = Attributes()
        attrs.put(attribute: attribute)
        XCTAssertTrue(attrs.clone().asList().first is CustomAttribute)
    }

    func testIndexedAndCachedQueriesMatchDirectTraversalAfterMutations() throws {
        let doc = try SwiftSoup.parse("<main><section id='left'></section><section id='right'></section></main>")
        let left = try XCTUnwrap(doc.select("#left").first())
        let right = try XCTUnwrap(doc.select("#right").first())
        var nodes: [Element] = []
        for i in 0..<8 {
            let node = try left.appendElement("a")
            try node.attr("id", "item-\(i)").attr("class", "before").attr("href", "/before").attr("data-k", "x")
            try node.text("before")
            nodes.append(node)
        }
        let queries = ["*", "a", "b", ".before", ".after", "#item-1", "[href]", "[href='/before']",
            "a.before[href='/before']", "[data-k='x']", "[data-k!='x']", "[data-k^='x']", "[data-k$='y']",
            "[data-k*='x']", "a:contains(before)", "a:containsOwn(after)", "section:has(.after)",
            "a + a", "a ~ b", "a:nth-child(2)", "a:nth-of-type(2)", "a:first-child", "a:last-child", "a:only-child",
            "section > a", "a:not(.before)", "a, b.after"]
        let evaluators = try queries.map { try QueryParser.parse($0) }
        for step in 0..<80 {
            for root in [doc, left, right] {
                var all: [Element] = []
                var stack: [Node] = [root]
                while let node = stack.popLast() {
                    if let element = node as? Element { all.append(element) }
                    stack.append(contentsOf: node.getChildNodes().reversed())
                }
                for (query, evaluator) in zip(queries, evaluators) {
                    let expected = try all.filter { try evaluator.matches(root, $0) }.map(ObjectIdentifier.init)
                    let actual = try root.select(query).array().map(ObjectIdentifier.init)
                    XCTAssertEqual(actual, expected, "step \(step), query \(query), root \(root.tagName())")
                }
            }
            let node = nodes[(step * 7 + step / 8) % nodes.count]
            switch step % 8 {
            case 0: try node.attr("class", step % 16 == 0 ? "after" : "before")
            case 1: try node.attr("href", "/after")
            case 2: try node.attr("data-k", "xy")
            case 3: try node.tagName(node.tagName() == "a" ? "b" : "a")
            case 4: try node.text(step % 16 == 4 ? "after" : "before")
            case 5: try (node.parent() === left ? right : left).appendChild(node)
            case 6: try node.removeAttr("href")
            default:
                node.getAttributes()?.asList().first { $0.getKey() == "class" }?.setValue(value: Array("after".utf8))
            }
        }
    }

    func testLiveAttributeValueMutationInvalidatesSelectorsAndSerialization() throws {
        let doc = try SwiftSoup.parse("<div class='before'>text</div>")
        doc.outputSettings().prettyPrint(pretty: false)
        let div = try XCTUnwrap(doc.select("div").first())
        let attribute = try XCTUnwrap(div.getAttributes()?.asList().first { $0.getKey() == "class" })
        for _ in 0..<3 { XCTAssertEqual(try doc.select(".before").size(), 1) }
        _ = try doc.outerHtml()
        attribute.setValue(value: Array("after".utf8))
        XCTAssertEqual(try div.attr("class"), "after")
        XCTAssertEqual(try doc.select(".before").size(), 0)
        XCTAssertEqual(try doc.select(".after").size(), 1)
        XCTAssertTrue(try doc.outerHtml().contains("class=\"after\""))
    }
}
