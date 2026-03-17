// Purpose: Manages unified reflow content loading and state.
// Dispatches to format-specific loaders (TXT, MD, EPUB) and holds the loaded content.
// Extracted from ReaderContainerView to reduce file size (pure refactor).
//
// @coordinates-with ReaderContainerView.swift, UnifiedTextRenderer.swift,
//   MDParser.swift, EPUBParser.swift, EPUBTextStripper.swift

import SwiftUI

/// Owns the unified reflow engine state: text content, attributed text, and EPUB load status.
@Observable
@MainActor
final class ReaderUnifiedCoordinator {

    /// Text loaded for the unified reflow engine (WI-B04). Nil until loaded.
    var textContent: String?
    /// Attributed text for unified MD/EPUB rendering (WI-B05, WI-B07). Nil until loaded.
    var attributedText: NSAttributedString?
    /// Whether EPUB unified loading completed (true = done loading, false = still loading).
    var epubLoadComplete = false
    /// Warning message from EPUB unified loading (e.g., "3 of 10 chapters could not be loaded").
    var epubLoadWarning: String?

    /// Loads text content for the unified reflow engine from TXT files.
    func loadTextContent(fileURL: URL) async {
        let url = fileURL
        let text: String? = await Task.detached {
            try? String(contentsOf: url, encoding: .utf8)
        }.value
        if let text, !text.isEmpty {
            textContent = text
        }
    }

    /// Loads and renders Markdown content as attributed text for the unified engine (WI-B05).
    func loadMDContent(fileURL: URL) async {
        let url = fileURL
        let rawText = await Task.detached {
            try? String(contentsOf: url, encoding: .utf8)
        }.value
        guard let rawText, !rawText.isEmpty else { return }

        let parser = MDParser()
        let docInfo = await parser.parse(text: rawText, config: .default)
        textContent = docInfo.renderedText
        attributedText = docInfo.renderedAttributedString
    }

    /// Loads simple EPUB chapters as attributed text for the unified engine (WI-B07).
    /// Concatenates all simple chapters into one attributed string.
    /// If any chapter is complex, falls back to placeholder.
    /// Issue 10: Counts and reports skipped chapters instead of silently ignoring them.
    func loadEPUBContent(fileURL: URL) async {
        let url = fileURL
        let parser = EPUBParser()
        do {
            let metadata = try await parser.open(url: url)
            let combinedText = NSMutableAttributedString()
            var allSimple = true
            var skippedCount = 0
            let totalCount = metadata.spineItems.count

            for item in metadata.spineItems {
                guard let xhtml = try? await parser.contentForSpineItem(href: item.href) else {
                    skippedCount += 1
                    continue
                }
                if EPUBTextStripper.shouldUseNative(html: xhtml) {
                    allSimple = false
                    break
                }
                if let attrChapter = EPUBTextStripper.attributedString(from: xhtml) {
                    if combinedText.length > 0 {
                        combinedText.append(NSAttributedString(string: "\n\n"))
                    }
                    combinedText.append(attrChapter)
                } else {
                    skippedCount += 1
                }
            }
            await parser.close()

            let result = UnifiedEPUBLoadResult(
                text: combinedText.length > 0 ? combinedText.string : nil,
                attributedText: combinedText.length > 0 ? combinedText : nil,
                skippedChapterCount: skippedCount,
                totalChapterCount: totalCount
            )

            if allSimple, combinedText.length > 0 {
                textContent = combinedText.string
                attributedText = combinedText
            }
            // Issue 10: Surface warning/error for skipped chapters
            if result.allChaptersFailed {
                epubLoadWarning = result.errorMessage
            } else if result.hasSkippedChapters {
                epubLoadWarning = result.warningMessage
            }
            epubLoadComplete = true
        } catch {
            await parser.close()
            epubLoadComplete = true
        }
    }
}
