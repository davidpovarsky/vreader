// Purpose: Actor-isolated suspension/resolution for confirmation UI. Each request
// owns exactly one checked continuation and is removed before any resume/persist.

import Foundation

actor AIActionConfirmationBroker {
    private final class TerminalGate: @unchecked Sendable {
        private enum State {
            case pending
            case cancelled
            case resolved
        }

        private let lock = NSLock()
        private var state = State.pending

        func cancel() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard state == .pending else { return false }
            state = .cancelled
            return true
        }

        func resolve() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard state == .pending else { return false }
            state = .resolved
            return true
        }
    }

    private struct Pending {
        let request: AIActionConfirmationRequest
        let terminalGate: TerminalGate
        let continuation: CheckedContinuation<AIActionConfirmationOutcome, Never>
    }

    private let preferencesStore: any AIAgentPreferencesStoring
    private var pending: [UUID: Pending] = [:]
    private var observers: [UUID: AsyncStream<[AIActionConfirmationRequest]>.Continuation] = [:]

    init(preferencesStore: any AIAgentPreferencesStoring = AIAgentPreferencesStore.shared) {
        self.preferencesStore = preferencesStore
    }

    var pendingRequestCount: Int { pending.count }

    func pendingRequests() -> [AIActionConfirmationRequest] {
        currentRequests()
    }

    /// A buffering-newest stream gives future UI an initial snapshot and every
    /// subsequent state change without coupling this domain actor to SwiftUI.
    func pendingRequestUpdates() -> AsyncStream<[AIActionConfirmationRequest]> {
        let observerID = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            observers[observerID] = continuation
            continuation.yield(currentRequests())
            continuation.onTermination = { @Sendable [weak self] _ in
                Task { await self?.removeObserver(observerID) }
            }
        }
    }

    func requestConfirmation(
        _ request: AIActionConfirmationRequest
    ) async -> AIActionConfirmationOutcome {
        let terminalGate = TerminalGate()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled, pending[request.id] == nil else {
                    _ = terminalGate.cancel()
                    continuation.resume(returning: .cancelled)
                    return
                }
                pending[request.id] = Pending(
                    request: request,
                    terminalGate: terminalGate,
                    continuation: continuation
                )
                publishPendingRequests()
            }
        } onCancel: {
            // Mark synchronously before hopping back to the actor. A UI approval
            // racing this cancellation cannot observe stale "not cancelled" state.
            if terminalGate.cancel() {
                Task { await self.invalidate(request.id) }
            }
        }
    }

    @discardableResult
    func resolve(
        _ requestID: UUID,
        with response: AIActionConfirmationResponse
    ) async -> Bool {
        guard let entry = pending[requestID] else { return false }

        if response == .alwaysAllow,
           (!entry.request.rememberAllowEligible
            || entry.request.isDestructive
            || entry.request.permissionCategory == .removeData) {
            return false
        }

        pending.removeValue(forKey: requestID)
        publishPendingRequests()

        guard entry.terminalGate.resolve() else {
            entry.continuation.resume(returning: .cancelled)
            return false
        }

        switch response {
        case .allowOnce:
            entry.continuation.resume(returning: .allowed)
        case .deny:
            entry.continuation.resume(returning: .denied)
        case .alwaysAllow:
            // Eligibility was checked before removal. Destructive/removeData
            // requests normalize eligibility to false at model construction.
            // Resume first: this is the atomic approval point relative to the
            // synchronous cancellation flag; persistence is the ensuing side effect.
            entry.continuation.resume(returning: .allowed)
            await preferencesStore.setDecision(
                .allow,
                for: entry.request.permissionCategory
            )
            if entry.request.permissionCategory == .readAhead {
                await preferencesStore.setReadAheadMode(.wholeBookAllowed)
            }
        }
        return true
    }

    func invalidate(_ requestID: UUID) {
        guard let entry = pending.removeValue(forKey: requestID) else { return }
        _ = entry.terminalGate.cancel()
        publishPendingRequests()
        entry.continuation.resume(returning: .cancelled)
    }

    func cancelTurn(_ turnID: String) {
        let ids = pending.values.compactMap {
            $0.request.turnID == turnID ? $0.request.id : nil
        }
        cancel(ids)
    }

    /// Reader/chat teardown. Callers may keep the broker and begin a later turn.
    func cancelAll() {
        cancel(Array(pending.keys))
    }

    private func cancel(_ requestIDs: [UUID]) {
        let entries = requestIDs.compactMap { pending.removeValue(forKey: $0) }
        guard !entries.isEmpty else { return }
        publishPendingRequests()
        for entry in entries {
            _ = entry.terminalGate.cancel()
            entry.continuation.resume(returning: .cancelled)
        }
    }

    private func currentRequests() -> [AIActionConfirmationRequest] {
        pending.values.map(\.request).sorted {
            $0.id.uuidString < $1.id.uuidString
        }
    }

    private func publishPendingRequests() {
        let snapshot = currentRequests()
        for continuation in observers.values {
            continuation.yield(snapshot)
        }
    }

    private func removeObserver(_ observerID: UUID) {
        observers.removeValue(forKey: observerID)
    }
}
