// Purpose: Static catalog of fixture books bundled with DEBUG builds, used by
// vreader-debug://seed (feature #44 DebugBridge). Each entry maps a stable
// fixture name to a bundle resource so automated tests have deterministic
// content to load. Adding a new fixture: drop the file into
// vreader/Resources/DebugFixtures/ and add a catalog entry here.
// DEBUG-only.

#if DEBUG

import Foundation

/// A bundled fixture book.
struct DebugFixture: Equatable {
    /// Stable identifier passed to `vreader-debug://seed?fixture=<name>`.
    let name: String
    /// Source format. Drives the importer/reader path the seeded book uses.
    let format: Format
    /// Bundle resource base name (without extension).
    let resourceName: String
    /// Bundle resource file extension (without dot).
    let resourceExtension: String

    enum Format: String, Equatable {
        case epub
        case txt
        case pdf
        case azw3
        case md
    }
}

/// Static catalog of fixture books. Single source of truth for fixture names.
enum DebugFixtureCatalog {

    private static let entries: [DebugFixture] = [
        DebugFixture(name: "alice",      format: .epub, resourceName: "alice",      resourceExtension: "epub"),
        DebugFixture(name: "warpeace",   format: .txt,  resourceName: "warpeace",   resourceExtension: "txt"),
        DebugFixture(name: "sample-pdf", format: .pdf,  resourceName: "sample-pdf", resourceExtension: "pdf"),
    ]

    /// All catalog entries.
    static func all() -> [DebugFixture] {
        return entries
    }

    /// Look up a fixture by name. Returns nil for unknown or empty names.
    static func find(name: String) -> DebugFixture? {
        guard !name.isEmpty else { return nil }
        return entries.first { $0.name == name }
    }
}

#endif
