// Purpose: ViewModifier that attaches shared reader notification handlers.
// Eliminates duplicate .onReceive blocks between TXT and MD container views (WI-003).
//
// Key decisions:
// - Owns AddNoteSheet presentation (single owner — containers must NOT attach their own).
// - contentTapped stays local in each container (chrome toggle is container-specific).
// - Uses ReaderNotificationHandlers for testable pure logic.
// - Bindings are mutated directly in the modifier (no snapshot+syncBack — audit fix).
//
// @coordinates-with ReaderNotificationHandlers.swift,
//   TXTReaderContainerView.swift, MDReaderContainerView.swift,
//   ReaderNotifications.swift, AddNoteSheet.swift

import SwiftUI

/// ViewModifier that attaches 4 notification handlers + AddNoteSheet.
struct ReaderNotificationModifier: ViewModifier {
    let deps: ReaderNotificationDeps

    @Binding var scrollToOffset: Int?
    @Binding var highlightRange: NSRange?
    @Binding var highlightIsTemporary: Bool
    @Binding var persistedHighlightRanges: [NSRange]
    @Binding var pendingAnnotationInfo: TextSelectionInfo?
    @Binding var annotationNoteText: String

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .readerBookmarkRequested)) { _ in
                // Bookmark is fire-and-forget — no UI state mutation needed
                Task {
                    await ReaderNotificationHandlers.handleBookmarkRequest(deps: deps)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .readerNavigateToLocator)) { notification in
                guard let locator = notification.object as? Locator else { return }
                // Sync handler — mutate bindings directly (no race)
                guard let offset = locator.charOffsetUTF16 ?? locator.charRangeStartUTF16 else { return }
                scrollToOffset = offset
                highlightIsTemporary = true
                if let start = locator.charRangeStartUTF16,
                   let end = locator.charRangeEndUTF16, end > start {
                    highlightRange = NSRange(location: start, length: end - start)
                } else {
                    highlightRange = nil
                }
                deps.onNavigate(offset)
            }
            .onReceive(NotificationCenter.default.publisher(for: .readerHighlightRequested)) { notification in
                guard let info = notification.object as? TextSelectionInfo else { return }
                guard info.endUTF16 > info.startUTF16 else { return } // audit fix: validate range
                guard let locator = deps.locatorFactory(
                    deps.bookFingerprint, info.startUTF16, info.endUTF16, deps.sourceText()
                ) else { return }
                // Mutate UI state synchronously before async persistence
                highlightIsTemporary = false
                let newRange = NSRange(location: info.startUTF16, length: info.endUTF16 - info.startUTF16)
                highlightRange = newRange
                persistedHighlightRanges.append(newRange)
                // Fire-and-forget persistence
                Task {
                    try? await deps.highlightPersistence.addHighlight(
                        locator: locator,
                        selectedText: info.selectedText,
                        color: "yellow",
                        note: nil,
                        toBookWithKey: deps.bookFingerprintKey
                    )
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .readerAnnotationRequested)) { notification in
                guard let info = notification.object as? TextSelectionInfo else { return }
                pendingAnnotationInfo = info
                annotationNoteText = ""
            }
            .sheet(isPresented: .init(
                get: { pendingAnnotationInfo != nil },
                set: { if !$0 { pendingAnnotationInfo = nil } }
            )) {
                AddNoteSheet(
                    selectedText: pendingAnnotationInfo?.selectedText ?? "",
                    noteText: $annotationNoteText,
                    onSave: {
                        guard let info = pendingAnnotationInfo else {
                            pendingAnnotationInfo = nil
                            return
                        }
                        let trimmed = annotationNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else {
                            pendingAnnotationInfo = nil
                            return
                        }
                        guard let locator = deps.locatorFactory(
                            deps.bookFingerprint, info.startUTF16, info.endUTF16, deps.sourceText()
                        ) else {
                            pendingAnnotationInfo = nil
                            return
                        }
                        pendingAnnotationInfo = nil
                        Task {
                            try? await deps.annotationPersistence.addAnnotation(
                                locator: locator,
                                content: trimmed,
                                toBookWithKey: deps.bookFingerprintKey
                            )
                        }
                    },
                    onCancel: {
                        pendingAnnotationInfo = nil
                    }
                )
                .presentationDetents([.medium])
            }
    }
}

// MARK: - View Extension

extension View {
    /// Attaches shared reader notification handlers and AddNoteSheet.
    func readerNotificationHandlers(
        deps: ReaderNotificationDeps,
        scrollToOffset: Binding<Int?>,
        highlightRange: Binding<NSRange?>,
        highlightIsTemporary: Binding<Bool>,
        persistedHighlightRanges: Binding<[NSRange]>,
        pendingAnnotationInfo: Binding<TextSelectionInfo?>,
        annotationNoteText: Binding<String>
    ) -> some View {
        modifier(ReaderNotificationModifier(
            deps: deps,
            scrollToOffset: scrollToOffset,
            highlightRange: highlightRange,
            highlightIsTemporary: highlightIsTemporary,
            persistedHighlightRanges: persistedHighlightRanges,
            pendingAnnotationInfo: pendingAnnotationInfo,
            annotationNoteText: annotationNoteText
        ))
    }
}
