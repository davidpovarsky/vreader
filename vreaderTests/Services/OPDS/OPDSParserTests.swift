// Purpose: Tests for OPDSParser — OPDS 1.2 Atom XML feed parsing.
// Covers navigation feeds, acquisition feeds, search, pagination,
// metadata extraction, multiple formats, empty feeds, invalid XML,
// relative URL resolution, and deduplication.

import Testing
import Foundation
@testable import vreader

@Suite("OPDSParser")
struct OPDSParserTests {

    // MARK: - Test XML Helpers

    private func xmlData(_ xml: String) -> Data {
        xml.data(using: .utf8)!
    }

    private static let atomNS = "xmlns=\"http://www.w3.org/2005/Atom\""

    /// Wraps entries in a minimal Atom feed.
    private func wrapFeed(
        title: String = "Test Catalog",
        id: String = "urn:test:catalog",
        feedLinks: String = "",
        entries: String = ""
    ) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed \(Self.atomNS)
              xmlns:opds="http://opds-spec.org/2010/catalog">
          <title>\(title)</title>
          <id>\(id)</id>
          \(feedLinks)
          \(entries)
        </feed>
        """
    }

    // MARK: - Navigation Feed

    @Test func parseNavigationFeed_extractsEntries() throws {
        let xml = wrapFeed(
            title: "Root Catalog",
            entries: """
            <entry>
              <title>Popular Books</title>
              <id>urn:popular</id>
              <link rel="subsection" href="/popular" type="application/atom+xml;profile=opds-catalog;kind=acquisition"/>
            </entry>
            <entry>
              <title>New Arrivals</title>
              <id>urn:new</id>
              <link rel="subsection" href="/new" type="application/atom+xml;profile=opds-catalog;kind=acquisition"/>
            </entry>
            """
        )

        let feed = try OPDSParser.parse(data: xmlData(xml))

        #expect(feed.title == "Root Catalog")
        #expect(feed.entries.count == 2)
        #expect(feed.entries[0].title == "Popular Books")
        #expect(feed.entries[1].title == "New Arrivals")
        #expect(feed.kind == .navigation)
    }

    // MARK: - Acquisition Feed

    @Test func parseAcquisitionFeed_extractsDownloadLinks() throws {
        let xml = wrapFeed(entries: """
        <entry>
          <title>Pride and Prejudice</title>
          <id>urn:book:pride</id>
          <link rel="http://opds-spec.org/acquisition/open-access"
                href="https://example.com/pride.epub"
                type="application/epub+zip"/>
        </entry>
        """)

        let feed = try OPDSParser.parse(data: xmlData(xml))

        #expect(feed.kind == .acquisition)
        #expect(feed.entries.count == 1)
        let entry = feed.entries[0]
        #expect(entry.acquisitionLinks.count == 1)
        #expect(entry.acquisitionLinks[0].href == "https://example.com/pride.epub")
        #expect(entry.acquisitionLinks[0].formatLabel == "EPUB")
    }

    // MARK: - Search Feed

    @Test func parseSearchFeed_extractsSearchURL() throws {
        let xml = wrapFeed(
            feedLinks: """
            <link rel="search"
                  href="https://example.com/search.xml"
                  type="application/opensearchdescription+xml"/>
            """
        )

        let feed = try OPDSParser.parse(
            data: xmlData(xml),
            baseURL: URL(string: "https://example.com/")
        )

        #expect(feed.searchURL != nil)
        #expect(feed.searchURL?.absoluteString == "https://example.com/search.xml")
    }

    // MARK: - Pagination

    @Test func parsePagination_extractsNextLink() throws {
        let xml = wrapFeed(
            feedLinks: """
            <link rel="next" href="/catalog?page=2" type="application/atom+xml"/>
            """
        )

        let feed = try OPDSParser.parse(
            data: xmlData(xml),
            baseURL: URL(string: "https://example.com/catalog")
        )

        #expect(feed.nextPageURL != nil)
        #expect(feed.nextPageURL?.absoluteString == "https://example.com/catalog?page=2")
    }

    // MARK: - Entry Metadata

    @Test func parseEntry_extractsMetadata() throws {
        let xml = wrapFeed(entries: """
        <entry>
          <title>War and Peace</title>
          <id>urn:book:war-peace</id>
          <author><name>Leo Tolstoy</name></author>
          <summary>An epic novel about the Napoleonic Wars.</summary>
          <updated>2024-01-15T12:00:00Z</updated>
          <link rel="http://opds-spec.org/image"
                href="https://example.com/covers/war-peace.jpg"
                type="image/jpeg"/>
          <link rel="http://opds-spec.org/acquisition/open-access"
                href="https://example.com/war-peace.epub"
                type="application/epub+zip"/>
        </entry>
        """)

        let feed = try OPDSParser.parse(
            data: xmlData(xml),
            baseURL: URL(string: "https://example.com/")
        )

        let entry = feed.entries[0]
        #expect(entry.title == "War and Peace")
        #expect(entry.id == "urn:book:war-peace")
        #expect(entry.author == "Leo Tolstoy")
        #expect(entry.summary == "An epic novel about the Napoleonic Wars.")
        #expect(entry.updated == "2024-01-15T12:00:00Z")
        #expect(entry.coverURL(against: feed.baseURL)?.absoluteString == "https://example.com/covers/war-peace.jpg")
    }

    // MARK: - Multiple Formats

    @Test func parseEntry_multipleFormats() throws {
        let xml = wrapFeed(entries: """
        <entry>
          <title>Multi-Format Book</title>
          <id>urn:book:multi</id>
          <link rel="http://opds-spec.org/acquisition/open-access"
                href="https://example.com/book.epub"
                type="application/epub+zip"/>
          <link rel="http://opds-spec.org/acquisition/open-access"
                href="https://example.com/book.pdf"
                type="application/pdf"/>
        </entry>
        """)

        let feed = try OPDSParser.parse(data: xmlData(xml))
        let entry = feed.entries[0]

        #expect(entry.acquisitionLinks.count == 2)
        #expect(entry.acquisitionLinks[0].formatLabel == "EPUB")
        #expect(entry.acquisitionLinks[1].formatLabel == "PDF")
    }

    // MARK: - Empty Feed

    @Test func parseFeed_emptyFeed_returnsEmpty() throws {
        let xml = wrapFeed()

        let feed = try OPDSParser.parse(data: xmlData(xml))

        #expect(feed.entries.isEmpty)
        #expect(feed.title == "Test Catalog")
        #expect(feed.kind == .navigation)
    }

    // MARK: - Invalid XML

    @Test func parseFeed_invalidXML_returnsError() {
        let badXML = "<feed><broken"

        #expect(throws: OPDSParserError.self) {
            try OPDSParser.parse(data: xmlData(badXML))
        }
    }

    @Test func parseFeed_emptyData_returnsError() {
        #expect(throws: OPDSParserError.emptyData) {
            try OPDSParser.parse(data: Data())
        }
    }

    // MARK: - Relative URL Resolution

    @Test func parseEntry_relativeURL_resolved() throws {
        let xml = wrapFeed(entries: """
        <entry>
          <title>Relative Book</title>
          <id>urn:book:relative</id>
          <link rel="http://opds-spec.org/acquisition/open-access"
                href="/books/relative.epub"
                type="application/epub+zip"/>
        </entry>
        """)

        let baseURL = URL(string: "https://catalog.example.com/opds")!
        let feed = try OPDSParser.parse(data: xmlData(xml), baseURL: baseURL)

        let entry = feed.entries[0]
        let resolved = entry.acquisitionLinks[0].resolvedHref(against: feed.baseURL)
        #expect(resolved?.absoluteString == "https://catalog.example.com/books/relative.epub")
    }

    // MARK: - Deduplication

    @Test func parseFeed_duplicateEntries_deduplicated() throws {
        let xml = wrapFeed(entries: """
        <entry>
          <title>First Instance</title>
          <id>urn:book:dup</id>
          <link rel="http://opds-spec.org/acquisition/open-access"
                href="https://example.com/first.epub"
                type="application/epub+zip"/>
        </entry>
        <entry>
          <title>Second Instance</title>
          <id>urn:book:dup</id>
          <link rel="http://opds-spec.org/acquisition/open-access"
                href="https://example.com/second.epub"
                type="application/epub+zip"/>
        </entry>
        """)

        let feed = try OPDSParser.parse(data: xmlData(xml))

        // Should be deduplicated to 1 entry (first wins)
        #expect(feed.entries.count == 1)
        #expect(feed.entries[0].title == "First Instance")
    }

    // MARK: - Additional Edge Cases

    @Test func parseLink_formatLabel_mobi() {
        let link = OPDSLink(
            rel: "http://opds-spec.org/acquisition",
            href: "https://example.com/book.mobi",
            type: "application/x-mobipocket-ebook",
            title: nil
        )
        #expect(link.formatLabel == "MOBI")
    }

    @Test func parseLink_formatLabel_unknown_returnsNil() {
        let link = OPDSLink(
            rel: "http://opds-spec.org/acquisition",
            href: "https://example.com/book.cbz",
            type: "application/x-cbz",
            title: nil
        )
        #expect(link.formatLabel == nil)
    }

    @Test func parseLink_noType_formatLabel_nil() {
        let link = OPDSLink(rel: nil, href: "test", type: nil, title: nil)
        #expect(link.formatLabel == nil)
    }

    @Test func parseLink_isAcquisition_variants() {
        let open = OPDSLink(rel: "http://opds-spec.org/acquisition/open-access", href: "", type: nil, title: nil)
        let buy = OPDSLink(rel: "http://opds-spec.org/acquisition/buy", href: "", type: nil, title: nil)
        let plain = OPDSLink(rel: "http://opds-spec.org/acquisition", href: "", type: nil, title: nil)
        let notAcq = OPDSLink(rel: "subsection", href: "", type: nil, title: nil)
        let nilRel = OPDSLink(rel: nil, href: "", type: nil, title: nil)

        #expect(open.isAcquisition == true)
        #expect(buy.isAcquisition == true)
        #expect(plain.isAcquisition == true)
        #expect(notAcq.isAcquisition == false)
        #expect(nilRel.isAcquisition == false)
    }

    @Test func resolvedHref_absoluteURL_returnsAsIs() {
        let link = OPDSLink(rel: nil, href: "https://other.com/book.epub", type: nil, title: nil)
        let resolved = link.resolvedHref(against: URL(string: "https://base.com/"))
        #expect(resolved?.absoluteString == "https://other.com/book.epub")
    }

    @Test func resolvedHref_relativeURL_noBase_attemptsRawParse() {
        let link = OPDSLink(rel: nil, href: "/books/test.epub", type: nil, title: nil)
        let resolved = link.resolvedHref(against: nil)
        // Without a base URL, a path-only string creates an invalid URL
        #expect(resolved?.absoluteString == "/books/test.epub")
    }

    @Test func feedKind_noEntries_isNavigation() {
        let feed = OPDSFeed(title: "", id: "", links: [], entries: [], baseURL: nil)
        #expect(feed.kind == .navigation)
    }

    @Test func entry_coverURL_thumbnail() throws {
        let entry = OPDSEntry(
            title: "Test",
            id: "test",
            author: nil,
            summary: nil,
            updated: nil,
            links: [
                OPDSLink(
                    rel: "http://opds-spec.org/image/thumbnail",
                    href: "/thumb.jpg",
                    type: "image/jpeg",
                    title: nil
                )
            ]
        )
        let base = URL(string: "https://example.com")!
        let coverURL = entry.coverURL(against: base)
        #expect(coverURL?.absoluteString == "https://example.com/thumb.jpg")
    }

    @Test func parseFeed_unicodeContent() throws {
        let xml = wrapFeed(
            title: "Chinese Catalog",
            entries: """
            <entry>
              <title>三国演义</title>
              <id>urn:book:sanguo</id>
              <author><name>罗贯中</name></author>
              <summary>中国四大名著之一</summary>
              <link rel="http://opds-spec.org/acquisition/open-access"
                    href="https://example.com/sanguo.epub"
                    type="application/epub+zip"/>
            </entry>
            """
        )

        let feed = try OPDSParser.parse(data: xmlData(xml))
        #expect(feed.title == "Chinese Catalog")
        #expect(feed.entries[0].title == "三国演义")
        #expect(feed.entries[0].author == "罗贯中")
        #expect(feed.entries[0].summary == "中国四大名著之一")
    }

    @Test func savedCatalog_codableRoundTrip() throws {
        let catalog = OPDSSavedCatalog(
            name: "My Library",
            url: "https://opds.example.com/catalog",
            username: "user",
            password: "pass"
        )
        let data = try JSONEncoder().encode(catalog)
        let decoded = try JSONDecoder().decode(OPDSSavedCatalog.self, from: data)
        #expect(decoded.name == catalog.name)
        #expect(decoded.url == catalog.url)
        #expect(decoded.username == catalog.username)
        #expect(decoded.password == catalog.password)
        #expect(decoded.id == catalog.id)
    }

    @Test func parseFeed_feedLevelId() throws {
        let xml = wrapFeed(id: "urn:uuid:12345")
        let feed = try OPDSParser.parse(data: xmlData(xml))
        #expect(feed.id == "urn:uuid:12345")
    }

    @Test func deduplication_preservesOrder() {
        let entries = [
            OPDSEntry(title: "A", id: "1", author: nil, summary: nil, updated: nil, links: []),
            OPDSEntry(title: "B", id: "2", author: nil, summary: nil, updated: nil, links: []),
            OPDSEntry(title: "C", id: "1", author: nil, summary: nil, updated: nil, links: []),
            OPDSEntry(title: "D", id: "3", author: nil, summary: nil, updated: nil, links: []),
        ]
        let deduped = OPDSFeed.deduplicated(entries)
        #expect(deduped.count == 3)
        #expect(deduped.map(\.title) == ["A", "B", "D"])
    }

    @Test func parseEntry_contentElement_asSummary() throws {
        let xml = wrapFeed(entries: """
        <entry>
          <title>Content Test</title>
          <id>urn:content</id>
          <content>This uses content instead of summary.</content>
        </entry>
        """)

        let feed = try OPDSParser.parse(data: xmlData(xml))
        #expect(feed.entries[0].summary == "This uses content instead of summary.")
    }
}
