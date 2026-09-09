from pathlib import Path
import subprocess

root = Path.cwd()
def blob(path):
    return subprocess.check_output(['git', 'hash-object', path], text=True).strip()
assert blob('Sources/TokenQueue.swift') == '68515eb7d561adce86e953880530de7eb88e5885'
assert blob('CHANGELOG.md') == '39e5aea954952e69546ebcd88325b184033e44cf'
p = root / 'Sources/TokenQueue.swift'
s = p.read_text()
def replace(before, after):
    global s
    assert s.count(before) == 1, before
    s = s.replace(before, after)
replace('''    open func chompBalanced(_ open: Character, _ close: Character) -> String {
        let start''', '''    open func chompBalanced(_ open: Character, _ close: Character) -> String {
        return chompBalanced(open, close, preservingDelimiters: false)
    }

    private func chompBalanced(_ open: Character, _ close: Character, preservingDelimiters: Bool) -> String {
        let start''')
replace('return chompBalanced(in: queue.unicodeScalars, from: start, open: openScalar, close: closeScalar)', '''return chompBalanced(in: queue.unicodeScalars, from: start, open: openScalar, close: closeScalar,
                                 preservingDelimiters: preservingDelimiters)''')
replace('return chompBalanced(in: queue, from: start, open: open, close: close)', '''return chompBalanced(in: queue, from: start, open: open, close: close,
                             preservingDelimiters: preservingDelimiters)''')
replace('open: Characters.Element, close: Characters.Element) -> String', '''open: Characters.Element, close: Characters.Element,
                                                      preservingDelimiters: Bool) -> String''')
replace('''        let result = payloadStart.map { String(decoding: queue.utf8[$0..<payloadEnd], as: UTF8.self) } ?? ""
        advanceCssPosition''', '''        // A compound selector must retain the actual source spelling, including
        // partial input. Rebuilding open + payload + close invents a delimiter at
        // EOF and can bypass the inner numeric parser or change literal content.
        let result = preservingDelimiters
            ? String(decoding: queue.utf8[start..<cursor], as: UTF8.self)
            : payloadStart.map { String(decoding: queue.utf8[$0..<payloadEnd], as: UTF8.self) } ?? ""
        advanceCssPosition''')
replace('''                result.append(open)
                result.append(chompBalanced(open, close))
                result.append(close)''', '''                result.append(chompBalanced(open, close, preservingDelimiters: true))''')
start = s.index('    public static func unescape(')
end = s.index('\n    /**', start)
s = s[:start] + '''    public static func unescape(_ input: String) -> String {
        let out = StringBuilder()
        var escaped = false
        // Quote one scalar at a time, including within a Swift grapheme. A run
        // of backslashes is consumed in pairs; a trailing lone escape is dropped
        // as before. This is text unescaping, not CSS hexadecimal decoding.
        for scalar in input.unicodeScalars {
            if escaped {
                out.appendCodePoint(scalar)
                escaped = false
            } else if scalar == "\\\\" {
                escaped = true
            } else {
                out.appendCodePoint(scalar)
            }
        }
        return out.toString()
    }
''' + s[end:]
p.write_text(s)
p = root / 'CHANGELOG.md'
s = p.read_text()
assert s.count('## Unreleased\n') == 1
s = s.replace('## Unreleased\n', '''## Unreleased
* Decode paired text escapes correctly in `TokenQueue.unescape` and `:contains` / `:containsOwn` / `:containsData`. Runs of backslashes now quote one scalar at a time, including inside graphemes, rather than duplicating escapes. A lone trailing backslash is still dropped. Regex arguments and CSS hexadecimal identifier decoding remain separate and unchanged.
* Preserve the exact consumed spelling of balanced expressions while splitting compound selectors. Missing numeric closing parentheses now fail consistently after combinators and within partial outer expressions, instead of being synthesized. Partial literal text/regex input is no longer changed by an invented closing delimiter. Public `TokenQueue.chompBalanced` partial-result behavior and existing nonnumeric EOF tolerance remain unchanged; this is not a new browser-equivalent EOF policy.
''', 1)
p.write_text(s)
assert blob('Sources/TokenQueue.swift') == '27bc340d3faa940e61bb3966df61b5d19fc7aafb'
assert blob('CHANGELOG.md') == '4717fcb3873db6b71d692de63f6486b63eb946c0'
