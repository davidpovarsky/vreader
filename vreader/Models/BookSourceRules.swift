// Purpose: Codable rule sub-models for BookSource extraction rules.
// Matches Legado's SearchRule, BookInfoRule, TocRule, ContentRule structure.
// Stored as JSON Data blobs on BookSource for safe SwiftData storage.
//
// Key decisions:
// - All fields are optional — sources may only define some rules.
// - Sendable for safe concurrent use in pipeline stages.
// - Equatable for testing and diff detection.
//
// @coordinates-with: BookSource.swift, LegadoImporter.swift (future)

import Foundation

/// Extraction rules for search results parsing.
struct BSSearchRule: Codable, Sendable, Equatable {
    var bookList: String?
    var name: String?
    var author: String?
    var bookUrl: String?
    var coverUrl: String?

    init(
        bookList: String? = nil,
        name: String? = nil,
        author: String? = nil,
        bookUrl: String? = nil,
        coverUrl: String? = nil
    ) {
        self.bookList = bookList
        self.name = name
        self.author = author
        self.bookUrl = bookUrl
        self.coverUrl = coverUrl
    }
}

/// Extraction rules for book detail page parsing.
struct BSBookInfoRule: Codable, Sendable, Equatable {
    var name: String?
    var author: String?
    var intro: String?
    var coverUrl: String?
    var tocUrl: String?

    init(
        name: String? = nil,
        author: String? = nil,
        intro: String? = nil,
        coverUrl: String? = nil,
        tocUrl: String? = nil
    ) {
        self.name = name
        self.author = author
        self.intro = intro
        self.coverUrl = coverUrl
        self.tocUrl = tocUrl
    }
}

/// Extraction rules for table of contents parsing.
struct BSTocRule: Codable, Sendable, Equatable {
    var chapterList: String?
    var chapterName: String?
    var chapterUrl: String?
    var nextTocUrl: String?

    init(
        chapterList: String? = nil,
        chapterName: String? = nil,
        chapterUrl: String? = nil,
        nextTocUrl: String? = nil
    ) {
        self.chapterList = chapterList
        self.chapterName = chapterName
        self.chapterUrl = chapterUrl
        self.nextTocUrl = nextTocUrl
    }
}

/// Extraction rules for chapter content parsing.
struct BSContentRule: Codable, Sendable, Equatable {
    var content: String?
    var nextContentUrl: String?
    var replaceRegex: String?

    init(
        content: String? = nil,
        nextContentUrl: String? = nil,
        replaceRegex: String? = nil
    ) {
        self.content = content
        self.nextContentUrl = nextContentUrl
        self.replaceRegex = replaceRegex
    }
}

// MARK: - hasAnyField Helpers

extension BSSearchRule {
    /// True if at least one extraction field is set.
    var hasAnyField: Bool {
        [bookList, name, author, bookUrl, coverUrl].contains(where: { $0 != nil })
    }
}

extension BSBookInfoRule {
    /// True if at least one extraction field is set.
    var hasAnyField: Bool {
        [name, author, intro, coverUrl, tocUrl].contains(where: { $0 != nil })
    }
}

extension BSTocRule {
    /// True if at least one extraction field is set.
    var hasAnyField: Bool {
        [chapterList, chapterName, chapterUrl, nextTocUrl].contains(where: { $0 != nil })
    }
}

extension BSContentRule {
    /// True if at least one extraction field is set.
    var hasAnyField: Bool {
        [content, nextContentUrl, replaceRegex].contains(where: { $0 != nil })
    }
}
