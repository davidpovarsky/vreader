#!/usr/bin/env python3
"""Apply CI-only source rewrites needed to produce a preview unsigned IPA.

These edits run only in the GitHub Actions checkout. They avoid Swift 6.1
main-actor default-argument diagnostics that block preview builds of the fork.
They do not change app behavior: each default value is still created, but inside
the initializer/function body instead of in the default-argument expression.
"""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def patch(path: str, replacements: list[tuple[str, str]]) -> None:
    file_path = ROOT / path
    text = file_path.read_text()
    original = text
    for old, new in replacements:
        if old not in text:
            raise SystemExit(f"error: pattern not found in {path}: {old[:120]!r}")
        text = text.replace(old, new, 1)
    if text != original:
        file_path.write_text(text)
        print(f"patched {path}")


patch(
    "vreader/Views/Reader/Bilingual/ReaderAIProvidersFlow.swift",
    [
        (
            """    init(\n        viewModel: AISettingsViewModel = AISettingsViewModel(),\n        onConfigured: @escaping () async -> Void\n    ) {\n        self.viewModel = viewModel\n        self.onConfigured = onConfigured\n    }""",
            """    init(\n        viewModel: AISettingsViewModel? = nil,\n        onConfigured: @escaping () async -> Void\n    ) {\n        self.viewModel = viewModel ?? AISettingsViewModel()\n        self.onConfigured = onConfigured\n    }""",
        ),
    ],
)

patch(
    "vreader/Views/Settings/Diagnostics/DiagnosticsLogView.swift",
    [
        (
            """    init(\n        theme: ReaderThemeV2 = .paper,\n        viewModel: DiagnosticsLogViewModel = DiagnosticsLogViewModel()\n    ) {\n        self.theme = theme\n        _viewModel = State(initialValue: viewModel)\n    }""",
            """    @MainActor\n    init(\n        theme: ReaderThemeV2 = .paper,\n        viewModel: DiagnosticsLogViewModel? = nil\n    ) {\n        self.theme = theme\n        _viewModel = State(initialValue: viewModel ?? DiagnosticsLogViewModel())\n    }""",
        ),
    ],
)

patch(
    "vreader/Views/Settings/Diagnostics/DiagnosticsLogViewModel.swift",
    [
        (
            """    init(store: DiagnosticsLogStore = DiagnosticsLogStore()) {\n        self.store = store\n    }""",
            """    init(store: DiagnosticsLogStore? = nil) {\n        self.store = store ?? DiagnosticsLogStore()\n    }""",
        ),
    ],
)

patch(
    "vreader/Views/Reader/FoliateHighlightMutator.swift",
    [
        (
            """    init(\n        persistence: any HighlightPersisting,\n        bookFingerprintKey: String,\n        jsBridge: FoliateHighlightJSBridge = FoliateHighlightJSBridge()\n    ) {\n        self.persistence = persistence\n        self.bookFingerprintKey = bookFingerprintKey\n        self.jsBridge = jsBridge\n    }""",
            """    init(\n        persistence: any HighlightPersisting,\n        bookFingerprintKey: String,\n        jsBridge: FoliateHighlightJSBridge? = nil\n    ) {\n        self.persistence = persistence\n        self.bookFingerprintKey = bookFingerprintKey\n        self.jsBridge = jsBridge ?? FoliateHighlightJSBridge()\n    }""",
        ),
    ],
)

patch(
    "vreader/Services/TTS/HTTPSpeechSynthesizer.swift",
    [
        (
            """    @MainActor\n    init(\n        config: HTTPTTSConfig,\n        player: HTTPTTSChunkPlayer = HTTPTTSChunkPlayer(),\n        makeProvider: @escaping (HTTPTTSConfig) -> TTSProvider = { HTTPTTSProvider(config: $0) }\n    ) {\n        self.config = config\n        self.player = player\n        self.makeProvider = makeProvider\n        super.init()\n    }""",
            """    @MainActor\n    init(\n        config: HTTPTTSConfig,\n        player: HTTPTTSChunkPlayer? = nil,\n        makeProvider: @escaping (HTTPTTSConfig) -> TTSProvider = { HTTPTTSProvider(config: $0) }\n    ) {\n        self.config = config\n        self.player = player ?? HTTPTTSChunkPlayer()\n        self.makeProvider = makeProvider\n        super.init()\n    }""",
        ),
    ],
)

patch(
    "vreader/Views/Reader/HighlightPopoverModifierBody.swift",
    [
        (
            """    func unifiedHighlightPopoverPresenter(\n        viewModel: HighlightPopoverViewModel,\n        router: HighlightPopoverActionRouter,\n        cardPresenter: any HighlightPopoverPresenting = UIKitHighlightPopoverPresenter(),\n        theme: ReaderThemeV2,\n        chapter: String? = nil,\n        hostViewProvider: @escaping () -> UIView?\n    ) -> some View {\n        modifier(\n            HighlightPopoverModifier(\n                viewModel: viewModel,\n                router: router,\n                cardPresenter: cardPresenter,\n                theme: theme,\n                chapter: chapter,\n                hostViewProvider: hostViewProvider\n            )\n        )\n    }""",
            """    @MainActor\n    func unifiedHighlightPopoverPresenter(\n        viewModel: HighlightPopoverViewModel,\n        router: HighlightPopoverActionRouter,\n        cardPresenter: (any HighlightPopoverPresenting)? = nil,\n        theme: ReaderThemeV2,\n        chapter: String? = nil,\n        hostViewProvider: @escaping () -> UIView?\n    ) -> some View {\n        modifier(\n            HighlightPopoverModifier(\n                viewModel: viewModel,\n                router: router,\n                cardPresenter: cardPresenter ?? UIKitHighlightPopoverPresenter(),\n                theme: theme,\n                chapter: chapter,\n                hostViewProvider: hostViewProvider\n            )\n        )\n    }""",
        ),
    ],
)

patch(
    "vreader/Services/TTS/TTSService.swift",
    [
        (
            """    init(synthesizerFactory: () -> SpeechSynthesizing = { TTSService.defaultSynthesizer() }) {\n        self.synthesizer = synthesizerFactory()\n        super.init()""",
            """    init(synthesizerFactory: (() -> SpeechSynthesizing)? = nil) {\n        let factory = synthesizerFactory ?? { TTSService.defaultSynthesizer() }\n        self.synthesizer = factory()\n        super.init()""",
        ),
    ],
)

patch(
    "vreader/Services/Backup/WebDAVProviderFactory.swift",
    [
        (
            """        appVersion: String = currentAppVersion(),\n        deviceName: String = currentDeviceName(),\n        bookImporter: (any BookImporting)? = nil\n    ) async throws -> WebDAVProvider {""",
            """        appVersion: String = currentAppVersion(),\n        deviceName: String? = nil,\n        bookImporter: (any BookImporting)? = nil\n    ) async throws -> WebDAVProvider {\n        let resolvedDeviceName = deviceName ?? currentDeviceName()""",
        ),
        (
            """            deviceName: deviceName,""",
            """            deviceName: resolvedDeviceName,""",
        ),
    ],
)
