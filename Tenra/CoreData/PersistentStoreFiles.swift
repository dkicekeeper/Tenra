//
//  PersistentStoreFiles.swift
//  Tenra
//
//  File-level steps of backup and restore, free of Core Data so they can be tested
//  on their own. A Core Data SQLite store is up to three files: `Tenra.sqlite`,
//  `Tenra.sqlite-wal` (recent saves SQLite has not folded into the main file yet)
//  and `Tenra.sqlite-shm` (an index SQLite rebuilds from the -wal, never worth
//  copying). Only a store nothing has open may be copied or moved file by file; the
//  live store is copied through Core Data (CoreDataStack+Backup.swift).
//

import Foundation
import SQLite3

nonisolated enum PersistentStoreFiles {

    enum StoreFileError: LocalizedError {
        /// SQLite's page check found damage, e.g. a truncated file whose header still reads.
        case integrityCheckFailed(String)
        /// A copied file doesn't have the size of its source.
        case incompleteCopy(file: String, expected: Int64, actual: Int64)

        var errorDescription: String? {
            switch self {
            case .integrityCheckFailed(let report):
                return "SQLite integrity check: \(report)"
            case .incompleteCopy(let file, let expected, let actual):
                return "\(file): \(actual) of \(expected) bytes copied"
            }
        }
    }

    enum SwapError: LocalizedError {
        /// Moving the new files in, or opening them, failed. The previous store is back in
        /// place and open.
        case swapFailed(Error)
        /// Putting the previous store back failed too. Whatever of its files could not be
        /// moved back is still in `preservedAt`.
        case rollbackFailed(swapError: Error, rollbackError: Error, preservedAt: URL)

        var errorDescription: String? {
            switch self {
            case .swapFailed(let error):
                return error.localizedDescription
            case .rollbackFailed(let swapError, let rollbackError, _):
                return "\(swapError.localizedDescription) (\(rollbackError.localizedDescription))"
            }
        }
    }

    // MARK: - Store files

    static func walURL(ofStore storeURL: URL) -> URL {
        URL(fileURLWithPath: storeURL.path + "-wal")
    }

    static func shmURL(ofStore storeURL: URL) -> URL {
        URL(fileURLWithPath: storeURL.path + "-shm")
    }

    /// The main file and both SQLite companions, whether or not they exist.
    static func allFileURLs(ofStore storeURL: URL) -> [URL] {
        [storeURL, walURL(ofStore: storeURL), shmURL(ofStore: storeURL)]
    }

    /// The files that hold the store's data: the main file, plus the -wal when it isn't empty.
    static func contentFileURLs(ofStore storeURL: URL) -> [URL] {
        let wal = walURL(ofStore: storeURL)
        return fileSize(of: wal) > 0 ? [storeURL, wal] : [storeURL]
    }

    /// Bytes in the store's content files.
    static func contentSize(ofStore storeURL: URL) -> Int64 {
        contentFileURLs(ofStore: storeURL).reduce(0) { $0 + fileSize(of: $1) }
    }

    /// Size of a file in bytes, 0 when it doesn't exist.
    static func fileSize(of url: URL) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else { return 0 }
        return size.int64Value
    }

    // MARK: - Copy

    /// Copies a store that nothing has open (its main file, and its -wal when that holds
    /// anything) into `directory`, created if needed, and returns the copy's main file.
    /// Every copied file must come out the size of its source. The -shm is never copied.
    @discardableResult
    static func copyStore(at storeURL: URL, into directory: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        for source in contentFileURLs(ofStore: storeURL) {
            let destination = directory.appendingPathComponent(source.lastPathComponent)
            try fm.copyItem(at: source, to: destination)
            let expected = fileSize(of: source)
            let actual = fileSize(of: destination)
            guard actual == expected else {
                throw StoreFileError.incompleteCopy(
                    file: source.lastPathComponent, expected: expected, actual: actual
                )
            }
        }
        return directory.appendingPathComponent(storeURL.lastPathComponent)
    }

    // MARK: - Integrity

    /// Runs SQLite's page check (`PRAGMA quick_check`) on a database file nothing else has
    /// open. A truncated or damaged file can still have a readable header and even open in
    /// Core Data; this reads every page. The connection is read-write, so a -wal next to the
    /// file is folded into it when the check ends: run it on a copy, never on a backup.
    /// A zero-byte file passes (SQLite reads it as an empty database): callers check that
    /// the file is a Core Data store first.
    static func checkIntegrity(ofDatabaseAt url: URL) throws {
        var database: OpaquePointer?
        defer { sqlite3_close(database) }
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            throw StoreFileError.integrityCheckFailed(errorMessage(of: database))
        }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, "PRAGMA quick_check", -1, &statement, nil) == SQLITE_OK else {
            throw StoreFileError.integrityCheckFailed(errorMessage(of: database))
        }
        var report: [String] = []
        var step = sqlite3_step(statement)
        while step == SQLITE_ROW {
            if let text = sqlite3_column_text(statement, 0) {
                report.append(String(cString: text))
            }
            step = sqlite3_step(statement)
        }
        guard step == SQLITE_DONE else {
            throw StoreFileError.integrityCheckFailed(errorMessage(of: database))
        }
        guard report == ["ok"] else {
            throw StoreFileError.integrityCheckFailed(report.joined(separator: "; "))
        }
    }

    private static func errorMessage(of database: OpaquePointer?) -> String {
        guard let database, let message = sqlite3_errmsg(database) else {
            return "SQLite could not open the file"
        }
        return String(cString: message)
    }

    // MARK: - Swap

    /// Puts a staged store in place of a live one that is closed (removed from its
    /// coordinator). The live files are moved into `asideDirectory` first and stay there
    /// until `addStore` has opened the new ones. When a move or `addStore` fails, the new
    /// files are removed, the live ones go back and `addStore` reopens them. Moving, not
    /// copying, keeps the previous store bit for bit and costs a rename on the same volume.
    ///
    /// `asideDirectory` is removed at the end, except after `SwapError.rollbackFailed`:
    /// then it may hold the only copy of the previous store.
    static func swapStoreFiles(
        live liveStoreURL: URL,
        staged stagedStoreURL: URL,
        asideDirectory: URL,
        addStore: (URL) throws -> Void
    ) throws {
        let fm = FileManager.default
        var movedAside: [(original: URL, aside: URL)] = []
        var liveLocationHoldsNewFiles = false
        do {
            try fm.createDirectory(at: asideDirectory, withIntermediateDirectories: true)
            for original in allFileURLs(ofStore: liveStoreURL) where fm.fileExists(atPath: original.path) {
                let aside = asideDirectory.appendingPathComponent(original.lastPathComponent)
                try fm.moveItem(at: original, to: aside)
                movedAside.append((original, aside))
            }
            // From here on everything at the live location belongs to the new store.
            liveLocationHoldsNewFiles = true
            let stagedWAL = walURL(ofStore: stagedStoreURL)
            let movesWAL = contentFileURLs(ofStore: stagedStoreURL).contains(stagedWAL)
            try fm.moveItem(at: stagedStoreURL, to: liveStoreURL)
            if movesWAL {
                try fm.moveItem(at: stagedWAL, to: walURL(ofStore: liveStoreURL))
            }
            try addStore(liveStoreURL)
        } catch {
            do {
                if liveLocationHoldsNewFiles {
                    for url in allFileURLs(ofStore: liveStoreURL) where fm.fileExists(atPath: url.path) {
                        try fm.removeItem(at: url)
                    }
                }
                for (original, aside) in movedAside.reversed() {
                    try fm.moveItem(at: aside, to: original)
                }
                try addStore(liveStoreURL)
            } catch let rollbackError {
                throw SwapError.rollbackFailed(
                    swapError: error, rollbackError: rollbackError, preservedAt: asideDirectory
                )
            }
            try? fm.removeItem(at: asideDirectory)
            throw SwapError.swapFailed(error)
        }
        try? fm.removeItem(at: asideDirectory)
    }
}
