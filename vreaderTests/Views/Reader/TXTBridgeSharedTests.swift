// Purpose: Tests for shared TXT bridge functions extracted in WI-002.
// Validates postSelectionNotification and buildReaderEditMenu.

import Testing
import Foundation
import UIKit
@testable import vreader

@Suite("TXTBridgeShared")
struct TXTBridgeSharedTests {

    // MARK: - postSelectionNotification

    @Test @MainActor func postSelectionNotificationPostsCorrectInfo() async {
        let tv = UITextView()
        tv.text = "Hello World"
        let range = NSRange(location: 0, length: 5)

        var received: TextSelectionInfo?
        let observer = NotificationCenter.default.addObserver(
            forName: .readerHighlightRequested, object: nil, queue: .main
        ) { note in
            received = note.object as? TextSelectionInfo
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        TXTBridgeShared.postSelectionNotification(
            .readerHighlightRequested, from: tv, range: range
        )

        #expect(received != nil)
        #expect(received?.selectedText == "Hello")
        #expect(received?.startUTF16 == 0)
        #expect(received?.endUTF16 == 5)
    }

    @Test @MainActor func postSelectionNotificationWithChunkOffset() async {
        let tv = UITextView()
        tv.text = "World"
        let range = NSRange(location: 0, length: 5)

        var received: TextSelectionInfo?
        let observer = NotificationCenter.default.addObserver(
            forName: .readerAnnotationRequested, object: nil, queue: .main
        ) { note in
            received = note.object as? TextSelectionInfo
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        TXTBridgeShared.postSelectionNotification(
            .readerAnnotationRequested, from: tv, range: range, chunkOffset: 1000
        )

        #expect(received != nil)
        #expect(received?.selectedText == "World")
        #expect(received?.startUTF16 == 1000)
        #expect(received?.endUTF16 == 1005)
    }

    @Test @MainActor func postSelectionNotificationIgnoresOutOfBoundsRange() {
        let tv = UITextView()
        tv.text = "Hi"
        let range = NSRange(location: 0, length: 999)

        var received: TextSelectionInfo?
        let observer = NotificationCenter.default.addObserver(
            forName: .readerHighlightRequested, object: nil, queue: .main
        ) { note in
            received = note.object as? TextSelectionInfo
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        TXTBridgeShared.postSelectionNotification(
            .readerHighlightRequested, from: tv, range: range
        )

        #expect(received == nil)
    }

    @Test @MainActor func postSelectionNotificationIgnoresEmptyText() {
        let tv = UITextView()
        tv.text = ""
        let range = NSRange(location: 0, length: 0)

        var received: TextSelectionInfo?
        let observer = NotificationCenter.default.addObserver(
            forName: .readerHighlightRequested, object: nil, queue: .main
        ) { note in
            received = note.object as? TextSelectionInfo
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        TXTBridgeShared.postSelectionNotification(
            .readerHighlightRequested, from: tv, range: range
        )

        // Empty range — should still post (empty selection is valid for position marking)
        // But text is empty so range.location + range.length (0) <= nsText.length (0) passes
        #expect(received != nil)
        #expect(received?.selectedText == "")
    }

    // MARK: - buildReaderEditMenu

    @Test @MainActor func buildReaderEditMenuReturnsTwoActions() {
        let tv = UITextView()
        tv.text = "Hello World"
        let range = NSRange(location: 0, length: 5)

        let menu = TXTBridgeShared.buildReaderEditMenu(
            range: range, textView: tv, suggestedActions: []
        )

        #expect(menu != nil)
        // First child is our inline menu with 2 actions
        let children = menu!.children
        #expect(children.count == 1)
        if let inlineMenu = children.first as? UIMenu {
            #expect(inlineMenu.children.count == 2)
            if let highlight = inlineMenu.children.first as? UIAction {
                #expect(highlight.title == "Highlight")
            }
            if let note = inlineMenu.children.last as? UIAction {
                #expect(note.title == "Add Note")
            }
        }
    }

    @Test @MainActor func buildReaderEditMenuPassesThroughSuggestedActionsForEmptyRange() {
        let tv = UITextView()
        tv.text = "Hello"
        let range = NSRange(location: 0, length: 0)
        let suggested = [UIAction(title: "Copy") { _ in }]

        let menu = TXTBridgeShared.buildReaderEditMenu(
            range: range, textView: tv, suggestedActions: suggested
        )

        #expect(menu != nil)
        #expect(menu!.children.count == 1) // only suggested, no custom
    }

    // MARK: - postContentTappedNotification

    @Test @MainActor func postContentTappedNotificationPostsCorrectName() {
        var received = false
        let observer = NotificationCenter.default.addObserver(
            forName: .readerContentTapped, object: nil, queue: .main
        ) { _ in
            received = true
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        TXTBridgeShared.postContentTappedNotification()

        #expect(received == true)
    }
}
