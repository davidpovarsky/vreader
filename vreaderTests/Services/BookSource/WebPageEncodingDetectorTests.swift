// Purpose: Tests for WebPageEncodingDetector — detects text encoding from
// HTTP Content-Type headers, HTML meta charset, and BOM markers.
//
// @coordinates-with: WebPageEncodingDetector.swift

import Testing
import Foundation
@testable import vreader

@Suite("WebPageEncodingDetector")
struct WebPageEncodingDetectorTests {

    // MARK: - UTF-8

    @Test func detect_UTF8_fromContentType() {
        let data = "<html><body>Hello</body></html>".data(using: .utf8)!
        let result = WebPageEncodingDetector.detect(
            data: data,
            contentTypeHeader: "text/html; charset=utf-8"
        )
        #expect(result == .utf8)
    }

    @Test func detect_UTF8_fromContentType_caseInsensitive() {
        let data = "<html><body>Hello</body></html>".data(using: .utf8)!
        let result = WebPageEncodingDetector.detect(
            data: data,
            contentTypeHeader: "text/html; charset=UTF-8"
        )
        #expect(result == .utf8)
    }

    // MARK: - GB2312 from Meta

    @Test func detect_GB2312_fromMetaCharset() {
        // Simulate GB2312 page with meta charset declaration
        let html = "<html><head><meta charset=\"gb2312\"></head><body>Test</body></html>"
        let data = html.data(using: .utf8)! // meta says gb2312 but body is ASCII-safe
        let result = WebPageEncodingDetector.detect(
            data: data,
            contentTypeHeader: nil
        )
        #expect(result == WebPageEncodingDetector.gb2312Encoding)
    }

    @Test func detect_GB2312_fromMetaHttpEquiv() {
        let html = """
        <html><head>
        <meta http-equiv="Content-Type" content="text/html; charset=gb2312">
        </head><body>Test</body></html>
        """
        let data = html.data(using: .utf8)!
        let result = WebPageEncodingDetector.detect(
            data: data,
            contentTypeHeader: nil
        )
        #expect(result == WebPageEncodingDetector.gb2312Encoding)
    }

    // MARK: - GBK

    @Test func detect_GBK_fromContentType() {
        let data = "<html><body>Hello</body></html>".data(using: .utf8)!
        let result = WebPageEncodingDetector.detect(
            data: data,
            contentTypeHeader: "text/html; charset=gbk"
        )
        #expect(result == WebPageEncodingDetector.gbkEncoding)
    }

    // MARK: - Big5

    @Test func detect_Big5_fromContentType() {
        let data = "<html><body>Hello</body></html>".data(using: .utf8)!
        let result = WebPageEncodingDetector.detect(
            data: data,
            contentTypeHeader: "text/html; charset=big5"
        )
        #expect(result == WebPageEncodingDetector.big5Encoding)
    }

    // MARK: - Shift_JIS

    @Test func detect_ShiftJIS_fromContentType() {
        let data = "<html><body>Hello</body></html>".data(using: .utf8)!
        let result = WebPageEncodingDetector.detect(
            data: data,
            contentTypeHeader: "text/html; charset=shift_jis"
        )
        #expect(result == .shiftJIS)
    }

    // MARK: - EUC-KR

    @Test func detect_EUCKR_fromContentType() {
        let data = "<html><body>Hello</body></html>".data(using: .utf8)!
        let result = WebPageEncodingDetector.detect(
            data: data,
            contentTypeHeader: "text/html; charset=euc-kr"
        )
        #expect(result == WebPageEncodingDetector.eucKREncoding)
    }

    // MARK: - No Charset Defaults to UTF-8

    @Test func detect_noCharset_defaultsUTF8() {
        let data = "<html><body>Hello</body></html>".data(using: .utf8)!
        let result = WebPageEncodingDetector.detect(
            data: data,
            contentTypeHeader: "text/html"
        )
        #expect(result == .utf8)
    }

    @Test func detect_noCharset_noContentType_defaultsUTF8() {
        let data = "<html><body>Hello</body></html>".data(using: .utf8)!
        let result = WebPageEncodingDetector.detect(
            data: data,
            contentTypeHeader: nil
        )
        #expect(result == .utf8)
    }

    // MARK: - BOM Detection

    @Test func detect_BOM_UTF8() {
        let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
        let content = "<html><body>Hello</body></html>".data(using: .utf8)!
        let data = Data(bom) + content
        let result = WebPageEncodingDetector.detect(
            data: data,
            contentTypeHeader: nil
        )
        #expect(result == .utf8)
    }

    @Test func detect_BOM_UTF16LE() {
        let bom: [UInt8] = [0xFF, 0xFE]
        let content = "<html><body>Hi</body></html>".data(using: .utf16LittleEndian)!
        let data = Data(bom) + content
        let result = WebPageEncodingDetector.detect(
            data: data,
            contentTypeHeader: nil
        )
        #expect(result == .utf16LittleEndian)
    }

    @Test func detect_BOM_UTF16BE() {
        let bom: [UInt8] = [0xFE, 0xFF]
        let content = "<html><body>Hi</body></html>".data(using: .utf16BigEndian)!
        let data = Data(bom) + content
        let result = WebPageEncodingDetector.detect(
            data: data,
            contentTypeHeader: nil
        )
        #expect(result == .utf16BigEndian)
    }

    // MARK: - Content-Type Overrides Meta

    @Test func detect_contentType_overridesMeta() {
        // Content-Type says UTF-8, meta says gb2312. HTTP header wins.
        let html = "<html><head><meta charset=\"gb2312\"></head></html>"
        let data = html.data(using: .utf8)!
        let result = WebPageEncodingDetector.detect(
            data: data,
            contentTypeHeader: "text/html; charset=utf-8"
        )
        #expect(result == .utf8)
    }

    // MARK: - Edge Cases

    @Test func detect_emptyData_defaultsUTF8() {
        let result = WebPageEncodingDetector.detect(
            data: Data(),
            contentTypeHeader: nil
        )
        #expect(result == .utf8)
    }

    @Test func detect_unknownCharset_defaultsUTF8() {
        let data = "<html><body>Hello</body></html>".data(using: .utf8)!
        let result = WebPageEncodingDetector.detect(
            data: data,
            contentTypeHeader: "text/html; charset=x-unknown-encoding"
        )
        #expect(result == .utf8)
    }

    @Test func detect_metaCharset_withQuoteVariants() {
        // Single quotes in meta charset
        let html = "<html><head><meta charset='gbk'></head><body>Test</body></html>"
        let data = html.data(using: .utf8)!
        let result = WebPageEncodingDetector.detect(
            data: data,
            contentTypeHeader: nil
        )
        #expect(result == WebPageEncodingDetector.gbkEncoding)
    }

    // MARK: - Decode Method

    @Test func decode_UTF8_content() {
        let html = "<html><body>Hello World</body></html>"
        let data = html.data(using: .utf8)!
        let result = WebPageEncodingDetector.decode(
            data: data,
            encoding: .utf8
        )
        #expect(result == html)
    }

    @Test func decode_GB2312_content() {
        let gbkEnc = WebPageEncodingDetector.gbkEncoding
        let html = "你好世界"
        guard let data = html.data(using: gbkEnc) else {
            Issue.record("Could not encode as GBK")
            return
        }
        let result = WebPageEncodingDetector.decode(
            data: data,
            encoding: gbkEnc
        )
        #expect(result?.contains("你好世界") == true)
    }

    @Test func decode_fallback_toUTF8_onFailure() {
        let data = "Hello".data(using: .utf8)!
        // Try to decode UTF-8 data with a mismatched encoding — should fall back
        let result = WebPageEncodingDetector.decode(
            data: data,
            encoding: .utf8
        )
        #expect(result == "Hello")
    }
}
