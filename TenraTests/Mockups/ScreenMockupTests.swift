//
//  ScreenMockupTests.swift
//  TenraTests
//
//  Renders screens to PNG for the owner to look at before a layout ships (CLAUDE.md, "To check
//  a layout you changed"). A UIWindow with a UIHostingController, drawn by `drawHierarchy`, so
//  glass, navigation bars and scroll views come out as on the phone (ImageRenderer leaves
//  UIKit-backed views out). Runs only where MOCKUP_DIR is set: Actions → Mockups
//  (`.github/workflows/mockups.yml`) sets it per language and uploads the folder. A screen's
//  mockup stays here while its layout is in review; drop it once approved.
//

import Testing
import SwiftUI
import UIKit
@testable import Tenra

@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["MOCKUP_DIR"] != nil), .serialized)
struct ScreenMockupTests {

    private var directory: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["MOCKUP_DIR"] ?? NSTemporaryDirectory())
    }

    // Nothing in review: the 1.7 screens (welcome with a backup, the auto-capture step, Home's
    // For today, auto-capture and iCloud cards) were approved on 2026-10-23 and ship in the app.
    // A new screen in review gets a `@Test` here that calls `render(_:height:_:)`.

    // MARK: - Rendering

    /// Draws `content` in an iPhone-sized window, in the light and the dark theme, into
    /// `<name>-light.png` and `<name>-dark.png`.
    private func render<Content: View>(
        _ name: String,
        height: CGFloat = 874,
        @ViewBuilder _ content: () -> Content
    ) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for style in [UIUserInterfaceStyle.light, .dark] {
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
            window.frame = CGRect(x: 0, y: 0, width: 402, height: height)
            window.overrideUserInterfaceStyle = style
            window.rootViewController = UIHostingController(rootView: content())
            window.isHidden = false
            // Lay out, load fonts and let entrance animations settle: polls, not a deadline
            // (CLAUDE.md, Testing).
            for _ in 0..<40 { try await Task.sleep(for: .milliseconds(50)) }
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let file = directory.appendingPathComponent("\(name)-\(style == .dark ? "dark" : "light").png")
            try #require(image.pngData()).write(to: file)
            window.isHidden = true
            window.rootViewController = nil
        }
    }
}
