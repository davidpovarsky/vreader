// Purpose: Format-specific host views that own ViewModel lifecycle via @State.
// Each host creates its ViewModel on appear and passes it to the format container.
// Extracted from ReaderContainerView (WI-004) to reduce file size.
//
// @coordinates-with ReaderContainerView.swift, TXTReaderContainerView.swift,
//   PDFReaderContainerView.swift, MDReaderContainerView.swift,
//   EPUBReaderContainerView.swift

#if canImport(UIKit)
import SwiftUI
import SwiftData

/// Owns TXTReaderViewModel lifecycle via @State.
struct TXTReaderHost: View {
    let fileURL: URL
    let fingerprint: DocumentFingerprint
    let modelContainer: ModelContainer
    let settingsStore: ReaderSettingsStore
    let ttsService: TTSService

    @State private var viewModel: TXTReaderViewModel?

    var body: some View {
        Group {
            if let viewModel {
                TXTReaderContainerView(fileURL: fileURL, viewModel: viewModel, settingsStore: settingsStore, modelContainer: modelContainer, ttsService: ttsService)
            } else {
                ProgressView()
            }
        }
        .task {
            guard viewModel == nil else { return }
            let persistence = PersistenceActor(modelContainer: modelContainer)
            let tracker = ReadingSessionTracker(
                clock: SystemClock(),
                store: SwiftDataSessionStore(modelContainer: modelContainer),
                deviceId: ReaderContainerView.deviceId
            )
            viewModel = TXTReaderViewModel(
                bookFingerprint: fingerprint,
                txtService: TXTService(),
                positionStore: persistence,
                sessionTracker: tracker,
                deviceId: ReaderContainerView.deviceId
            )
        }
    }
}

/// Owns PDFReaderViewModel lifecycle via @State.
struct PDFReaderHost: View {
    let fileURL: URL
    let fingerprint: DocumentFingerprint
    let modelContainer: ModelContainer
    let ttsService: TTSService

    @State private var viewModel: PDFReaderViewModel?

    var body: some View {
        Group {
            if let viewModel {
                PDFReaderContainerView(fileURL: fileURL, viewModel: viewModel, modelContainer: modelContainer, ttsService: ttsService)
            } else {
                ProgressView()
            }
        }
        .task {
            guard viewModel == nil else { return }
            let persistence = PersistenceActor(modelContainer: modelContainer)
            let tracker = ReadingSessionTracker(
                clock: SystemClock(),
                store: SwiftDataSessionStore(modelContainer: modelContainer),
                deviceId: ReaderContainerView.deviceId
            )
            viewModel = PDFReaderViewModel(
                bookFingerprint: fingerprint,
                positionStore: persistence,
                sessionTracker: tracker,
                deviceId: ReaderContainerView.deviceId
            )
        }
    }
}

/// Owns MDReaderViewModel lifecycle via @State.
struct MDReaderHost: View {
    let fileURL: URL
    let fingerprint: DocumentFingerprint
    let modelContainer: ModelContainer
    let settingsStore: ReaderSettingsStore
    let ttsService: TTSService

    @State private var viewModel: MDReaderViewModel?

    var body: some View {
        Group {
            if let viewModel {
                MDReaderContainerView(fileURL: fileURL, viewModel: viewModel, settingsStore: settingsStore, modelContainer: modelContainer, ttsService: ttsService)
            } else {
                ProgressView()
            }
        }
        .task {
            guard viewModel == nil else { return }
            let persistence = PersistenceActor(modelContainer: modelContainer)
            let tracker = ReadingSessionTracker(
                clock: SystemClock(),
                store: SwiftDataSessionStore(modelContainer: modelContainer),
                deviceId: ReaderContainerView.deviceId
            )
            viewModel = MDReaderViewModel(
                bookFingerprint: fingerprint,
                parser: MDParser(),
                positionStore: persistence,
                sessionTracker: tracker,
                deviceId: ReaderContainerView.deviceId
            )
        }
    }
}

/// Owns EPUBReaderViewModel lifecycle via @State.
struct EPUBReaderHost: View {
    let fileURL: URL
    let fingerprint: DocumentFingerprint
    let modelContainer: ModelContainer
    let settingsStore: ReaderSettingsStore
    let ttsService: TTSService

    @State private var viewModel: EPUBReaderViewModel?
    @State private var parser: EPUBParser?

    var body: some View {
        Group {
            if let viewModel, let parser {
                EPUBReaderContainerView(
                    fileURL: fileURL,
                    viewModel: viewModel,
                    parser: parser,
                    settingsStore: settingsStore,
                    modelContainer: modelContainer,
                    ttsService: ttsService
                )
            } else {
                ProgressView()
            }
        }
        .task {
            guard viewModel == nil else { return }
            let persistence = PersistenceActor(modelContainer: modelContainer)
            let tracker = ReadingSessionTracker(
                clock: SystemClock(),
                store: SwiftDataSessionStore(modelContainer: modelContainer),
                deviceId: ReaderContainerView.deviceId
            )
            let epubParser = EPUBParser()
            parser = epubParser
            viewModel = EPUBReaderViewModel(
                bookFingerprint: fingerprint,
                parser: epubParser,
                positionStore: persistence,
                sessionTracker: tracker,
                deviceId: ReaderContainerView.deviceId
            )
        }
    }
}
#endif
