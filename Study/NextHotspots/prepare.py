"""Reconstruct only the two isolated, hash-guarded candidate trees."""
import os
import shutil
import subprocess
from pathlib import Path

candidate = os.environ['CANDIDATE']
assert candidate in ('exclusion', 'ordered')
source = Path('/tmp/next-hotspot-input')
if candidate == 'exclusion':
    p = Path('Sources/CssSelector.swift')
    s = p.read_text()
    old = '''        for el: Element in elements where !outs.contains(el) {
            output.add(el)
        }
'''
    new = '''        if elements.count >= 64 && outs.count >= 64 {
            // Element equality requires object identity. Keep input order and
            // duplicates, but avoid rescanning a large exclusion list per item.
            var excluded = Set<ObjectIdentifier>()
            excluded.reserveCapacity(outs.count)
            for el in outs { excluded.insert(ObjectIdentifier(el)) }
            for el in elements where !excluded.contains(ObjectIdentifier(el)) {
                output.add(el)
            }
        } else {
            // Small or strongly asymmetric inputs do not amortize a hash table.
            for el in elements where !outs.contains(el) {
                output.add(el)
            }
        }
'''
    assert s.count(old) == 1
    p.write_text(s.replace(old, new))
    test = 'SelectorExclusionTest.swift'
    client = 'benchmark_exclusion.swift'
    runner = 'compare_exclusion.py'
    workloads = '''WORKLOADS = {
    'exclusion': ['not-8', 'not-128', 'not-512', 'not-2048', 'not-8192',
                  'sparse-control', 'descendant-control', 'parse-not', 'parse-control'],
}'''
    expected_tree = '5946c517f48d1300112386018d43afaeeaa0fa10'
else:
    p = Path('Sources/OrderedSet.swift')
    s = p.read_text()
    old = '''\t\t// Append our object, then swap them until its at the end.
\t\tappend(object)

\t\tfor i in (index..<count-1).reversed() {
\t\t\tswapObject(self[i], with: self[i+1])
\t\t}
'''
    new = '''\t\tif index == count {
\t\t\tappend(object)
\t\t\treturn
\t\t}

\t\t// Shift array storage once, then update each affected index once.
\t\tsequencedContents.insert(object, at: index)
\t\tfor i in index..<sequencedContents.count {
\t\t\tcontents[sequencedContents[i]] = i
\t\t}
'''
    assert s.count(old) == 1
    p.write_text(s.replace(old, new))
    test = 'OrderedSetInsertionTest.swift'
    client = 'benchmark_ordered_insertion.swift'
    runner = 'compare_ordered_insertion.py'
    workloads = '''WORKLOADS = {
    'ordered': ['head-16', 'middle-16', 'head-128', 'middle-128',
                'head-1024', 'middle-1024', 'tail-128', 'duplicate-128', 'parse-control'],
}'''
    expected_tree = 'f84be08ac6c0f981e4b9d6c126cb79d1349cf5bd'
shutil.copyfile(source / test, Path('Tests/SwiftSoupTests') / test)
shutil.copyfile(source / client, Path('Tools') / client)
comparison = Path('Tools/compare_independent_hotspots.py').read_text()
a = comparison.index('WORKLOADS =')
b = comparison.index('\n\ndef main():', a)
Path('Tools', runner).write_text(comparison[:a] + workloads + comparison[b:])
subprocess.run(['git', 'diff', '--check'], check=True)
subprocess.run(['git', 'add', str(p), 'Tests/SwiftSoupTests/' + test, 'Tools/' + client, 'Tools/' + runner], check=True)
tree = subprocess.check_output(['git', 'write-tree'], text=True).strip()
assert tree == expected_tree, (tree, expected_tree)
Path('/tmp/next-hotspot-evidence/tree.txt').write_text(tree + '\n')
