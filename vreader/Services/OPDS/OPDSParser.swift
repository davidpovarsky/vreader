// Purpose: XMLParser-based parser for OPDS 1.2 Atom XML feeds.
// Extracts feed metadata, entries, and links from standard OPDS catalogs.
//
// Key decisions:
// - Uses Foundation XMLParser (no external dependencies).
// - Delegate pattern with NSObject subclass for XMLParserDelegate.
// - Supports navigation feeds, acquisition feeds, and search links.
// - Resolves relative URLs against the feed's base URL.
// - Deduplicates entries by ID.
//
// @coordinates-with: OPDSModels.swift, OPDSClient.swift

import Foundation

/// Parses OPDS 1.2 Atom XML feeds into OPDSFeed models.
enum OPDSParser {

    /// Parses XML data into an OPDSFeed.
    ///
    /// - Parameters:
    ///   - data: Raw XML data of the Atom feed.
    ///   - baseURL: Base URL for resolving relative links.
    /// - Returns: Parsed OPDSFeed.
    /// - Throws: OPDSParserError if the XML is invalid or empty.
    static func parse(data: Data, baseURL: URL? = nil) throws -> OPDSFeed {
        guard !data.isEmpty else {
            throw OPDSParserError.emptyData
        }

        let delegate = OPDSXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            let errorDesc = parser.parserError?.localizedDescription ?? "Unknown XML error"
            throw OPDSParserError.invalidXML(errorDesc)
        }

        if let delegateError = delegate.parseError {
            throw delegateError
        }

        let deduped = OPDSFeed.deduplicated(delegate.entries)

        return OPDSFeed(
            title: delegate.feedTitle ?? "",
            id: delegate.feedId ?? "",
            links: delegate.feedLinks,
            entries: deduped,
            baseURL: baseURL
        )
    }
}

// MARK: - XML Delegate

/// XMLParserDelegate that builds OPDSFeed components from SAX events.
private final class OPDSXMLDelegate: NSObject, XMLParserDelegate, @unchecked Sendable {

    // Feed-level
    var feedTitle: String?
    var feedId: String?
    var feedLinks: [OPDSLink] = []
    var entries: [OPDSEntry] = []
    var parseError: OPDSParserError?

    // Current entry being built
    private var currentEntry: EntryBuilder?
    private var insideEntry = false
    private var insideAuthor = false
    private var currentElement = ""
    private var currentText = ""

    // Nested element tracking
    private struct EntryBuilder {
        var title = ""
        var id = ""
        var author: String?
        var summary: String?
        var updated: String?
        var links: [OPDSLink] = []
    }

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        currentElement = elementName
        currentText = ""

        switch elementName {
        case "entry":
            insideEntry = true
            currentEntry = EntryBuilder()

        case "link":
            let link = OPDSLink(
                rel: attributes["rel"],
                href: attributes["href"] ?? "",
                type: attributes["type"],
                title: attributes["title"]
            )
            if insideEntry {
                currentEntry?.links.append(link)
            } else {
                feedLinks.append(link)
            }

        case "author":
            insideAuthor = true

        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "entry":
            if let builder = currentEntry {
                let entry = OPDSEntry(
                    title: builder.title,
                    id: builder.id,
                    author: builder.author,
                    summary: builder.summary,
                    updated: builder.updated,
                    links: builder.links
                )
                entries.append(entry)
            }
            currentEntry = nil
            insideEntry = false

        case "title":
            if insideEntry {
                currentEntry?.title = text
            } else {
                feedTitle = text
            }

        case "id":
            if insideEntry {
                currentEntry?.id = text
            } else {
                feedId = text
            }

        case "name":
            if insideAuthor && insideEntry {
                currentEntry?.author = text
            }

        case "summary", "content":
            if insideEntry {
                currentEntry?.summary = text
            }

        case "updated":
            if insideEntry {
                currentEntry?.updated = text
            }

        case "author":
            insideAuthor = false

        default:
            break
        }

        currentElement = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = .invalidXML(parseError.localizedDescription)
    }
}
