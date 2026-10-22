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

    // MARK: - Onboarding

    @Test("Welcome with a backup in iCloud")
    func welcomeWithBackup() async throws {
        let vm = OnboardingViewModel.makeForTesting()
        vm.hasCloudBackup = true
        try await render("01-welcome-restore") {
            NavigationStack { OnboardingWelcomeStep(vm: vm) }
        }
    }

    @Test("Step 4: let Tenra log it for you")
    func autoCaptureStep() async throws {
        let vm = OnboardingViewModel.makeForTesting()
        try await render("02-onboarding-auto-capture") {
            NavigationStack { OnboardingAutoCaptureStep(vm: vm, showsBankNotifications: true) }
        }
        vm.afterFinish = .statement
        try await render("03-onboarding-auto-capture-statement") {
            NavigationStack { OnboardingAutoCaptureStep(vm: vm, showsBankNotifications: true) }
        }
    }

    // MARK: - Home

    @Test("Home: the history card, For today and the auto-capture card")
    func homeCards() async throws {
        try await render("04-home-cards") {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    TransactionsSummaryCard(
                        summary: Summary(
                            totalIncome: 450_000,
                            totalExpenses: 287_400,
                            totalInternalTransfers: 0,
                            netFlow: 162_600,
                            currency: "KZT",
                            startDate: "2026-10-01",
                            endDate: "2026-10-31",
                            plannedAmount: 23_990
                        ),
                        currency: "KZT",
                        isEmpty: false
                    )
                    DailyAllowanceCard(
                        amount: 8_400,
                        currency: "KZT",
                        until: Calendar.current.date(byAdding: .day, value: 6, to: Date()),
                        setAside: 23_990,
                        isLoading: false
                    )
                    AutoCaptureSetupCard(onSetUp: {}, onHide: {})
                }
                .screenPadding()
                .padding(.vertical, AppSpacing.lg)
            }
            .background(AppColors.Background.base)
        }
    }

    @Test("Home: the one-time iCloud ask for an older install")
    func homeICloudAsk() async throws {
        try await render("05-home-icloud-ask", height: 500) {
            VStack(spacing: AppSpacing.lg) {
                ICloudBackupAskCard(onTurnOn: {}, onHide: {})
                AutoCaptureSetupCard(onSetUp: {}, onHide: {})
                Spacer()
            }
            .screenPadding()
            .padding(.vertical, AppSpacing.xl)
            .background(AppColors.Background.base)
        }
    }

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
