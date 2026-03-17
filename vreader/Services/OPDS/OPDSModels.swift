// Purpose: Data models for OPDS 1.2 catalog feeds.
// Defines Feed, Entry, Link, and supporting types for Atom XML feeds
// with OPDS-specific link relations.
//
// Key decisions:
// - Value types (structs) for immutability and Sendable compliance.
// - Link.rel uses raw strings matching OPDS 1.2 spec URIs.
// - Feed.kind inferred from entry link relations (navigation vs acquisition).
// - All models are Codable for potential persistence of saved catalogs.
//
// @coordinates-with: OPDSParser.swift, OPDSClient.swift, OPDSBrowserView.swift

import Foundation

// MARK: - Feed

/// An OPDS catalog feed parsed from Atom XML.
struct OPDSFeed: Sendable, Equatable {
    /// Feed title from `<title>`.
    let title: String

    /// Feed ID from `<id>`.
    let id: String

    /// Feed-level links (self, next, search, etc.).
    let links: [OPDSLink]

    /// Entries in this feed.
    let entries: [OPDSEntry]

    /// The base URL used to resolve relative URLs.
    let baseURL: URL?

    /// Whether this is a navigation or acquisition feed.
    var kind: OPDSFeedKind {
        // A feed is "acquisition" if any entry has an acquisition link.
        // Otherwise it's navigation.
        let hasAcquisition = entries.contains { entry in
            entry.links.contains { $0.isAcquisition }
        }
        return hasAcquisition ? .acquisition : .navigation
    }

    /// URL for the next page, if paginated.
    var nextPageURL: URL? {
        links.first { $0.rel == "next" }?.resolvedHref(against: baseURL)
    }

    /// OpenSearch description URL, if present.
    var searchURL: URL? {
        links.first { $0.rel == "search" && $0.type?.contains("opensearchdescription") == true }?
            .resolvedHref(against: baseURL)
    }

    /// Deduplicated entries (by id). First occurrence wins.
    static func deduplicated(_ entries: [OPDSEntry]) -> [OPDSEntry] {
        var seen = Set<String>()
        return entries.filter { entry in
            guard !seen.contains(entry.id) else { return false }
            seen.insert(entry.id)
            return true
        }
    }
}

/// Kind of OPDS feed.
enum OPDSFeedKind: String, Sendable, Equatable {
    case navigation
    case acquisition
}

// MARK: - Entry

/// A single entry in an OPDS feed (a book or a navigation category).
struct OPDSEntry: Sendable, Equatable {
    /// Entry title from `<title>`.
    let title: String

    /// Entry ID from `<id>`.
    let id: String

    /// Author name from `<author><name>`.
    let author: String?

    /// Summary/description from `<summary>` or `<content>`.
    let summary: String?

    /// Last updated from `<updated>`.
    let updated: String?

    /// Links associated with this entry.
    let links: [OPDSLink]

    /// Cover image URL (from link with rel containing "image" or "thumbnail").
    func coverURL(against baseURL: URL?) -> URL? {
        let imageLink = links.first {
            $0.rel?.contains("http://opds-spec.org/image") == true ||
            $0.rel?.contains("http://opds-spec.org/image/thumbnail") == true
        }
        return imageLink?.resolvedHref(against: baseURL)
    }

    /// Acquisition links (download links for the book).
    var acquisitionLinks: [OPDSLink] {
        links.filter { $0.isAcquisition }
    }

    /// Navigation link (for browsing into subcategories).
    func navigationURL(against baseURL: URL?) -> URL? {
        let navLink = links.first {
            $0.rel == nil ||
            $0.rel == "subsection" ||
            $0.rel == "http://opds-spec.org/sort/popular" ||
            $0.rel == "http://opds-spec.org/sort/new" ||
            ($0.type?.contains("atom+xml") == true && !$0.isAcquisition)
        }
        return navLink?.resolvedHref(against: baseURL)
    }
}

// MARK: - Link

/// A link element from an OPDS feed.
struct OPDSLink: Sendable, Equatable {
    /// Link relation (rel attribute).
    let rel: String?

    /// Link href (may be relative).
    let href: String

    /// MIME type of the linked resource.
    let type: String?

    /// Title attribute, if present.
    let title: String?

    /// Whether this is an acquisition (download) link.
    var isAcquisition: Bool {
        guard let rel = rel else { return false }
        return rel.hasPrefix("http://opds-spec.org/acquisition")
    }

    /// Human-readable format label derived from MIME type.
    var formatLabel: String? {
        guard let type = type else { return nil }
        if type.contains("epub") { return "EPUB" }
        if type.contains("pdf") { return "PDF" }
        if type.contains("mobi") || type.contains("x-mobipocket") { return "MOBI" }
        return nil
    }

    /// Resolves the href against a base URL. Returns nil if both href and base are invalid.
    func resolvedHref(against baseURL: URL?) -> URL? {
        if let absolute = URL(string: href), absolute.scheme != nil {
            return absolute
        }
        guard let base = baseURL else {
            return URL(string: href)
        }
        return URL(string: href, relativeTo: base)?.absoluteURL
    }
}

// MARK: - Saved Catalog

/// A saved OPDS catalog server entry.
struct OPDSSavedCatalog: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var url: String
    var username: String?
    var password: String?

    init(id: UUID = UUID(), name: String, url: String, username: String? = nil, password: String? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.username = username
        self.password = password
    }
}

// MARK: - Parser Errors

/// Errors from OPDS feed parsing.
enum OPDSParserError: Error, Sendable, Equatable, LocalizedError {
    case invalidXML(String)
    case emptyData
    case networkError(String)
    case httpError(Int)
    case invalidURL(String)

    var errorDescription: String? {
        switch self {
        case .invalidXML(let detail):
            return "Failed to parse OPDS feed: \(detail)"
        case .emptyData:
            return "The server returned an empty response."
        case .networkError(let detail):
            return "Network error: \(detail)"
        case .httpError(let code):
            return "Server returned HTTP \(code)."
        case .invalidURL(let url):
            return "Invalid catalog URL: \(url)"
        }
    }
}
