# Change Log

All notable changes to this project will be documented in this file.

## Unreleased
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
