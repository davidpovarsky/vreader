/// Centralized Logger instances for structured logging via os_log.
/// Use these instead of print() so logs are captured by `simctl log stream`.
///
/// Usage:
///   AppLogger.reader.debug("chapter loaded: \(index)")
///   AppLogger.epub.error("JS eval failed: \(error)")
///
/// Filter in terminal:
///   xcrun simctl spawn booted log stream --predicate 'subsystem == "com.vreader.app"'
///   xcrun simctl spawn booted log stream --predicate 'subsystem == "com.vreader.app" AND category == "reader"'

import OSLog

enum AppLogger {
    static let reader = Logger(subsystem: "com.vreader.app", category: "reader")
    static let epub = Logger(subsystem: "com.vreader.app", category: "epub")
    static let txt = Logger(subsystem: "com.vreader.app", category: "txt")
    static let pdf = Logger(subsystem: "com.vreader.app", category: "pdf")
    static let foliate = Logger(subsystem: "com.vreader.app", category: "foliate")
    static let search = Logger(subsystem: "com.vreader.app", category: "search")
    static let importer = Logger(subsystem: "com.vreader.app", category: "importer")
    static let persistence = Logger(subsystem: "com.vreader.app", category: "persistence")
    static let tts = Logger(subsystem: "com.vreader.app", category: "tts")
    static let ai = Logger(subsystem: "com.vreader.app", category: "ai")
    static let general = Logger(subsystem: "com.vreader.app", category: "general")
}
