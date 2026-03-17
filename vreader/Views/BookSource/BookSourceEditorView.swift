// Purpose: Form-based editor for creating and editing a BookSource.
// Provides text fields for all configurable source properties including rules.
//
// Key decisions:
// - Source and rule fields presented in grouped form sections.
// - URL validation before save (non-empty, trimmed).
// - Rule fields are plain text (CSS selectors, regex, Legado syntax) —
//   no validation here, that's the rule engine's job.
// - Editing an existing source modifies it in-place; creating inserts a new one.
//
// @coordinates-with: BookSource.swift, BookSourceRules.swift, BookSourceListView.swift

import SwiftUI

/// Form editor for a single BookSource's properties and rules.
struct BookSourceEditorView: View {
    let source: BookSource?
    let onSave: (BookSource) -> Void
    let onCancel: () -> Void

    // MARK: - Form State

    @State private var sourceURL = ""
    @State private var sourceName = ""
    @State private var sourceGroup = ""
    @State private var sourceType = 0
    @State private var searchURL = ""
    @State private var header = ""

    // Search rule fields
    @State private var searchBookList = ""
    @State private var searchName = ""
    @State private var searchAuthor = ""
    @State private var searchBookUrl = ""
    @State private var searchCoverUrl = ""

    // Book info rule fields
    @State private var infoName = ""
    @State private var infoAuthor = ""
    @State private var infoIntro = ""
    @State private var infoCoverUrl = ""
    @State private var infoTocUrl = ""

    // TOC rule fields
    @State private var tocChapterList = ""
    @State private var tocChapterName = ""
    @State private var tocChapterUrl = ""
    @State private var tocNextTocUrl = ""

    // Content rule fields
    @State private var contentRule = ""
    @State private var contentNextUrl = ""
    @State private var contentReplaceRegex = ""

    private var isEditing: Bool { source != nil }

    private var canSave: Bool {
        BookSource.validateSourceURL(sourceURL)
            && !sourceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            basicInfoSection
            searchRuleSection
            bookInfoRuleSection
            tocRuleSection
            contentRuleSection
        }
        .navigationTitle(isEditing ? "Edit Source" : "New Source")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(!canSave)
                    .accessibilityIdentifier("bookSourceSaveButton")
            }
        }
        .onAppear(perform: loadFromSource)
    }

    // MARK: - Form Sections

    private var basicInfoSection: some View {
        Section("Source Info") {
            TextField("Source URL", text: $sourceURL)
                .keyboardType(.URL)
                .autocapitalization(.none)
                .accessibilityIdentifier("bookSourceURLField")

            TextField("Source Name", text: $sourceName)
                .accessibilityIdentifier("bookSourceNameField")

            TextField("Group (optional)", text: $sourceGroup)

            Picker("Type", selection: $sourceType) {
                Text("Text").tag(0)
                Text("Audio").tag(1)
                Text("Image").tag(2)
                Text("File").tag(3)
            }
            .accessibilityIdentifier("bookSourceTypePicker")

            TextField("Search URL (use {{key}})", text: $searchURL)
                .keyboardType(.URL)
                .autocapitalization(.none)

            TextField("Custom Headers (JSON)", text: $header)
                .font(.system(.body, design: .monospaced))
                .autocapitalization(.none)
        }
    }

    private var searchRuleSection: some View {
        Section("Search Rules") {
            ruleField("Book List", text: $searchBookList)
            ruleField("Name", text: $searchName)
            ruleField("Author", text: $searchAuthor)
            ruleField("Book URL", text: $searchBookUrl)
            ruleField("Cover URL", text: $searchCoverUrl)
        }
    }

    private var bookInfoRuleSection: some View {
        Section("Book Info Rules") {
            ruleField("Name", text: $infoName)
            ruleField("Author", text: $infoAuthor)
            ruleField("Introduction", text: $infoIntro)
            ruleField("Cover URL", text: $infoCoverUrl)
            ruleField("TOC URL", text: $infoTocUrl)
        }
    }

    private var tocRuleSection: some View {
        Section("TOC Rules") {
            ruleField("Chapter List", text: $tocChapterList)
            ruleField("Chapter Name", text: $tocChapterName)
            ruleField("Chapter URL", text: $tocChapterUrl)
            ruleField("Next TOC URL", text: $tocNextTocUrl)
        }
    }

    private var contentRuleSection: some View {
        Section("Content Rules") {
            ruleField("Content", text: $contentRule)
            ruleField("Next Content URL", text: $contentNextUrl)
            ruleField("Replace Regex", text: $contentReplaceRegex)
        }
    }

    private func ruleField(_ label: String, text: Binding<String>) -> some View {
        TextField(label, text: text)
            .font(.system(.body, design: .monospaced))
            .autocapitalization(.none)
    }

    // MARK: - Load / Save

    private func loadFromSource() {
        guard let source else { return }

        sourceURL = source.sourceURL
        sourceName = source.sourceName
        sourceGroup = source.sourceGroup ?? ""
        sourceType = source.sourceType
        searchURL = source.searchURL ?? ""
        header = source.header ?? ""

        if let search = source.ruleSearch {
            searchBookList = search.bookList ?? ""
            searchName = search.name ?? ""
            searchAuthor = search.author ?? ""
            searchBookUrl = search.bookUrl ?? ""
            searchCoverUrl = search.coverUrl ?? ""
        }

        if let info = source.ruleBookInfo {
            infoName = info.name ?? ""
            infoAuthor = info.author ?? ""
            infoIntro = info.intro ?? ""
            infoCoverUrl = info.coverUrl ?? ""
            infoTocUrl = info.tocUrl ?? ""
        }

        if let toc = source.ruleToc {
            tocChapterList = toc.chapterList ?? ""
            tocChapterName = toc.chapterName ?? ""
            tocChapterUrl = toc.chapterUrl ?? ""
            tocNextTocUrl = toc.nextTocUrl ?? ""
        }

        if let content = source.ruleContent {
            contentRule = content.content ?? ""
            contentNextUrl = content.nextContentUrl ?? ""
            contentReplaceRegex = content.replaceRegex ?? ""
        }
    }

    private func save() {
        let trimmedURL = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = sourceName.trimmingCharacters(in: .whitespacesAndNewlines)

        let target: BookSource
        if let existing = source {
            target = existing
            target.sourceURL = trimmedURL
        } else {
            target = BookSource(sourceURL: trimmedURL, sourceName: trimmedName, sourceType: sourceType)
        }

        target.sourceName = trimmedName
        target.sourceGroup = sourceGroup.isEmpty ? nil : sourceGroup
        target.sourceType = sourceType
        target.searchURL = searchURL.isEmpty ? nil : searchURL
        target.header = header.isEmpty ? nil : header
        target.lastUpdateTime = Date()

        // Build and set rules (only if any field is non-empty)
        target.updateSearchRule(buildSearchRule())
        target.updateBookInfoRule(buildBookInfoRule())
        target.updateTocRule(buildTocRule())
        target.updateContentRule(buildContentRule())

        onSave(target)
    }

    // MARK: - Rule Builders

    private func buildSearchRule() -> BSSearchRule? {
        let rule = BSSearchRule(
            bookList: searchBookList.nilIfEmpty,
            name: searchName.nilIfEmpty,
            author: searchAuthor.nilIfEmpty,
            bookUrl: searchBookUrl.nilIfEmpty,
            coverUrl: searchCoverUrl.nilIfEmpty
        )
        return rule.hasAnyField ? rule : nil
    }

    private func buildBookInfoRule() -> BSBookInfoRule? {
        let rule = BSBookInfoRule(
            name: infoName.nilIfEmpty,
            author: infoAuthor.nilIfEmpty,
            intro: infoIntro.nilIfEmpty,
            coverUrl: infoCoverUrl.nilIfEmpty,
            tocUrl: infoTocUrl.nilIfEmpty
        )
        return rule.hasAnyField ? rule : nil
    }

    private func buildTocRule() -> BSTocRule? {
        let rule = BSTocRule(
            chapterList: tocChapterList.nilIfEmpty,
            chapterName: tocChapterName.nilIfEmpty,
            chapterUrl: tocChapterUrl.nilIfEmpty,
            nextTocUrl: tocNextTocUrl.nilIfEmpty
        )
        return rule.hasAnyField ? rule : nil
    }

    private func buildContentRule() -> BSContentRule? {
        let rule = BSContentRule(
            content: contentRule.nilIfEmpty,
            nextContentUrl: contentNextUrl.nilIfEmpty,
            replaceRegex: contentReplaceRegex.nilIfEmpty
        )
        return rule.hasAnyField ? rule : nil
    }
}

// MARK: - String Extension

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// hasAnyField extensions live in BookSourceRules.swift
