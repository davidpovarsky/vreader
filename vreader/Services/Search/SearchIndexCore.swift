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

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "vreader",
        category: "SearchIndexCore"
    )

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

    /// Opens a file-backed SQLite database at the given path.
    /// Creates parent directories if needed. If the existing DB is corrupt,
    /// deletes it and creates a fresh one (corruption recovery).
    init(databasePath: String) throws {
        // Ensure parent directory exists
        let dirPath = (databasePath as NSString).deletingLastPathComponent
        if !dirPath.isEmpty {
            try FileManager.default.createDirectory(
                atPath: dirPath, withIntermediateDirectories: true
            )
        }

        var dbPtr: OpaquePointer?
        let rc = sqlite3_open(databasePath, &dbPtr)

        if rc == SQLITE_OK, let dbPtr {
            // Verify integrity -- detect corruption
            if Self.isCorrupt(db: dbPtr) {
                Self.logger.warning("Corrupt database at \(databasePath), recreating")
                sqlite3_close(dbPtr)
                Self.deleteDBFiles(at: databasePath)
                var freshPtr: OpaquePointer?
                let freshRC = sqlite3_open(databasePath, &freshPtr)
                guard freshRC == SQLITE_OK, let freshPtr else {
                    let msg = freshPtr.flatMap {
                        String(cString: sqlite3_errmsg($0))
                    } ?? "unknown"
                    throw SearchIndexError.databaseOpenFailed(msg)
                }
                self.db = freshPtr
            } else {
                self.db = dbPtr
            }
        } else if FileManager.default.fileExists(atPath: databasePath) {
            Self.logger.warning("Failed to open DB at \(databasePath), recreating")
            if let dbPtr { sqlite3_close(dbPtr) }
            Self.deleteDBFiles(at: databasePath)
            var freshPtr: OpaquePointer?
            let freshRC = sqlite3_open(databasePath, &freshPtr)
            guard freshRC == SQLITE_OK, let freshPtr else {
                let msg = freshPtr.flatMap {
                    String(cString: sqlite3_errmsg($0))
                } ?? "unknown"
                throw SearchIndexError.databaseOpenFailed(msg)
            }
            self.db = freshPtr
        } else {
            let msg = dbPtr.flatMap {
                String(cString: sqlite3_errmsg($0))
            } ?? "unknown"
            throw SearchIndexError.databaseOpenFailed(msg)
        }
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    // MARK: - Corruption Recovery

    /// Checks if a database is corrupt via integrity_check pragma.
    private static func isCorrupt(db: OpaquePointer) -> Bool {
        var stmt: OpaquePointer?
        let sql = "PRAGMA integrity_check(1)"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              let stmt else {
            return true
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return true }
        guard let text = sqlite3_column_text(stmt, 0) else { return true }
        return String(cString: text).lowercased() != "ok"
    }

    /// Deletes a SQLite database file and its journal/WAL companions.
    private static func deleteDBFiles(at path: String) {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm", "-journal"] {
            try? fm.removeItem(atPath: path + suffix)
        }
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
