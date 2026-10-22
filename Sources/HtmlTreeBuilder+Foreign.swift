import Foundation

extension HtmlTreeBuilder {
    func isHTMLIntegrationPoint(_ element: Element) -> Bool {
        let name = element.tagNameNormal()
        if element.namespace() == .svg { return ["foreignobject", "desc", "title"].contains(name) }
        if element.namespace() == .mathml, name == "annotation-xml" {
            let encoding = (try? element.attr("encoding"))?.lowercased()
            return encoding == "text/html" || encoding == "application/xhtml+xml"
        }
        return false
    }

    func isMathTextIntegrationPoint(_ element: Element) -> Bool {
        element.namespace() == .mathml && ["mi", "mo", "mn", "ms", "mtext"].contains(element.tagNameNormal())
    }

    func isForeignScopeBoundary(_ element: Element) -> Bool {
        isMathTextIntegrationPoint(element)
            || (element.namespace() == .mathml && element.tagNameNormal() == "annotation-xml")
            || (element.namespace() == .svg && ["foreignobject", "desc", "title"].contains(element.tagNameNormal()))
    }

    func shouldProcessForeign(_ token: Token) -> Bool {
        guard let current = adjustedCurrentElement(), current.namespace() != .html, !token.isEOF() else { return false }
        if isMathTextIntegrationPoint(current) {
            if token.isCharacter() { return false }
            if token.isStartTag(), !["mglyph", "malignmark"].contains(String(decoding: token.asStartTag().normalName() ?? [], as: UTF8.self)) { return false }
        }
        if current.namespace() == .mathml, current.tagNameNormal() == "annotation-xml",
           token.isStartTag(), token.asStartTag().normalNameEquals(UTF8Arrays.svg) { return false }
        if isHTMLIntegrationPoint(current), token.isStartTag() || token.isCharacter() { return false }
        return true
    }

    @discardableResult
    func insertForeign(_ start: Token.StartTag, namespace: Element.Namespace) throws -> Element {
        // Do not use insert(StartTag): its HTML self-closing shortcut synthesizes
        // an end token, and HTML void-element traits do not apply here.
        start.ensureAttributes()
        var name = String(decoding: start.normalName() ?? [], as: UTF8.self)
        if namespace == .svg { name = Self.svgNames[name] ?? name }
        let tag = try Tag.valueOf(name, ParseSettings.preserveCase)
        let element = Element(tag, baseUri, start._attributes ?? Attributes())
        element.elementNamespace = namespace
        if namespace == .svg, let attributes = element.getAttributes() {
            for attribute in attributes.asList() {
                let key = attribute.getKey()
                if let corrected = Self.svgAttributes[key] {
                    let value = attribute.getValue()
                    try element.removeAttr(key)
                    try element.attr(corrected, value)
                }
            }
        } else if namespace == .mathml, element.hasAttr("definitionurl") {
            let value = try element.attr("definitionurl")
            try element.removeAttr("definitionurl")
            try element.attr("definitionURL", value)
        }
        if let range = start.sourceRange { element.setSourceRange(range, complete: start.isSelfClosing()) }
        try insertNode(element)
        if start.isSelfClosing() { tokeniser.acknowledgeSelfClosingFlag() }
        else { push(element) }
        return element
    }

    func processForeign(_ token: Token) throws -> Bool {
        guard let current = adjustedCurrentElement() else { return try process(token, state()) }
        switch token.type {
        case .Char:
            // Null foreign characters become replacement characters.
            if let bytes = token.asCharacter().getData(), bytes.contains(0) {
                try insert(Token.Char().data(Array(String(decoding: bytes, as: UTF8.self).replacingOccurrences(of: "\0", with: "\u{FFFD}").utf8)))
            } else { try insert(token.asCharacter()) }
            if !HtmlTreeBuilderState.isWhitespace(token) { framesetOk(false) }
        case .Comment:
            try insert(token.asComment())
        case .Doctype:
            return false
        case .StartTag:
            let start = token.asStartTag()
            start.ensureAttributes()
            let name = String(decoding: start.normalName() ?? [], as: UTF8.self)
            let fontBreakout = name == "font" && ["color", "face", "size"].contains(where: { start._attributes?.hasKeyIgnoreCase(key: $0.utf8Array) == true })
            if Self.foreignBreakouts.contains(name) || fontBreakout {
                while let node = currentElement(), node.namespace() != .html,
                      !isMathTextIntegrationPoint(node), !isHTMLIntegrationPoint(node) { pop() }
                return try process(token, state())
            }
            try insertForeign(start, namespace: current.namespace())
        case .EndTag:
            let name = String(decoding: token.asEndTag().normalName() ?? [], as: UTF8.self)
            if name == "br" || name == "p" {
                while let node = currentElement(), node.namespace() != .html,
                      !isMathTextIntegrationPoint(node), !isHTMLIntegrationPoint(node) { pop() }
                return try process(token, state())
            }
            for node in stack.reversed() {
                if node.namespace() == .html { return try process(token, state()) }
                if node.tagNameNormal() == name {
                    while let top = currentElement() {
                        pop()
                        if top === node { break }
                    }
                    return true
                }
            }
        case .EOF: break
        }
        return true
    }

    private static let foreignBreakouts: Set<String> = ["b", "big", "blockquote", "body", "br", "center", "code", "dd", "div", "dl", "dt", "em", "embed", "h1", "h2", "h3", "h4", "h5", "h6", "head", "hr", "i", "img", "li", "listing", "menu", "meta", "nobr", "ol", "p", "pre", "ruby", "s", "small", "span", "strong", "strike", "sub", "sup", "table", "tt", "u", "ul", "var"]

    private static let svgNames: [String: String] = Dictionary(uniqueKeysWithValues: ["altGlyph", "altGlyphDef", "altGlyphItem", "animateColor", "animateMotion", "animateTransform", "clipPath", "feBlend", "feColorMatrix", "feComponentTransfer", "feComposite", "feConvolveMatrix", "feDiffuseLighting", "feDisplacementMap", "feDistantLight", "feDropShadow", "feFlood", "feFuncA", "feFuncB", "feFuncG", "feFuncR", "feGaussianBlur", "feImage", "feMerge", "feMergeNode", "feMorphology", "feOffset", "fePointLight", "feSpecularLighting", "feSpotLight", "feTile", "feTurbulence", "foreignObject", "glyphRef", "linearGradient", "radialGradient", "textPath"].map { ($0.lowercased(), $0) })

    private static let svgAttributes: [String: String] = Dictionary(uniqueKeysWithValues: ["attributeName", "attributeType", "baseFrequency", "baseProfile", "calcMode", "clipPathUnits", "diffuseConstant", "edgeMode", "filterUnits", "glyphRef", "gradientTransform", "gradientUnits", "kernelMatrix", "kernelUnitLength", "keyPoints", "keySplines", "keyTimes", "lengthAdjust", "limitingConeAngle", "markerHeight", "markerUnits", "markerWidth", "maskContentUnits", "maskUnits", "numOctaves", "pathLength", "patternContentUnits", "patternTransform", "patternUnits", "pointsAtX", "pointsAtY", "pointsAtZ", "preserveAlpha", "preserveAspectRatio", "primitiveUnits", "refX", "refY", "repeatCount", "repeatDur", "requiredExtensions", "requiredFeatures", "specularConstant", "specularExponent", "spreadMethod", "startOffset", "stdDeviation", "stitchTiles", "surfaceScale", "systemLanguage", "tableValues", "targetX", "targetY", "textLength", "viewBox", "viewTarget", "xChannelSelector", "yChannelSelector", "zoomAndPan"].map { ($0.lowercased(), $0) })
}
