//
//  StoreLoadFailureTests.swift
//  TenraTests
//
//  Pins how a store-loading error is classified for the blocking error screen: a failed
//  migration, a full disk (anywhere in the error chain), or anything else.
//

import Foundation
import Testing
@testable import Tenra

struct StoreLoadFailureTests {

    private func kind(_ error: NSError) -> StoreLoadFailure.Kind {
        StoreLoadFailure(error: error).kind
    }

    @Test("Core Data migration errors are migrations", arguments: [134_020, 134_100, 134_110, 134_130, 134_140, 134_190])
    func migrationCodes(code: Int) {
        #expect(kind(NSError(domain: NSCocoaErrorDomain, code: code)) == .migration)
    }

    @Test("A SQLite failure (134180) is not a migration")
    func sqliteErrorIsOther() {
        #expect(kind(NSError(domain: NSCocoaErrorDomain, code: 134_180)) == .other)
    }

    @Test("SQLITE_FULL in the userInfo means the disk is full")
    func sqliteFullInUserInfo() {
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: 134_180,
            userInfo: [StoreLoadFailure.sqliteErrorKey: NSNumber(value: 13)]
        )
        #expect(kind(error) == .diskFull)
    }

    @Test("Running out of space in an underlying error wins over a migration code")
    func underlyingOutOfSpace() {
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: 134_110,
            userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: 28)]
        )
        #expect(kind(error) == .diskFull)
    }

    @Test("NSFileWriteOutOfSpaceError means the disk is full")
    func fileWriteOutOfSpace() {
        #expect(kind(NSError(domain: NSCocoaErrorDomain, code: 640)) == .diskFull)
    }

    @Test("Other errors, and migration codes from another domain, are other")
    func otherErrors() {
        #expect(kind(NSError(domain: NSCocoaErrorDomain, code: 256)) == .other)
        #expect(kind(NSError(domain: "SomeDomain", code: 134_110)) == .other)
    }

    @Test("The reference is the domain and code, for the screen and the support e-mail")
    func reference() {
        let failure = StoreLoadFailure(error: NSError(domain: NSCocoaErrorDomain, code: 134_110))
        #expect(failure.reference == "NSCocoaErrorDomain 134110")
    }
}
