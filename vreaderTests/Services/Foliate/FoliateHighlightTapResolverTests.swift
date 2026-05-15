// Purpose: Tests for FoliateHighlightTapResolver — Feature #53 WI-5.
// The Foliate JS bridge emits an `annotation-show` event with only a CFI when
// the user taps an existing highlight. To post the cross-format
// `.readerHighlightTapped` notification (carrying `ReaderHighlightTapEvent
// { highlightID: UUID, sourceRect: CGRect }`), we need to resolve the tapped
// CFI back to the persisted highlight's UUID. This resolver is the
// pure-function gate.

import Testing
import Foundation
import CoreGraphics
@testable import vreader

@Suite("FoliateHighlightTapResolver — CFI → UUID (Feature #53 WI-5)")
struct FoliateHighlightTapResolverTests {

    private let azw3Fingerprint = DocumentFingerprint(
        contentSHA256: "azw3_test_sha256_000000000000000000000000000000000000000000000000",
        fileByteCount: 4096,
        format: .azw3
    )

    private func makeEPUBHighlightRecord(
        id: UUID = UUID(),
        cfi: String,
        href: String = "OEBPS/chapter1.xhtml"
    ) -> HighlightRecord {
        let locator = LocatorFactory.epub(
            fingerprint: azw3Fingerprint,
            href: href,
            progression: 0.0
        )!
        return HighlightRecord(
            highlightId: id,
            locator: locator,
            anchor: .epub(
                href: href,
                cfi: cfi,
                serializedRange: EPUBSerializedRange(
                    startContainerPath: "/html/body/p[1]",
                    startOffset: 0,
                    endContainerPath: "/html/body/p[1]",
                    endOffset: 5
                )
            ),
            profileKey: "\(azw3Fingerprint.canonicalKey):\(locator.canonicalHash)",
            selectedText: "selected text",
            color: "yellow",
            note: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    @Test
    func resolve_matchingCFI_returnsHighlightID() {
        let id = UUID()
        let target = "epubcfi(/6/4!/4/2/1:0,/4/2/1:5)"
        let records = [
            makeEPUBHighlightRecord(cfi: "epubcfi(/6/2!/4/2/1:0,/4/2/1:3)"),
            makeEPUBHighlightRecord(id: id, cfi: target),
            makeEPUBHighlightRecord(cfi: "epubcfi(/6/6!/4/2/1:0,/4/2/1:7)"),
        ]
        let resolved = FoliateHighlightTapResolver.resolveHighlightID(
            forCFI: target, in: records
        )
        #expect(resolved == id)
    }

    @Test
    func resolve_noMatch_returnsNil() {
        let records = [
            makeEPUBHighlightRecord(cfi: "epubcfi(/6/2!/4/2/1:0,/4/2/1:3)"),
            makeEPUBHighlightRecord(cfi: "epubcfi(/6/4!/4/2/1:0,/4/2/1:5)"),
        ]
        let resolved = FoliateHighlightTapResolver.resolveHighlightID(
            forCFI: "epubcfi(/6/99!/4/2/1:0,/4/2/1:3)", in: records
        )
        #expect(resolved == nil,
                "No matching CFI must return nil (covers a JS-vs-Swift race where the tapped annotation was deleted between render + tap)")
    }

    @Test
    func resolve_emptyRecords_returnsNil() {
        let resolved = FoliateHighlightTapResolver.resolveHighlightID(
            forCFI: "epubcfi(/6/4!/4/2/1:0,/4/2/1:5)", in: []
        )
        #expect(resolved == nil)
    }

    @Test
    func resolve_emptyCFI_returnsNil() {
        // Defensive: foliate-host.js could in theory post an empty value;
        // the resolver should not return any record (including one whose
        // CFI happened to be empty — that'd be malformed).
        let records = [makeEPUBHighlightRecord(cfi: "epubcfi(/6/4!/4/2/1:0,/4/2/1:5)")]
        let resolved = FoliateHighlightTapResolver.resolveHighlightID(
            forCFI: "", in: records
        )
        #expect(resolved == nil)
    }

    @Test
    func resolve_textAnchor_isIgnored() {
        // Sanity guard: Foliate only persists EPUB-flavored anchors, but the
        // resolver receives whatever fetchHighlights returns for the book.
        // A misclassified text anchor (which never matches a CFI) must not
        // accidentally resolve.
        let locator = LocatorFactory.txtPosition(
            fingerprint: azw3Fingerprint,
            charOffsetUTF16: 0
        )!
        let textRecord = HighlightRecord(
            highlightId: UUID(),
            locator: locator,
            anchor: .text(sourceUnitId: "ch1", startUTF16: 0, endUTF16: 5),
            profileKey: "\(azw3Fingerprint.canonicalKey):\(locator.canonicalHash)",
            selectedText: "selected text",
            color: "yellow",
            note: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        let resolved = FoliateHighlightTapResolver.resolveHighlightID(
            forCFI: "epubcfi(/6/4!/4/2/1:0,/4/2/1:5)", in: [textRecord]
        )
        #expect(resolved == nil, "Non-EPUB anchor must not match any CFI")
    }

    @Test
    func resolve_firstMatchWins_whenDuplicateCFIs() {
        // Edge: if two highlights somehow share the same CFI (overlapping
        // selections, restore from backup duplicates), return the first
        // matching record's UUID. Deterministic by array order, which
        // matches `fetchHighlights`'s sort order at the persistence layer.
        let firstID = UUID()
        let cfi = "epubcfi(/6/4!/4/2/1:0,/4/2/1:5)"
        let records = [
            makeEPUBHighlightRecord(id: firstID, cfi: cfi),
            makeEPUBHighlightRecord(cfi: cfi),
        ]
        let resolved = FoliateHighlightTapResolver.resolveHighlightID(
            forCFI: cfi, in: records
        )
        #expect(resolved == firstID)
    }
}
