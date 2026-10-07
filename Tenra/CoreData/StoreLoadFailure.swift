//
//  StoreLoadFailure.swift
//  Tenra
//
//  Why the database could not be opened (or read) at launch, as plain values. The blocking
//  error screen, the launch health check, the App Intents refusal and the tests use it
//  without touching Core Data.
//
//  Classification works on numeric error codes (Core Data's names in the comments), so this
//  file compiles without Core Data.
//

import Foundation

nonisolated struct StoreLoadFailure: Error, Equatable, Sendable {

    enum Kind: String, Equatable, Sendable {
        /// The store exists but could not be converted to this build's model, or was written by
        /// a newer build. Retrying rarely helps; an app update usually does.
        case migration
        /// The device ran out of space (SQLite needs room for its journal even to open).
        case diskFull
        /// Anything else: an I/O error, file protection while the device is locked, corruption.
        case other
    }

    let kind: Kind
    /// Domain and code, e.g. "NSCocoaErrorDomain 134110": the error code on the blocking screen
    /// and in the support e-mail.
    let reference: String
    /// The error's own description (English), for the log and the support e-mail only.
    let details: String

    init(kind: Kind, reference: String, details: String) {
        self.kind = kind
        self.reference = reference
        self.details = details
    }

    init(error: NSError) {
        var codes: [(domain: String, code: Int)] = []
        var current: NSError? = error
        // The chain is short; the cap only guards against a cyclic userInfo.
        while let next = current, codes.count < 8 {
            codes.append((next.domain, next.code))
            if let sqlite = (next.userInfo[Self.sqliteErrorKey] as? NSNumber)?.intValue {
                codes.append((Self.sqliteErrorKey, sqlite))
            }
            current = next.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        self.init(
            kind: Self.kind(codes: codes),
            reference: "\(error.domain) \(error.code)",
            details: error.localizedDescription
        )
    }

    /// The key Core Data uses for the SQLite result code, both as a userInfo key and as the
    /// domain of a wrapped SQLite error.
    static let sqliteErrorKey = "NSSQLiteErrorDomain"

    /// `codes` is the error followed by its underlying errors (and SQLite result codes).
    /// Running out of space anywhere in the chain wins: it is the one cause the user can fix.
    static func kind(codes: [(domain: String, code: Int)]) -> Kind {
        if codes.contains(where: isOutOfSpace) { return .diskFull }
        if let first = codes.first, isMigration(domain: first.domain, code: first.code) {
            return .migration
        }
        return .other
    }

    private static func isOutOfSpace(_ entry: (domain: String, code: Int)) -> Bool {
        switch entry.domain {
        case NSCocoaErrorDomain: return entry.code == 640     // NSFileWriteOutOfSpaceError
        case sqliteErrorKey:     return entry.code == 13      // SQLITE_FULL
        case NSPOSIXErrorDomain: return entry.code == 28      // ENOSPC
        default:                 return false
        }
    }

    private static func isMigration(domain: String, code: Int) -> Bool {
        guard domain == NSCocoaErrorDomain else { return false }
        switch code {
        case 134_020:              // NSPersistentStoreIncompatibleSchemaError
            return true
        case 134_180:              // NSSQLiteError: a SQLite failure, not a model mismatch
            return false
        case 134_100...134_190:    // NSPersistentStoreIncompatibleVersionHashError (134100),
                                   // NSMigrationError (134110) … NSInferredMappingModelError (134190)
            return true
        default:
            return false
        }
    }
}
