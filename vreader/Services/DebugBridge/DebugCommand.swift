// Purpose: Parser and value type for the vreader-debug:// URL grammar
// (feature #44 DebugBridge). Pure value-type parsing, no OS dependencies.
// DEBUG-only — entire file compiled out of Release builds.

#if DEBUG

import Foundation

/// A command parsed from a `vreader-debug://` URL.
///
/// Grammar: `vreader-debug://<command>[?<params>]`
///
/// - `reset` — wipe library and reset settings.
/// - `seed?fixture=<name>` — seed a bundled fixture book.
/// - `open?bookId=<uuid>[&cfi=<position>]` — open a book at an optional position.
/// - `theme?mode=<dark|light>[&fontSize=<int>]` — set appearance state.
/// - `settle?token=<id>` — write `Caches/ready-<id>.json` after layout settles.
/// - `snapshot?dest=<file>` — write semantic state JSON to the app container.
/// - `eval?bridge=<name>&js=<base64>` — evaluate JS in the named webview bridge.
enum DebugCommand: Equatable {
    case reset
    case seed(fixture: String)
    case open(bookId: String, position: String?)
    case theme(mode: ThemeMode, fontSize: Int?)
    case settle(token: String)
    case snapshot(dest: String)
    case eval(bridge: String, js: String)

    enum ThemeMode: String, Equatable {
        case dark
        case light
    }
}

/// Errors produced by `DebugCommand.parse(_:)`.
enum DebugCommandError: Error, Equatable {
    case invalidScheme
    case unknownCommand(String)
    case missingParam(String)
    case invalidParam(String, reason: String)
}

extension DebugCommand {

    /// Expected URL scheme. The URL host names the command.
    static let scheme = "vreader-debug"

    /// Parse a URL into a `DebugCommand`, or throw a `DebugCommandError`.
    ///
    /// Validates scheme, command name, and required/typed parameters. Empty-string
    /// values for required params are treated as missing.
    static func parse(_ url: URL) throws -> DebugCommand {
        guard url.scheme == scheme else {
            throw DebugCommandError.invalidScheme
        }
        guard let host = url.host, !host.isEmpty else {
            throw DebugCommandError.unknownCommand("")
        }
        let params = queryParams(url)

        switch host {
        case "reset":
            return .reset

        case "seed":
            let fixture = try requireParam("fixture", in: params)
            return .seed(fixture: fixture)

        case "open":
            let bookId = try requireParam("bookId", in: params)
            let position = nonEmpty(params["cfi"])
            return .open(bookId: bookId, position: position)

        case "theme":
            let modeRaw = try requireParam("mode", in: params)
            guard let mode = ThemeMode(rawValue: modeRaw) else {
                throw DebugCommandError.invalidParam("mode", reason: "expected dark|light, got \(modeRaw)")
            }
            let fontSize: Int?
            if let raw = nonEmpty(params["fontSize"]) {
                guard let parsed = Int(raw) else {
                    throw DebugCommandError.invalidParam("fontSize", reason: "expected integer, got \(raw)")
                }
                fontSize = parsed
            } else {
                fontSize = nil
            }
            return .theme(mode: mode, fontSize: fontSize)

        case "settle":
            let token = try requireParam("token", in: params)
            return .settle(token: token)

        case "snapshot":
            let dest = try requireParam("dest", in: params)
            return .snapshot(dest: dest)

        case "eval":
            let bridge = try requireParam("bridge", in: params)
            let encoded = try requireParam("js", in: params)
            guard let data = Data(base64Encoded: encoded),
                  let js = String(data: data, encoding: .utf8) else {
                throw DebugCommandError.invalidParam("js", reason: "not valid base64-encoded UTF-8")
            }
            return .eval(bridge: bridge, js: js)

        default:
            throw DebugCommandError.unknownCommand(host)
        }
    }

    // MARK: - Helpers

    private static func queryParams(_ url: URL) -> [String: String] {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = comps.queryItems else {
            return [:]
        }
        var out: [String: String] = [:]
        for item in items {
            out[item.name] = item.value ?? ""
        }
        return out
    }

    private static func requireParam(_ name: String, in params: [String: String]) throws -> String {
        guard let raw = params[name], !raw.isEmpty else {
            throw DebugCommandError.missingParam(name)
        }
        return raw
    }

    private static func nonEmpty(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        return raw
    }
}

#endif
