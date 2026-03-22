// Purpose: Detects text encoding from HTTP responses and HTML content.
// Used by BookSourceHTTPClient to correctly decode web pages.
//
// Pipeline: HTTP Content-Type header → HTML meta charset → BOM → default UTF-8
//
// Key decisions:
// - HTTP Content-Type charset takes highest priority (server-authoritative).
// - HTML meta charset is parsed from raw bytes (ASCII-safe scan) before full decode.
// - BOM detection as fallback for unusual encodings.
// - Supports GB2312, GBK, Big5, Shift_JIS, EUC-KR, UTF-8 (common for Chinese novels).
// - Enum (not actor) because detection is a pure function with no mutable state.
//
// @coordinates-with: BookSourceHTTPClient.swift

import Foundation

/// Detects and resolves text encoding for web page content.
enum WebPageEncodingDetector {

    // MARK: - Public Encoding Constants

    /// GBK / GB18030 encoding (covers GB2312 as a subset).
    static let gbkEncoding = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
    )

    /// GB2312 encoding — maps to GBK/GB18030 on Apple platforms.
    static let gb2312Encoding = gbkEncoding

    /// Big5 encoding (Traditional Chinese).
    static let big5Encoding = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.big5.rawValue)
        )
    )

    /// EUC-KR encoding (Korean).
    static let eucKREncoding = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.EUC_KR.rawValue)
        )
    )

    // MARK: - Detect Encoding

    /// Detects the encoding of web page data using multiple signals.
    ///
    /// Priority order:
    /// 1. HTTP Content-Type charset (if present and recognized)
    /// 2. HTML `<meta charset>` or `<meta http-equiv>` (parsed from raw bytes)
    /// 3. BOM (Byte Order Mark)
    /// 4. Default: UTF-8
    ///
    /// - Parameters:
    ///   - data: Raw response body bytes.
    ///   - contentTypeHeader: Value of the HTTP `Content-Type` header, if available.
    /// - Returns: The detected `String.Encoding`.
    static func detect(data: Data, contentTypeHeader: String?) -> String.Encoding {
        // 1. Check HTTP Content-Type header
        if let header = contentTypeHeader,
           let charset = parseCharset(from: header),
           let encoding = encodingFromName(charset) {
            return encoding
        }

        // 2. Check HTML meta charset (scan raw bytes for ASCII-safe patterns)
        if let charset = parseMetaCharset(from: data),
           let encoding = encodingFromName(charset) {
            return encoding
        }

        // 3. Check BOM
        if let encoding = detectBOM(data: data) {
            return encoding
        }

        // 4. Default
        return .utf8
    }

    // MARK: - Decode Data

    /// Decodes raw bytes using the specified encoding, with UTF-8 fallback.
    ///
    /// - Parameters:
    ///   - data: Raw bytes to decode.
    ///   - encoding: The encoding to use.
    /// - Returns: Decoded string, or nil if decoding fails entirely.
    static func decode(data: Data, encoding: String.Encoding) -> String? {
        if data.isEmpty { return "" }

        // Try requested encoding first
        if let text = String(data: data, encoding: encoding) {
            return text
        }

        // Fallback to UTF-8
        if encoding != .utf8, let text = String(data: data, encoding: .utf8) {
            return text
        }

        // Last resort: lossy UTF-8
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Private: Parse Charset from Content-Type

    /// Extracts charset value from a Content-Type header string.
    /// Example: `"text/html; charset=utf-8"` → `"utf-8"`
    private static func parseCharset(from contentType: String) -> String? {
        let lower = contentType.lowercased()
        guard let range = lower.range(of: "charset=") else { return nil }

        var value = String(lower[range.upperBound...])
            .trimmingCharacters(in: .whitespaces)

        // Remove quotes if present
        if value.hasPrefix("\"") || value.hasPrefix("'") {
            value = String(value.dropFirst())
        }
        if value.hasSuffix("\"") || value.hasSuffix("'") {
            value = String(value.dropLast())
        }

        // Remove trailing semicolons or whitespace
        if let semi = value.firstIndex(of: ";") {
            value = String(value[..<semi])
        }

        return value.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Private: Parse Meta Charset from HTML Bytes

    /// Scans the first 1024 bytes of HTML for a meta charset declaration.
    /// Works on raw bytes to avoid chicken-and-egg encoding problem.
    ///
    /// Matches patterns:
    /// - `<meta charset="utf-8">`
    /// - `<meta charset='utf-8'>`
    /// - `<meta http-equiv="Content-Type" content="text/html; charset=utf-8">`
    private static func parseMetaCharset(from data: Data) -> String? {
        // Only scan the head section (first 1024 bytes is sufficient)
        let scanSize = min(data.count, 1024)
        guard scanSize > 0 else { return nil }

        // Convert to ASCII string for pattern matching (safe because charset
        // names and HTML tags are ASCII)
        let bytes = [UInt8](data.prefix(scanSize))
        guard let ascii = String(bytes: bytes, encoding: .ascii) else { return nil }
        let lower = ascii.lowercased()

        // Pattern 1: <meta charset="..." /> or <meta charset='...'>
        if let match = matchPattern(
            in: lower,
            pattern: #"<meta\s+charset\s*=\s*[\"']?([a-z0-9_\-]+)[\"']?"#
        ) {
            return match
        }

        // Pattern 2: <meta http-equiv="Content-Type" content="text/html; charset=...">
        if let match = matchPattern(
            in: lower,
            pattern: #"<meta\s+http-equiv\s*=\s*[\"']?content-type[\"']?\s+content\s*=\s*[\"'][^\"']*charset=([a-z0-9_\-]+)"#
        ) {
            return match
        }

        return nil
    }

    /// Regex helper: returns first capture group match.
    private static func matchPattern(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(
                in: text,
                range: NSRange(text.startIndex..., in: text)
              ),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }

    // MARK: - Private: BOM Detection

    /// Detects encoding from Byte Order Mark.
    private static func detectBOM(data: Data) -> String.Encoding? {
        guard data.count >= 2 else { return nil }

        let bytes = [UInt8](data.prefix(4))

        // UTF-8 BOM: EF BB BF
        if bytes.count >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF {
            return .utf8
        }

        // UTF-16 LE BOM: FF FE (check before UTF-32 LE which starts the same)
        if bytes.count >= 4 && bytes[0] == 0xFF && bytes[1] == 0xFE
            && bytes[2] == 0x00 && bytes[3] == 0x00 {
            return .utf32LittleEndian
        }

        // UTF-32 BE BOM: 00 00 FE FF
        if bytes.count >= 4 && bytes[0] == 0x00 && bytes[1] == 0x00
            && bytes[2] == 0xFE && bytes[3] == 0xFF {
            return .utf32BigEndian
        }

        // UTF-16 LE BOM: FF FE
        if bytes[0] == 0xFF && bytes[1] == 0xFE {
            return .utf16LittleEndian
        }

        // UTF-16 BE BOM: FE FF
        if bytes[0] == 0xFE && bytes[1] == 0xFF {
            return .utf16BigEndian
        }

        return nil
    }

    // MARK: - Private: Encoding Name Mapping

    /// Maps a charset name string to a Swift `String.Encoding`.
    /// Handles common aliases used in web content.
    private static func encodingFromName(_ name: String) -> String.Encoding? {
        switch name.lowercased() {
        case "utf-8", "utf8":
            return .utf8
        case "gb2312", "gbk", "gb18030", "x-gbk":
            return gbkEncoding
        case "big5", "big5-hkscs":
            return big5Encoding
        case "shift_jis", "shift-jis", "sjis", "x-sjis":
            return .shiftJIS
        case "euc-kr", "euckr", "ks_c_5601-1987":
            return eucKREncoding
        case "euc-jp", "eucjp":
            return .japaneseEUC
        case "iso-8859-1", "latin1":
            return .isoLatin1
        case "windows-1252", "cp1252":
            return .windowsCP1252
        case "utf-16", "utf16":
            return .utf16
        case "utf-16le":
            return .utf16LittleEndian
        case "utf-16be":
            return .utf16BigEndian
        default:
            // Try CoreFoundation IANA charset name mapping
            let cfEncoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
            if cfEncoding != kCFStringEncodingInvalidId {
                let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
                return String.Encoding(rawValue: nsEncoding)
            }
            return nil
        }
    }
}
