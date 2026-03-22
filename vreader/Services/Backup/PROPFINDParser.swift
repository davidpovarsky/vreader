// Purpose: Parses WebDAV PROPFIND multi-status XML responses into WebDAVEntry values.
// Extracted from WebDAVClient.swift to keep files under 300 lines.
//
// Key decisions:
// - Uses Foundation XMLParser (no third-party deps).
// - Handles DAV: namespace with various prefix conventions (D:, d:, no prefix)
//   by stripping prefixes and matching local element names.
// - HTTP date formatter uses en_US_POSIX locale for reliable parsing.
//
// @coordinates-with: WebDAVClient.swift

import Foundation

/// Parses WebDAV PROPFIND multi-status XML responses.
///
/// Handles DAV: namespace with various prefix conventions (D:, d:, no prefix).
final class PROPFINDParser: NSObject, XMLParserDelegate {

    private let data: Data
    private var entries: [WebDAVEntry] = []

    // Current parsing state
    private var currentHref: String?
    private var currentContentLength: Int64 = 0
    private var currentLastModified: Date?
    private var currentIsDirectory = false
    private var currentText = ""
    private var inResponse = false
    private var parseError: Error?

    /// HTTP date formatter for getlastmodified values.
    private static let httpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()

    init(data: Data) {
        self.data = data
        super.init()
    }

    func parse() throws -> [WebDAVEntry] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = true
        let success = parser.parse()

        if let error = parseError {
            throw error
        }
        if !success {
            throw WebDAVError.invalidResponse(
                parser.parserError?.localizedDescription ?? "Unknown XML parse error"
            )
        }
        return entries
    }

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        let localName = elementName.components(separatedBy: ":").last ?? elementName
        currentText = ""

        if localName == "response" {
            inResponse = true
            currentHref = nil
            currentContentLength = 0
            currentLastModified = nil
            currentIsDirectory = false
        } else if localName == "collection" && inResponse {
            currentIsDirectory = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let localName = elementName.components(separatedBy: ":").last ?? elementName
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if localName == "href" && inResponse {
            currentHref = trimmed
        } else if localName == "getcontentlength" && inResponse {
            currentContentLength = Int64(trimmed) ?? 0
        } else if localName == "getlastmodified" && inResponse {
            currentLastModified = Self.httpDateFormatter.date(from: trimmed)
        } else if localName == "response" {
            if let href = currentHref {
                entries.append(WebDAVEntry(
                    href: href,
                    contentLength: currentContentLength,
                    lastModified: currentLastModified,
                    isDirectory: currentIsDirectory
                ))
            }
            inResponse = false
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = WebDAVError.invalidResponse(parseError.localizedDescription)
    }
}
