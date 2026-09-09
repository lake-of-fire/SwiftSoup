import base64, gzip, hashlib, json, subprocess, sys
from pathlib import Path

source, checkout, variant = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
assert variant in ('child', 'only')
encoded = (source / 'payload.b64').read_text().strip()
# Repair a duplicated segment from the text transfer, never silently accept it.
# The decoded archive must still match the canonical local SHA-256 below.
marker = 'OLOBBFec+V3Z3'
if encoded.count(marker) == 2:
    encoded = encoded[:encoded.index(marker)] + encoded[encoded.rindex(marker):]
    print('Removed duplicated staging transport segment')
data = base64.b64decode(encoded, validate=True)
assert hashlib.sha256(data).hexdigest() == 'f5f88b53dd77434c2f1020303940c79c03ded241ab6fdb3901da93a8d0bc4909', 'transport digest'
files = json.loads(gzip.decompress(data))
subprocess.run(['git', 'apply', '-'], input=files[variant + '.patch'], text=True, cwd=checkout, check=True)
test = 'ChildIndexedReadTest.swift' if variant == 'child' else 'OnlyChildExistenceTest.swift'
(checkout / 'Tests/SwiftSoupTests' / test).write_text(files['tests/' + test])
for name in ['benchmark_child_reads.swift', 'compare_child_reads.py']:
    contents = files['tools/' + name]
    if name == 'benchmark_child_reads.swift':
        old = 'f.elements.last()!.remove()'
        assert contents.count(old) == 1
        contents = contents.replace(old, 'f.elements.last!.remove()')
    (checkout / 'Tools' / name).write_text(contents)
subprocess.run(['git', 'add', 'Sources', 'Tests/SwiftSoupTests', 'Tools/benchmark_child_reads.swift', 'Tools/compare_child_reads.py'], cwd=checkout, check=True)
expected = {'child': '6d67b9425fdc8f6428ee19e3ce8270928fb7d51a', 'only': 'fb429602415045f5dc3b4153fde7b4a849bb2904'}[variant]
actual = subprocess.check_output(['git', 'write-tree'], cwd=checkout, text=True).strip()
assert actual == expected, (variant, actual, expected)
print('Verified complete source tree:', actual)
