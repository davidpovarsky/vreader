// Purpose: Tests for FoliateURLSchemeHandler pure logic — MIME type resolution,
// URL path routing, and bundle resource path parsing.
//
// These tests cover the static/pure functions extracted from the handler.
// WKURLSchemeTask interactions (WebKit callbacks) are NOT tested here;
// those are covered by integration tests in the Xcode UI test target.
//
// @coordinates-with: FoliateURLSchemeHandler.swift

import Testing
import Foundation
@testable import vreader

@Suite("FoliateURLSchemeHandler")
struct FoliateURLSchemeHandlerTests {

    // MARK: - mimeTypeForExtension — Success Cases

    @Test("js returns application/javascript")
    func testMIMETypeJS() {
        #expect(FoliateURLSchemeHandler.mimeTypeForExtension("js") == "application/javascript")
    }

    @Test("mjs returns application/javascript")
    func testMIMETypeMJS() {
        #expect(FoliateURLSchemeHandler.mimeTypeForExtension("mjs") == "application/javascript")
    }

    @Test("html returns text/html")
    func testMIMETypeHTML() {
        #expect(FoliateURLSchemeHandler.mimeTypeForExtension("html") == "text/html")
    }

    @Test("htm returns text/html")
    func testMIMETypeHTM() {
        #expect(FoliateURLSchemeHandler.mimeTypeForExtension("htm") == "text/html")
    }

    @Test("css returns text/css")
    func testMIMETypeCSS() {
        #expect(FoliateURLSchemeHandler.mimeTypeForExtension("css") == "text/css")
    }

    @Test("json returns application/json")
    func testMIMETypeJSON() {
        #expect(FoliateURLSchemeHandler.mimeTypeForExtension("json") == "application/json")
    }

    @Test("svg returns image/svg+xml")
    func testMIMETypeSVG() {
        #expect(FoliateURLSchemeHandler.mimeTypeForExtension("svg") == "image/svg+xml")
    }

    @Test("png returns image/png")
    func testMIMETypePNG() {
        #expect(FoliateURLSchemeHandler.mimeTypeForExtension("png") == "image/png")
    }

    @Test("jpg returns image/jpeg")
    func testMIMETypeJPG() {
        #expect(FoliateURLSchemeHandler.mimeTypeForExtension("jpg") == "image/jpeg")
    }

    @Test("jpeg returns image/jpeg")
    func testMIMETypeJPEG() {
        #expect(FoliateURLSchemeHandler.mimeTypeForExtension("jpeg") == "image/jpeg")
    }

    @Test("gif returns image/gif")
    func testMIMETypeGIF() {
        #expect(FoliateURLSchemeHandler.mimeTypeForExtension("gif") == "image/gif")
    }

    @Test("woff returns font/woff")
    func testMIMETypeWOFF() {
        #expect(FoliateURLSchemeHandler.mimeTypeForExtension("woff") == "font/woff")
    }

    @Test("woff2 returns font/woff2")
    func testMIMETypeWOFF2() {
        #expect(FoliateURLSchemeHandler.mimeTypeForExtension("woff2") == "font/woff2")
    }

    @Test("ttf returns font/ttf")
    func testMIMETypeTTF() {
        #expect(FoliateURLSchemeHandler.mimeTypeForExtension("ttf") == "font/ttf")
    }

    @Test("otf returns font/otf")
    func testMIMETypeOTF() {
        #expect(FoliateURLSchemeHandler.mimeTypeForExtension("otf") == "font/otf")
    }

    // MARK: - mimeTypeForExtension — Case Insensitivity

    @Test("MIME type lookup is case-insensitive")
    func testMIMETypeCaseInsensitive() {
        #expect(FoliateURLSchemeHandler.mimeTypeForExtension("JS") == "application/javascript")
        #expect(FoliateURLSchemeHandler.mimeTypeForExtension("Html") == "text/html")
        #expect(FoliateURLSchemeHandler.mimeTypeForExtension("CSS") == "text/css")
        #expect(FoliateURLSchemeHandler.mimeTypeForExtension("PNG") == "image/png")
        #expect(FoliateURLSchemeHandler.mimeTypeForExtension("WOFF2") == "font/woff2")
    }

    // MARK: - mimeTypeForExtension — Unknown / Fallback

    @Test("unknown extension returns application/octet-stream")
    func testMIMETypeUnknown() {
        #expect(FoliateURLSchemeHandler.mimeTypeForExtension("xyz") == "application/octet-stream")
    }

    @Test("empty extension returns application/octet-stream")
    func testMIMETypeEmpty() {
        #expect(FoliateURLSchemeHandler.mimeTypeForExtension("") == "application/octet-stream")
    }

    @Test("extension with dots is treated literally")
    func testMIMETypeDotsInExtension() {
        // If someone passes "tar.gz" as an extension, it won't match any case
        #expect(FoliateURLSchemeHandler.mimeTypeForExtension("tar.gz") == "application/octet-stream")
    }

    // MARK: - bookMIMEType — Success Cases

    @Test("epub returns application/epub+zip")
    func testBookMIMETypeEPUB() {
        #expect(FoliateURLSchemeHandler.bookMIMEType("epub") == "application/epub+zip")
    }

    @Test("azw3 returns application/octet-stream")
    func testBookMIMETypeAZW3() {
        #expect(FoliateURLSchemeHandler.bookMIMEType("azw3") == "application/octet-stream")
    }

    @Test("azw returns application/octet-stream")
    func testBookMIMETypeAZW() {
        #expect(FoliateURLSchemeHandler.bookMIMEType("azw") == "application/octet-stream")
    }

    @Test("mobi returns application/octet-stream")
    func testBookMIMETypeMOBI() {
        #expect(FoliateURLSchemeHandler.bookMIMEType("mobi") == "application/octet-stream")
    }

    @Test("prc returns application/octet-stream")
    func testBookMIMETypePRC() {
        #expect(FoliateURLSchemeHandler.bookMIMEType("prc") == "application/octet-stream")
    }

    // MARK: - bookMIMEType — Case Sensitivity (intentional: caller lowercases)

    @Test("bookMIMEType is case-sensitive — EPUB does not match epub case")
    func testBookMIMETypeCaseSensitive() {
        // The handler lowercases the extension before calling bookMIMEType,
        // so bookMIMEType itself does exact matching. "EPUB" won't match "epub".
        #expect(FoliateURLSchemeHandler.bookMIMEType("EPUB") == "application/octet-stream")
    }

    // MARK: - bookMIMEType — Unknown

    @Test("unknown book extension returns application/octet-stream")
    func testBookMIMETypeUnknown() {
        #expect(FoliateURLSchemeHandler.bookMIMEType("pdf") == "application/octet-stream")
    }

    @Test("empty book extension returns application/octet-stream")
    func testBookMIMETypeEmpty() {
        #expect(FoliateURLSchemeHandler.bookMIMEType("") == "application/octet-stream")
    }

    // MARK: - bookMIMEType vs mimeTypeForExtension — epub is distinct

    @Test("epub has different MIME in bookMIMEType vs mimeTypeForExtension")
    func testEpubDistinctMIME() {
        // bookMIMEType knows epub is application/epub+zip
        // mimeTypeForExtension doesn't have an epub case, returns octet-stream
        let bookMIME = FoliateURLSchemeHandler.bookMIMEType("epub")
        let genericMIME = FoliateURLSchemeHandler.mimeTypeForExtension("epub")
        #expect(bookMIME == "application/epub+zip")
        #expect(genericMIME == "application/octet-stream")
        #expect(bookMIME != genericMIME)
    }

    // MARK: - route(for:) — Core Routing

    @Test("/index.html routes to readerHTML")
    func testRouteIndexHTML() {
        #expect(FoliateURLSchemeHandler.route(for: "/index.html") == .readerHTML)
    }

    @Test("/ routes to readerHTML")
    func testRouteRoot() {
        #expect(FoliateURLSchemeHandler.route(for: "/") == .readerHTML)
    }

    @Test("/book/file routes to bookFile")
    func testRouteBookFile() {
        #expect(FoliateURLSchemeHandler.route(for: "/book/file") == .bookFile)
    }

    @Test("/foliate-bundle.js routes to bundleResource")
    func testRouteBundleJS() {
        #expect(FoliateURLSchemeHandler.route(for: "/foliate-bundle.js") == .bundleResource(path: "/foliate-bundle.js"))
    }

    @Test("/vendor/zip.js routes to bundleResource preserving path")
    func testRouteSubdirectoryResource() {
        #expect(FoliateURLSchemeHandler.route(for: "/vendor/zip.js") == .bundleResource(path: "/vendor/zip.js"))
    }

    @Test("/some/deep/path.css routes to bundleResource")
    func testRouteDeepPath() {
        #expect(FoliateURLSchemeHandler.route(for: "/some/deep/path.css") == .bundleResource(path: "/some/deep/path.css"))
    }

    // MARK: - route(for:) — Boundary Cases

    @Test("empty string routes to bundleResource, not readerHTML")
    func testRouteEmptyString() {
        // Empty string is NOT "/" so it goes to bundleResource
        #expect(FoliateURLSchemeHandler.route(for: "") == .bundleResource(path: ""))
    }

    @Test("/index.html with query string does NOT match readerHTML")
    func testRouteIndexHTMLWithQuery() {
        // url.path strips query params, but if someone passes "/index.html?v=1" as path
        // it won't match the exact string
        #expect(FoliateURLSchemeHandler.route(for: "/index.html?v=1") == .bundleResource(path: "/index.html?v=1"))
    }

    @Test("/book/file/extra does NOT match bookFile")
    func testRouteBookFileSubpath() {
        // Only exact match "/book/file" routes to book
        #expect(FoliateURLSchemeHandler.route(for: "/book/file/extra") == .bundleResource(path: "/book/file/extra"))
    }

    @Test("/BOOK/FILE does NOT match bookFile (case-sensitive)")
    func testRouteBookFileCaseSensitive() {
        #expect(FoliateURLSchemeHandler.route(for: "/BOOK/FILE") == .bundleResource(path: "/BOOK/FILE"))
    }

    @Test("/INDEX.HTML does NOT match readerHTML (case-sensitive)")
    func testRouteIndexHTMLCaseSensitive() {
        #expect(FoliateURLSchemeHandler.route(for: "/INDEX.HTML") == .bundleResource(path: "/INDEX.HTML"))
    }

    // MARK: - parseBundleResourcePath — Success Cases

    @Test("simple filename with extension")
    func testParseSimplePath() {
        let result = FoliateURLSchemeHandler.parseBundleResourcePath("/foliate-bundle.js")
        #expect(result != nil)
        #expect(result?.filename == "foliate-bundle")
        #expect(result?.ext == "js")
    }

    @Test("path without leading slash")
    func testParseNoLeadingSlash() {
        let result = FoliateURLSchemeHandler.parseBundleResourcePath("style.css")
        #expect(result != nil)
        #expect(result?.filename == "style")
        #expect(result?.ext == "css")
    }

    @Test("subdirectory path")
    func testParseSubdirectoryPath() {
        let result = FoliateURLSchemeHandler.parseBundleResourcePath("/vendor/zip.js")
        #expect(result != nil)
        #expect(result?.filename == "vendor/zip")
        #expect(result?.ext == "js")
    }

    @Test("file with no extension")
    func testParseNoExtension() {
        let result = FoliateURLSchemeHandler.parseBundleResourcePath("/Makefile")
        #expect(result != nil)
        #expect(result?.filename == "Makefile")
        #expect(result?.ext == "")
    }

    @Test("file with multiple dots uses last dot for extension")
    func testParseMultipleDots() {
        let result = FoliateURLSchemeHandler.parseBundleResourcePath("/archive.tar.gz")
        #expect(result != nil)
        #expect(result?.filename == "archive.tar")
        #expect(result?.ext == "gz")
    }

    @Test("dotfile with extension")
    func testParseDotfileWithExt() {
        let result = FoliateURLSchemeHandler.parseBundleResourcePath("/.hidden.js")
        #expect(result != nil)
        #expect(result?.filename == ".hidden")
        #expect(result?.ext == "js")
    }

    // MARK: - parseBundleResourcePath — Guard / Invalid Cases

    @Test("empty path returns nil")
    func testParseEmptyPath() {
        let result = FoliateURLSchemeHandler.parseBundleResourcePath("")
        #expect(result == nil)
    }

    @Test("slash-only path returns nil (empty after stripping)")
    func testParseSlashOnly() {
        let result = FoliateURLSchemeHandler.parseBundleResourcePath("/")
        #expect(result == nil)
    }

    // MARK: - parseBundleResourcePath — Boundary Cases

    @Test("path with trailing dot")
    func testParseTrailingDot() {
        let result = FoliateURLSchemeHandler.parseBundleResourcePath("/file.")
        #expect(result != nil)
        #expect(result?.filename == "file")
        #expect(result?.ext == "")
    }

    @Test("path that is just a dot after stripping slash")
    func testParseDotOnly() {
        let result = FoliateURLSchemeHandler.parseBundleResourcePath("/.")
        #expect(result != nil)
        // "." → lastIndex of "." is index 0 → filename = "", ext = ""
        #expect(result?.filename == "")
        #expect(result?.ext == "")
    }

    @Test("deeply nested path with extension")
    func testParseDeepPath() {
        let result = FoliateURLSchemeHandler.parseBundleResourcePath("/a/b/c/d.woff2")
        #expect(result != nil)
        #expect(result?.filename == "a/b/c/d")
        #expect(result?.ext == "woff2")
    }

    // MARK: - scheme constant

    @Test("scheme constant is vreader-resource")
    func testSchemeConstant() {
        #expect(FoliateURLSchemeHandler.scheme == "vreader-resource")
    }

    // MARK: - Hardcoded Return Defense
    //
    // These tests ensure a naive "return constant" implementation for any single
    // function would fail at least one test case. The key differentiators:
    //
    // - mimeTypeForExtension: "js" -> "application/javascript" vs "xyz" -> "application/octet-stream"
    //   A hardcoded return of either value fails the other test.
    //
    // - bookMIMEType: "epub" -> "application/epub+zip" vs "azw3" -> "application/octet-stream"
    //   Hardcoded "application/epub+zip" fails azw3; hardcoded octet-stream fails epub.
    //
    // - route(for:): Three distinct enum cases are tested with different paths.
    //   Any hardcoded single case fails the other two.
    //
    // - parseBundleResourcePath: nil case (empty) vs non-nil case ("/file.js")
    //   prevent hardcoded nil or hardcoded tuple.
}
