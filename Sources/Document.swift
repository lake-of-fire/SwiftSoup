        let out = (_outputSettings.copy() as! OutputSettings).prettyPrint(pretty: false)
        var patches: [SourcePatch] = []

        func collect(_ node: Node, _ ancestorDirty: Bool) {
            let nodeDirty = node.sourceRangeDirty
            if nodeDirty && !ancestorDirty,
               node.sourceRangeIsComplete,
               let range = node.sourceRange,
               range.isValid,
               let source = sourceBuffer?.bytes,
               range.end <= source.count {
                if let replacement = try? node.outerHtmlUTF8Internal(out, allowRawSource: false) {
                    patches.append(SourcePatch(range: range, replacement: replacement))
                    return
                }
            }
            let hasOwnRange = node.sourceRangeIsComplete && node.sourceRange != nil
            let childAncestorDirty = ancestorDirty || (nodeDirty && hasOwnRange)
            if node.hasChildNodes() {
                for child in node.childNodes {
                    collect(child, childAncestorDirty)
                }
            }
        }

        if roots.isEmpty {
            collect(self, false)
        } else {
            for root in roots {
                collect(root, false)
            }
        }
        if patches.count > 1 {
            patches.sort { $0.range.start < $1.range.start }
        }
        return patches
    }

    @usableFromInline
    internal func patchedOuterHtmlUTF8() throws -> [UInt8]? {
        guard !_outputSettings.prettyPrint(),
              let source = sourceBuffer?.bytes else {
            return nil
        }

        let patches = try sourcePatches()
        if patches.isEmpty {
            return source
        }

        var previousEnd = 0

    private var _prettyPrint: Bool = true
    private var _outline: Bool = false
    private var _indentAmount: UInt  = 1
    private var _syntax = Syntax.html

    public init() {}

    /**
     Get the document's current HTML escape mode: `e`, which provides a limited set of named HTML
