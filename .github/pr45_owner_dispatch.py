from pathlib import Path

p = Path('Sources/Node.swift')
s = p.read_text()
old = """            if let document = current as? Document {
                return document
            }
"""
new = """            if let document = current as? Document {
                // Preserve the historical virtual dispatch at the owning
                // Document while keeping the ancestor walk itself iterative.
                return document.ownerDocument()
            }
"""
if s.count(old) != 1:
    raise SystemExit(f'owner terminal count={s.count(old)}')
p.write_text(s.replace(old, new))
