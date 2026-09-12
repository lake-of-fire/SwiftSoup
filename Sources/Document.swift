        let out = (_outputSettings.copy() as! OutputSettings).prettyPrint(pretty: false)
        var patches: [SourcePatch] = []

        let sourceRoots: [Node] = roots.isEmpty ? [self] : roots
        var pending: [(node: Node, ancestorDirty: Bool)] = sourceRoots.map { ($0, false) }
        while let (node, ancestorDirty) = pending.popLast() {
            let nodeDirty = node.sourceRangeDirty
            if nodeDirty && !ancestorDirty,
               node.sourceRangeIsComplete,
               let range = node.sourceRange,
               range.isValid,
               let source = sourceBuffer?.bytes,
               range.end <= source.count,
               let replacement = try? node.outerHtmlUTF8Internal(out, allowRawSource: false) {
                patches.append(SourcePatch(range: range, replacement: replacement))
                continue
            }
            let hasOwnRange = node.sourceRangeIsComplete && node.sourceRange != nil
            let childAncestorDirty = ancestorDirty || (nodeDirty && hasOwnRange)
            for child in node.childNodes.reversed() {
                pending.append((child, childAncestorDirty))
            }
        }
        if patches.count > 1 {
            patches.sort { $0.range.start < $1.range.start }
        }
        return patches
    }

    @usableFromInline
    internal func patchedOuterHtmlUTF8() throws -> [UInt8]? {
        guard _outputSettings.canReuseSource(parsedAsXml: parsedAsXml),
              let source = sourceBuffer?.bytes else {
            return nil
        }

        // Synthetic fragment containers have no replaceable source range. Their
        // child edits cannot be represented by splicing ranges from the input.
        guard currentDirtySourceRoots().allSatisfy({
            $0.sourceRangeIsComplete && $0.sourceRange != nil
        }) else { return nil }
        let patches = try sourcePatches()
        if patches.isEmpty, sourceRangeDirty { return nil }
        if patches.isEmpty {
            return source
        }

        var previousEnd = 0

    private var _prettyPrint: Bool = true
    private var _outline: Bool = false
    private var _indentAmount: UInt  = 1
    private var _syntax = Syntax.html

    public init() {}

    /// Source slices preserve their original entity spelling. Only the default
    /// encoding/escape policy can reuse them without bypassing output settings.
    @usableFromInline
    internal func canReuseSource(parsedAsXml: Bool) -> Bool {
        !_prettyPrint && _encoder == .utf8 && _escapeMode == .base
            && parsedAsXml == (_syntax == .xml)
    }

    /**
     Get the document's current HTML escape mode: `e`, which provides a limited set of named HTML
