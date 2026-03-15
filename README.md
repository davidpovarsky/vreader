# VReader

An iOS reader app for EPUB, PDF, TXT, and Markdown files — built with Swift 6, SwiftUI, and SwiftData.

## About

VReader is a modern reading app designed for iPhone and iPad. It provides a unified reading experience across multiple document formats with features like reading position persistence, bookmarks, highlights, full-text search, and reading time tracking. Documents sync across devices via iCloud.

## Features

- **Multi-format support** — Read EPUB, PDF, TXT, and Markdown files in a single app
- **Reading position persistence** — Automatically saves and restores your scroll position per book, surviving app backgrounding, kills, and relaunches
- **CJK & encoding support** — Automatic encoding detection for GBK, Big5, Shift-JIS, EUC-KR, and other non-UTF-8 files
- **Large file performance** — Chunked rendering (UITableView) for TXT files over 500K characters; no glyph storage blowup
- **Bookmarks & highlights** — Save your place and annotate passages with color-coded highlights and notes
- **EPUB/PDF annotation** — Text selection + highlight/note actions in EPUB (CSS Highlight API) and PDF (PDFAnnotation). Persists across sessions via unified AnnotationAnchor schema
- **Full-text search** — Search across your entire library with SQLite FTS5 and CJK-aware tokenization. Highlights match at destination
- **Reading progress bar** — Draggable scrubber in all 4 formats: continuous for TXT/MD, page-based for PDF, chapter-based for EPUB
- **Table of contents** — Auto-generated for Markdown (heading extraction), built-in for EPUB/PDF
- **AI assistant** — Summarize sections, multi-turn chat with book context, bilingual translation (9 languages), general AI chat. OpenAI-compatible API
- **Reading time tracking** — Automatic session tracking with per-book statistics and reading speed calculations
- **Reader settings** — Configurable font size, font family, line spacing, letter spacing, and theme
- **Library management** — Grid/list view with persistent preferences, book info sheet, share, context menu
- **Import from anywhere** — Open files via Share Sheet, Files app, or direct download

## Tech Stack

| Component   | Technology                                         |
| ----------- | -------------------------------------------------- |
| UI          | SwiftUI                                            |
| Persistence | SwiftData + CloudKit                               |
| EPUB        | WKWebView bridge with CSS theme injection + JS highlight API |
| PDF         | PDFKit + PDFAnnotation for highlights              |
| TXT         | TextKit 1 (UITextView) + chunked UITableView       |
| Markdown    | NSAttributedString rendering via MDParser           |
| Search      | SQLite FTS5 with CJK tokenization                  |
| AI          | OpenAI-compatible API (summarize, chat, translate) |
| Encoding    | ICU + heuristic detection (UTF-8/GBK/Big5/Shift-JIS) |
| Concurrency | Swift 6 strict concurrency                         |
| Project gen | XcodeGen                                           |

## Requirements

- iOS 17.0+
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Getting Started

```bash
# Generate the Xcode project
xcodegen generate

# Open in Xcode
open vreader.xcodeproj
```

Then select a simulator or device and run.

## Architecture

```
vreader/
├── App/                 # App entry point, configuration
├── Models/              # SwiftData models (Book, ReadingPosition, Bookmark, etc.)
├── Views/
│   ├── Reader/          # Reader views per format (EPUB, PDF, TXT, MD)
│   ├── Library/          # Library views, book info, context menu
│   ├── Settings/         # AI settings, preferences
│   └── AI/               # Chat view
├── ViewModels/          # Per-reader and per-feature view models
├── Services/
│   ├── EPUB/            # EPUB parsing and rendering
│   ├── TXT/             # TXT service, chunker, attributed string builder
│   ├── MD/              # Markdown parser and renderer
│   ├── Search/          # FTS5 indexing, text extraction, tokenization
│   ├── AI/              # AI service, configuration, context extraction
│   ├── Sync/            # iCloud sync coordination
│   └── Locator/         # Reading position model (Readium-inspired)
└── Utils/               # Helpers, extensions, encoding detection
vreaderTests/            # Unit tests (2040+ test cases)
vreaderUITests/          # UI tests (XCTest)
```

### Key Design Decisions

- **TextKit 1 for TXT rendering** — UITextView with `NSLayoutManager` for reliable offset-to-scroll mapping. TextKit 2 has better performance but lacks the `charOffset ↔ scrollOffset` APIs needed for position persistence.
- **Chunked rendering for large files** — Files over 500K UTF-16 code units use a UITableView where each cell renders one ~16K chunk. Only visible cells build attributed strings (LRU cache of 20 chunks).
- **Two-phase scroll restore** — Position restore uses a Phase 1 (t+0.15s) + Phase 2 (t+0.8s) pattern to handle TextKit 1 compatibility mode relayout storms that reset `contentOffset`.
- **`@State` for one-shot values** — Rapidly-mutating `@Observable` properties are never read in SwiftUI body to avoid observation feedback loops. Position restore uses `@State` captured once after `open()`.
- **Background task protection** — `UIApplication.beginBackgroundTask` wraps all critical saves (`close()`, `onBackground()`) to prevent data loss when iOS suspends the process.

## AI-Powered Development

VReader is built using an AI-assisted coding workflow with multiple agents collaborating through structured processes.

### Tools

| Tool | Role |
|------|------|
| [Claude Code](https://claude.com/claude-code) | Primary coding agent — implementation, editing, code review, fixes |
| [Codex CLI](https://github.com/openai/codex) | Architecture review, auditing, autonomous implementation in sandbox |

### Workflow

The development process follows a gated, multi-agent pipeline:

1. **Plan** — Features are designed as detailed implementation plans with work items, acceptance criteria, and test requirements (`docs/codex-plans/`)
2. **Review** — Plans go through multi-round architecture review via Codex (consistency, completeness, feasibility, ambiguity, risk)
3. **Implement** — Work items are implemented by the implementer agent following TDD (RED-GREEN-REFACTOR)
4. **Audit** — Code is audited across 9 dimensions (correctness, security, concurrency, performance, etc.)
5. **Fix** — Audit findings are fixed and verified in iterative loops until clean
6. **Commit** — Changes are committed only on explicit request after passing all gates

### Agent Rules

Shared rules for all AI agents live in [`AGENTS.md`](AGENTS.md):

- **Test-first is mandatory** — Write a failing test before implementing any new behavior
- **Research before building** — Search for established patterns and proven solutions before inventing
- **Edge cases are not optional** — Brainstorm and test: empty input, null values, Unicode/CJK, concurrent access, network failures
- **Keep files under ~300 lines** — Split proactively to maintain readability
- **Keep diffs focused** — No drive-by refactors; only change what's needed

### Configuration

- `.claude/rules/` — Rule files for TDD, UI consistency, design tokens, keyboard shortcuts, version bumping
- `.claude/skills/` — Custom skill definitions (plan-audit, etc.)
- `CLAUDE.md` — Claude Code project instructions
- `AGENTS.md` — Shared instructions for all AI coding agents

## License

TBD
