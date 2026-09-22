// Purpose: Self-contained HebrewBooks catalog + PDF transport for HomeSource.
//
// Source:
// Otzaria publishes the HebrewBooks metadata it uses on desktop as a compact
// Zstandard-compressed SQLite database. VReader consumes that public catalog
// directly, caches it in Application Support, and reads ONLY the
// `hebrew_books` table.
//
// Isolation / merge policy:
// - No persistence schema changes.
// - No changes to the upstream OPDS client.
// - No changes to the PDF reader.
// - The only project-level additions are libzstd (SPM) + system sqlite3.
// - All catalog/update/download behavior lives in Views/HomeSource.
//
// Catalog release:
// https://github.com/Otzaria/otzar-HB_catalog/releases/latest
//
// PDF transport uses HebrewBooks' own direct download endpoint. The user has
// confirmed permission from the HebrewBooks developers for this integration.

import Foundation
import SQLite3
import libzstd

struct HebrewBooksCatalogBook: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let author: String?
    let printingPlace: String?
    let printingYear: String?
    let topics: String

    var stableCoverKey: String { "hb:\(id)" }

    var metadataLine: String? {
        let parts = [printingPlace, printingYear]
            .compactMap { value -> String? in
                guard let value else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

actor HebrewBooksCatalogService {
    static let shared = HebrewBooksCatalogService()

    static let releaseAPIURL = URL(
        string: "https://api.github.com/repos/Otzaria/otzar-HB_catalog/releases/latest"
    )!
    static let databaseAssetName = "otzar-HB_catalog.db.zst"

    // HebrewBooks' direct public PDF endpoint. Keep PDF delivery independent
    // from the Otzaria catalog host: Otzaria supplies metadata only.
    private static let pdfDownloadURL =
        "https://download.hebrewbooks.org/downloadhandler.ashx"

    private static let cachedReleaseTagKey =
        "homeSource.hebrewBooks.cachedReleaseTag"
    private static let lastUpdateCheckKey =
        "homeSource.hebrewBooks.lastUpdateCheck"

    private static let updateCheckInterval: TimeInterval = 6 * 60 * 60
    private static let maximumUncompressedCatalogBytes = 512 * 1024 * 1024

    private let fileManager = FileManager.default
    private let defaults = UserDefaults.standard

    private init() {}

    // MARK: - Public catalog API

    func databaseExists() -> Bool {
        fileManager.fileExists(atPath: databaseURL.path)
    }

    func cachedReleaseTag() -> String? {
        defaults.string(forKey: Self.cachedReleaseTagKey)
    }

    /// Ensures a readable local database exists. If a database already exists
    /// this does not delay the first presentation for a network version check.
    func installCatalogIfMissing() async throws {
        guard !databaseExists() else { return }
        _ = try await refreshCatalog(force: true)
    }

    /// Checks the latest GitHub release and replaces the local DB only when the
    /// tag changed. Pull-to-refresh passes `force: true`; normal launches are
    /// rate-limited so the catalog screen remains instant when cached.
    @discardableResult
    func refreshCatalog(force: Bool = false) async throws -> Bool {
        let now = Date()

        if !force,
           databaseExists(),
           let last = defaults.object(forKey: Self.lastUpdateCheckKey) as? Date,
           now.timeIntervalSince(last) < Self.updateCheckInterval {
            return false
        }

        let release = try await fetchLatestRelease()
        defaults.set(now, forKey: Self.lastUpdateCheckKey)

        if databaseExists(),
           defaults.string(forKey: Self.cachedReleaseTagKey) == release.tagName {
            return false
        }

        guard let asset = release.assets.first(where: {
            $0.name == Self.databaseAssetName
        }), let assetURL = URL(string: asset.downloadURL) else {
            throw HebrewBooksCatalogError.catalogAssetMissing
        }

        let compressed = try await fetchData(
            from: assetURL,
            headers: [:]
        )
        let databaseBytes = try decompressCatalog(compressed)
        try installDatabaseAtomically(databaseBytes)

        defaults.set(release.tagName, forKey: Self.cachedReleaseTagKey)
        return true
    }

    func countBooks() throws -> Int {
        try withReadOnlyDatabase { db in
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(
                db,
                "SELECT COUNT(*) FROM hebrew_books",
                -1,
                &statement,
                nil
            ) == SQLITE_OK else {
                throw sqliteError(db)
            }

            guard sqlite3_step(statement) == SQLITE_ROW else {
                throw sqliteError(db)
            }
            return Int(sqlite3_column_int64(statement, 0))
        }
    }

    func books(
        matching rawQuery: String,
        limit: Int,
        offset: Int
    ) throws -> [HebrewBooksCatalogBook] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeLimit = max(1, min(limit, 250))
        let safeOffset = max(0, offset)

        return try withReadOnlyDatabase { db in
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            let sql: String
            if query.isEmpty {
                sql = """
                SELECT id_book, title, author, printing_place, printing_year,
                       pub_date, tags
                FROM hebrew_books
                ORDER BY title COLLATE NOCASE
                LIMIT ? OFFSET ?
                """
            } else {
                sql = """
                SELECT id_book, title, author, printing_place, printing_year,
                       pub_date, tags
                FROM hebrew_books
                WHERE title LIKE ?
                   OR author LIKE ?
                   OR tags LIKE ?
                   OR printing_place LIKE ?
                   OR printing_year LIKE ?
                ORDER BY
                    CASE WHEN title LIKE ? THEN 0 ELSE 1 END,
                    title COLLATE NOCASE
                LIMIT ? OFFSET ?
                """
            }

            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
                  let statement else {
                throw sqliteError(db)
            }

            if query.isEmpty {
                sqlite3_bind_int(statement, 1, Int32(safeLimit))
                sqlite3_bind_int(statement, 2, Int32(safeOffset))
            } else {
                let contains = "%\(query)%"
                let prefix = "\(query)%"

                bindText(contains, to: statement, index: 1)
                bindText(contains, to: statement, index: 2)
                bindText(contains, to: statement, index: 3)
                bindText(contains, to: statement, index: 4)
                bindText(contains, to: statement, index: 5)
                bindText(prefix, to: statement, index: 6)
                sqlite3_bind_int(statement, 7, Int32(safeLimit))
                sqlite3_bind_int(statement, 8, Int32(safeOffset))
            }

            var output: [HebrewBooksCatalogBook] = []
            output.reserveCapacity(safeLimit)

            while true {
                switch sqlite3_step(statement) {
                case SQLITE_ROW:
                    let id = Int(sqlite3_column_int64(statement, 0))
                    let title = columnText(statement, index: 1) ?? ""
                    let author = normalized(columnText(statement, index: 2))
                    let place = normalized(columnText(statement, index: 3))
                    let printingYear = normalized(columnText(statement, index: 4))
                    let pubDate = normalized(columnText(statement, index: 5))
                    let topics = normalizedTopics(columnText(statement, index: 6))

                    output.append(
                        HebrewBooksCatalogBook(
                            id: id,
                            title: title,
                            author: author,
                            printingPlace: place,
                            printingYear: printingYear ?? pubDate,
                            topics: topics
                        )
                    )

                case SQLITE_DONE:
                    return output

                default:
                    throw sqliteError(db)
                }
            }
        }
    }

    /// Downloads one HebrewBooks PDF to a temporary URL. The caller owns the
    /// returned file and may move/import/delete it.
    func downloadPDF(bookID: Int) async throws -> URL {
        guard var components = URLComponents(string: Self.pdfDownloadURL) else {
            throw HebrewBooksCatalogError.invalidPDFURL
        }
        components.queryItems = [
            URLQueryItem(name: "req", value: String(bookID))
        ]
        guard let url = components.url else {
            throw HebrewBooksCatalogError.invalidPDFURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 180
        request.setValue(
            "VReader/1.0 (+HebrewBooks)",
            forHTTPHeaderField: "User-Agent"
        )

        // Use URLSession's file-backed download path instead of holding a
        // potentially large scanned sefer in memory.
        let (temporaryURL, response) = try await URLSession.shared.download(
            for: request
        )
        try validateDownloadedHTTP(response)

        let handle = try FileHandle(forReadingFrom: temporaryURL)
        defer { try? handle.close() }
        let prefix = try handle.read(upToCount: 5) ?? Data()
        guard prefix.count == 5,
              String(decoding: prefix, as: UTF8.self) == "%PDF-" else {
            throw HebrewBooksCatalogError.invalidPDFResponse
        }

        let target = fileManager.temporaryDirectory
            .appendingPathComponent(
                "vreader-hebrewbooks-\(bookID)-\(UUID().uuidString)"
            )
            .appendingPathExtension("pdf")

        try? fileManager.removeItem(at: target)
        try fileManager.moveItem(at: temporaryURL, to: target)
        return target
    }

    // MARK: - Paths

    private var storageDirectory: URL {
        let root = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory

        return root
            .appendingPathComponent("VReader", isDirectory: true)
            .appendingPathComponent("HomeSource", isDirectory: true)
            .appendingPathComponent("HebrewBooks", isDirectory: true)
    }

    private var databaseURL: URL {
        storageDirectory.appendingPathComponent("otzar-HB_catalog.db")
    }

    // MARK: - Release / network

    private struct GitHubRelease: Decodable, Sendable {
        let tagName: String
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case assets
        }

        struct Asset: Decodable, Sendable {
            let name: String
            let downloadURL: String

            enum CodingKeys: String, CodingKey {
                case name
                case downloadURL = "browser_download_url"
            }
        }
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: Self.releaseAPIURL)
        request.setValue(
            "application/vnd.github+json",
            forHTTPHeaderField: "Accept"
        )
        request.setValue(
            "2022-11-28",
            forHTTPHeaderField: "X-GitHub-Api-Version"
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response, data: data)
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    private func fetchData(
        from url: URL,
        headers: [String: String]
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 180
        request.setValue(
            "VReader/1.0 (+HebrewBooks catalog)",
            forHTTPHeaderField: "User-Agent"
        )
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response, data: data)
        return data
    }

    private func validateHTTP(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw HebrewBooksCatalogError.invalidHTTPResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let preview = String(decoding: data.prefix(160), as: UTF8.self)
            throw HebrewBooksCatalogError.http(
                status: http.statusCode,
                preview: preview
            )
        }
    }

    private func validateDownloadedHTTP(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw HebrewBooksCatalogError.invalidHTTPResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw HebrewBooksCatalogError.http(
                status: http.statusCode,
                preview: ""
            )
        }
    }

    // MARK: - Zstandard

    private func decompressCatalog(_ compressed: Data) throws -> Data {
        let frameSize: UInt64 = compressed.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return UInt64.max }
            return ZSTD_getFrameContentSize(base, bytes.count)
        }

        // zstd's documented sentinels:
        // ZSTD_CONTENTSIZE_ERROR   == UInt64.max
        // ZSTD_CONTENTSIZE_UNKNOWN == UInt64.max - 1
        guard frameSize != UInt64.max else {
            throw HebrewBooksCatalogError.invalidCompressedCatalog
        }
        guard frameSize != UInt64.max - 1 else {
            throw HebrewBooksCatalogError.unknownCatalogSize
        }
        guard frameSize > 0,
              frameSize <= UInt64(Self.maximumUncompressedCatalogBytes),
              frameSize <= UInt64(Int.max) else {
            throw HebrewBooksCatalogError.catalogTooLarge
        }

        var output = Data(count: Int(frameSize))
        let result: Int = output.withUnsafeMutableBytes { destination in
            compressed.withUnsafeBytes { source in
                guard let dst = destination.baseAddress,
                      let src = source.baseAddress else { return 0 }
                return ZSTD_decompress(
                    dst,
                    destination.count,
                    src,
                    source.count
                )
            }
        }

        guard ZSTD_isError(result) == 0 else {
            let message = String(cString: ZSTD_getErrorName(result))
            throw HebrewBooksCatalogError.decompressionFailed(message)
        }

        output.count = result

        // Cheap corruption guard before SQLite ever sees the file.
        let sqliteHeader = Data("SQLite format 3\0".utf8)
        guard output.count >= sqliteHeader.count,
              output.prefix(sqliteHeader.count) == sqliteHeader else {
            throw HebrewBooksCatalogError.invalidDatabase
        }

        return output
    }

    // MARK: - Atomic install

    private func installDatabaseAtomically(_ bytes: Data) throws {
        try fileManager.createDirectory(
            at: storageDirectory,
            withIntermediateDirectories: true
        )

        let tempURL = storageDirectory
            .appendingPathComponent("otzar-HB_catalog.db.download")

        try? fileManager.removeItem(at: tempURL)
        try bytes.write(to: tempURL, options: .atomic)

        // Validate the expected table before replacing a good existing cache.
        try validateDatabase(at: tempURL)

        if fileManager.fileExists(atPath: databaseURL.path) {
            _ = try fileManager.replaceItemAt(
                databaseURL,
                withItemAt: tempURL
            )
        } else {
            try fileManager.moveItem(at: tempURL, to: databaseURL)
        }
    }

    private func validateDatabase(at url: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open_v2(
            url.path,
            &db,
            SQLITE_OPEN_READONLY,
            nil
        ) == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            throw HebrewBooksCatalogError.invalidDatabase
        }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(
            db,
            "SELECT id_book, title FROM hebrew_books LIMIT 1",
            -1,
            &statement,
            nil
        ) == SQLITE_OK else {
            throw HebrewBooksCatalogError.invalidDatabase
        }

        let step = sqlite3_step(statement)
        guard step == SQLITE_ROW || step == SQLITE_DONE else {
            throw HebrewBooksCatalogError.invalidDatabase
        }
    }

    // MARK: - SQLite helpers

    private func withReadOnlyDatabase<T>(
        _ body: (OpaquePointer) throws -> T
    ) throws -> T {
        guard databaseExists() else {
            throw HebrewBooksCatalogError.catalogNotInstalled
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(
            databaseURL.path,
            &db,
            SQLITE_OPEN_READONLY,
            nil
        ) == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            throw HebrewBooksCatalogError.invalidDatabase
        }
        defer { sqlite3_close(db) }

        return try body(db)
    }

    private func sqliteError(_ db: OpaquePointer) -> HebrewBooksCatalogError {
        HebrewBooksCatalogError.sqlite(
            String(cString: sqlite3_errmsg(db))
        )
    }

    private func bindText(
        _ value: String,
        to statement: OpaquePointer,
        index: Int32
    ) {
        let transient = unsafeBitCast(
            -1,
            to: sqlite3_destructor_type.self
        )
        sqlite3_bind_text(statement, index, value, -1, transient)
    }

    private func columnText(
        _ statement: OpaquePointer,
        index: Int32
    ) -> String? {
        guard let value = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: value)
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Otzaria stores tags either as JSON arrays or comma-separated text.
    private func normalizedTopics(_ raw: String?) -> String {
        guard let raw = normalized(raw) else { return "" }

        if raw.hasPrefix("["),
           let data = raw.data(using: .utf8),
           let values = try? JSONDecoder().decode([String].self, from: data) {
            return values
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
        }

        return raw
    }
}

enum HebrewBooksCatalogError: LocalizedError {
    case catalogNotInstalled
    case catalogAssetMissing
    case invalidHTTPResponse
    case http(status: Int, preview: String)
    case invalidCompressedCatalog
    case unknownCatalogSize
    case catalogTooLarge
    case decompressionFailed(String)
    case invalidDatabase
    case sqlite(String)
    case invalidPDFURL
    case invalidPDFResponse

    var errorDescription: String? {
        switch self {
        case .catalogNotInstalled:
            return "The HebrewBooks catalog has not been downloaded yet."
        case .catalogAssetMissing:
            return "The latest HebrewBooks catalog release does not contain the expected database."
        case .invalidHTTPResponse:
            return "The server returned an invalid response."
        case .http(let status, let preview):
            let suffix = preview.isEmpty ? "" : " — \(preview)"
            return "The server returned HTTP \(status)\(suffix)"
        case .invalidCompressedCatalog:
            return "The downloaded HebrewBooks catalog is not a valid Zstandard archive."
        case .unknownCatalogSize:
            return "The HebrewBooks catalog archive does not report its expanded size."
        case .catalogTooLarge:
            return "The HebrewBooks catalog is unexpectedly large."
        case .decompressionFailed(let message):
            return "Could not decompress the HebrewBooks catalog: \(message)"
        case .invalidDatabase:
            return "The downloaded HebrewBooks catalog database is invalid."
        case .sqlite(let message):
            return "Could not read the HebrewBooks catalog: \(message)"
        case .invalidPDFURL:
            return "The HebrewBooks PDF address is invalid."
        case .invalidPDFResponse:
            return "HebrewBooks did not return a valid PDF for this book."
        }
    }
}
