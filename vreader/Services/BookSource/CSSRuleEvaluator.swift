// Purpose: Evaluates CSS-like selectors against HTML using Foundation regex.
// No external dependencies (no SwiftSoup). Handles common selectors:
// tag, .class, #id, tag.class, and single-level descendant selectors.
//
// Key decisions:
// - Enum namespace (stateless, all static).
// - Uses NSRegularExpression for HTML tag matching (not a full DOM parser).
// - Delegates attribute parsing, URL resolution, and HTML stripping to HTMLHelper.
// - Self-closing tags (img, br, hr, input, meta, link) handled specially.
//
// Limitations:
// - Not a full CSS selector engine. Handles tag, .class, #id, tag.class,
//   and one-level descendant selectors (e.g., "div.x p").
// - Does not support combinators like >, +, ~.
//
// @coordinates-with: RuleEngine.swift, LegadoRuleParser.swift, HTMLHelper.swift

import Foundation

/// Evaluates CSS-like selectors against HTML content using Foundation regex.
enum CSSRuleEvaluator {

    // MARK: - Self-closing Tags

    private static let selfClosingTags: Set<String> = [
        "img", "br", "hr", "input", "meta", "link", "area",
        "base", "col", "embed", "source", "track", "wbr"
    ]

    // MARK: - Evaluate

    /// Evaluates a CSS selector against HTML and returns extracted values.
    static func evaluate(
        selector: String,
        attribute: String?,
        index: Int?,
        html: String,
        baseURL: URL?
    ) -> [String] {
        guard !selector.isEmpty, !html.isEmpty else { return [] }

        let parts = parseDescendantSelector(selector)
        let results: [String]

        if parts.count > 1 {
            results = evaluateDescendant(
                parts: parts, attribute: attribute,
                html: html, baseURL: baseURL
            )
        } else {
            results = evaluateSimple(
                simple: parts[0], attribute: attribute,
                html: html, baseURL: baseURL
            )
        }

        return HTMLHelper.applyIndex(results: results, index: index)
    }

    // MARK: - Descendant Selector

    private static func parseDescendantSelector(
        _ selector: String
    ) -> [SimpleSelector] {
        selector
            .split(separator: " ", omittingEmptySubsequences: true)
            .map { parseSimpleSelector(String($0)) }
    }

    private static func evaluateDescendant(
        parts: [SimpleSelector],
        attribute: String?,
        html: String,
        baseURL: URL?
    ) -> [String] {
        guard let first = parts.first else { return [] }

        let outerMatches = findElements(matching: first, in: html)

        if parts.count == 1 {
            return outerMatches.map {
                extractValue(from: $0, attribute: attribute, baseURL: baseURL)
            }
        }

        let remaining = Array(parts.dropFirst())
        var results: [String] = []

        for match in outerMatches {
            let inner: [String]
            if remaining.count == 1 {
                inner = evaluateSimple(
                    simple: remaining[0], attribute: attribute,
                    html: match.innerHTML, baseURL: baseURL
                )
            } else {
                inner = evaluateDescendant(
                    parts: remaining, attribute: attribute,
                    html: match.innerHTML, baseURL: baseURL
                )
            }
            results.append(contentsOf: inner)
        }

        return results
    }

    // MARK: - Simple Selector

    private static func evaluateSimple(
        simple: SimpleSelector,
        attribute: String?,
        html: String,
        baseURL: URL?
    ) -> [String] {
        findElements(matching: simple, in: html).map {
            extractValue(from: $0, attribute: attribute, baseURL: baseURL)
        }
    }

    // MARK: - Element Finding

    private struct ElementMatch {
        let fullMatch: String
        let tagAttributes: String
        let innerHTML: String
    }

    private static func findElements(
        matching selector: SimpleSelector,
        in html: String
    ) -> [ElementMatch] {
        if let tag = selector.tag {
            return findTagElements(
                tag: tag, className: selector.className,
                id: selector.id, in: html
            )
        } else {
            return findAnyTagElements(
                className: selector.className,
                id: selector.id, in: html
            )
        }
    }

    /// Finds elements by a specific tag name.
    private static func findTagElements(
        tag: String,
        className: String?,
        id: String?,
        in html: String
    ) -> [ElementMatch] {
        let pattern: String
        if selfClosingTags.contains(tag.lowercased()) {
            pattern = "<\(tag)(\\s[^>]*)?\\/?>(?:([\\s\\S]*?)<\\/\(tag)>)?"
        } else {
            pattern = "<\(tag)(\\s[^>]*)?>([\\s\\S]*?)<\\/\(tag)>"
        }

        guard let regex = try? NSRegularExpression(
            pattern: pattern, options: [.caseInsensitive]
        ) else { return [] }

        let nsHTML = html as NSString
        let range = NSRange(location: 0, length: nsHTML.length)

        return regex.matches(in: html, range: range).compactMap { match in
            let fullMatch = nsHTML.substring(with: match.range)
            let attrs = HTMLHelper.safeSubstring(nsHTML, match: match, group: 1)
            let content = HTMLHelper.safeSubstring(nsHTML, match: match, group: 2)

            if let className,
               !HTMLHelper.parseClasses(from: attrs).contains(className) {
                return nil
            }
            if let id, HTMLHelper.parseAttribute(named: "id", from: attrs) != id {
                return nil
            }

            return ElementMatch(
                fullMatch: fullMatch,
                tagAttributes: attrs,
                innerHTML: content
            )
        }
    }

    /// Finds elements of any tag name, filtering by class or ID.
    private static func findAnyTagElements(
        className: String?,
        id: String?,
        in html: String
    ) -> [ElementMatch] {
        let openPattern =
            "<([a-zA-Z][a-zA-Z0-9]*)(\\s[^>]*)?>|<([a-zA-Z][a-zA-Z0-9]*)>"
        guard let openRegex = try? NSRegularExpression(
            pattern: openPattern, options: [.caseInsensitive]
        ) else { return [] }

        let nsHTML = html as NSString
        let fullRange = NSRange(location: 0, length: nsHTML.length)
        let openMatches = openRegex.matches(in: html, range: fullRange)

        var results: [ElementMatch] = []

        for openMatch in openMatches {
            let tagName: String
            let attrs: String

            if openMatch.range(at: 1).location != NSNotFound {
                tagName = nsHTML.substring(with: openMatch.range(at: 1))
                attrs = HTMLHelper.safeSubstring(
                    nsHTML, match: openMatch, group: 2
                )
            } else if openMatch.range(at: 3).location != NSNotFound {
                tagName = nsHTML.substring(with: openMatch.range(at: 3))
                attrs = ""
            } else {
                continue
            }

            if selfClosingTags.contains(tagName.lowercased()) { continue }

            if let className,
               !HTMLHelper.parseClasses(from: attrs).contains(className) {
                continue
            }
            if let id,
               HTMLHelper.parseAttribute(named: "id", from: attrs) != id {
                continue
            }

            let contentStart =
                openMatch.range.location + openMatch.range.length
            let closingTag = "</\(tagName)>"
            let searchRange = NSRange(
                location: contentStart,
                length: nsHTML.length - contentStart
            )
            let closeRange = nsHTML.range(
                of: closingTag,
                options: [.caseInsensitive],
                range: searchRange
            )

            guard closeRange.location != NSNotFound else { continue }

            let innerRange = NSRange(
                location: contentStart,
                length: closeRange.location - contentStart
            )
            let innerHTML = nsHTML.substring(with: innerRange)

            let fullMatchRange = NSRange(
                location: openMatch.range.location,
                length: closeRange.location + closeRange.length
                    - openMatch.range.location
            )
            let fullMatch = nsHTML.substring(with: fullMatchRange)

            results.append(ElementMatch(
                fullMatch: fullMatch,
                tagAttributes: attrs,
                innerHTML: innerHTML
            ))
        }

        return results
    }

    // MARK: - Evaluate Raw HTML

    /// Evaluates a CSS selector and returns the full HTML of each match.
    ///
    /// Used for container-level rules (bookList, chapterList) where
    /// sub-rules are applied to each element's HTML.
    static func evaluateRawHTML(
        selector: String,
        index: Int?,
        html: String
    ) -> [String] {
        guard !selector.isEmpty, !html.isEmpty else { return [] }

        let parts = parseDescendantSelector(selector)
        let matches: [ElementMatch]

        if parts.count > 1 {
            matches = findDescendantMatches(parts: parts, html: html)
        } else {
            matches = findElements(matching: parts[0], in: html)
        }

        let rawHTMLs = matches.map { $0.fullMatch }
        return HTMLHelper.applyIndex(results: rawHTMLs, index: index)
    }

    /// Finds descendant matches, returning ElementMatch objects.
    private static func findDescendantMatches(
        parts: [SimpleSelector],
        html: String
    ) -> [ElementMatch] {
        guard let first = parts.first else { return [] }

        let outerMatches = findElements(matching: first, in: html)
        if parts.count == 1 { return outerMatches }

        let remaining = Array(parts.dropFirst())
        var results: [ElementMatch] = []

        for match in outerMatches {
            if remaining.count == 1 {
                results.append(
                    contentsOf: findElements(
                        matching: remaining[0], in: match.innerHTML
                    )
                )
            } else {
                results.append(
                    contentsOf: findDescendantMatches(
                        parts: remaining, html: match.innerHTML
                    )
                )
            }
        }

        return results
    }

    // MARK: - Value Extraction

    private static func extractValue(
        from element: ElementMatch,
        attribute: String?,
        baseURL: URL?
    ) -> String {
        if let attr = attribute {
            let value =
                HTMLHelper.parseAttribute(
                    named: attr, from: element.tagAttributes
                )
                ?? HTMLHelper.parseAttribute(
                    named: attr, from: element.fullMatch
                )
                ?? ""
            return HTMLHelper.resolveURL(
                value, attribute: attr, baseURL: baseURL
            )
        } else {
            return HTMLHelper.stripHTMLTags(element.innerHTML)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    // MARK: - Selector Parsing

    struct SimpleSelector {
        let tag: String?
        let className: String?
        let id: String?
    }

    private static func parseSimpleSelector(
        _ selector: String
    ) -> SimpleSelector {
        if selector.hasPrefix("#") {
            return SimpleSelector(
                tag: nil, className: nil,
                id: String(selector.dropFirst())
            )
        }
        if selector.hasPrefix(".") {
            return SimpleSelector(
                tag: nil, className: String(selector.dropFirst()),
                id: nil
            )
        }
        if let dotIdx = selector.firstIndex(of: ".") {
            let tag = String(selector[..<dotIdx])
            let afterDot = String(
                selector[selector.index(after: dotIdx)...]
            )
            let cls: String
            if let nextDot = afterDot.firstIndex(of: ".") {
                cls = String(afterDot[..<nextDot])
            } else {
                cls = afterDot
            }
            return SimpleSelector(tag: tag, className: cls, id: nil)
        }
        if let hashIdx = selector.firstIndex(of: "#") {
            return SimpleSelector(
                tag: String(selector[..<hashIdx]),
                className: nil,
                id: String(selector[selector.index(after: hashIdx)...])
            )
        }
        return SimpleSelector(tag: selector, className: nil, id: nil)
    }
}
