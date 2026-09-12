    @inline(__always)
    open func ownerDocument() -> Document? {
        var current: Node? = self
        while let node = current {
            if let document = node as? Document { return document }
            current = node.parentNode
        }
        return nil
    }

    /// A token that changes when text content in this node's tree mutates.

    @inline(__always)
    @usableFromInline
    internal func markSourceDirty(force: Bool = false) {
        markSourceDirty(force: force, registerDirtyRoot: true)
    }

    @inline(__always)
    @usableFromInline
    internal func markSourceDirty(force: Bool = false, registerDirtyRoot: Bool) {
        if !sourceRangeDirty, !force, treeBuilder?.isBulkBuilding == true { return }
        if registerDirtyRoot {
            sourceRangeDirty = true
            ownerDocument()?.registerDirtySourceRoot(self)
        }
        var current: Node? = registerDirtyRoot ? parentNode : self
        while let node = current {
            if node.sourceRangeDirty { break }
            if !force, node.treeBuilder?.isBulkBuilding == true { break }
            node.sourceRangeDirty = true
            current = node.parentNode
        }
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
        if !out.canReuseSource(parsedAsXml: doc.parsedAsXml) || range.end > source.count {
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

    @inline(__always)
    internal func outerHtmlFastWithoutSourceReuse(
        _ accum: StringBuilder,
        _ depth: Int,
        _ out: OutputSettings
    ) throws {
        try outerHtmlFast(accum, depth, out, allowRawSource: false)
    }
