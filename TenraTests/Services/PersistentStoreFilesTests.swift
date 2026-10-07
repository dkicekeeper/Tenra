//
//  PersistentStoreFilesTests.swift
//  TenraTests
//
//  The file-level steps of backup and restore, on plain SQLite databases in temporary
//  directories: SQLite's page check refuses damaged files, a staged copy keeps the saves
//  that live only in a -wal, and a failed swap puts the previous store back bit for bit.
//

import Testing
import Foundation
import SQLite3
@testable import Tenra

struct PersistentStoreFilesTests {

    private struct OpenFailed: Error {}

    // MARK: - Fixtures

    private func makeDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StoreFilesTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func execute(_ database: OpaquePointer?, _ sql: String) {
        let result = sqlite3_exec(database, sql, nil, nil, nil)
        #expect(result == SQLITE_OK, "\(sql)")
    }

    /// A WAL-mode database with `rows` rows, closed (so its WAL is folded in).
    private func makeDatabase(at url: URL, rows: Int) {
        var database: OpaquePointer?
        sqlite3_open(url.path, &database)
        execute(database, "PRAGMA journal_mode=WAL")
        execute(database, "CREATE TABLE t(id INTEGER PRIMARY KEY, v TEXT)")
        execute(database, "CREATE INDEX t_v ON t(v)")
        execute(database, "BEGIN")
        for i in 0..<rows {
            execute(database, "INSERT INTO t(v) VALUES ('row \(i) \(String(repeating: "x", count: 200))')")
        }
        execute(database, "COMMIT")
        sqlite3_close(database)
    }

    private func rowCount(at url: URL) -> Int {
        var database: OpaquePointer?
        defer { sqlite3_close(database) }
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else { return -1 }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, "SELECT COUNT(*) FROM t", -1, &statement, nil) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW else { return -1 }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func fails(_ body: () throws -> Void) -> Bool {
        do { try body(); return false } catch { return true }
    }

    // MARK: - Integrity

    @Test func soundDatabasePassesTheIntegrityCheck() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Tenra.sqlite")
        makeDatabase(at: url, rows: 300)

        #expect(!fails { try PersistentStoreFiles.checkIntegrity(ofDatabaseAt: url) })
    }

    @Test func garbageAndTruncatedFilesFailTheIntegrityCheck() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let garbage = dir.appendingPathComponent("garbage.sqlite")
        try Data(repeating: 0xFF, count: 4096).write(to: garbage)
        #expect(fails { try PersistentStoreFiles.checkIntegrity(ofDatabaseAt: garbage) })

        let truncated = dir.appendingPathComponent("Tenra.sqlite")
        makeDatabase(at: truncated, rows: 300)
        let size = PersistentStoreFiles.fileSize(of: truncated)
        let handle = try FileHandle(forWritingTo: truncated)
        try handle.truncate(atOffset: UInt64(size / 2))
        try handle.close()
        #expect(fails { try PersistentStoreFiles.checkIntegrity(ofDatabaseAt: truncated) })
    }

    // MARK: - Copy

    @Test func stagedCopyKeepsTheSavesOnlyInTheWAL() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fm = FileManager.default

        // A backup in the pre-2026-10 format: the three files copied while the store was
        // open, the rows still only in the -wal.
        let liveDir = dir.appendingPathComponent("live", isDirectory: true)
        let backupDir = dir.appendingPathComponent("backup", isDirectory: true)
        try fm.createDirectory(at: liveDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
        let live = liveDir.appendingPathComponent("Tenra.sqlite")
        var database: OpaquePointer?
        sqlite3_open(live.path, &database)
        execute(database, "PRAGMA journal_mode=WAL")
        execute(database, "PRAGMA wal_autocheckpoint=0")
        execute(database, "CREATE TABLE t(id INTEGER PRIMARY KEY, v TEXT)")
        for i in 0..<50 { execute(database, "INSERT INTO t(v) VALUES ('wal row \(i)')") }
        for file in PersistentStoreFiles.allFileURLs(ofStore: live) {
            try fm.copyItem(at: file, to: backupDir.appendingPathComponent(file.lastPathComponent))
        }
        sqlite3_close(database)
        let backup = backupDir.appendingPathComponent("Tenra.sqlite")
        let backupWAL = PersistentStoreFiles.walURL(ofStore: backup)
        let walSize = PersistentStoreFiles.fileSize(of: backupWAL)
        #expect(walSize > 0)

        let staged = try PersistentStoreFiles.copyStore(at: backup, into: dir.appendingPathComponent("staged"))
        #expect(fm.fileExists(atPath: PersistentStoreFiles.walURL(ofStore: staged).path))
        #expect(!fm.fileExists(atPath: PersistentStoreFiles.shmURL(ofStore: staged).path))
        #expect(!fails { try PersistentStoreFiles.checkIntegrity(ofDatabaseAt: staged) })
        #expect(rowCount(at: staged) == 50)
        // The backup itself is never written to.
        #expect(PersistentStoreFiles.fileSize(of: backupWAL) == walSize)
    }

    @Test func copyOfAMissingStoreThrows() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let missing = dir.appendingPathComponent("missing/Tenra.sqlite")
        #expect(fails { try PersistentStoreFiles.copyStore(at: missing, into: dir.appendingPathComponent("out")) })
    }

    // MARK: - Swap

    /// A live store with all three files, and a staged one with a different row count.
    private func makeSwapFixture(in dir: URL) throws -> (live: URL, staged: URL, aside: URL) {
        let fm = FileManager.default
        let liveDir = dir.appendingPathComponent("live", isDirectory: true)
        let stagedDir = dir.appendingPathComponent("work/staged", isDirectory: true)
        try fm.createDirectory(at: liveDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: stagedDir, withIntermediateDirectories: true)
        let live = liveDir.appendingPathComponent("Tenra.sqlite")
        makeDatabase(at: live, rows: 10)
        try Data().write(to: PersistentStoreFiles.walURL(ofStore: live))
        try Data(repeating: 1, count: 32_768).write(to: PersistentStoreFiles.shmURL(ofStore: live))
        let staged = stagedDir.appendingPathComponent("Tenra.sqlite")
        makeDatabase(at: staged, rows: 20)
        return (live, staged, dir.appendingPathComponent("work/previous", isDirectory: true))
    }

    @Test func swapPutsTheStagedStoreInPlace() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (live, staged, aside) = try makeSwapFixture(in: dir)

        var opened: [URL] = []
        try PersistentStoreFiles.swapStoreFiles(live: live, staged: staged, asideDirectory: aside) {
            opened.append($0)
        }

        #expect(opened == [live])
        #expect(rowCount(at: live) == 20)
        #expect(!FileManager.default.fileExists(atPath: aside.path))
    }

    @Test func failedOpenPutsThePreviousStoreBackBitForBit() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (live, staged, aside) = try makeSwapFixture(in: dir)
        let previous = try Data(contentsOf: live)
        let previousSHM = try Data(contentsOf: PersistentStoreFiles.shmURL(ofStore: live))

        var opens = 0
        do {
            try PersistentStoreFiles.swapStoreFiles(live: live, staged: staged, asideDirectory: aside) { url in
                opens += 1
                if opens == 1 {
                    // What a failed open can leave behind.
                    try Data(repeating: 9, count: 100).write(to: PersistentStoreFiles.walURL(ofStore: url))
                    throw OpenFailed()
                }
            }
            Issue.record("the swap should have thrown")
        } catch let error as PersistentStoreFiles.SwapError {
            guard case .swapFailed = error else {
                Issue.record("expected swapFailed, got \(error)")
                return
            }
        }

        #expect(opens == 2, "the previous store is reopened")
        #expect(try Data(contentsOf: live) == previous)
        #expect(try Data(contentsOf: PersistentStoreFiles.shmURL(ofStore: live)) == previousSHM)
        #expect(PersistentStoreFiles.fileSize(of: PersistentStoreFiles.walURL(ofStore: live)) == 0)
        #expect(!FileManager.default.fileExists(atPath: aside.path))
    }

    @Test func failedRollbackKeepsTheAsideDirectory() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (live, staged, aside) = try makeSwapFixture(in: dir)

        do {
            try PersistentStoreFiles.swapStoreFiles(live: live, staged: staged, asideDirectory: aside) { _ in
                throw OpenFailed()
            }
            Issue.record("the swap should have thrown")
        } catch let error as PersistentStoreFiles.SwapError {
            guard case .rollbackFailed(_, _, let preservedAt) = error else {
                Issue.record("expected rollbackFailed, got \(error)")
                return
            }
            #expect(preservedAt == aside)
        }

        #expect(FileManager.default.fileExists(atPath: aside.path))
        #expect(rowCount(at: live) == 10, "the previous files are back at the live location")
    }
}
