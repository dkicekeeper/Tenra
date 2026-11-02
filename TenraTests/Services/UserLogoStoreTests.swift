//
//  UserLogoStoreTests.swift
//  TenraTests
//
//  Pins the person's own logo pictures (UserLogoStore): a picture kept as a 512 px square
//  under a "photo:<uuid>" key reads back, and a key never names a path outside the folder.
//

import Testing
import UIKit
@testable import Tenra

struct UserLogoStoreTests {

    @Test("A picture is kept as a square and reads back by its key")
    func roundTrip() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let picture = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40), format: format).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        }
        let key = try #require(UserLogoStore.save(picture))
        defer { UserLogoStore.fileURL(forKey: key).map { try? FileManager.default.removeItem(at: $0) } }

        #expect(UserLogoStore.isPhotoKey(key))
        #expect(UserLogoStore.isPhoto(.brandService(key)))
        let read = try #require(UserLogoStore.image(forKey: key))
        #expect(read.size.width * read.scale == UserLogoStore.pixelSize)
    }

    @Test("Only a photo key with a UUID names a file")
    func keys() {
        #expect(UserLogoStore.fileURL(forKey: "netflix.com") == nil)
        #expect(UserLogoStore.fileURL(forKey: "photo:../Tenra.sqlite") == nil)
        #expect(UserLogoStore.fileURL(forKey: "photo:\(UUID().uuidString)") != nil)
        #expect(!UserLogoStore.isPhoto(.sfSymbol("star")))
        #expect(UserLogoStore.image(forKey: "photo:\(UUID().uuidString)") == nil)
    }
}
