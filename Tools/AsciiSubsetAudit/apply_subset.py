#!/usr/bin/env python3
"""Reconstruct a narrow PR36 follow-up; refuse any source/tree drift."""
from pathlib import Path
import hashlib, shutil, subprocess, sys
root = Path(sys.argv[1]).resolve()
audit = Path(__file__).resolve().parent
expected_base = 'fef621ee15ac065f463e70bc2b87fb3ac88447cc'
assert subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip() == expected_base
assert subprocess.check_output(['git', 'rev-parse', 'HEAD^{tree}'], cwd=root, text=True).strip() == 'f513bedb4b276741ba872d08a4ef0887563270b1'
def replace(path, before, after):
    p = root / path
    s = p.read_text()
    assert s.count(before) == 1, path
    p.write_text(s.replace(before, after))
replace('Sources/OrderedSet.swift',
    'The input is consumed at most once and stops when all members are found.\n\tTemporary membership storage is bounded by the receiver count.',
    'Collections retain their membership checks; other sequences are consumed\n\tat most once and stop when all members are found. Empty receivers do not\n\tconsume the input. Temporary storage is bounded by the receiver count.')
replace('Sources/OrderedSet.swift',
    '\t\tguard !contents.isEmpty else { return true }\n\t\t// Sequence need not be restartable.',
    '''\t\tguard !contents.isEmpty else { return true }
\t\t// Collections are restartable and may answer contains without scanning
\t\t// (notably Set and Range). A singleton needs only one membership query,
\t\t// even for a single-pass Sequence, and needs no temporary membership set.
\t\tif contents.count == 1 || sequence is any Collection {
\t\t\tfor object in contents.keys {
\t\t\t\tif !sequence.contains(object) { return false }
\t\t\t}
\t\t\treturn true
\t\t}
\t\t// Sequence need not be restartable.''')
replace('CHANGELOG.md',
    '* Check `OrderedSet.isSubset(of:)` with a single input traversal. Single-pass sequences no longer lose earlier matches or depend on hash iteration order. Empty receivers do not consume the input; successful checks stop once all required members are found. The temporary membership set is bounded by receiver size.',
    '* Check `OrderedSet.isSubset(of:)` without restarting single-pass inputs. Such sequences no longer lose earlier matches or depend on hash iteration order; successful checks stop once all required members are found. Collections retain their specialized membership checks (including Set and Range), and singleton receivers need only one check without temporary membership storage. Empty receivers do not consume the input. Temporary membership storage for multi-member, non-Collection inputs is bounded by receiver size.')
test = 'Tests/SwiftSoupTests/OrderedSetCollectionMembershipTest.swift'
shutil.copyfile(audit / 'OrderedSetCollectionMembershipTest.swift', root / test)
blobs = {'Sources/OrderedSet.swift': '86964fd50e0955d1a8355c325d07007ef98780f0',
         'CHANGELOG.md': 'e5270e1eb8f6bd83721245b93a03b30f9e263f8d',
         test: '51d5a2565709aa9695e995e92922a6c5a4701471'}
for path, expected in blobs.items():
    data = (root / path).read_bytes()
    actual = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
    assert actual == expected, (path, actual)
subprocess.run(['git', 'add', '--', *blobs], cwd=root, check=True)
actual = subprocess.check_output(['git', 'write-tree'], cwd=root, text=True).strip()
assert actual == '5a2e9ca801de6553126eef1d51399c2359465b17', actual
print(actual)
