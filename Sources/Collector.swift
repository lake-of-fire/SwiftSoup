//
//  Collector.swift
//  SwiftSoup
//
//  Created by Nabil Chatbi on 22/10/16.
//

import Foundation

/**
 * Collects a list of elements that match the supplied criteria.
 *
 */
open class Collector {

    private init() {
    }


    /**
     Build a list of elements, by visiting root and every descendant of root, and testing it against the evaluator.
     - parameter eval: Evaluator to test elements against
     - parameter root: root of tree to descend
     - returns: list of matches; empty if none
     */
    public static func collect (_ eval: Evaluator, _ root: Element) throws -> Elements {
        if eval is Evaluator.AllElements {
            let elements = Elements()
            var stack: ContiguousArray<Element> = []
            stack.reserveCapacity(root.childNodes.count + 1)
            stack.append(root)
            while let el = stack.popLast() {
                elements.add(el)
                let children = el.childNodes
                var i = children.count
                while i > 0 {
                    i &-= 1
                    if let childEl = children[i] as? Element {
                        stack.append(childEl)
                    }
                }
            }
            return elements
        }
        let elements: Elements = Elements()
        if let andEval = eval as? CombiningEvaluator.And,
           let seeded = try seedCandidates(for: andEval, root: root) {
            let (seedElements, skipIndex) = seeded
            if seedElements.isEmpty {
                return seedElements
            }
            elements.reserveCapacity(seedElements.size())
            if let skipIndex {
                let evaluators = andEval.evaluators
                for el in seedElements.array() {
                    var matchesAll = true
                    for (idx, evaluator) in evaluators.enumerated() {
                        if idx == skipIndex { continue }
                        let matched = try evaluator.matches(root, el)
                        if !matched {
                            matchesAll = false
                            break
                        }
                    }
                    if matchesAll {
                        elements.add(el)
                    }
                }
            } else {
                for el in seedElements.array() {
                    if try andEval.matches(root, el) { elements.add(el) }
                }
            }
            return elements
        }
        if let fast = try simpleEvaluatorFastPath(eval, root: root) {
            return fast
        }
        // Manual DFS to reduce NodeTraversor/visitor overhead in hot selector paths.
        var stack: ContiguousArray<Element> = []
        stack.reserveCapacity(root.childNodes.count + 1)
        stack.append(root)
        while let el = stack.popLast() {
            let matched = try eval.matches(root, el)
            if matched {
                elements.add(el)
            }
            let children = el.childNodes
            var i = children.count
            while i > 0 {
                i &-= 1
                if let childEl = children[i] as? Element {
                    stack.append(childEl)
                }
            }
        }
        return elements
    }

    private static func simpleEvaluatorFastPath(_ eval: Evaluator, root: Element) throws -> Elements? {
        if let idEval = eval as? Evaluator.Id {
            return root.getElementsById(idEval.idBytes)
        }
        if let tagEval = eval as? Evaluator.Tag {
            return try root.getElementsByTagNormalized(tagEval.tagNameNormal)
        }
        if let classEval = eval as? Evaluator.Class {
            let classBytes = classEval.classNameBytes
            let normalizedClass: [UInt8]
            if !Attributes.containsAsciiUppercase(classBytes) {
                normalizedClass = classBytes
            } else {
                normalizedClass = classBytes.lowercased()
            }
            return root.getElementsByClassNormalizedBytes(normalizedClass)
        }
        if let attrEval = eval as? Evaluator.Attribute {
            return root.getElementsByAttributeNormalized(attrEval.keyBytes)
        }
        if let attrValueEval = eval as? Evaluator.AttributeWithValue {
            if attrValueEval.keyBytes.starts(with: UTF8Arrays.absPrefix) {
                return nil
            }
            return try root.getElementsByAttributeValueNormalized(
                attrValueEval.keyBytes,
                attrValueEval.valueBytes,
                attrValueEval.key,
                attrValueEval.value
            )
        }
        if eval is StructuralEvaluator.Root {
            return Elements([root])
        }
        return nil
    }

    private static func seedCandidates(for eval: CombiningEvaluator.And, root: Element) throws -> (Elements, Int?)? {
        let evaluators = eval.evaluators

        @inline(__always)
        func shouldSkipIndex(_ index: Int) -> Int? {
            return index
        }

        for (idx, evaluator) in evaluators.enumerated() {
            if let idEval = evaluator as? Evaluator.Id {
                return (root.getElementsById(idEval.idBytes), shouldSkipIndex(idx))
            }
        }

        for (idx, evaluator) in evaluators.enumerated() {
            if let attrValueEval = evaluator as? Evaluator.AttributeWithValue {
                if attrValueEval.keyBytes.starts(with: UTF8Arrays.absPrefix) {
                    return nil
                }
                return (try root.getElementsByAttributeValueNormalized(
                            attrValueEval.keyBytes,
                            attrValueEval.valueBytes,
                            attrValueEval.key,
                            attrValueEval.value
                        ),
                        shouldSkipIndex(idx))
            }
        }

        for (idx, evaluator) in evaluators.enumerated() {
            if let classEval = evaluator as? Evaluator.Class {
                let classBytes = classEval.classNameBytes
                let normalizedClass: [UInt8]
                if !Attributes.containsAsciiUppercase(classBytes) {
                    normalizedClass = classBytes
                } else {
                    normalizedClass = classBytes.lowercased()
                }
                return (root.getElementsByClassNormalizedBytes(normalizedClass),
                        shouldSkipIndex(idx))
            }
        }

        for (idx, evaluator) in evaluators.enumerated() {
            if let tagEval = evaluator as? Evaluator.Tag {
                return (try root.getElementsByTagNormalized(tagEval.tagNameNormal),
                        shouldSkipIndex(idx))
            }
        }

        for (idx, evaluator) in evaluators.enumerated() {
            if let attrEval = evaluator as? Evaluator.Attribute {
                return (root.getElementsByAttributeNormalized(attrEval.keyBytes),
                        shouldSkipIndex(idx))
            }
        }

        for evaluator in evaluators {
            if let attrMatchingEval = evaluator as? Evaluator.AttributeWithValueMatching {
                if Element.isAbsAttributeKey(attrMatchingEval.key.utf8Array) { return nil }
                return (root.getElementsByAttributeNormalized(attrMatchingEval.key.utf8Array), nil)
            }
        }

        for evaluator in evaluators {
            if evaluator is Evaluator.AttributeWithValueNot {
                continue
            }
            if let attrKeyPairEval = evaluator as? Evaluator.AttributeKeyPair {
                if Element.isAbsAttributeKey(attrKeyPairEval.keyBytes) { return nil }
                return (root.getElementsByAttributeNormalized(attrKeyPairEval.keyBytes), nil)
            }
        }

        return nil
    }

}

private final class Accumulator: NodeVisitor {
    private let root: Element
    private let elements: Elements
    private let eval: Evaluator

    init(_ root: Element, _ elements: Elements, _ eval: Evaluator) {
        self.root = root
        self.elements = elements
        self.eval = eval
    }

    @inlinable
    public func head(_ node: Node, _ depth: Int) {
        guard let el = node as? Element else {
            return
        }
        do {
            if try eval.matches(root, el) {
                elements.add(el)
            }
        } catch {}
    }

    public func tail(_ node: Node, _ depth: Int) {
        // void
    }
}
