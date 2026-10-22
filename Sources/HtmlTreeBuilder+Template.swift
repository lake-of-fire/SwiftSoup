import Foundation

extension HtmlTreeBuilder {
    func hasTemplateMode() -> Bool { !templateModes.isEmpty }

    /// Templates have their own insertion mode and active-formatting marker.
    /// The public tree keeps their contents as children for SwiftSoup API
    /// compatibility; stack boundaries still follow HTML tree construction.
    func beginTemplate(_ start: Token.StartTag) throws {
        // HTML ignores the self-closing flag on non-void template elements.
        start._selfClosing = false
        try insert(start)
        insertMarkerToFormattingElements()
        framesetOk(false)
        templateModes.append(.InTemplate)
        transition(.InTemplate)
    }

    @discardableResult
    func endTemplate() throws -> Bool {
        guard stack.contains(where: { $0.namespace() == .html && $0.tagNameNormal() == "template" }) else {
            return false
        }
        popStackToClose("template".utf8Array)
        clearFormattingElementsToLastMarker()
        if !templateModes.isEmpty { templateModes.removeLast() }
        resetInsertionMode()
        return true
    }

    func processTemplate(_ token: Token) throws -> Bool {
        switch token.type {
        case .Char, .Comment, .Doctype:
            return try process(token, .InBody)
        case .StartTag:
            let name = String(decoding: token.asStartTag().normalName() ?? [], as: UTF8.self)
            if ["base", "basefont", "bgsound", "link", "meta", "noframes", "script", "style", "template", "title"].contains(name) {
                return try process(token, .InHead)
            }
            let mode: HtmlTreeBuilderState
            switch name {
            case "caption", "colgroup", "tbody", "tfoot", "thead": mode = .InTable
            case "col": mode = .InColumnGroup
            case "tr": mode = .InTableBody
            case "td", "th": mode = .InRow
            default: mode = .InBody
            }
            if !templateModes.isEmpty { templateModes[templateModes.count - 1] = mode }
            transition(mode)
            return try process(token)
        case .EndTag:
            return token.asEndTag().normalNameEquals("template".utf8Array) ? try endTemplate() : false
        case .EOF:
            while try endTemplate() {}
            return true
        }
    }
}
