from pathlib import Path
import hashlib, shutil, sys

inputs = Path(sys.argv[1])
for filename, destination in [
    ('StringSearchBoundaryTest.swift', 'Tests/SwiftSoupTests/StringSearchBoundaryTest.swift'),
    ('benchmark_tokenqueue_search.swift', 'Tools/benchmark_tokenqueue_search.swift')
]:
    shutil.copyfile(inputs / filename, destination)

p = Path('Sources/String.swift')
s = p.read_text()
start = s.index('\tfunc indexOf(_ substring: String, _ offset: Int ) -> Int {')
end = s.index('\n    @inline(__always)', start)
s = s[:start] + '''    func indexOf(_ substring: String, _ offset: Int) -> Int {
        // Offsets and candidate windows remain Character-based. Advance the
        // two bounds instead of rescanning from startIndex for every window.
        guard offset >= 0,
              var lower = index(startIndex, offsetBy: offset, limitedBy: endIndex),
              var upper = index(lower, offsetBy: substring.count, limitedBy: endIndex) else {
            return -1
        }
        var position = offset
        while true {
            if self[lower..<upper] == substring { return position }
            guard upper < endIndex else { return -1 }
            formIndex(after: &lower)
            formIndex(after: &upper)
            position += 1
        }
    }
''' + s[end:]
p.write_text(s)

s = Path('Tools/compare_exclusion.py').read_text()
start = s.index('WORKLOADS =')
end = s.index('\ndef main():', start)
names = ['early-ascii', 'tiny-ascii', 'late-ascii-2048', 'late-japanese-128', 'late-japanese-512', 'late-japanese-2048', 'miss-japanese-512', 'mixed-graphemes', 'offset-japanese', 'canonical-match', 'numeric-parse-512', 'normal-parse-control']
s = s[:start] + 'WORKLOADS = {"search": ' + repr(names) + '}\n' + s[end:]
s = s.replace('calibration=[]; iterations={}; expected={}', 'calibration=[]; iterations={"A":{},"B":{}}; expected={}')
s = s.replace("speeds.append(sample['elapsed_ns']/sample['iterations'])", "speeds.append(sample['elapsed_ns']/sample['iterations'])\n            iterations[k][w]=max(4,min(2_000_000,math.ceil(a.ms*1e6/speeds[-1])))")
s = s.replace('        iterations[w]=max(4,min(2_000_000,math.ceil(a.ms*1e6/min(speeds))))', '        # Calibrate each revision separately: avoid timing an enormous baseline\n        # batch merely because the candidate eliminates quadratic index walks.')
s = s.replace('str(iterations[w])', 'str(iterations[k][w])')
s = s.replace('expected[w]*iterations[w]', 'expected[w]*iterations[k][w]')
s = s.replace("'iterations':iterations[w]", "'iterations':{k:iterations[k][w] for k in paths}")
Path('Tools/compare_tokenqueue_search.py').write_text(s)

expected = {
    'Sources/String.swift': '33649c2a55609cad1284788633be82ff2dbca9902c5a2e4b486212144d69d033',
    'Tests/SwiftSoupTests/StringSearchBoundaryTest.swift': '6c30a07e42fad5cd377bf0530f57e1d81d7396b10430a6d3c2cf4165aa94a2a5',
    'Tools/benchmark_tokenqueue_search.swift': 'f4991d2c7416d4ddf677536ef1b9f314ed63b914cfda6b84c52a56abae21ab48',
    'Tools/compare_tokenqueue_search.py': 'ecba54c0cfe54beae9f1a5090986a5512e971b39d72ffac7745ce6a1972a8d1a'
}
for name, digest in expected.items():
    actual = hashlib.sha256(Path(name).read_bytes()).hexdigest()
    assert actual == digest, (name, actual, digest)
print('All four source/tool/test hashes match the locally tested candidate.')
