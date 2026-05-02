// Purpose: Tests for DebugBridge orchestrator — wires URL parsing
// (DebugCommand) to per-command handlers (DebugBridgeContext) for
// feature #44. Verifies dispatch routing, error handling, and that
// handlers receive the parsed command faithfully.

#if DEBUG

import XCTest
@testable import vreader

final class DebugBridgeTests: XCTestCase {

    // MARK: - Routing

    @MainActor
    func test_handle_resetURL_callsResetHandler() async {
        let context = RecordingDebugBridgeContext()
        let bridge = DebugBridge(context: context)

        await bridge.handle(URL(string: "vreader-debug://reset")!)

        XCTAssertEqual(context.calls, [.reset])
    }

    @MainActor
    func test_handle_seedURL_callsSeedHandlerWithFixtureName() async {
        let context = RecordingDebugBridgeContext()
        let bridge = DebugBridge(context: context)

        await bridge.handle(URL(string: "vreader-debug://seed?fixture=alice")!)

        XCTAssertEqual(context.calls, [.seed(fixture: "alice")])
    }

    @MainActor
    func test_handle_unknownCommand_recordsParseErrorWithoutCallingHandlers() async {
        let context = RecordingDebugBridgeContext()
        let bridge = DebugBridge(context: context)

        await bridge.handle(URL(string: "vreader-debug://teleport")!)

        XCTAssertTrue(context.calls.isEmpty, "no handlers should be invoked")
        XCTAssertNotNil(bridge.lastError, "parse error should be recorded")
    }

    @MainActor
    func test_handle_wrongScheme_recordsErrorWithoutCallingHandlers() async {
        let context = RecordingDebugBridgeContext()
        let bridge = DebugBridge(context: context)

        await bridge.handle(URL(string: "https://example.com")!)

        XCTAssertTrue(context.calls.isEmpty)
        XCTAssertNotNil(bridge.lastError)
    }

    @MainActor
    func test_handle_successClearsLastError() async {
        let context = RecordingDebugBridgeContext()
        let bridge = DebugBridge(context: context)

        // First a failing call
        await bridge.handle(URL(string: "vreader-debug://teleport")!)
        XCTAssertNotNil(bridge.lastError)

        // Then a succeeding call
        await bridge.handle(URL(string: "vreader-debug://reset")!)
        XCTAssertNil(bridge.lastError, "lastError should clear after a successful dispatch")
    }

    @MainActor
    func test_handle_multipleCommands_areDispatchedInOrder() async {
        let context = RecordingDebugBridgeContext()
        let bridge = DebugBridge(context: context)

        await bridge.handle(URL(string: "vreader-debug://reset")!)
        await bridge.handle(URL(string: "vreader-debug://seed?fixture=alice")!)
        await bridge.handle(URL(string: "vreader-debug://reset")!)

        XCTAssertEqual(context.calls, [.reset, .seed(fixture: "alice"), .reset])
    }
}

// MARK: - Recorder

/// Records every command the bridge dispatches, in order. Each method is a
/// no-op except for the recording. Used to verify routing without coupling
/// tests to real app state.
@MainActor
final class RecordingDebugBridgeContext: DebugBridgeContext {
    enum Call: Equatable {
        case reset
        case seed(fixture: String)
        case open(bookId: String, position: String?)
        case theme(mode: DebugCommand.ThemeMode, fontSize: Int?)
        case settle(token: String)
        case snapshot(dest: String)
        case eval(bridge: String, js: String)
    }

    private(set) var calls: [Call] = []

    func reset() async { calls.append(.reset) }
    func seed(fixture: String) async { calls.append(.seed(fixture: fixture)) }
    func open(bookId: String, position: String?) async {
        calls.append(.open(bookId: bookId, position: position))
    }
    func theme(mode: DebugCommand.ThemeMode, fontSize: Int?) async {
        calls.append(.theme(mode: mode, fontSize: fontSize))
    }
    func settle(token: String) async { calls.append(.settle(token: token)) }
    func snapshot(dest: String) async { calls.append(.snapshot(dest: dest)) }
    func eval(bridge: String, js: String) async {
        calls.append(.eval(bridge: bridge, js: js))
    }
}

#endif
