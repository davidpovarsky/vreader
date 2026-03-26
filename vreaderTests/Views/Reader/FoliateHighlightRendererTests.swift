// Purpose: Tests for FoliateHighlightRenderer — JS string generation for
// Foliate-js SVG overlay annotations (add, remove, restore, color mapping).
//
// All methods are pure functions (String in → String out), so no mocks are needed.
// Tests verify the generated JS contains the correct API calls, parameters, and
// proper escaping of special characters in CFI strings.
//
// @coordinates-with: FoliateHighlightRenderer.swift

import Testing
import Foundation
@testable import vreader

// MARK: - addAnnotationJS

@Suite("FoliateHighlightRenderer — addAnnotationJS")
struct FoliateHighlightRendererAddTests {

    @Test("output contains readerAPI.addAnnotation call")
    func addAnnotationContainsAPICall() {
        let js = FoliateHighlightRenderer.addAnnotationJS(
            cfi: "epubcfi(/6/4!/4/2/1:0)",
            color: "yellow"
        )
        #expect(js.contains("readerAPI.addAnnotation"))
    }

    @Test("output includes the CFI value")
    func addAnnotationIncludesCFI() {
        let cfi = "epubcfi(/6/14!/4/2/3:5,/6/14!/4/2/3:42)"
        let js = FoliateHighlightRenderer.addAnnotationJS(cfi: cfi, color: "blue")
        #expect(js.contains("epubcfi(/6/14!/4/2/3:5,/6/14!/4/2/3:42)"))
    }

    @Test("output includes the color value")
    func addAnnotationIncludesColor() {
        let js = FoliateHighlightRenderer.addAnnotationJS(
            cfi: "epubcfi(/6/2!/4/2)",
            color: "green"
        )
        #expect(js.contains("green"))
    }

    @Test("escapes CFI containing single quotes")
    func addAnnotationEscapesSingleQuotes() {
        // A CFI like epubcfi(/6/4[chap01.xhtml]!/4/2) is normal,
        // but test with embedded single quote to verify escaping
        let cfi = "epubcfi(/6/4[it's]!/4/2)"
        let js = FoliateHighlightRenderer.addAnnotationJS(cfi: cfi, color: "yellow")

        // The JS must be valid — the raw single quote must be escaped
        // (either as \' or the string uses double quotes and the raw ' is fine,
        // but the unescaped raw quote must not appear between single-quote delimiters)
        #expect(js.contains("readerAPI.addAnnotation"))

        // Verify the CFI content is present (possibly escaped)
        // If using single-quoted JS strings, the quote must be escaped:
        let hasSafeQuote = !js.contains("'it's'")
        #expect(hasSafeQuote, "Single quote in CFI must be escaped to avoid breaking JS")
    }

    @Test("escapes CFI containing backslashes")
    func addAnnotationEscapesBackslashes() {
        let cfi = "epubcfi(/6/4!/4\\2)"
        let js = FoliateHighlightRenderer.addAnnotationJS(cfi: cfi, color: "yellow")
        #expect(js.contains("readerAPI.addAnnotation"))
        // Backslash must be escaped in JS string literal
        // A raw single backslash would be interpreted as an escape sequence
        #expect(js.contains("\\\\"), "Backslash in CFI must be escaped for JS string literal")
    }

    @Test("output differs for different CFI values (not hardcoded)")
    func addAnnotationDiffersPerCFI() {
        let js1 = FoliateHighlightRenderer.addAnnotationJS(
            cfi: "epubcfi(/6/2!/4/2)", color: "yellow"
        )
        let js2 = FoliateHighlightRenderer.addAnnotationJS(
            cfi: "epubcfi(/6/100!/4/2/3:99)", color: "yellow"
        )
        #expect(js1 != js2, "Different CFIs must produce different JS output")
    }

    @Test("output differs for different colors (not hardcoded)")
    func addAnnotationDiffersPerColor() {
        let js1 = FoliateHighlightRenderer.addAnnotationJS(
            cfi: "epubcfi(/6/4!/4/2)", color: "yellow"
        )
        let js2 = FoliateHighlightRenderer.addAnnotationJS(
            cfi: "epubcfi(/6/4!/4/2)", color: "blue"
        )
        #expect(js1 != js2, "Different colors must produce different JS output")
    }
}

// MARK: - removeAnnotationJS

@Suite("FoliateHighlightRenderer — removeAnnotationJS")
struct FoliateHighlightRendererRemoveTests {

    @Test("output contains readerAPI.deleteAnnotation call")
    func removeAnnotationContainsAPICall() {
        let js = FoliateHighlightRenderer.removeAnnotationJS(
            cfi: "epubcfi(/6/4!/4/2/1:0)"
        )
        #expect(js.contains("readerAPI.deleteAnnotation"))
    }

    @Test("output includes the CFI value")
    func removeAnnotationIncludesCFI() {
        let cfi = "epubcfi(/6/8!/4/2/3:5,/6/8!/4/2/3:42)"
        let js = FoliateHighlightRenderer.removeAnnotationJS(cfi: cfi)
        #expect(js.contains(cfi))
    }

    @Test("output differs for different CFI values (not hardcoded)")
    func removeAnnotationDiffersPerCFI() {
        let js1 = FoliateHighlightRenderer.removeAnnotationJS(
            cfi: "epubcfi(/6/2!/4/2)"
        )
        let js2 = FoliateHighlightRenderer.removeAnnotationJS(
            cfi: "epubcfi(/6/50!/4/2/7:10)"
        )
        #expect(js1 != js2, "Different CFIs must produce different JS output")
    }
}

// MARK: - restoreAllJS

@Suite("FoliateHighlightRenderer — restoreAllJS")
struct FoliateHighlightRendererRestoreTests {

    @Test("3 highlights generate 3 addAnnotation calls")
    func restoreThreeHighlightsGeneratesThreeCalls() {
        let highlights: [(cfi: String, color: String)] = [
            ("epubcfi(/6/2!/4/2)", "yellow"),
            ("epubcfi(/6/4!/4/2)", "blue"),
            ("epubcfi(/6/6!/4/2)", "green"),
        ]
        let js = FoliateHighlightRenderer.restoreAllJS(highlights: highlights)

        // Count occurrences of addAnnotation
        let count = js.components(separatedBy: "addAnnotation").count - 1
        #expect(count == 3, "Expected 3 addAnnotation calls, got \(count)")
    }

    @Test("empty list returns empty string")
    func restoreEmptyListReturnsEmptyString() {
        let js = FoliateHighlightRenderer.restoreAllJS(highlights: [])
        #expect(js.isEmpty, "Empty highlights array must produce empty string")
    }

    @Test("each highlight's CFI appears in output")
    func restoreIncludesAllCFIs() {
        let highlights: [(cfi: String, color: String)] = [
            ("epubcfi(/6/10!/4/2)", "yellow"),
            ("epubcfi(/6/20!/4/2)", "pink"),
        ]
        let js = FoliateHighlightRenderer.restoreAllJS(highlights: highlights)
        #expect(js.contains("epubcfi(/6/10!/4/2)"))
        #expect(js.contains("epubcfi(/6/20!/4/2)"))
    }

    @Test("each highlight's color appears in output")
    func restoreIncludesAllColors() {
        let highlights: [(cfi: String, color: String)] = [
            ("epubcfi(/6/2!/4/2)", "yellow"),
            ("epubcfi(/6/4!/4/2)", "pink"),
        ]
        let js = FoliateHighlightRenderer.restoreAllJS(highlights: highlights)
        #expect(js.contains("yellow"))
        #expect(js.contains("pink"))
    }

    @Test("single highlight produces exactly 1 addAnnotation call")
    func restoreSingleHighlight() {
        let highlights: [(cfi: String, color: String)] = [
            ("epubcfi(/6/2!/4/2)", "yellow"),
        ]
        let js = FoliateHighlightRenderer.restoreAllJS(highlights: highlights)
        let count = js.components(separatedBy: "addAnnotation").count - 1
        #expect(count == 1, "Expected 1 addAnnotation call, got \(count)")
    }
}

// MARK: - foliateColor

@Suite("FoliateHighlightRenderer — foliateColor")
struct FoliateHighlightRendererColorTests {

    @Test("maps yellow to yellow")
    func mapsYellow() {
        #expect(FoliateHighlightRenderer.foliateColor(from: "yellow") == "yellow")
    }

    @Test("maps blue to blue")
    func mapsBlue() {
        #expect(FoliateHighlightRenderer.foliateColor(from: "blue") == "blue")
    }

    @Test("maps green to green")
    func mapsGreen() {
        #expect(FoliateHighlightRenderer.foliateColor(from: "green") == "green")
    }

    @Test("maps pink to pink")
    func mapsPink() {
        #expect(FoliateHighlightRenderer.foliateColor(from: "pink") == "pink")
    }

    @Test("unknown color defaults to yellow")
    func unknownColorDefaultsToYellow() {
        #expect(
            FoliateHighlightRenderer.foliateColor(from: "magenta") == "yellow",
            "Unknown color 'magenta' should default to 'yellow'"
        )
    }

    @Test("empty string defaults to yellow")
    func emptyStringDefaultsToYellow() {
        #expect(
            FoliateHighlightRenderer.foliateColor(from: "") == "yellow",
            "Empty color string should default to 'yellow'"
        )
    }
}
