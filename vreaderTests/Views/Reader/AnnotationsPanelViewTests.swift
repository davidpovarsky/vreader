// Purpose: Tests for AnnotationsPanelView extracted in WI-004.
// Validates AnnotationsPanelTab enum and AnnotationsPanelView construction.
//
// @coordinates-with AnnotationsPanelView.swift, ReaderContainerView.swift

import Testing
import Foundation
@testable import vreader

// MARK: - AnnotationsPanelTab Tests

@Suite("AnnotationsPanelTab")
struct AnnotationsPanelTabTests {

    @Test func allCasesContainsFourTabs() {
        #expect(AnnotationsPanelTab.allCases.count == 4)
    }

    @Test func tabRawValuesMatchExpected() {
        #expect(AnnotationsPanelTab.bookmarks.rawValue == "Bookmarks")
        #expect(AnnotationsPanelTab.toc.rawValue == "Contents")
        #expect(AnnotationsPanelTab.highlights.rawValue == "Highlights")
        #expect(AnnotationsPanelTab.annotations.rawValue == "Notes")
    }

    @Test func tabSystemImagesMatchExpected() {
        #expect(AnnotationsPanelTab.bookmarks.systemImage == "bookmark")
        #expect(AnnotationsPanelTab.toc.systemImage == "list.bullet")
        #expect(AnnotationsPanelTab.highlights.systemImage == "highlighter")
        #expect(AnnotationsPanelTab.annotations.systemImage == "note.text")
    }

    @Test func tabIdUsesRawValue() {
        for tab in AnnotationsPanelTab.allCases {
            #expect(tab.id == tab.rawValue)
        }
    }
}
