from pathlib import Path
import shutil, subprocess
p = Path('Sources/StringUtil.swift')
s = p.read_text()
old = '''        if (string.isEmpty) {
            return true
        }

        for chr in string {
            if (!StringUtil.isWhitespace(chr)) {
                return false
            }
        }
        return true
'''
new = '''        return isBlankTextBytes(string.utf8)
    }

    // CharacterExt's whitespace set consists only of these ASCII scalars
    // (including the CRLF Character). Any other byte makes the text nonblank,
    // including malformed UTF-8, which String(decoding:) would replace.
    @inline(__always)
    static func isBlankTextBytes<Bytes: Collection>(_ bytes: Bytes) -> Bool where Bytes.Element == UInt8 {
        for byte in bytes {
            switch byte {
            case 0x09, 0x0A, 0x0C, 0x0D, 0x20: continue
            default: return false
            }
        }
        return true
'''
assert s.count(old) == 1
p.write_text(s.replace(old, new))
p = Path('Sources/TextNode.swift')
s = p.read_text()
old = '''    open func isBlank() -> Bool {
        return StringUtil.isBlank(getWholeText())
    }'''
new = '''    open func isBlank() -> Bool {
        if type(of: self) == TextNode.self {
            // Keep the authoritative byte getter and its materialization behavior,
            // but do not decode the whole value merely to test for ASCII whitespace.
            return StringUtil.isBlankTextBytes(getWholeTextUTF8())
        }
        return StringUtil.isBlank(getWholeText())
    }'''
assert s.count(old) == 1
p.write_text(s.replace(old, new))
shutil.copyfile('/tmp/blank-input/BlankTextBytesTest.swift', 'Tests/SwiftSoupTests/BlankTextBytesTest.swift')
shutil.copyfile('/tmp/blank-input/benchmark_blank_text.swift', 'Tools/benchmark_blank_text.swift')
s = subprocess.check_output(['git', 'show', '0aa13e0b536841406443e31a0335c0be287572b7:Tools/compare_cursor_moves.py']).decode()
start = s.index('WORKLOADS = {')
end = s.index('\n\ndef main():', start)
s = s[:start] + '''WORKLOADS = {
    "blank": ["string-short", "string-blank-long", "string-unicode", "node-short", "node-blank-long", "node-unicode", "node-late-text", "node-custom", "hastext-blank", "hastext-nonblank", "serialize-pretty", "parse-hastext", "parse-control"]
}''' + s[end:]
Path('Tools/compare_blank_text.py').write_text(s)
