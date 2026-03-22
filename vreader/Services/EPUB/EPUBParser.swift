// Purpose: Production EPUB parser. Selectively extracts EPUB entries on demand,
// parses container.xml and OPF for metadata/spine, and serves content.
//
// Key decisions:
// - Selective extraction: only container.xml + OPF + first chapter + CSS/fonts on open.
// - On-demand: additional chapters extracted when contentForSpineItem() is called.
// - Persistent cache: extracted files in Caches/EPUBCache/{key}/ survive app restart.
//   iOS purges Caches/ under storage pressure automatically.
// - ZIPReader uses memory-mapped Data (not heap copy) for random access.
// - Parses container.xml to find the OPF rootfile path.
// - Parses OPF using XMLParser for metadata, manifest, and spine.
// - Validates all resolved paths stay within the cache directory.
// - Actor-isolated for thread safety.
//
// @coordinates-with: EPUBParserProtocol.swift, ZIPReader.swift, EPUBTypes.swift

import Foundation

private extension URL {
    /// File size in bytes, or 0 if unavailable. Used for cache key generation.
    var fileSizeOrZero: Int64 {
        (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
    }
}

/// Production implementation of EPUBParserProtocol.
/// Extracts the EPUB to a temporary directory and parses its structure.
actor EPUBParser: EPUBParserProtocol {

    private var extractedDir: URL?
    private var opfDir: URL?
    private var _isOpen = false

    var isOpen: Bool { _isOpen }

    deinit {
        // PERF: No cleanup needed — cache directory is persistent.
        // iOS purges Caches/ under storage pressure automatically.
    }

    /// Cached ZIP reader for on-demand entry extraction.
    private var zipReader: ZIPReader?

    func open(url: URL) async throws -> EPUBMetadata {
        guard !_isOpen else { throw EPUBParserError.alreadyOpen }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw EPUBParserError.fileNotFound(url.lastPathComponent)
        }

        // PERF: Use persistent cache directory keyed by file size + name hash.
        // If cache exists from a previous session, skip extraction entirely.
        let cacheKey = "\(url.lastPathComponent)-\(url.fileSizeOrZero)"
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("EPUBCache", isDirectory: true)
            .appendingPathComponent(cacheKey, isDirectory: true)
        let fm = FileManager.default

        // Check if we have a valid cache (container.xml exists = cache hit)
        let cachedContainer = cacheDir
            .appendingPathComponent("META-INF")
            .appendingPathComponent("container.xml")
        let isCacheHit = fm.fileExists(atPath: cachedContainer.path)

        let zip: ZIPReader
        if isCacheHit {
            // Cache hit — reuse extracted files, still need ZIP for on-demand entries
            zip = try ZIPReader(fileURL: url)
        } else {
            // Cache miss — selective extraction (NOT extractAll)
            try fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            zip = try ZIPReader(fileURL: url)

            // Extract only META-INF/container.xml first
            _ = try await zip.extractEntry(path: "META-INF/container.xml", to: cacheDir)
        }

        zipReader = zip
        extractedDir = cacheDir

        // Parse container.xml to find OPF path
        let containerData = try Data(contentsOf: cachedContainer.path == cachedContainer.path ? cachedContainer : cacheDir.appendingPathComponent("META-INF/container.xml"))
        let opfRelPath = try Self.parseContainerXML(containerData)

        // Extract OPF if not cached
        let opfURL = cacheDir.appendingPathComponent(opfRelPath)
        if !fm.fileExists(atPath: opfURL.path) {
            _ = try await zip.extractEntry(path: opfRelPath, to: cacheDir)
        }

        try Self.validateContainment(child: opfURL, parent: cacheDir)
        opfDir = opfURL.deletingLastPathComponent()

        guard fm.fileExists(atPath: opfURL.path) else {
            throw EPUBParserError.invalidFormat("OPF file not found")
        }

        // Parse OPF
        let opfData = try Data(contentsOf: opfURL)
        let result = try Self.parseOPF(opfData)

        // Extract first chapter + shared resources (CSS, fonts) for immediate display
        let opfDirRel = (opfRelPath as NSString).deletingLastPathComponent
        if let firstSpine = result.metadata.spineItems.first {
            let chapterPath = opfDirRel.isEmpty ? firstSpine.href : "\(opfDirRel)/\(firstSpine.href)"
            if !fm.fileExists(atPath: cacheDir.appendingPathComponent(chapterPath).path) {
                _ = try? await zip.extractEntry(path: chapterPath, to: cacheDir)
            }
        }
        // Extract CSS/font files from ZIP for first chapter rendering
        let styleExtensions: Set<String> = ["css", "ttf", "otf", "woff", "woff2"]
        for entry in await zip.listEntries() {
            let ext = (entry.path as NSString).pathExtension.lowercased()
            guard styleExtensions.contains(ext), !entry.isDirectory else { continue }
            if !fm.fileExists(atPath: cacheDir.appendingPathComponent(entry.path).path) {
                _ = try? await zip.extractEntry(path: entry.path, to: cacheDir)
            }
        }

        // Parse nav/NCX for real TOC titles (bug #74)
        // Extract nav/ncx if needed
        if let navHref = result.navHref {
            let navPath = opfDirRel.isEmpty ? navHref : "\(opfDirRel)/\(navHref)"
            if !fm.fileExists(atPath: cacheDir.appendingPathComponent(navPath).path) {
                _ = try? await zip.extractEntry(path: navPath, to: cacheDir)
            }
        }
        if let ncxHref = result.ncxHref {
            let ncxPath = opfDirRel.isEmpty ? ncxHref : "\(opfDirRel)/\(ncxHref)"
            if !fm.fileExists(atPath: cacheDir.appendingPathComponent(ncxPath).path) {
                _ = try? await zip.extractEntry(path: ncxPath, to: cacheDir)
            }
        }

        let opfDirURL = opfURL.deletingLastPathComponent()
        var metadata = result.metadata
        let navTitles = Self.extractNavTitles(
            navHref: result.navHref,
            ncxHref: result.ncxHref,
            opfDir: opfDirURL
        )
        if !navTitles.isEmpty {
            metadata = metadata.withResolvedTitles(navTitles)
        }

        _isOpen = true
        return metadata
    }

    func close() async {
        _isOpen = false
        opfDir = nil
        zipReader = nil
        // PERF: Do NOT delete cache directory — persistent cache for instant reopen.
        // Cache is in Caches/ directory, so iOS can purge it under storage pressure.
        extractedDir = nil
    }

    func contentForSpineItem(href: String) async throws -> String {
        guard _isOpen, let opfDir, let extractedDir else { throw EPUBParserError.notOpen }

        // Validate resolved path stays within extracted directory
        let fileURL = opfDir.appendingPathComponent(href).standardizedFileURL
        try Self.validateContainment(child: fileURL, parent: extractedDir)

        // PERF: On-demand extraction — extract from ZIP if not already cached
        if !FileManager.default.fileExists(atPath: fileURL.path), let zip = zipReader {
            let relPath = fileURL.path.replacingOccurrences(
                of: extractedDir.standardizedFileURL.path + "/", with: ""
            )
            _ = try? await zip.extractEntry(path: relPath, to: extractedDir)
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw EPUBParserError.resourceNotFound(href)
        }

        // Try UTF-8 first, fall back to Latin-1
        let data = try Data(contentsOf: fileURL)
        if let content = String(data: data, encoding: .utf8) {
            return content
        }
        if let content = String(data: data, encoding: .isoLatin1) {
            return content
        }
        throw EPUBParserError.parsingFailed("Unable to decode content encoding for \(href)")
    }

    func resourceBaseURL() async throws -> URL {
        guard _isOpen, let opfDir else { throw EPUBParserError.notOpen }
        return opfDir
    }

    func extractedRootURL() async throws -> URL {
        guard _isOpen, let extractedDir else { throw EPUBParserError.notOpen }
        return extractedDir
    }

    // MARK: - Path Validation

    /// Ensures the child URL is contained within the parent directory.
    /// Appends trailing "/" to parent to prevent sibling-prefix bypass
    /// (e.g., "/tmp/root-evil" matching "/tmp/root").
    private static func validateContainment(child: URL, parent: URL) throws {
        let childPath = child.standardizedFileURL.path
        var parentPath = parent.standardizedFileURL.path
        if !parentPath.hasSuffix("/") { parentPath += "/" }
        guard childPath.hasPrefix(parentPath) else {
            throw EPUBParserError.invalidFormat("Path traversal detected")
        }
    }

    // MARK: - Nav / NCX Title Extraction (bug #74)

    /// Extracts chapter titles from EPUB 3 nav.xhtml or EPUB 2 toc.ncx.
    /// Returns a mapping of href → title. Empty if neither is available.
    private static func extractNavTitles(
        navHref: String?,
        ncxHref: String?,
        opfDir: URL
    ) -> [String: String] {
        // EPUB 3: nav.xhtml
        if let href = navHref {
            let url = opfDir.appendingPathComponent(href)
            if let data = try? Data(contentsOf: url) {
                let titles = parseNavXHTML(data)
                if !titles.isEmpty { return titles }
            }
        }
        // EPUB 2: toc.ncx
        if let href = ncxHref {
            let url = opfDir.appendingPathComponent(href)
            if let data = try? Data(contentsOf: url) {
                let titles = parseNCX(data)
                if !titles.isEmpty { return titles }
            }
        }
        return [:]
    }

    /// Parses EPUB 3 nav.xhtml for TOC entries.
    /// Extracts <a href="...">title</a> from the <nav epub:type="toc"> element.
    private static func parseNavXHTML(_ data: Data) -> [String: String] {
        let delegate = NavXHTMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        _ = parser.parse()
        return delegate.titles
    }

    /// Parses EPUB 2 toc.ncx for TOC entries.
    /// Extracts navLabel/text + content@src from navPoint elements.
    private static func parseNCX(_ data: Data) -> [String: String] {
        let delegate = NCXDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        _ = parser.parse()
        return delegate.titles
    }

    // MARK: - container.xml Parsing

    /// Extracts the rootfile full-path from META-INF/container.xml.
    private static func parseContainerXML(_ data: Data) throws -> String {
        let delegate = ContainerXMLDelegate()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = delegate
        guard xmlParser.parse() else {
            let errorDesc = xmlParser.parserError?.localizedDescription ?? "Unknown XML error"
            throw EPUBParserError.parsingFailed("container.xml: \(errorDesc)")
        }
        guard let rootfile = delegate.rootfilePath else {
            throw EPUBParserError.invalidFormat("No rootfile found in container.xml")
        }
        return rootfile
    }

    // MARK: - OPF Parsing

    struct OPFResult {
        let metadata: EPUBMetadata
        /// Manifest href of the EPUB 3 nav document (properties="nav"), if any.
        let navHref: String?
        /// Manifest href of the EPUB 2 NCX file (spine toc attribute → manifest), if any.
        let ncxHref: String?
    }

    private static func parseOPF(_ data: Data) throws -> OPFResult {
        let delegate = OPFXMLDelegate()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = delegate
        guard xmlParser.parse() else {
            let errorDesc = xmlParser.parserError?.localizedDescription ?? "Unknown XML error"
            throw EPUBParserError.parsingFailed("OPF: \(errorDesc)")
        }

        let title = delegate.title ?? "Untitled"
        let author = delegate.author

        // Build spine items from spine references + manifest
        var spineItems: [EPUBSpineItem] = []
        for (index, idref) in delegate.spineIdrefs.enumerated() {
            guard let href = delegate.manifest[idref] else { continue }
            let itemTitle = delegate.navTitles[href]
            spineItems.append(EPUBSpineItem(
                id: idref,
                href: href,
                title: itemTitle ?? "Section \(index + 1)",
                index: index
            ))
        }

        guard !spineItems.isEmpty else {
            throw EPUBParserError.parsingFailed("No spine items found in OPF")
        }

        let metadata = EPUBMetadata(
            title: title,
            author: author,
            language: delegate.language,
            readingDirection: delegate.direction ?? .ltr,
            layout: delegate.layout ?? .reflowable,
            spineItems: spineItems
        )

        // Detect nav/NCX references for TOC title extraction (bug #74)
        let navHref = delegate.navItemHref
        let ncxHref: String?
        if let tocId = delegate.spineTocId, let href = delegate.manifest[tocId] {
            ncxHref = href
        } else {
            ncxHref = nil
        }

        return OPFResult(metadata: metadata, navHref: navHref, ncxHref: ncxHref)
    }
}

// MARK: - XML Delegates

/// Parses container.xml to extract the OPF rootfile path.
private final class ContainerXMLDelegate: NSObject, XMLParserDelegate, @unchecked Sendable {
    var rootfilePath: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        if elementName == "rootfile" || elementName.hasSuffix(":rootfile") {
            rootfilePath = attributes["full-path"]
        }
    }
}

/// Parses OPF (Open Packaging Format) for metadata, manifest, and spine.
private final class OPFXMLDelegate: NSObject, XMLParserDelegate, @unchecked Sendable {
    var title: String?
    var author: String?
    var language: String?
    var direction: ReadingDirection?
    var layout: EPUBLayout?
    /// manifest: id -> href
    var manifest: [String: String] = [:]
    /// Ordered spine item idrefs
    var spineIdrefs: [String] = []
    /// nav titles by href (populated if NCX/nav is found)
    var navTitles: [String: String] = [:]
    /// EPUB 3 nav document href (manifest item with properties="nav"). (bug #74)
    var navItemHref: String?
    /// EPUB 2 NCX id from spine toc attribute. (bug #74)
    var spineTocId: String?

    private var currentElement = ""
    private var currentText = ""
    private var inMetadata = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        let local = elementName.components(separatedBy: ":").last ?? elementName
        currentElement = local
        currentText = ""

        switch local {
        case "metadata":
            inMetadata = true

        case "item":
            if let id = attributes["id"], let href = attributes["href"] {
                manifest[id] = href
                // EPUB 3: detect nav document (bug #74)
                if let props = attributes["properties"], props.contains("nav") {
                    navItemHref = href
                }
            }

        case "itemref":
            if let idref = attributes["idref"] {
                spineIdrefs.append(idref)
            }

        case "spine":
            if let dir = attributes["page-progression-direction"] {
                direction = ReadingDirection(rawValue: dir)
            }
            // EPUB 2: NCX toc reference (bug #74)
            if let tocId = attributes["toc"] {
                spineTocId = tocId
            }

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
        let local = elementName.components(separatedBy: ":").last ?? elementName
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if inMetadata {
            switch local {
            case "title" where title == nil && !trimmed.isEmpty:
                title = trimmed
            case "creator" where author == nil && !trimmed.isEmpty:
                author = trimmed
            case "language" where language == nil && !trimmed.isEmpty:
                language = trimmed
            case "metadata":
                inMetadata = false
            default:
                break
            }
        }

        currentText = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }
}

// MARK: - EPUB 3 Nav XHTML Delegate (bug #74)

/// Parses nav.xhtml to extract <a> elements inside <nav epub:type="toc">.
private final class NavXHTMLDelegate: NSObject, XMLParserDelegate, @unchecked Sendable {
    var titles: [String: String] = [:]

    private var inTocNav = false
    private var currentHref: String?
    private var currentText = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        let local = elementName.components(separatedBy: ":").last ?? elementName
        if local == "nav" {
            let epubType = attributes["epub:type"] ?? attributes["type"] ?? ""
            if epubType.contains("toc") {
                inTocNav = true
            }
        }
        if inTocNav && local == "a" {
            currentHref = attributes["href"]
            currentText = ""
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        let local = elementName.components(separatedBy: ":").last ?? elementName
        if local == "nav" {
            inTocNav = false
        }
        if inTocNav && local == "a" {
            let title = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if let href = currentHref, !title.isEmpty {
                // Strip fragment identifier for matching against spine hrefs
                let baseHref = href.components(separatedBy: "#").first ?? href
                titles[baseHref] = title
            }
            currentHref = nil
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }
}

// MARK: - EPUB 2 NCX Delegate (bug #74)

/// Parses toc.ncx to extract navPoint > navLabel > text + content@src.
private final class NCXDelegate: NSObject, XMLParserDelegate, @unchecked Sendable {
    var titles: [String: String] = [:]

    private var inNavPoint = false
    private var inNavLabel = false
    private var currentSrc: String?
    private var currentText = ""
    private var pendingTitle: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        let local = elementName.components(separatedBy: ":").last ?? elementName
        switch local {
        case "navPoint":
            inNavPoint = true
            pendingTitle = nil
            currentSrc = nil
        case "navLabel":
            if inNavPoint { inNavLabel = true; currentText = "" }
        case "text":
            if inNavLabel { currentText = "" }
        case "content":
            if inNavPoint, let src = attributes["src"] {
                currentSrc = src.components(separatedBy: "#").first ?? src
            }
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
        let local = elementName.components(separatedBy: ":").last ?? elementName
        switch local {
        case "text":
            if inNavLabel {
                pendingTitle = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        case "navLabel":
            inNavLabel = false
        case "navPoint":
            if let title = pendingTitle, let src = currentSrc, !title.isEmpty {
                titles[src] = title
            }
            inNavPoint = false
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }
}
