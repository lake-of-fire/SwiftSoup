    @inline(__always)
    open func ownerDocument() -> Document? {
        if let document = self as? Document {
            return document
        }
        return parentNode?.ownerDocument()
    }

    /// A token that changes when text content in this node's tree mutates.

    @inline(__always)
    @usableFromInline
    internal func markSourceDirty(force: Bool = false) {
        if sourceRangeDirty {
            ownerDocument()?.registerDirtySourceRoot(self)
            return
        }
        if !force, treeBuilder?.isBulkBuilding == true {
            return
        }
        sourceRangeDirty = true
        ownerDocument()?.registerDirtySourceRoot(self)
        parentNode?.markSourceDirty(force: force, registerDirtyRoot: false)
    }

    @inline(__always)
    @usableFromInline
    internal func markSourceDirty(force: Bool = false, registerDirtyRoot: Bool) {
        if sourceRangeDirty {
            if registerDirtyRoot {
                ownerDocument()?.registerDirtySourceRoot(self)
            }
            return
        }
        if !force, treeBuilder?.isBulkBuilding == true {
            return
        }
        sourceRangeDirty = true
        if registerDirtyRoot {
            ownerDocument()?.registerDirtySourceRoot(self)
        }
        parentNode?.markSourceDirty(force: force, registerDirtyRoot: false)
    }

    @inline(__always)
    @usableFromInline
    internal func setSourceRange(_ range: SourceRange, complete: Bool) {

    @inline(__always)
    private func rawSourceSlice(_ out: OutputSettings, allowRawSource: Bool) -> ArraySlice<UInt8>? {
        guard allowRawSource,
              !out.prettyPrint(),
              !sourceRangeDirty,
              sourceRangeIsComplete,
              let range = sourceRange,
              range.isValid,
              let doc = ownerDocument(),
              let source = sourceBuffer?.bytes ?? doc.sourceBuffer?.bytes
        else {
            return nil
        }
        let syntax = out.syntax()
        if syntax == .xml && !doc.parsedAsXml {
            return nil
        }
        if syntax == .html || syntax == .xml {
            // ok
        } else {
            return nil
        }
        if range.end > source.count {
            return nil
        }
        return source[range.start..<range.end]
    }

    @inline(__always)
    @usableFromInline
    internal func sourceSliceUTF8() -> ArraySlice<UInt8>? {
        guard let range = sourceRange,
              range.isValid,
              let source = sourceBuffer?.bytes ?? ownerDocument()?.sourceBuffer?.bytes,
              range.end <= source.count
        else {
            return nil
        }
        return source[range.start..<range.end]
    }

    @inline(__always)
    internal func outerHtmlFast(_ accum: StringBuilder, _ depth: Int, _ out: OutputSettings, allowRawSource: Bool) throws {
        if let raw = rawSourceSlice(out, allowRawSource: allowRawSource) {
            accum.append(raw)
            return
        }
        try outerHtmlHead(accum, depth, out)
        if !childNodes.isEmpty {
            for child in childNodes {
                try child.outerHtmlFast(accum, depth + 1, out, allowRawSource: allowRawSource)
            }
        }
        try outerHtmlTail(accum, depth, out)
    }

    @inline(__always)
    internal func outerHtmlFastWithoutSourceReuse(
        _ accum: StringBuilder,
        _ depth: Int,
        _ out: OutputSettings
    ) throws {
        try outerHtmlHead(accum, depth, out)
        if !childNodes.isEmpty {
            for child in childNodes {
                try child.outerHtmlFastWithoutSourceReuse(accum, depth + 1, out)
            }
        }
        try outerHtmlTail(accum, depth, out)
    }
