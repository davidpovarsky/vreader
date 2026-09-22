// Purpose: Low-conflict home-source UI for Library + saved OPDS catalogs.
//
// This file deliberately reuses the committed Library visual language:
// Source Serif title typography, warm-paper palette, and the existing
// LibraryCardTokens. The menu behavior is native SwiftUI Menu, while its label
// renders exactly where the original "Library" title lives.
//
// Upstream integration is intentionally tiny: LibraryView owns one selection
// state, renders HomeSourceTitleMenu in its existing title block, and swaps only
// the content region below that title.

import SwiftUI

enum HomeSourceSelection: Hashable {
    case library
    case hebrewBooks
    case catalog(UUID)
}

struct HomeSourceTitleMenu: View {
    @Binding var selection: HomeSourceSelection
    let catalogs: [OPDSSavedCatalog]
    let onManageCatalogs: () -> Void

    private var currentTitle: String {
        switch selection {
        case .library:
            return "Library"
        case .hebrewBooks:
            return "HebrewBooks"
        case .catalog(let id):
            return catalogs.first(where: { $0.id == id })?.name ?? "Catalog"
        }
    }

    var body: some View {
        Menu {
            Button {
                selection = .library
            } label: {
                Label(
                    "Library",
                    systemImage: selection == .library ? "checkmark" : "books.vertical"
                )
            }

            Button {
                selection = .hebrewBooks
            } label: {
                Label(
                    "HebrewBooks",
                    systemImage: selection == .hebrewBooks
                        ? "checkmark"
                        : "book.closed"
                )
            }

            if !catalogs.isEmpty {
                Divider()

                Section("Catalogs") {
                    ForEach(catalogs) { catalog in
                        Button {
                            selection = .catalog(catalog.id)
                        } label: {
                            Label(
                                catalog.name,
                                systemImage: selection == .catalog(catalog.id)
                                    ? "checkmark"
                                    : "globe"
                            )
                        }
                    }
                }
            }

            Divider()

            Button(action: onManageCatalogs) {
                Label("Manage Catalogs…", systemImage: "slider.horizontal.3")
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(currentTitle)
                    .font(LibraryCardTokens.serifTitleFont(
                        size: LibraryCardTokens.titleFontSize
                    ))
                    .fontWeight(.semibold)
                    .foregroundStyle(LibraryCardTokens.ink)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LibraryCardTokens.subText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Reading source")
        .accessibilityValue(currentTitle)
        .accessibilityIdentifier("homeSourceMenu")
    }
}

/// Read-only projection of the existing upstream OPDS catalog storage.
///
/// OPDSCatalogListView remains the sole writer. Keeping storage ownership there
/// avoids duplicating upstream behavior and makes future merges low-conflict.
enum HomeCatalogStore {
    private static let storageKey = "opds.savedCatalogs"
    private static let keychainServiceIdentifier = "com.vreader.opds"

    static func loadCatalogs(
        defaults: UserDefaults = .standard
    ) -> [OPDSSavedCatalog] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([OPDSSavedCatalog].self, from: data)
        else {
            return []
        }

        let keychain = KeychainService(serviceIdentifier: keychainServiceIdentifier)

        return decoded.map { catalog in
            var hydrated = catalog
            if let stored = try? keychain.readString(forAccount: catalog.id.uuidString),
               !stored.isEmpty {
                hydrated.password = stored
            }
            return hydrated
        }
    }

    static func credentials(for catalog: OPDSSavedCatalog) -> OPDSCredentials? {
        guard let username = catalog.username,
              let password = catalog.password,
              !username.isEmpty
        else {
            return nil
        }
        return OPDSCredentials(username: username, password: password)
    }
}
