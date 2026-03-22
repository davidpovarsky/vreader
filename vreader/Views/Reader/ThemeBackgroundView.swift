#if canImport(UIKit)
import SwiftUI
import UIKit
struct ThemeBackgroundView: View {
    let settingsStore: ReaderSettingsStore
    @State private var backgroundImage: UIImage?
    var body: some View {
        ZStack {
            Color(settingsStore.uiBackgroundColor).ignoresSafeArea()
            if settingsStore.useCustomBackground, let image = backgroundImage {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
                    .opacity(settingsStore.backgroundOpacity).ignoresSafeArea()
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .onAppear { loadBackground() }
        .onChange(of: settingsStore.theme) { _, _ in loadBackground() }
        .onChange(of: settingsStore.useCustomBackground) { _, v in if v { loadBackground() } }
    }
    private func loadBackground() {
        backgroundImage = ThemeBackgroundStore.loadBackground(for: settingsStore.theme.rawValue)
    }
}
#endif
