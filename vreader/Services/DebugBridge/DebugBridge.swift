// Purpose: Orchestrator for the vreader-debug:// URL scheme (feature #44).
// Parses incoming URLs via DebugCommand, dispatches to a DebugBridgeContext
// implementation. Pure routing — does not own state or side effects so it can
// be unit-tested with mock contexts. DEBUG-only.

#if DEBUG

import Foundation

/// All side-effectful command handlers used by the debug bridge. Implementations
/// own real app state; the bridge itself stays a pure dispatcher.
@MainActor
protocol DebugBridgeContext {
    func reset() async
    func seed(fixture: String) async
    func open(bookId: String, position: String?) async
    func theme(mode: DebugCommand.ThemeMode, fontSize: Int?) async
    func settle(token: String) async
    func snapshot(dest: String) async
    func eval(bridge: String, js: String) async
}

/// Routes parsed `DebugCommand` values to a `DebugBridgeContext`.
/// Records the most recent error (parse failures) for debugging.
///
/// Concurrency: commands are serialized through a chained Task so that two
/// rapid `handle(_:)` calls cannot interleave. `@MainActor` alone wouldn't
/// guarantee this — actor methods are reentrant across `await` points, and
/// `.onOpenURL` callbacks spawn independent unstructured tasks.
@MainActor
final class DebugBridge {
    private let context: DebugBridgeContext
    private(set) var lastError: Error?
    /// Tail of the chain of in-flight command tasks. Each new `handle(_:)`
    /// awaits the previous task before processing, giving FIFO semantics.
    private var pendingTask: Task<Void, Never>?

    init(context: DebugBridgeContext) {
        self.context = context
    }

    /// Parse `url`, dispatch to the matching context method, serialized
    /// after any previously-enqueued command. Returns when this command
    /// (and the chain in front of it) has completed.
    /// Sets `lastError` on parse failure; clears it on successful dispatch.
    func handle(_ url: URL) async {
        let previous = pendingTask
        let next = Task<Void, Never> { @MainActor [weak self] in
            _ = await previous?.value
            await self?.process(url)
        }
        pendingTask = next
        await next.value
    }

    private func process(_ url: URL) async {
        do {
            let cmd = try DebugCommand.parse(url)
            await dispatch(cmd)
            lastError = nil
        } catch {
            lastError = error
        }
    }

    private func dispatch(_ cmd: DebugCommand) async {
        switch cmd {
        case .reset:
            await context.reset()
        case .seed(let fixture):
            await context.seed(fixture: fixture)
        case .open(let bookId, let position):
            await context.open(bookId: bookId, position: position)
        case .theme(let mode, let fontSize):
            await context.theme(mode: mode, fontSize: fontSize)
        case .settle(let token):
            await context.settle(token: token)
        case .snapshot(let dest):
            await context.snapshot(dest: dest)
        case .eval(let bridge, let js):
            await context.eval(bridge: bridge, js: js)
        }
    }
}

#endif
