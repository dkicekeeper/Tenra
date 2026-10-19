//
//  StoreArtRenderTests.swift
//  TenraTests
//
//  Not a check: draws Ten's still pictures (DesignKit's `ParticleCreature.image`) for the App
//  Store's header and search art, which scripts/compose_store_art.py composes. Runs only when
//  STORE_ART_DIR names a folder on the host (Actions → Screenshots with `art`, passed as
//  TEST_RUNNER_STORE_ART_DIR); every other run passes at once.
//

import SwiftUI
import Testing
@testable import Tenra

@MainActor
struct StoreArtRenderTests {

    /// 600 pt at 4x: 2400 px, larger than Ten ever shows in the art.
    private static let side: CGFloat = 600
    private static let scale: CGFloat = 4

    private static let moods: [(name: String, mood: ParticleCreature.Mood)] = [
        ("idle", .idle), ("happy", .happy), ("love", .love), ("proud", .proud),
        ("celebrating", .celebrating), ("wink", .wink),
    ]

    @Test func drawsTenForTheStoreArt() throws {
        guard let folder = ProcessInfo.processInfo.environment["STORE_ART_DIR"], !folder.isEmpty else { return }
        let directory = URL(fileURLWithPath: folder, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, mood) in Self.moods {
            for (scheme, colorScheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
                let image = try #require(ParticleCreature.image(mood: mood, side: Self.side, colorScheme: colorScheme, scale: Self.scale))
                let data = try #require(image.pngData())
                try data.write(to: directory.appending(path: "ten-\(name)-\(scheme).png"))
            }
        }
    }
}
