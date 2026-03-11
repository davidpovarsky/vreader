// Purpose: Minimal SQLite3 wrapper owning the database handle and lock.
// Provides thread-safe query execution without exposing raw pointers.
//
// Key decisions:
// - Owns db + lock — single owner of the connection lifecycle.
// - `withLock` for multi-statement transactions (BEGIN/INSERT/COMMIT).
// - `query()` owns full statement lifecycle — no OpaquePointer escapes.
// - `exec()` for DDL/DML that return no rows.
// - Extracted from SearchIndexStore in WI-007.
//
// @coordinates-with: SearchIndexStore.swift, SearchQueryExecutor.swift

import Foundation
import SQLite3
import os

/// Minimal SQLite3 database wrapper. Thread-safe via internal lock.
final class SearchIndexCore: @unchecked Sendable {

    private var db: OpaquePointer?
    private let lock = OSAllocatedUnfairLock()

    /// Opens an in-memory SQLite database.
    init() throws {
        var dbPtr: OpaquePointer?
        let rc = sqlite3_open(":memory:", &dbPtr)
        guard rc == SQLITE_OK, let dbPtr else {
            let msg = dbPtr.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw SearchIndexError.databaseOpenFailed(msg)
        }
        self.db = dbPtr
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    // MARK: - Thread-Safe Access

    /// Executes a closure while holding the internal lock.
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    // MARK: - DDL / DML (No Result Rows)

    /// Executes a SQL statement that returns no rows.
    func exec(_ sql: String) throws {
        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if rc != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(errMsg)
            throw SearchIndexError.indexFailed(msg)
        }
    }

    /// Executes a parameterized SQL statement that returns no rows.
    func execBind(_ sql: String, params: [String]) throws {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let stmt else { throw SearchIndexError.indexFailed(errMsg()) }
        defer { sqlite3_finalize(stmt) }
        for (i, param) in params.enumerated() { try bindTextChecked(stmt, Int32(i + 1), param) }
        let stepRC = sqlite3_step(stmt)
        guard stepRC == SQLITE_DONE || stepRC == SQLITE_ROW else {
            throw SearchIndexError.indexFailed(errMsg())
        }
    }

    // MARK: - Query (Returns Rows)

    /// Prepares, binds, steps, and maps a query. Statement lifecycle is fully owned.
    func query<T>(_ sql: String, params: [String], map: (RowReader) -> T) throws -> [T] {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let stmt else { throw SearchIndexError.queryFailed(errMsg()) }
        defer { sqlite3_finalize(stmt) }
        for (i, param) in params.enumerated() { try bindTextChecked(stmt, Int32(i + 1), param) }
        var results: [T] = []
        let reader = RowReader(stmt: stmt)
        var stepRC = sqlite3_step(stmt)
        while stepRC == SQLITE_ROW {
            results.append(map(reader))
            stepRC = sqlite3_step(stmt)
        }
        guard stepRC == SQLITE_DONE else {
            throw SearchIndexError.queryFailed(errMsg())
        }
        return results
    }

    // MARK: - Row Reader

    /// Safe row reader that wraps a statement pointer. Only valid during `query` callback.
    struct RowReader {
        fileprivate let stmt: OpaquePointer

        func text(_ col: Int32) -> String {
            guard let ptr = sqlite3_column_text(stmt, col) else { return "" }
            return String(cString: ptr)
        }

        func int64(_ col: Int32) -> Int64 {
            sqlite3_column_int64(stmt, col)
        }
    }

    // MARK: - Private

    private static let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func bindTextChecked(_ stmt: OpaquePointer, _ idx: Int32, _ value: String) throws {
        let rc = sqlite3_bind_text(stmt, idx, value, -1, Self.SQLITE_TRANSIENT)
        guard rc == SQLITE_OK else {
            throw SearchIndexError.indexFailed("bind failed at index \(idx): \(errMsg())")
        }
    }

    func errMsg() -> String {
        db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
    }
}
