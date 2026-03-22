// Purpose: Unified-mode dispatch and error/unsupported format placeholder views
// for ReaderContainerView. Pure code extraction — no logic changes.
//
// @coordinates-with: ReaderContainerView.swift, UnifiedTextRenderer.swift,
//   UnifiedPlaceholderView.swift, ReaderUnifiedCoordinator.swift

import SwiftUI

extension ReaderContainerView {

    /// Dispatches to the unified reflow engine for supported formats,
    /// or falls back to native reader for complex content.
    /// - TXT: plain text, no formatting.
    /// - MD: attributed text with bold/italic/headings (WI-B05).
    /// - EPUB (simple): HTML converted to attributed text (WI-B07).
    /// - EPUB (complex): falls back to native WKWebView reader (Phase B Audit fix).
    @ViewBuilder
    func unifiedReaderView(fingerprint: DocumentFingerprint) -> some View {
        switch book.format.lowercased() {
        case "txt":
            if let text = unifiedCoordinator.textContent {
                UnifiedTextRenderer(
                    text: text,
                    settingsStore: settingsStore,
                    readingProgress: $unifiedReadingProgress,
                    paginationCache: paginationCache,
                    documentFingerprint: fingerprint.canonicalKey
                )
                .tapZoneOverlay(config: tapZoneStore.config)
            } else {
                ProgressView("Loading\u{2026}")
                    .task { await unifiedCoordinator.loadTextContent(fileURL: resolvedFileURL) }
            }
        case "md":
            if let text = unifiedCoordinator.textContent {
                UnifiedTextRenderer(
                    text: text,
                    settingsStore: settingsStore,
                    readingProgress: $unifiedReadingProgress,
                    attributedText: unifiedCoordinator.attributedText,
                    paginationCache: paginationCache,
                    documentFingerprint: fingerprint.canonicalKey
                )
                .tapZoneOverlay(config: tapZoneStore.config)
            } else {
                ProgressView("Loading\u{2026}")
                    .task { await unifiedCoordinator.loadMDContent(fileURL: resolvedFileURL) }
            }
        case "epub":
            if let text = unifiedCoordinator.textContent {
                VStack(spacing: 0) {
                    // Issue 10: Show warning banner when some chapters were skipped
                    if let warning = unifiedCoordinator.epubLoadWarning {
                        Text(warning)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                            .background(Color.orange.opacity(0.1))
                            .accessibilityIdentifier("epubUnifiedLoadWarning")
                    }
                    UnifiedTextRenderer(
                        text: text,
                        settingsStore: settingsStore,
                        readingProgress: $unifiedReadingProgress,
                        attributedText: unifiedCoordinator.attributedText,
                        paginationCache: paginationCache,
                        documentFingerprint: fingerprint.canonicalKey
                    )
                    .tapZoneOverlay(config: tapZoneStore.config)
                }
            } else if unifiedCoordinator.epubLoadComplete {
                // EPUB has complex chapters — fall back to native WKWebView reader.
                // No tapZoneOverlay — WKWebView has its own JS click handler. (bug #70)
                nativeReaderView(fingerprint: fingerprint)
            } else {
                ProgressView("Loading\u{2026}")
                    .task { await unifiedCoordinator.loadEPUBContent(fileURL: resolvedFileURL) }
            }
        default:
            UnifiedPlaceholderView(settingsStore: settingsStore)
        }
    }

    var fingerprintErrorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Unable to open this book.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("fingerprintErrorView")
    }

    func unsupportedFormatView(format: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("\(format) reader coming soon")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("unsupportedFormatView")
    }
}
