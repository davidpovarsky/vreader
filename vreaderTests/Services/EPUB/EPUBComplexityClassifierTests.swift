// Purpose: Tests for EPUBComplexityClassifier — determines whether EPUB
// chapter HTML is simple (suitable for Unified reflow engine) or complex
// (requires Native WKWebView renderer).
//
// @coordinates-with: EPUBComplexityClassifier.swift, FormatCapabilities.swift

import Testing
@testable import vreader

@Suite("EPUBComplexityClassifier")
struct EPUBComplexityClassifierTests {

    // MARK: - Simple Content (should NOT be classified as complex)

    @Test("plain paragraph text is simple")
    func simpleHTML_isNotComplex() {
        let html = "<html><body><p>Hello world</p></body></html>"
        #expect(EPUBComplexityClassifier.classify(html: html) == .simple)
    }

    @Test("empty HTML is simple")
    func emptyHTML_isNotComplex() {
        #expect(EPUBComplexityClassifier.classify(html: "") == .simple)
    }

    @Test("images alone do not make content complex")
    func htmlWithImages_isNotComplex() {
        let html = """
        <html><body>
        <p>Some text</p>
        <img src="photo.jpg" alt="Photo" />
        <p>More text</p>
        </body></html>
        """
        #expect(EPUBComplexityClassifier.classify(html: html) == .simple)
    }

    @Test("links alone do not make content complex")
    func htmlWithLinks_isNotComplex() {
        let html = """
        <html><body>
        <p>Visit <a href="https://example.com">Example</a></p>
        </body></html>
        """
        #expect(EPUBComplexityClassifier.classify(html: html) == .simple)
    }

    @Test("nested inline formatting is simple")
    func htmlWithNestedFormatting_isNotComplex() {
        let html = """
        <html><body>
        <p><em><strong>Bold and italic</strong></em> text</p>
        </body></html>
        """
        #expect(EPUBComplexityClassifier.classify(html: html) == .simple)
    }

    @Test("flexbox alone is not complex (common in simple EPUBs)")
    func htmlWithCSS_flexbox_isNotComplex() {
        let html = """
        <html><head>
        <style>body { display: flex; }</style>
        </head><body><p>Content</p></body></html>
        """
        #expect(EPUBComplexityClassifier.classify(html: html) == .simple)
    }

    @Test("headings and lists are simple")
    func htmlWithHeadingsAndLists_isNotComplex() {
        let html = """
        <html><body>
        <h1>Title</h1>
        <h2>Subtitle</h2>
        <ul><li>Item 1</li><li>Item 2</li></ul>
        <ol><li>First</li><li>Second</li></ol>
        </body></html>
        """
        #expect(EPUBComplexityClassifier.classify(html: html) == .simple)
    }

    @Test("blockquote and preformatted text are simple")
    func htmlWithBlockquoteAndPre_isNotComplex() {
        let html = """
        <html><body>
        <blockquote>A wise quote</blockquote>
        <pre><code>let x = 1</code></pre>
        </body></html>
        """
        #expect(EPUBComplexityClassifier.classify(html: html) == .simple)
    }

    @Test("br tags are simple")
    func htmlWithBr_isNotComplex() {
        let html = "<html><body><p>Line 1<br/>Line 2</p></body></html>"
        #expect(EPUBComplexityClassifier.classify(html: html) == .simple)
    }

    @Test("span and div containers are simple")
    func htmlWithSpanAndDiv_isNotComplex() {
        let html = """
        <html><body>
        <div class="chapter"><span class="dropcap">O</span>nce upon a time</div>
        </body></html>
        """
        #expect(EPUBComplexityClassifier.classify(html: html) == .simple)
    }

    // MARK: - Complex Content (SHOULD be classified as complex)

    @Test("table makes content complex")
    func htmlWithTable_isComplex() {
        let html = """
        <html><body>
        <table><tr><td>Cell 1</td><td>Cell 2</td></tr></table>
        </body></html>
        """
        #expect(EPUBComplexityClassifier.classify(html: html) == .complex)
    }

    @Test("MathML makes content complex")
    func htmlWithMath_isComplex() {
        let html = """
        <html><body>
        <p>The equation is:</p>
        <math xmlns="http://www.w3.org/1998/Math/MathML">
          <mi>x</mi><mo>=</mo><mfrac><mn>1</mn><mn>2</mn></mfrac>
        </math>
        </body></html>
        """
        #expect(EPUBComplexityClassifier.classify(html: html) == .complex)
    }

    @Test("SVG makes content complex")
    func htmlWithSVG_isComplex() {
        let html = """
        <html><body>
        <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">
          <circle cx="50" cy="50" r="40"/>
        </svg>
        </body></html>
        """
        #expect(EPUBComplexityClassifier.classify(html: html) == .complex)
    }

    @Test("viewport meta with fixed width makes content complex")
    func htmlWithFixedLayout_isComplex() {
        let html = """
        <html><head>
        <meta name="viewport" content="width=600, height=800"/>
        </head><body><p>Fixed layout content</p></body></html>
        """
        #expect(EPUBComplexityClassifier.classify(html: html) == .complex)
    }

    @Test("CSS grid layout makes content complex")
    func htmlWithCSS_grid_isComplex() {
        let html = """
        <html><head>
        <style>.container { display: grid; grid-template-columns: 1fr 1fr; }</style>
        </head><body><div class="container"><p>Col 1</p><p>Col 2</p></div></body></html>
        """
        #expect(EPUBComplexityClassifier.classify(html: html) == .complex)
    }

    @Test("iframe makes content complex")
    func htmlWithIframe_isComplex() {
        let html = """
        <html><body>
        <iframe src="embedded.html"></iframe>
        </body></html>
        """
        #expect(EPUBComplexityClassifier.classify(html: html) == .complex)
    }

    @Test("canvas makes content complex")
    func htmlWithCanvas_isComplex() {
        let html = """
        <html><body>
        <canvas id="myCanvas" width="200" height="100"></canvas>
        </body></html>
        """
        #expect(EPUBComplexityClassifier.classify(html: html) == .complex)
    }

    @Test("video makes content complex")
    func htmlWithVideo_isComplex() {
        let html = """
        <html><body>
        <video src="movie.mp4" controls></video>
        </body></html>
        """
        #expect(EPUBComplexityClassifier.classify(html: html) == .complex)
    }

    @Test("audio makes content complex")
    func htmlWithAudio_isComplex() {
        let html = """
        <html><body>
        <audio src="narration.mp3" controls></audio>
        </body></html>
        """
        #expect(EPUBComplexityClassifier.classify(html: html) == .complex)
    }

    @Test("CSS display:table makes content complex")
    func htmlWithCSSDisplayTable_isComplex() {
        let html = """
        <html><head>
        <style>.data { display: table; }</style>
        </head><body><div class="data">Tabular data</div></body></html>
        """
        #expect(EPUBComplexityClassifier.classify(html: html) == .complex)
    }

    @Test("CSS position:fixed makes content complex")
    func htmlWithCSSPositionFixed_isComplex() {
        let html = """
        <html><head>
        <style>.overlay { position: fixed; top: 0; left: 0; }</style>
        </head><body><div class="overlay">Overlay</div></body></html>
        """
        #expect(EPUBComplexityClassifier.classify(html: html) == .complex)
    }

    @Test("CSS position:absolute makes content complex")
    func htmlWithCSSPositionAbsolute_isComplex() {
        let html = """
        <html><head>
        <style>.positioned { position: absolute; top: 10px; left: 20px; }</style>
        </head><body><div class="positioned">Absolute positioned</div></body></html>
        """
        #expect(EPUBComplexityClassifier.classify(html: html) == .complex)
    }

    // MARK: - Edge Cases

    @Test("case-insensitive tag detection")
    func caseInsensitiveTagDetection() {
        let html = "<html><body><TABLE><TR><TD>Data</TD></TR></TABLE></body></html>"
        #expect(EPUBComplexityClassifier.classify(html: html) == .complex)
    }

    @Test("complex tag inside attribute value is NOT a false positive")
    func tagInAttributeValue_notFalsePositive() {
        // The word "table" appearing in an attribute should not trigger
        // false positive; but "<table" with angle bracket should.
        let html = """
        <html><body>
        <p class="table-like">Not a real table</p>
        </body></html>
        """
        #expect(EPUBComplexityClassifier.classify(html: html) == .simple)
    }

    @Test("SVG in img src attribute is NOT complex")
    func svgInImgSrc_isNotComplex() {
        // An <img> referencing an SVG file is fine — it's the inline <svg> tag
        // that makes content complex.
        let html = """
        <html><body>
        <img src="diagram.svg" alt="Diagram" />
        </body></html>
        """
        #expect(EPUBComplexityClassifier.classify(html: html) == .simple)
    }

    @Test("whitespace-only HTML is simple")
    func whitespaceOnlyHTML_isNotComplex() {
        #expect(EPUBComplexityClassifier.classify(html: "   \n\t  ") == .simple)
    }

    @Test("CSS grid in attribute value not false positive")
    func gridInAttributeNotFalsePositive() {
        // "display:grid" inside class name shouldn't trigger
        let html = """
        <html><body>
        <div class="display-grid-like">Content</div>
        </body></html>
        """
        #expect(EPUBComplexityClassifier.classify(html: html) == .simple)
    }

    // MARK: - Book-Level Classification

    @Test("all simple chapters → book is simple")
    func classifyBook_allSimple() {
        let chapters = [
            "<html><body><p>Chapter 1</p></body></html>",
            "<html><body><p>Chapter 2</p></body></html>",
            "<html><body><p>Chapter 3</p></body></html>",
        ]
        #expect(EPUBComplexityClassifier.classifyBook(chapterHTMLs: chapters) == .simple)
    }

    @Test("one complex chapter → book is complex")
    func classifyBook_oneComplex() {
        let chapters = [
            "<html><body><p>Chapter 1</p></body></html>",
            "<html><body><table><tr><td>Data</td></tr></table></body></html>",
            "<html><body><p>Chapter 3</p></body></html>",
        ]
        #expect(EPUBComplexityClassifier.classifyBook(chapterHTMLs: chapters) == .complex)
    }

    @Test("empty chapter list → book is simple")
    func classifyBook_empty() {
        #expect(EPUBComplexityClassifier.classifyBook(chapterHTMLs: []) == .simple)
    }

    @Test("single complex chapter → book is complex")
    func classifyBook_singleComplex() {
        let chapters = [
            "<html><body><svg><circle/></svg></body></html>",
        ]
        #expect(EPUBComplexityClassifier.classifyBook(chapterHTMLs: chapters) == .complex)
    }
}
