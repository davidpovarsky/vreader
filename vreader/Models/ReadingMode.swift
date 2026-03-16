// Purpose: Defines the reading mode toggle — Native vs Unified rendering engine.
// Native dispatches to format-specific readers; Unified uses a shared reflow engine (Phase B).
//
// Key decisions:
// - String-backed RawRepresentable for UserDefaults persistence.
// - Default is .native (all existing readers are native).
// - .unified is a placeholder until the unified engine ships in V2.
//
// @coordinates-with: ReaderSettingsStore.swift, ReaderContainerView.swift

/// Reading engine mode: native per-format readers vs unified reflow engine.
enum ReadingMode: String, Codable, Sendable, Hashable, CaseIterable {
    /// Per-format native reader (EPUB WebView, PDF PDFKit, TXT/MD attributed string).
    case native
    /// Unified reflow engine for reflowable formats (TXT, MD, simple EPUB).
    /// Placeholder — actual engine ships in Phase B (V2).
    case unified
}
