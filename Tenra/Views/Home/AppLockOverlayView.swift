//
//  AppLockOverlayView.swift
//  Tenra
//
//  Full-screen cover for the optional app lock (AppLockService).
//
//  Hosted in its own UIWindow above `.alert` level by AppLockWindowPresenter:
//  sheets presented by MainTabView are UIKit presentations that sit above any
//  view in the root SwiftUI hierarchy, so only a separate window can cover them.
//

import SwiftUI
import UIKit

struct AppLockOverlayView: View {
    @State private var lock = AppLockService.shared

    var body: some View {
        ZStack {
            AppColors.bgBase.ignoresSafeArea()

            VStack(spacing: AppSpacing.lg) {
                Image(systemName: "lock.fill")
                    .font(.system(size: AppIconSize.xxl, weight: .semibold))
                    .foregroundStyle(AppColors.accent)

                Text("Tenra")
                    .font(AppTypography.h4)
                    .foregroundStyle(AppColors.textPrimary)

                if lock.isLocked {
                    Text(String(localized: "appLock.title"))
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)

                    Button {
                        Task { await lock.unlock() }
                    } label: {
                        Text(String(localized: "appLock.unlock"))
                            .frame(maxWidth: .infinity)
                    }
                    .primaryButton()
                    .padding(.top, AppSpacing.md)
                }
            }
            .screenPadding()
            .padding(.horizontal, AppSpacing.xxxl)
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - AppLockWindowPresenter

@MainActor
final class AppLockWindowPresenter {

    static let shared = AppLockWindowPresenter()

    private var window: UIWindow?

    func setVisible(_ visible: Bool) {
        guard visible else {
            window?.isHidden = true
            return
        }
        if window == nil {
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first else { return }
            let overlay = UIWindow(windowScene: scene)
            overlay.windowLevel = .alert + 1
            overlay.rootViewController = UIHostingController(rootView: AppLockOverlayView())
            window = overlay
        }
        // No makeKeyAndVisible(): it would take key status and keyboard focus
        // from the main window. Touches reach the topmost visible window anyway.
        window?.isHidden = false
    }
}

#Preview {
    AppLockOverlayView()
}
