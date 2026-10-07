//
//  StoreUnavailableView.swift
//  Tenra
//
//  Blocking screen shown instead of the app when the database can't be opened or loaded
//  (a failed migration, a full disk, an I/O error). It says what happened, that the data is
//  still on the device, and offers a retry and the support inbox. Nothing here reads or
//  writes the store: TenraApp builds no coordinator in this state, so no screen can save
//  over the data and no repository falls back to the legacy UserDefaults copy.
//

import SwiftUI

struct StoreUnavailableView: View {
    let failure: StoreLoadFailure
    let onRetry: () async -> Void

    @Environment(\.openURL) private var openURL
    @State private var isRetrying = false

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                Icon(
                    source: .sfSymbol("externaldrive.badge.exclamationmark"),
                    style: .circle(size: AppIconSize.Tile.xxxl, tint: .destructiveMonochrome)
                )
                .accessibilityHidden(true)

                VStack(spacing: AppSpacing.sm) {
                    Text(String(localized: "storeUnavailable.title"))
                        .font(AppTypography.h3)
                        .foregroundStyle(AppColors.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text(message)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                    Text(String(localized: "storeUnavailable.dataSafe"))
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(AppColors.textPrimary)
                }
                .multilineTextAlignment(.center)

                VStack(spacing: AppSpacing.md) {
                    DSButton(
                        String(localized: "button.retry"),
                        systemImage: "arrow.clockwise",
                        fullWidth: true,
                        isLoading: isRetrying
                    ) {
                        retry()
                    }

                    if let supportURL {
                        DSButton(
                            String(localized: "storeUnavailable.contactSupport"),
                            systemImage: "envelope",
                            appearance: .secondary,
                            fullWidth: true
                        ) {
                            openURL(supportURL)
                        }
                    }
                }

                Text(String(format: String(localized: "storeUnavailable.errorCode"), failure.reference))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, AppSpacing.xxl)
            .padding(.vertical, AppSpacing.xxxl)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(AppColors.bgBase.ignoresSafeArea())
    }

    private var message: String {
        switch failure.kind {
        case .migration: String(localized: "storeUnavailable.message.migration")
        case .diskFull:  String(localized: "storeUnavailable.message.diskFull")
        case .other:     String(localized: "storeUnavailable.message.other")
        }
    }

    /// The e-mail carries the error code and description, so support can tell the cases apart.
    private var supportURL: URL? {
        SupportContact.mailURL(
            subject: String(localized: "storeUnavailable.title"),
            details: "\(failure.reference): \(failure.details)"
        )
    }

    private func retry() {
        guard !isRetrying else { return }
        HapticManager.light()
        isRetrying = true
        Task {
            await onRetry()
            isRetrying = false
        }
    }
}

#Preview("Migration failed") {
    StoreUnavailableView(
        failure: StoreLoadFailure(
            kind: .migration,
            reference: "NSCocoaErrorDomain 134110",
            details: "The model used to open the store is incompatible with the one used to create the store."
        ),
        onRetry: {}
    )
}

#Preview("Disk full") {
    StoreUnavailableView(
        failure: StoreLoadFailure(kind: .diskFull, reference: "NSCocoaErrorDomain 640", details: "Out of space"),
        onRetry: {}
    )
}
