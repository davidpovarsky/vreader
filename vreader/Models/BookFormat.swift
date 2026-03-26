// Purpose: Defines supported book formats for the reader.
// .md is importable as of WI-6B.
//
// @coordinates-with: FormatCapabilities.swift — `capabilities` convenience property

/// Supported document formats for the reader.
enum BookFormat: String, Codable, Hashable, Sendable, CaseIterable {
    case epub
    case pdf
    case txt
    case md
    case azw3

    /// Formats that can be imported.
    static var importableFormats: [BookFormat] {
        [.epub, .pdf, .txt, .md, .azw3]
    }

    /// Whether this format is importable.
    var isImportableV1: Bool {
        true
    }

    /// Common file extensions for this format.
    var fileExtensions: [String] {
        switch self {
        case .epub: return ["epub"]
        case .pdf: return ["pdf"]
        case .txt: return ["txt", "text"]
        case .md: return ["md", "markdown"]
        case .azw3: return ["azw3", "azw", "mobi", "prc"]
        }
    }

    /// Default capabilities for this format (assumes simple EPUB).
    var capabilities: FormatCapabilities {
        FormatCapabilities.capabilities(for: self)
    }
}
