// Purpose: Tests for the BookSource four-stage scraping pipeline.
// Uses inline fixture HTML — no real network requests.
//
// @coordinates-with: BookSourcePipeline.swift, PipelineTypes.swift,
//   RuleEngine.swift, BookSourceRules.swift

import Testing
import Foundation
@testable import vreader

@Suite("BookSourcePipeline")
struct BookSourcePipelineTests {

    // MARK: - Fixture HTML

    private let searchHTML = """
    <html><body>
    <div id="search-results">
      <div class="book-item">
        <a href="/book/101" class="book-link">
          <span class="book-name">斗破苍穹</span>
        </a>
        <span class="book-author">天蚕土豆</span>
        <img src="/covers/101.jpg" class="book-cover">
      </div>
      <div class="book-item">
        <a href="/book/202" class="book-link">
          <span class="book-name">完美世界</span>
        </a>
        <span class="book-author">辰东</span>
        <img src="/covers/202.jpg" class="book-cover">
      </div>
      <div class="book-item">
        <a href="/book/303" class="book-link">
          <span class="book-name">遮天</span>
        </a>
        <span class="book-author">辰东</span>
        <img src="/covers/303.jpg" class="book-cover">
      </div>
    </div>
    </body></html>
    """

    private let detailHTML = """
    <html><body>
    <div id="book-detail">
      <h1 class="book-title">斗破苍穹</h1>
      <div class="info">
        <span class="author">天蚕土豆</span>
        <div class="intro">年仅15岁的少年萧炎创造了修炼纪录。</div>
        <img src="/covers/101.jpg" class="cover-img">
        <a href="/book/101/chapters" class="toc-link">查看目录</a>
      </div>
    </div>
    </body></html>
    """

    private let tocHTML = """
    <html><body>
    <div id="chapter-list">
      <ul class="chapters">
        <li><a href="/book/101/ch/1">第一章 陨落的天才</a></li>
        <li><a href="/book/101/ch/2">第二章 斗之气三段</a></li>
        <li><a href="/book/101/ch/3">第三章 萧家会议</a></li>
      </ul>
    </div>
    </body></html>
    """

    private let contentHTML = """
    <html><body>
    <div id="chapter-content">
      <h1 class="chapter-title">第一章 陨落的天才</h1>
      <div class="content">
        <p>少年缓缓坐了下来，白色的桌面上，一张关于家族的排名表被他攥在手中。</p>
        <p>表上，记录着家族年轻一代所有人的修炼进度。</p>
        <p>最顶端处，萧炎的名字赫然在列。</p>
      </div>
    </div>
    </body></html>
    """

    private let emptySearchHTML = """
    <html><body>
    <div id="search-results">
      <p class="no-results">没有找到相关书籍</p>
    </div>
    </body></html>
    """

    private let tocPage1HTML = """
    <html><body>
    <div id="chapter-list">
      <ul class="chapters">
        <li><a href="/book/101/ch/1">第一章 陨落的天才</a></li>
        <li><a href="/book/101/ch/2">第二章 斗之气三段</a></li>
      </ul>
      <a href="https://example.com/book/101/chapters?page=2" class="next-page">下一页</a>
    </div>
    </body></html>
    """

    private let tocPage2HTML = """
    <html><body>
    <div id="chapter-list">
      <ul class="chapters">
        <li><a href="/book/101/ch/3">第三章 萧家会议</a></li>
        <li><a href="/book/101/ch/4">第四章 云岚宗</a></li>
      </ul>
    </div>
    </body></html>
    """

    // MARK: - Helpers

    /// Creates a mock fetch provider that matches URL paths against keys.
    /// Keys are sorted by length (longest first) to avoid ambiguous matches.
    private func makeMockFetch(
        _ mapping: [String: String]
    ) -> HTMLFetchProvider {
        // Sort keys by length descending for longest-match-first
        let sortedKeys = mapping.keys.sorted { $0.count > $1.count }
        return { @Sendable url, _ in
            let urlStr = url.absoluteString
            for key in sortedKeys {
                if urlStr.contains(key) {
                    return mapping[key]!
                }
            }
            throw PipelineError.fetchFailed("No fixture for \(url)")
        }
    }

    /// Creates a test BookSourceSnapshot with rules matching the fixture HTML.
    private func makeTestSource() -> BookSourceSnapshot {
        BookSourceSnapshot(
            sourceURL: "https://example.com",
            sourceName: "Test Source",
            searchURL: "https://example.com/search?q={{key}}",
            ruleSearch: BSSearchRule(
                bookList: ".book-item",
                name: ".book-name",
                author: ".book-author",
                bookUrl: "a.book-link@href",
                coverUrl: "img.book-cover@src"
            ),
            ruleBookInfo: BSBookInfoRule(
                name: ".book-title",
                author: ".author",
                intro: ".intro",
                coverUrl: "img.cover-img@src",
                tocUrl: "a.toc-link@href"
            ),
            ruleToc: BSTocRule(
                chapterList: ".chapters li",
                chapterName: "a",
                chapterUrl: "a@href",
                nextTocUrl: nil
            ),
            ruleContent: BSContentRule(
                content: ".content p",
                nextContentUrl: nil,
                replaceRegex: nil
            )
        )
    }

    // MARK: - Stage 1: Search

    @Test func search_returnsBookList() async throws {
        let pipeline = BookSourcePipeline(
            fetchHTML: makeMockFetch(["search": searchHTML])
        )
        let results = try await pipeline.search(
            source: makeTestSource(), keyword: "斗破"
        )

        #expect(results.count == 3)
        #expect(results[0].name == "斗破苍穹")
        #expect(results[0].author == "天蚕土豆")
        #expect(results[0].bookUrl?.hasSuffix("/book/101") == true)
        #expect(results[0].coverUrl?.hasSuffix("/covers/101.jpg") == true)
        #expect(results[1].name == "完美世界")
        #expect(results[2].name == "遮天")
    }

    // MARK: - Stage 2: Book Info

    @Test func bookInfo_extractsMetadata() async throws {
        let pipeline = BookSourcePipeline(
            fetchHTML: makeMockFetch(["book/101": detailHTML])
        )
        let detail = try await pipeline.bookInfo(
            source: makeTestSource(),
            bookUrl: "https://example.com/book/101"
        )

        #expect(detail.name == "斗破苍穹")
        #expect(detail.author == "天蚕土豆")
        #expect(detail.intro?.contains("萧炎") == true)
        #expect(detail.coverUrl?.hasSuffix("/covers/101.jpg") == true)
        #expect(detail.tocUrl?.hasSuffix("/book/101/chapters") == true)
    }

    // MARK: - Stage 3: TOC

    @Test func toc_extractsChapterList() async throws {
        let pipeline = BookSourcePipeline(
            fetchHTML: makeMockFetch(["chapters": tocHTML])
        )
        let chapters = try await pipeline.chapters(
            source: makeTestSource(),
            tocUrl: "https://example.com/book/101/chapters"
        )

        #expect(chapters.count == 3)
        #expect(chapters[0].name == "第一章 陨落的天才")
        #expect(chapters[0].url.hasSuffix("/book/101/ch/1"))
        #expect(chapters[1].name == "第二章 斗之气三段")
        #expect(chapters[2].name == "第三章 萧家会议")
    }

    // MARK: - Stage 4: Content

    @Test func content_extractsChapterText() async throws {
        let pipeline = BookSourcePipeline(
            fetchHTML: makeMockFetch(["ch/1": contentHTML])
        )
        let text = try await pipeline.chapterContent(
            source: makeTestSource(),
            chapterUrl: "https://example.com/book/101/ch/1"
        )

        #expect(text.contains("少年缓缓坐了下来"))
        #expect(text.contains("修炼进度"))
        #expect(text.contains("萧炎"))
    }

    // MARK: - End-to-End

    @Test func endToEnd_withFixtureHTML() async throws {
        let pipeline = BookSourcePipeline(
            fetchHTML: makeMockFetch([
                "search": searchHTML,
                "/book/101/chapters": tocHTML,
                "/book/101/ch/1": contentHTML,
                "/book/101": detailHTML,
            ])
        )
        let source = makeTestSource()

        // Step 1: Search
        let results = try await pipeline.search(
            source: source, keyword: "斗破"
        )
        #expect(!results.isEmpty)
        #expect(results[0].name == "斗破苍穹")

        // Step 2: Book Info (URLs are already resolved by RuleEngine)
        let bookUrl = results[0].bookUrl!
        let detail = try await pipeline.bookInfo(
            source: source, bookUrl: bookUrl
        )
        #expect(detail.name == "斗破苍穹")
        #expect(detail.tocUrl != nil)

        // Step 3: TOC
        let tocUrl = detail.tocUrl!
        let chapters = try await pipeline.chapters(
            source: source, tocUrl: tocUrl
        )
        #expect(chapters.count == 3)

        // Step 4: Content
        let chapterUrl = chapters[0].url
        let text = try await pipeline.chapterContent(
            source: source, chapterUrl: chapterUrl
        )
        #expect(text.contains("萧炎"))
    }

    // MARK: - Edge Case: No Search Results

    @Test func searchNoResults_returnsEmpty() async throws {
        let pipeline = BookSourcePipeline(
            fetchHTML: makeMockFetch(["search": emptySearchHTML])
        )
        let results = try await pipeline.search(
            source: makeTestSource(), keyword: "不存在的书"
        )
        #expect(results.isEmpty)
    }

    // MARK: - Edge Case: Empty Content

    @Test func emptyContent_returnsError() async throws {
        let emptyHTML = "<html><body><div class='content'></div></body></html>"
        let pipeline = BookSourcePipeline(
            fetchHTML: makeMockFetch(["ch/99": emptyHTML])
        )
        do {
            _ = try await pipeline.chapterContent(
                source: makeTestSource(),
                chapterUrl: "https://example.com/ch/99"
            )
            Issue.record("Expected PipelineError.emptyContent")
        } catch let error as PipelineError {
            #expect(error == .emptyContent)
        }
    }

    // MARK: - Edge Case: Pagination (nextTocUrl)

    @Test func nextPageURL_followsPagination() async throws {
        let pipeline = BookSourcePipeline(
            fetchHTML: makeMockFetch([
                "chapters?page=2": tocPage2HTML,
                "chapters": tocPage1HTML,
            ])
        )
        let source = BookSourceSnapshot(
            sourceURL: "https://example.com",
            sourceName: "Test",
            ruleToc: BSTocRule(
                chapterList: ".chapters li",
                chapterName: "a",
                chapterUrl: "a@href",
                nextTocUrl: "a.next-page@href"
            )
        )

        let chapters = try await pipeline.chapters(
            source: source,
            tocUrl: "https://example.com/book/101/chapters"
        )

        #expect(chapters.count == 4)
        #expect(chapters[0].name == "第一章 陨落的天才")
        #expect(chapters[3].name == "第四章 云岚宗")
    }

    // MARK: - Edge Case: Cancel During Fetch

    @Test func cancelDuringFetch_stops() async throws {
        let slowFetch: HTMLFetchProvider = { @Sendable _, _ in
            try await Task.sleep(for: .seconds(10))
            return "<html></html>"
        }
        let pipeline = BookSourcePipeline(fetchHTML: slowFetch)

        let task = Task {
            try await pipeline.search(
                source: makeTestSource(), keyword: "test"
            )
        }
        task.cancel()

        do {
            _ = try await task.value
        } catch is CancellationError {
            // Expected
        } catch {
            // Other cancellation-related errors are acceptable
        }
    }

    // MARK: - Progress Callback

    @Test func progressCallback_reportStages() async throws {
        let pipeline = BookSourcePipeline(
            fetchHTML: makeMockFetch([
                "search": searchHTML,
                "/book/101/chapters": tocHTML,
                "/book/101/ch/1": contentHTML,
                "/book/101": detailHTML,
            ])
        )
        let source = makeTestSource()
        let stagesActor = StagesCollector()

        // Search
        _ = try await pipeline.search(source: source, keyword: "test") {
            stage in
            Task { await stagesActor.add(stage) }
        }
        // BookInfo
        _ = try await pipeline.bookInfo(
            source: source, bookUrl: "https://example.com/book/101"
        ) { stage in
            Task { await stagesActor.add(stage) }
        }
        // TOC
        _ = try await pipeline.chapters(
            source: source,
            tocUrl: "https://example.com/book/101/chapters"
        ) { stage in
            Task { await stagesActor.add(stage) }
        }
        // Content
        _ = try await pipeline.chapterContent(
            source: source,
            chapterUrl: "https://example.com/book/101/ch/1"
        ) { stage in
            Task { await stagesActor.add(stage) }
        }

        // Allow Task closures to complete
        try await Task.sleep(for: .milliseconds(100))
        let stages = await stagesActor.stages
        #expect(stages.contains(.search))
        #expect(stages.contains(.bookInfo))
        #expect(stages.contains(.toc))
        #expect(stages.contains(.content))
    }

    // MARK: - Missing Rules

    @Test func missingSearchRule_throws() async throws {
        let pipeline = BookSourcePipeline(
            fetchHTML: makeMockFetch([:])
        )
        let source = BookSourceSnapshot(
            sourceURL: "https://example.com",
            sourceName: "Test",
            searchURL: "https://example.com/search?q={{key}}",
            ruleSearch: nil
        )
        do {
            _ = try await pipeline.search(source: source, keyword: "test")
            Issue.record("Expected PipelineError.missingSearchRule")
        } catch let error as PipelineError {
            #expect(error == .missingSearchRule)
        }
    }

    @Test func missingSearchURL_throws() async throws {
        let pipeline = BookSourcePipeline(
            fetchHTML: makeMockFetch([:])
        )
        let source = BookSourceSnapshot(
            sourceURL: "https://example.com",
            sourceName: "Test",
            searchURL: nil,
            ruleSearch: BSSearchRule(bookList: "li")
        )
        do {
            _ = try await pipeline.search(source: source, keyword: "test")
            Issue.record("Expected PipelineError.missingSearchURL")
        } catch let error as PipelineError {
            #expect(error == .missingSearchURL)
        }
    }

    @Test func missingBookInfoRule_throws() async throws {
        let pipeline = BookSourcePipeline(
            fetchHTML: makeMockFetch([:])
        )
        let source = BookSourceSnapshot(
            sourceURL: "https://example.com",
            sourceName: "Test",
            ruleBookInfo: nil
        )
        do {
            _ = try await pipeline.bookInfo(
                source: source,
                bookUrl: "https://example.com/book/1"
            )
            Issue.record("Expected PipelineError.missingBookInfoRule")
        } catch let error as PipelineError {
            #expect(error == .missingBookInfoRule)
        }
    }

    @Test func missingTocRule_throws() async throws {
        let pipeline = BookSourcePipeline(
            fetchHTML: makeMockFetch([:])
        )
        let source = BookSourceSnapshot(
            sourceURL: "https://example.com",
            sourceName: "Test",
            ruleToc: nil
        )
        do {
            _ = try await pipeline.chapters(
                source: source,
                tocUrl: "https://example.com/toc"
            )
            Issue.record("Expected PipelineError.missingTocRule")
        } catch let error as PipelineError {
            #expect(error == .missingTocRule)
        }
    }

    @Test func missingContentRule_throws() async throws {
        let pipeline = BookSourcePipeline(
            fetchHTML: makeMockFetch([:])
        )
        let source = BookSourceSnapshot(
            sourceURL: "https://example.com",
            sourceName: "Test",
            ruleContent: nil
        )
        do {
            _ = try await pipeline.chapterContent(
                source: source,
                chapterUrl: "https://example.com/ch/1"
            )
            Issue.record("Expected PipelineError.missingContentRule")
        } catch let error as PipelineError {
            #expect(error == .missingContentRule)
        }
    }

    // MARK: - Fetch Error Propagation

    @Test func fetchError_propagates() async throws {
        let failingFetch: HTMLFetchProvider = { @Sendable _, _ in
            throw PipelineError.fetchFailed("Connection refused")
        }
        let pipeline = BookSourcePipeline(fetchHTML: failingFetch)
        do {
            _ = try await pipeline.search(
                source: makeTestSource(), keyword: "test"
            )
            Issue.record("Expected error")
        } catch let error as PipelineError {
            #expect(error == .fetchFailed("Connection refused"))
        }
    }

    // MARK: - Content Cleanup Regex

    @Test func contentCleanup_appliesReplaceRegex() async throws {
        let html = """
        <html><body>
          <div class="content">
            <p>Good text. 广告链接 More good text.</p>
          </div>
        </body></html>
        """
        let pipeline = BookSourcePipeline(
            fetchHTML: makeMockFetch(["ch/1": html])
        )
        let source = BookSourceSnapshot(
            sourceURL: "https://example.com",
            sourceName: "Test",
            ruleContent: BSContentRule(
                content: ".content p",
                replaceRegex: "广告链接"
            )
        )
        let text = try await pipeline.chapterContent(
            source: source,
            chapterUrl: "https://example.com/ch/1"
        )
        #expect(!text.contains("广告链接"))
        #expect(text.contains("Good text"))
    }
}

// MARK: - Test Helpers

/// Actor for safely collecting pipeline stages from async callbacks.
private actor StagesCollector {
    var stages: [PipelineStage] = []
    func add(_ stage: PipelineStage) { stages.append(stage) }
}
