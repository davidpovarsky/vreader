// Purpose: Import/export BookSource in Legado's JSON format for ecosystem compatibility.
// Handles field mapping, compatibility classification, and duplicate deduplication.
//
// Key decisions:
// - Accepts both single-object and array JSON (Legado exports both forms).
// - Unknown fields are silently ignored via flexible DTO decoding.
// - Sources with empty/whitespace-only URLs are skipped (not errors).
// - Duplicate URLs are deduplicated (first occurrence wins).
// - Compatibility classification: Full (CSS/regex), Limited (XPath), Unsupported (JS).
//
// @coordinates-with: LegadoBookSourceDTO.swift, BookSource.swift, BookSourceRules.swift

import Foundation

// MARK: - Error Types

/// Errors that can occur during Legado JSON import.
enum LegadoImportError: Error, Sendable, Equatable {
    /// The input data is not valid JSON.
    case invalidJSON
    /// The JSON structure doesn't match the expected format.
    case unexpectedFormat
}

// MARK: - LegadoImporter

/// Imports and exports BookSource objects in Legado's JSON format.
enum LegadoImporter {

    // MARK: - Import

    /// Imports book sources from Legado JSON data.
    /// Accepts both a single object `{...}` and an array `[{...}, ...]`.
    /// - Parameter jsonData: Raw JSON bytes in Legado format.
    /// - Returns: Array of BookSource objects (deduplicated by URL).
    /// - Throws: `LegadoImportError` on invalid JSON.
    static func importSources(from jsonData: Data) throws -> [BookSource] {
        let dtos = try parseDTOs(from: jsonData)
        return convertAndDeduplicate(dtos)
    }

    // MARK: - Export

    /// Exports book sources to Legado-compatible JSON data.
    /// Always exports as an array (even for a single source).
    /// - Parameter sources: Array of BookSource objects to export.
    /// - Returns: JSON data in Legado format.
    static func exportSources(_ sources: [BookSource]) throws -> Data {
        let dtos = sources.map { convertToDTO($0) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(dtos)
    }

    // MARK: - Parse DTOs

    /// Parses JSON data into an array of DTOs.
    /// Handles both single-object and array forms.
    private static func parseDTOs(from data: Data) throws -> [LegadoBookSourceDTO] {
        let decoder = JSONDecoder()

        // Try array first (most common)
        if let array = try? decoder.decode(
            [LegadoBookSourceDTO].self,
            from: data
        ) {
            return array
        }

        // Try single object
        if let single = try? decoder.decode(
            LegadoBookSourceDTO.self,
            from: data
        ) {
            return [single]
        }

        throw LegadoImportError.invalidJSON
    }

    // MARK: - Convert and Deduplicate

    /// Converts DTOs to BookSource models, deduplicating by URL.
    private static func convertAndDeduplicate(
        _ dtos: [LegadoBookSourceDTO]
    ) -> [BookSource] {
        var seenURLs = Set<String>()
        var results: [BookSource] = []

        for dto in dtos {
            guard let url = dto.bookSourceUrl,
                  BookSource.validateSourceURL(url) else {
                continue // skip empty/missing URLs
            }

            guard !seenURLs.contains(url) else {
                continue // skip duplicates
            }
            seenURLs.insert(url)

            let source = convertToBookSource(dto)
            source.compatibilityLevel = classifyCompatibility(dto)
            results.append(source)
        }

        return results
    }

    // MARK: - DTO → BookSource

    /// Converts a Legado DTO to a VReader BookSource model.
    private static func convertToBookSource(
        _ dto: LegadoBookSourceDTO
    ) -> BookSource {
        let url = dto.bookSourceUrl ?? ""
        let name = dto.bookSourceName
            ?? (url.isEmpty ? "Unknown" : url)

        let source = BookSource(
            sourceURL: url,
            sourceName: name,
            sourceGroup: dto.bookSourceGroup,
            sourceType: dto.bookSourceType ?? 0,
            enabled: dto.enabled ?? true,
            searchURL: dto.searchUrl,
            header: dto.header,
            customOrder: dto.customOrder ?? 0
        )

        // Convert lastUpdateTime from Legado ms epoch to Date
        if let ms = dto.lastUpdateTime {
            source.lastUpdateTime = Date(
                timeIntervalSince1970: Double(ms) / 1000.0
            )
        }

        // Convert rules
        if let searchDTO = dto.ruleSearch {
            source.updateSearchRule(convertSearchRule(searchDTO))
        }
        if let bookInfoDTO = dto.ruleBookInfo {
            source.updateBookInfoRule(convertBookInfoRule(bookInfoDTO))
        }
        if let tocDTO = dto.ruleToc {
            source.updateTocRule(convertTocRule(tocDTO))
        }
        if let contentDTO = dto.ruleContent {
            source.updateContentRule(convertContentRule(contentDTO))
        }

        return source
    }

    // MARK: - BookSource → DTO

    /// Converts a VReader BookSource to a Legado DTO for export.
    private static func convertToDTO(_ source: BookSource) -> LegadoBookSourceDTO {
        var dto = LegadoBookSourceDTO()
        dto.bookSourceUrl = source.sourceURL
        dto.bookSourceName = source.sourceName
        dto.bookSourceGroup = source.sourceGroup
        dto.bookSourceType = source.sourceType
        dto.enabled = source.enabled
        dto.searchUrl = source.searchURL
        dto.header = source.header
        dto.customOrder = source.customOrder

        // Convert Date to Legado ms epoch
        if let date = source.lastUpdateTime {
            dto.lastUpdateTime = Int64(date.timeIntervalSince1970 * 1000)
        }

        // Convert rules
        if let rule = source.ruleSearch {
            dto.ruleSearch = exportSearchRule(rule)
        }
        if let rule = source.ruleBookInfo {
            dto.ruleBookInfo = exportBookInfoRule(rule)
        }
        if let rule = source.ruleToc {
            dto.ruleToc = exportTocRule(rule)
        }
        if let rule = source.ruleContent {
            dto.ruleContent = exportContentRule(rule)
        }

        return dto
    }

    // MARK: - Rule Conversion (Legado DTO → VReader)

    private static func convertSearchRule(
        _ dto: LegadoSearchRuleDTO
    ) -> BSSearchRule {
        BSSearchRule(
            bookList: dto.bookList,
            name: dto.name,
            author: dto.author,
            bookUrl: dto.bookUrl,
            coverUrl: dto.coverUrl
        )
    }

    private static func convertBookInfoRule(
        _ dto: LegadoBookInfoRuleDTO
    ) -> BSBookInfoRule {
        BSBookInfoRule(
            name: dto.name,
            author: dto.author,
            intro: dto.intro,
            coverUrl: dto.coverUrl,
            tocUrl: dto.tocUrl
        )
    }

    private static func convertTocRule(
        _ dto: LegadoTocRuleDTO
    ) -> BSTocRule {
        BSTocRule(
            chapterList: dto.chapterList,
            chapterName: dto.chapterName,
            chapterUrl: dto.chapterUrl,
            nextTocUrl: dto.nextTocUrl
        )
    }

    private static func convertContentRule(
        _ dto: LegadoContentRuleDTO
    ) -> BSContentRule {
        BSContentRule(
            content: dto.content,
            nextContentUrl: dto.nextContentUrl,
            replaceRegex: dto.replaceRegex
        )
    }

    // MARK: - Rule Conversion (VReader → Legado DTO)

    private static func exportSearchRule(
        _ rule: BSSearchRule
    ) -> LegadoSearchRuleDTO {
        LegadoSearchRuleDTO(
            bookList: rule.bookList,
            name: rule.name,
            author: rule.author,
            bookUrl: rule.bookUrl,
            coverUrl: rule.coverUrl
        )
    }

    private static func exportBookInfoRule(
        _ rule: BSBookInfoRule
    ) -> LegadoBookInfoRuleDTO {
        LegadoBookInfoRuleDTO(
            name: rule.name,
            author: rule.author,
            intro: rule.intro,
            coverUrl: rule.coverUrl,
            tocUrl: rule.tocUrl
        )
    }

    private static func exportTocRule(
        _ rule: BSTocRule
    ) -> LegadoTocRuleDTO {
        LegadoTocRuleDTO(
            chapterList: rule.chapterList,
            chapterName: rule.chapterName,
            chapterUrl: rule.chapterUrl,
            nextTocUrl: rule.nextTocUrl
        )
    }

    private static func exportContentRule(
        _ rule: BSContentRule
    ) -> LegadoContentRuleDTO {
        LegadoContentRuleDTO(
            content: rule.content,
            nextContentUrl: rule.nextContentUrl,
            replaceRegex: rule.replaceRegex
        )
    }

}
