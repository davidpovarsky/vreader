// Purpose: App-lifetime singleton for the DebugBridge (feature #44). Holds a
// single MainActor-isolated bridge instance so `.onOpenURL` callbacks in
// VReaderApp can dispatch to it without per-event allocation, and so future
// command handlers can carry state (open settle tokens, cached fixtures).
// DEBUG-only.

#if DEBUG

import Foundation
import OSLog

@MainActor
enum DebugBridgeProvider {
    /// Shared bridge for the app process. Currently routes to a logging
    /// no-op context; WI-5 swaps in a real context backed by the importer,
    /// persistence actor, and reader bridges.
    static var shared: DebugBridge = DebugBridge(context: LoggingDebugBridgeContext())
}

/// Placeholder context that logs every command without performing side
/// effects. Used until real handlers (WI-5) replace it.
@MainActor
final class LoggingDebugBridgeContext: DebugBridgeContext {
    private let log = Logger(subsystem: "com.vreader.app", category: "DebugBridge")

    /// Caches subdirectory the bridge writes sentinel/event files to.
    /// Stable, simctl-readable path: `~/Library/Developer/CoreSimulator/Devices/<sim>/data/Containers/Data/Application/<uuid>/Library/Caches/DebugBridge/events.log`
    private static let cachesDir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DebugBridge", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    private func record(_ message: String) {
        log.info("\(message, privacy: .public)")
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        let path = Self.cachesDir.appendingPathComponent("events.log")
        if let data = line.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: path) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: path)
            }
        }
    }

    func reset() async {
        record("reset")
    }

    func seed(fixture: String) async {
        record("seed fixture=\(fixture)")
    }

    func open(bookId: String, position: String?) async {
        record("open bookId=\(bookId) position=\(position ?? "nil")")
    }

    func theme(mode: DebugCommand.ThemeMode, fontSize: Int?) async {
        record("theme mode=\(mode.rawValue) fontSize=\(fontSize.map(String.init) ?? "nil")")
    }

    func settle(token: String) async {
        record("settle token=\(token)")
    }

    func snapshot(dest: String) async {
        record("snapshot dest=\(dest)")
    }

    func eval(bridge: String, js: String) async {
        record("eval bridge=\(bridge) jsLen=\(js.count)")
    }
}

#endif
