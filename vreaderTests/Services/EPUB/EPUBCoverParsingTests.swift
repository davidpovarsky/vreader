// Purpose: Tests for WI-1 — EPUB cover image reference extraction from OPF.
// Verifies EPUB2 (<meta name="cover">) and EPUB3 (properties="cover-image")
// detection paths, plus path resolution edge cases.
//
// @coordinates-with: EPUBParser.swift, EPUBTypes.swift

import Testing
import Foundation
@testable import vreader

// MARK: - OPF Cover Parsing Tests

@Suite("EPUBParser - Cover Image Extraction")
struct EPUBCoverParsingTests {

    // MARK: - EPUB2: <meta name="cover" content="id"/> + manifest lookup

    @Test("EPUB2 meta cover — extracts correct href from manifest")
    func epub2MetaCover() throws {
        let opfData = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="2.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>Test</dc:title>
            <meta name="cover" content="cover-img"/>
          </metadata>
          <manifest>
            <item id="cover-img" href="Images/cover.jpg" media-type="image/jpeg"/>
            <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine>
            <itemref idref="ch1"/>
          </spine>
        </package>
        """.utf8)

        let result = try EPUBParser.parseOPF(opfData)
        #expect(result.metadata.coverImageHref == "Images/cover.jpg")
    }

    // MARK: - EPUB3: properties="cover-image"

    @Test("EPUB3 cover-image property — extracts href directly")
    func epub3CoverImageProperty() throws {
        let opfData = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>Test</dc:title>
          </metadata>
          <manifest>
            <item id="cover" href="cover.jpg" media-type="image/jpeg" properties="cover-image"/>
            <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine>
            <itemref idref="ch1"/>
          </spine>
        </package>
        """.utf8)

        let result = try EPUBParser.parseOPF(opfData)
        #expect(result.metadata.coverImageHref == "cover.jpg")
    }

    // MARK: - EPUB3 takes priority over EPUB2

    @Test("EPUB3 cover-image property takes priority over EPUB2 meta")
    func epub3PriorityOverEpub2() throws {
        let opfData = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>Test</dc:title>
            <meta name="cover" content="old-cover"/>
          </metadata>
          <manifest>
            <item id="old-cover" href="old-cover.jpg" media-type="image/jpeg"/>
            <item id="new-cover" href="new-cover.png" media-type="image/png" properties="cover-image"/>
            <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine>
            <itemref idref="ch1"/>
          </spine>
        </package>
        """.utf8)

        let result = try EPUBParser.parseOPF(opfData)
        #expect(result.metadata.coverImageHref == "new-cover.png")
    }

    // MARK: - No cover

    @Test("No cover metadata — returns nil")
    func noCover() throws {
        let opfData = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>Test</dc:title>
          </metadata>
          <manifest>
            <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine>
            <itemref idref="ch1"/>
          </spine>
        </package>
        """.utf8)

        let result = try EPUBParser.parseOPF(opfData)
        #expect(result.metadata.coverImageHref == nil)
    }

    // MARK: - Cover ID in meta but missing from manifest

    @Test("Cover ID in meta but not in manifest — returns nil")
    func coverIdMissingFromManifest() throws {
        let opfData = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="2.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>Test</dc:title>
            <meta name="cover" content="nonexistent-id"/>
          </metadata>
          <manifest>
            <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine>
            <itemref idref="ch1"/>
          </spine>
        </package>
        """.utf8)

        let result = try EPUBParser.parseOPF(opfData)
        #expect(result.metadata.coverImageHref == nil)
    }

    // MARK: - Fragment stripping

    @Test("Href with fragment — fragment is stripped")
    func hrefFragmentStripped() throws {
        let opfData = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>Test</dc:title>
          </metadata>
          <manifest>
            <item id="cover" href="cover.jpg#fragment" media-type="image/jpeg" properties="cover-image"/>
            <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine>
            <itemref idref="ch1"/>
          </spine>
        </package>
        """.utf8)

        let result = try EPUBParser.parseOPF(opfData)
        #expect(result.metadata.coverImageHref == "cover.jpg")
    }

    // MARK: - Relative path with ../

    @Test("Href with ../ — preserved as-is (resolution happens at archive level)")
    func relativePathPreserved() throws {
        let opfData = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>Test</dc:title>
          </metadata>
          <manifest>
            <item id="cover" href="../Images/cover.jpg" media-type="image/jpeg" properties="cover-image"/>
            <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine>
            <itemref idref="ch1"/>
          </spine>
        </package>
        """.utf8)

        let result = try EPUBParser.parseOPF(opfData)
        // ../ is kept as-is — resolution relative to OPF dir happens
        // at the archive path level (in extractCover), not in parseOPF.
        #expect(result.metadata.coverImageHref == "../Images/cover.jpg")
    }

    // MARK: - Percent-encoded href

    @Test("Percent-encoded href — decoded correctly")
    func percentEncodedHref() throws {
        let opfData = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>Test</dc:title>
          </metadata>
          <manifest>
            <item id="cover" href="Images/cover%20image.jpg" media-type="image/jpeg" properties="cover-image"/>
            <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine>
            <itemref idref="ch1"/>
          </spine>
        </package>
        """.utf8)

        let result = try EPUBParser.parseOPF(opfData)
        #expect(result.metadata.coverImageHref == "Images/cover image.jpg")
    }

    // MARK: - EPUB3 cover-image with multiple properties

    @Test("EPUB3 cover-image among multiple properties")
    func epub3CoverImageMultipleProperties() throws {
        let opfData = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>Test</dc:title>
          </metadata>
          <manifest>
            <item id="cover" href="cover.svg" media-type="image/svg+xml" properties="cover-image svg"/>
            <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine>
            <itemref idref="ch1"/>
          </spine>
        </package>
        """.utf8)

        let result = try EPUBParser.parseOPF(opfData)
        #expect(result.metadata.coverImageHref == "cover.svg")
    }
}