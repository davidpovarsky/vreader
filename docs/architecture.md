# VReader Architecture

## Overview

VReader is an iOS e-book reader built with SwiftUI + SwiftData. It supports TXT, EPUB, PDF, and MD formats with dual rendering modes (Native UIKit bridges + Unified TextKit 2 reflow).

## System Diagram

```
┌──────────────────────────────────────────────────────┐
│                    VReaderApp                         │
│  SwiftData SchemaV3 · PersistenceActor · BookImporter│
└─────────────────────┬────────────────────────────────┘
                      │
          ┌───────────┴───────────┐
          │                       │
    ┌─────▼──────────┐    ┌──────▼──────────────────┐
    │  LibraryView    │    │  ReaderContainerView     │
    │  LibraryViewModel│   │  (format dispatcher)     │
    │  PreferenceStore │   │  ReaderChromeBar (overlay)│
    └─────────────────┘   └──────┬───────────────────┘
                                 │
        ┌────────┬───────────┬───┴────┐
        │        │           │        │
    ┌───▼──┐ ┌──▼───┐  ┌───▼──┐ ┌──▼───┐
    │ TXT  │ │ EPUB │  │ PDF  │ │  MD  │
    │Bridge│ │Bridge│  │Bridge│ │Bridge│
    └──────┘ └──────┘  └──────┘ └──────┘
    UITextView WKWebView PDFKit  UITextView
```

## Layers

### 1. App Layer (`vreader/App/`)
- `VReaderApp.swift` — SwiftData ModelContainer init, migration plan (V1→V2→V3), test seeding, error handling

### 2. Library Layer (`vreader/Views/LibraryView.swift`, `vreader/ViewModels/LibraryViewModel.swift`)
- Grid/list view with sort (persisted via `PreferenceStore`)
- Context menu: Info, Share, Set Cover, Delete
- Collections sidebar, OPDS catalog, AI chat entry points

### 3. Reader Layer (`vreader/Views/Reader/`)

#### Dispatcher
`ReaderContainerView.swift` routes to format-specific readers:
- If unified mode + format supports reflow → `UnifiedTextRenderer`
- Else → native format host (UIKit bridge)

#### Chrome
`ReaderChromeBar.swift` — custom overlay toolbar (not system nav bar). Floats on top of content, no safe area impact. Buttons: back, search, bookmark, annotations, AI, TTS, settings.

#### Format Hosts (`ReaderFormatHosts.swift`)
Each host owns its ViewModel lifecycle via `@State`:
- `TXTReaderHost` → `TXTReaderContainerView` → `TXTTextViewBridge` (small) or `TXTChunkedReaderBridge` (>500K UTF-16)
- `EPUBReaderHost` → `EPUBReaderContainerView` → `EPUBWebViewBridge` (WKWebView + JS injection)
- `PDFReaderHost` → `PDFReaderContainerView` → `PDFViewBridge` (PDFKit)
- `MDReaderHost` → `MDReaderContainerView` → reuses `TXTTextViewBridge` with NSAttributedString

#### Unified Engine
`ReaderUnifiedCoordinator` loads text + applies transforms (replacement rules, simp/trad). `UnifiedTextRenderer` displays with TextKit 2 pagination or scroll.

### 4. Coordinator Layer (`vreader/Views/Reader/`)

| Coordinator | Responsibility | Setup Timing |
|-------------|---------------|--------------|
| `ReaderAICoordinator` | AI ViewModels, text loading, context extraction | On AI/TTS invoke |
| `ReaderSearchCoordinator` | Search service, indexing, FTS5 | Service+VM on reader open (`prepareService`), indexing on search open |
| `ReaderUnifiedCoordinator` | Unified renderer state, text transforms | On reader open (unified mode only) |

### 5. Services Layer (`vreader/Services/`)

| Service | Backing | Purpose |
|---------|---------|---------|
| `PersistenceActor` | SwiftData (actor-isolated) | All DB writes serialized |
| `SearchService` + `SearchIndexStore` | SQLite FTS5 | Full-text search with persistent index |
| `AIService` | OpenAI-compatible REST API | Summarize, translate, chat |
| `TTSService` | AVSpeechSynthesizer + HTTP | Read aloud with controls |
| `BookContentCache` | In-memory | Text cache for AI context loading (TXT/MD only) |
| `PreferenceStore` | UserDefaults | Sort order, view mode persistence |
| `CustomCoverStore` | JPEG files | Custom book cover images |
| `WebDAVClient` | HTTP | Backup/restore to WebDAV server |

### 6. Data Layer (`vreader/Models/`)

SwiftData SchemaV3 entities:
- `Book` (fingerprintKey unique) → `ReadingPosition`, `Highlight`, `Bookmark`, `AnnotationNote`, `BookCollection`
- `ReadingSession`, `ReadingStats`

Additional `@Model` types (not in SchemaV3.models but registered separately):
- `ContentReplacementRule`, `BookSource`

Key types:
- `DocumentFingerprint` — `{format}:{SHA256}:{byteCount}` deterministic identity
- `Locator` — universal position: href+progression (EPUB), page (PDF), UTF-16 offset (TXT/MD)
- `AnnotationAnchor` — format-agnostic location encoding for highlights/bookmarks

## Notification Bus (`ReaderNotifications.swift`)

All cross-component communication uses NotificationCenter:

| Notification | Payload | Direction |
|-------------|---------|-----------|
| `.readerContentTapped` | nil | Bridge → Container (toggle chrome) |
| `.readerPositionDidChange` | `Locator` | Format container → ReaderContainerView → AI coordinator |
| `.readerNavigateToLocator` | `Locator` | Container → Format container |
| `.readerBookmarkRequested` | nil | Chrome → Format container |
| `.readerHighlightRequested` | `TextSelectionInfo` | Bridge → Container |
| `.readerHighlightRemoved` | UUID string | HighlightListVM → Container |
| `.readerDidClose` | fingerprintKey | ViewModel → LibraryView |
| `.readerAnnotationRequested` | `TextSelectionInfo` | Bridge → Container |
| `.readerDefineRequested` | `TextSelectionInfo` | Bridge → Container (dictionary) |
| `.readerTranslateRequested` | `TextSelectionInfo` | Bridge → Container (AI translate) |
| `.searchHighlightClear` | nil | SearchViewModel → Bridges |
| `.readerPreviousPage` | nil | TapZoneOverlay → Container |
| `.readerNextPage` | nil | TapZoneOverlay → Container |

## Key Design Patterns

1. **Bridge** — UIKit views (UITextView, WKWebView, PDFView) wrapped in `UIViewRepresentable` with Coordinator for delegate/gesture handling
2. **Coordinator** — Complex multi-subsystem flows managed by dedicated coordinator objects (AI, Search, Unified, Lifecycle)
3. **Protocol injection** — `LibraryPersisting`, `BookImporting`, `PreferenceStoring`, `TTSProviderProtocol` enable testing
4. **Actor isolation** — `PersistenceActor` serializes all SwiftData writes; `TXTService` is actor-isolated
5. **Deferred setup** — AI, search indexing, TOC building triggered on first use, not reader open
6. **Observer** — NotificationCenter decouples format-specific readers from chrome and coordinators

## Performance Optimizations

| Optimization | Target |
|-------------|--------|
| Sample-based encoding (8KB) | Fast TXT open for non-UTF-8 files |
| Chunked reader (UITableView) | Large TXT files (>500K UTF-16) |
| Deferred coordinator setup | Fast reader open (no AI/search/TOC upfront) |
| Persistent FTS5 index | Skip re-indexing on subsequent opens |
| Off-main-thread attributed string | Non-blocking TXT/MD rendering |
| PaginationCache | Avoid redundant TextKit layout passes |
| Non-contiguous layout | TextKit 1 performance for large documents |

## File Organization

```
vreader/
├── App/                    # VReaderApp, ContentView
├── Models/                 # SwiftData models, DocumentFingerprint, Locator
├── ViewModels/             # LibraryViewModel, format ViewModels
├── Views/
│   ├── LibraryView.swift   # Library grid/list
│   ├── Reader/             # Reader container, format containers, bridges
│   ├── Bookmarks/          # BookmarkListView, TOCListView
│   ├── Annotations/        # HighlightListView, AnnotationListView
│   └── Settings/           # SettingsView, ReaderSettingsPanel
├── Services/
│   ├── PersistenceActor.swift
│   ├── TXT/                # TXTService, TXTFileLoader
│   ├── EPUB/               # EPUBParser, EPUBTypes
│   ├── Search/             # SearchService, FTS5, extractors
│   ├── AI/                 # AIService, providers
│   ├── TTS/                # TTSService, providers
│   ├── Backup/             # WebDAV, BackupProvider
│   ├── Import/             # BookImporter
│   ├── Export/             # AnnotationExporter
│   ├── Locator/            # LocatorFactory, position resolution
│   ├── OPDS/               # OPDSClient, OPDSParser
│   ├── Sync/               # SyncService, SyncStatusMonitor
│   ├── Unified/            # PaginationCache, TextKit2 helpers
│   └── TextMapping/        # Transforms, offset mapping
└── (no Plugins/ directory — BookSource views are in Views/BookSource/)
```
