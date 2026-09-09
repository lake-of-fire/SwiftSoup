# Change Log

All notable changes to this project will be documented in this file.

## Unreleased
* Use wrapping integer arithmetic in `Attribute.hashCode()` so valid attribute keys cannot trigger an arithmetic-overflow trap during hash mixing. Equal attributes still receive equal process-local hashes.
* Avoid rescanning the registering owner's attribute array when re-observing a known member. Repeated snapshots/iteration of exclusively owned attributes no longer perform a quadratic identity-membership scan. Mutation notifications still validate every owner by identity and prune removed or expired owners.
* Make deferred attribute getters, presence checks, regenerated HTML, and selector indexes agree with materialized storage: trim/drop invalid keys and preserve the first position with the last value for exact duplicate keys. Distinct case variants retain their existing order. This corrects read-order-dependent results without changing the fork's materialized duplicate-key policy or eagerly creating Attribute objects.
* Initialize deferred TextNode attributes for byte-array `hasAttr` checks, just as for String checks. Reads do not dirty the source or restore removed text.
* Include comment contents in `Element.data()` and `:containsData`, as documented, in descendant document order. Traverse iteratively without intermediate subtree strings or materializing single-slice data nodes. Custom DataNode getter overrides remain respected. Queries previously ignoring comment contents may now match.
* Observe direct `Attribute.setKey` / `setValue` edits through every live owning collection and node, including references shared by `put` / `addAll`. Removed or replaced references no longer invalidate former owners. Reads that materialize deferred text/data do not count as DOM mutations.
* Clone mutable attribute objects independently, including implicit boolean attributes, while retaining immutable byte storage sharing. Cloned DOM mutations no longer change the original. Attribute keys that are empty after trimming are rejected before mutation.
* Keep attribute indexes consistent with case-insensitive getters when case variants or direct renames introduce duplicate names: the first matching attribute wins and elements appear once.
* Make deferred text and script-data attributes authoritative before public attribute access or edits. Subsequent reads/appends cannot overwrite edits or restore removed content. Direct non-element attribute edits invalidate text/selector caches and serialized source reuse.
* Return each element once from class indexes even when `class` repeats a token or case variant. Preserve traversal order in both combined and class-only rebuilds.
* Distinguish missing physical attributes from present empty values in equality, inequality, and regex predicates. Empty prefix/suffix/substring operands now match nothing, as required by CSS; existing SwiftSoup case/whitespace normalization is otherwise unchanged.
* Keep attribute fast plans consistent with the parser by delegating non-ASCII attribute selectors to it. Preserve parsed virtual `abs:` predicates with quoted empty operands, and recognize padded `abs:` keys in the public value getter.
* Honor case-preserving attribute updates in byte-slice predicates without dropping the lowercase-key fast path.
* Preserve value and regex predicates when an attribute-presence index seeds a compound selector. Presence alone does not prove a prefix, suffix, substring, or regex match. Keep exact-index shortcuts and check single-predicate `And` evaluators consistently.
* Resolve virtual `abs:` attribute presence through `hasAttr`, not the physical attribute-name index, and invalidate affected ancestor/subtree selector results when the base URI changes. Physical attribute indexes and text caches remain intact.
* Route unescaped punctuation in bare ID selectors through the parser, matching compound-selector validation. Literal punctuation in an ID must be escaped (for example `#x\]` for ID `x]`) or supplied through `getElementById`.
* Treat `getElementById` arguments as literal IDs, retaining leading/trailing whitespace. Callers that intentionally accepted padded input must now trim it themselves. Recognize form feed as a descendant combinator rather than an ID byte in the selector fast path.
* Preserve escaped trailing spaces and non-ASCII identifier content while removing CSS query padding, including direct parser and multi-root selection paths.
* Scan balanced and compound selectors at code-point boundaries; handle backslash parity and paired quote delimiters correctly. Unicode prepend characters no longer absorb closing parentheses or combinators. The public balanced scanner still supports multi-scalar delimiters.
* Match class tokens, never an entire whitespace-separated class list. Use HTML's five ASCII whitespace separators consistently in class getters, predicates, and indexes; vertical tab (U+000B) remains part of a class token.
* Preserve byte-distinct Unicode selector spellings in the parser, evaluator, fast-plan, and per-root result caches. Custom `QueryParserCache` implementations must also use code-point-exact key equality rather than Swift's canonical-equivalence equality.
* Generate ID/class escapes by Unicode scalar, preserving combining marks (including immediately after `#`/`.`), emoji, leading digits, controls, and literal backslashes. Escape spaces as code points so query trimming does not remove significant trailing spaces. CSS represents U+0000 as U+FFFD, not as a literal NUL.
* Preserve whitespace decoded from ID escapes during indexed selection. Anchor `:has(> ...)` against each candidate element and avoid the collect-once shortcut for root-dependent predicates.
* Decode CSS hexadecimal escapes in ID and class selectors: one to six hex digits, one optional CSS whitespace terminator (including CRLF), and U+FFFD for zero, surrogate, or out-of-range code points. Preserve the complete escape when splitting compound selectors.
* Compatibility: `p#\61` now matches ID `a`, not ID `61`. Clients that intended the old literal value should use `p#61` or `p#\36 1`; an ID containing a literal backslash followed by `61` is selected by `p#\\61`. ID/class parsing also accepts non-ASCII identifier code points so combining marks following hex digits are retained. Existing non-hex escapes remain supported. This does not change tag/attribute escape parsing or the separate text/regex unescape behavior.

## [2.3.2](https://github.com/scinfu/SwiftSoup/tree/2.3.2)
* Renamed Selector Class to CssSelector

## [1.7.4](https://github.com/scinfu/SwiftSoup/tree/1.7.4)
* Removed Some warnings
* Swift 4.2

## [1.7.1](https://github.com/scinfu/SwiftSoup/tree/1.7.1)
* Backward compatibility for Swift < 4.1

## [1.7.0](https://github.com/scinfu/SwiftSoup/tree/1.7.0)
* Removed StringBuilder from Element.cssSelector
* Lint Code
* Swift 4.1

## [1.6.5](https://github.com/scinfu/SwiftSoup/tree/1.6.5)
* Removed StringBuilder from Element.cssSelector
* Lint Code


## [1.6.4](https://github.com/scinfu/SwiftSoup/tree/1.6.4)
* Add newer simulators to targeted devices to build with Carthage [tvOS]

## [1.6.3](https://github.com/scinfu/SwiftSoup/tree/1.6.3)

* Add newer tvOS simulators to targeted devices to build with Carthage.
* Add newer watchOS simulators to targeted devices to build with Carthage.
