// Purpose: Placeholder view shown when user selects Unified reading mode.
// The unified reflow engine ships in Phase B (V2); this view explains the status
// and provides a button to switch back to Native mode.
//
// @coordinates-with: ReaderContainerView.swift, ReaderSettingsStore.swift, ReadingMode.swift

import SwiftUI

/// Placeholder for the unified reflow engine (Phase B / V2).
struct UnifiedPlaceholderView: View {
    @Bindable var settingsStore: ReaderSettingsStore

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Unified Mode Coming in V2")
                .font(.title2)
                .fontWeight(.semibold)

            Text("The unified reflow engine is under development. Switch back to Native mode to read this book.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                settingsStore.readingMode = .native
            } label: {
                Label("Switch to Native", systemImage: "arrow.uturn.backward")
                    .font(.body.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Switch to native reading mode")
            .accessibilityIdentifier("unifiedPlaceholderSwitchButton")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("unifiedPlaceholderView")
    }
}
