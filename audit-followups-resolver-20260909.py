from pathlib import Path
import re
import subprocess


def side(path, choice):
    p = Path(path)
    text = p.read_text()
    pattern = re.compile(r'^<<<<<<<[^\n]*\n(.*?)^=======\n(.*?)^>>>>>>>[^\n]*\n', re.M | re.S)
    text, count = pattern.subn(lambda match: match.group(choice), text)
    assert count > 0, path
    assert not re.search(r'^(<<<<<<<|=======|>>>>>>>)', text, re.M), path
    p.write_text(text)


side('Sources/Attributes.swift', 1)
side('Sources/TextNode.swift', 2)
p = 'Tests/SwiftSoupTests/TextSplitBoundaryTest.swift'
original = subprocess.check_output(['git', 'show', ':2:' + p], text=True)
refinement = subprocess.check_output(['git', 'show', ':3:' + p], text=True)
assert 'final class TextSplitBoundaryTest:' in refinement
Path(p).write_text(original)
Path('Tests/SwiftSoupTests/TextSplitRefinementCompatibilityTest.swift').write_text(
    refinement.replace('final class TextSplitBoundaryTest:', 'final class TextSplitRefinementCompatibilityTest:'))
p = Path('CHANGELOG.md')
text = subprocess.check_output(['git', 'show', 'HEAD:CHANGELOG.md'], text=True)
text = text.replace('## Unreleased\n', '## Unreleased\n* Keep validated absent attribute reads deferred and reject empty case-insensitive value queries before changing storage. Retain the existing bounded 32-name prefilter and exact comparisons. Validate both UTF-8 split partitions without recreating the entire text.\n', 1)
p.write_text(text)
