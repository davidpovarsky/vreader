// Purpose: Isolated home-source switcher for Library + saved OPDS catalogs.
//
// This feature intentionally lives outside the upstream Library / OPDS screens.
// The only integration point is one ViewModifier on LibraryView's root. Keeping
// source selection, catalog presentation and catalog management here minimizes
// merge conflicts when pulling future upstream changes.

import SwiftUI

enum HomeSourceSelection: Hashable {
    case library
    case catalog(UUID)
}

struct HomeSourceLayer: ViewModifier {
    @Environment(\.persistenceActor) private var persistenceActor

    @State private var selection: HomeSourceSelection = .library
    @State private var catalogs: [OPDSSavedCatalog] = []
    @State private var isShowingCatalogManager = false
    @State private var didRunTransientCleanup = false

    func body(content: Content) -> some View {
        Group {
            switch selection {
            case .library:
                VStack(spacing: 0) {
                    sourceBar
                    content
                }

            case .catalog(let id):
                if let catalog = catalogs.first(where: { $0.id == id }),
                   let url = URL(string: catalog.url) {
                    NavigationStack {
                        VStack(spacing: 0) {
                            sourceBar
                            HomeCatalogBrowserView(
                                catalogURL: url,
                                catalogName: catalog.name,
                                credentials: HomeCatalogStore.credentials(for: catalog)
                            )
                        }
                    }
                } else {
                    VStack(spacing: 0) {
                        sourceBar
                        ContentUnavailableView(
                            "Catalog Unavailable",
                            systemImage: "globe.badge.chevron.backward",
                            description: Text("The selected catalog is no longer available.")
                        )
                    }
                    .onAppear {
                        selection = .library
                    }
                }
            }
        }
        .onAppear {
            reloadCatalogs()

            guard !didRunTransientCleanup else { return }
            didRunTransientCleanup = true
            Task {
                await CatalogTransientStore.cleanupStale(using: persistenceActor)
            }
        }
        .sheet(isPresented: $isShowingCatalogManager, onDismiss: reloadCatalogs) {
            NavigationStack {
                OPDSCatalogListView()
                    .navigationTitle("OPDS Catalogs")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") {
                                isShowingCatalogManager = false
                            }
                        }
                    }
            }
        }
    }

    private var sourceBar: some View {
        HomeSourceBar(
            selection: $selection,
            catalogs: catalogs,
            onManageCatalogs: {
                isShowingCatalogManager = true
            }
        )
    }

    private func reloadCatalogs() {
        catalogs = HomeCatalogStore.loadCatalogs()

        if case .catalog(let id) = selection,
           !catalogs.contains(where: { $0.id == id }) {
            selection = .library
        }
    }
}

private struct HomeSourceBar: View {
    @Binding var selection: HomeSourceSelection
    let catalogs: [OPDSSavedCatalog]
    let onManageCatalogs: () -> Void

    private var currentTitle: String {
        switch selection {
        case .library:
            return "Library"
        case .catalog(let id):
            return catalogs.first(where: { $0.id == id })?.name ?? "Catalog"
        }
    }

    private var currentSymbol: String {
        switch selection {
        case .library:
            return "books.vertical"
        case .catalog:
            return "globe"
        }
    }

    var body: some View {
        HStack {
            Menu {
                Button {
                    selection = .library
                } label: {
                    Label(
                        "Library",
                        systemImage: selection == .library ? "checkmark" : "books.vertical"
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
                HStack(spacing: 7) {
                    Image(systemName: currentSymbol)
                    Text(currentTitle)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Reading source")
            .accessibilityValue(currentTitle)
            .accessibilityIdentifier("homeSourceMenu")

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.thinMaterial)
    }
}

/// Read-only projection of the existing upstream OPDS catalog storage.
///
/// The upstream manager remains the sole writer. This layer reads the same
/// UserDefaults contract and hydrates passwords from the same Keychain service.
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
