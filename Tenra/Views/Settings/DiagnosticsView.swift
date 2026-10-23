//
//  DiagnosticsView.swift
//  Tenra
//
//  Settings → About → Diagnostics: the launch health check (database, saved settings, the
//  App Store's products), what the Wallet and bank notification automations recorded, and the
//  crash and performance reports MetricKit delivered, with a share button for the check and the
//  reports. The owner's window into failures that would otherwise stay silent;
//  nothing leaves the device unless the user shares it.
//

import SwiftUI

struct DiagnosticsView: View {
    private let center = DiagnosticsCenter.shared

    @State private var payloads: [DiagnosticPayloadSummary] = []
    @State private var shareItems: [URL] = []

    var body: some View {
        // DesignKit 8.0.0: glass sections on the page (a List before).
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                launchCheckSection
                captureSection
                reportsSection
                FormSection {
                    ShareLink(items: shareItems) {
                        UniversalRow(
                            leadingIcon: .sfSymbol("square.and.arrow.up", color: AppColors.accent, size: AppIconSize.lg)
                        ) {
                            Text(String(localized: "diagnostics.share"))
                                .font(AppTypography.body)
                                .foregroundStyle(AppColors.textPrimary)
                        } trailing: {
                            EmptyView()
                        }
                    }
                    .disabled(shareItems.isEmpty)
                }
            }
            .screenPadding()
            .padding(.vertical, AppSpacing.md)
        }
        .navigationTitle(String(localized: "settings.diagnostics"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: center.lastReport?.finishedAt) {
            if center.lastReport == nil {
                // Opened before the launch check ran (or it was skipped): run it now; the
                // task restarts with its result.
                await center.runHealthCheck()
                return
            }
            payloads = await center.payloadSummaries()
            shareItems = await center.prepareShareItems(payloads: payloads)
        }
    }

    // MARK: - Launch check

    private var launchCheckSection: some View {
        FormSection(
            header: String(localized: "diagnostics.launchCheck.header"),
            footer: center.lastReport.map { report in
                String(
                    format: String(localized: "diagnostics.launchCheck.footer"),
                    report.finishedAt.formatted(date: .abbreviated, time: .shortened)
                )
            }
        ) {
            if let report = center.lastReport {
                ForEach(report.results) { result in
                    checkRow(result)
                }
            } else {
                UniversalRow {
                    Text(String(localized: "diagnostics.checking"))
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                } trailing: {
                    ProgressView()
                }
            }
            UniversalRow(
                String(localized: "diagnostics.runAgain"),
                icon: "arrow.clockwise",
                accessory: .action({ Task { await center.runHealthCheck() } })
            )
            .disabled(center.isChecking)
        }
    }

    // MARK: - Automatic capture

    /// Whether people keep the automations on: payments each one recorded lately, read from
    /// `WalletCaptureStore` (its 90 days of captures). Local, like the rest of this screen.
    private var captureSection: some View {
        let activity = WalletCaptureStore.shared.activity()
        return FormSection(
            header: String(localized: "diagnostics.capture.header"),
            footer: String(localized: "diagnostics.capture.footer")
        ) {
            UniversalRow(
                String(localized: "diagnostics.capture.applePay"),
                icon: "wave.3.right",
                config: .info,
                accessory: .info(counts(activity.applePayLast7Days, activity.applePayLast30Days))
            )
            UniversalRow(
                String(localized: "diagnostics.capture.notifications"),
                icon: "bell.badge",
                config: .info,
                accessory: .info(counts(activity.notificationsLast7Days, activity.notificationsLast30Days))
            )
            UniversalRow(
                String(localized: "walletReview.title"),
                icon: "checklist",
                config: .info,
                accessory: .info("\(activity.toReview)")
            )
            if activity.pending > 0 {
                UniversalRow(
                    String(localized: "diagnostics.capture.pending"),
                    icon: "hourglass",
                    config: .info,
                    accessory: .info("\(activity.pending)")
                )
            }
            UniversalRow(
                String(localized: "diagnostics.capture.last"),
                icon: "clock",
                config: .info,
                accessory: .info(
                    activity.lastCaptureAt?.formatted(date: .abbreviated, time: .shortened)
                        ?? String(localized: "diagnostics.capture.never")
                )
            )
        }
    }

    private func counts(_ week: Int, _ month: Int) -> String {
        String(format: String(localized: "diagnostics.capture.counts"), week, month)
    }

    private func checkRow(_ result: LaunchHealthCheck.Result) -> some View {
        UniversalRow(
            leadingIcon: .sfSymbol(icon(for: result.item), color: AppColors.accent, size: AppIconSize.lg)
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(title(for: result.item))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
                if let detail = detail(for: result.finding) {
                    Text(detail)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        } trailing: {
            statusIcon(result.status)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func statusIcon(_ status: LaunchHealthCheck.Status) -> some View {
        switch status {
        case .passed:
            Icon("checkmark.circle.fill", size: AppIconSize.md)
                .foregroundStyle(AppColors.success)
                .accessibilityLabel(String(localized: "diagnostics.status.passed"))
        case .failed:
            Icon("exclamationmark.triangle.fill", size: AppIconSize.md)
                .foregroundStyle(AppColors.destructive)
                .accessibilityLabel(String(localized: "diagnostics.status.failed"))
        case .skipped:
            Icon("minus.circle", size: AppIconSize.md)
                .foregroundStyle(AppColors.textSecondary)
                .accessibilityLabel(String(localized: "diagnostics.status.skipped"))
        }
    }

    private func icon(for item: LaunchHealthCheck.Item) -> String {
        switch item {
        case .database:  "internaldrive"
        case .settings:  "gearshape"
        case .purchases: "crown"
        }
    }

    private func title(for item: LaunchHealthCheck.Item) -> String {
        switch item {
        case .database:  String(localized: "diagnostics.check.database")
        case .settings:  String(localized: "diagnostics.check.settings")
        case .purchases: String(localized: "diagnostics.check.purchases")
        }
    }

    /// A line under failed (and skipped) checks; the technical code goes in brackets.
    private func detail(for finding: LaunchHealthCheck.Finding) -> String? {
        switch finding {
        case .databaseOpen, .settingsDecoded, .settingsNotSaved, .purchasesAvailable:
            return nil
        case .databaseUnavailable(let reference), .databaseUnreadable(let reference):
            return withReference(String(localized: "diagnostics.detail.database"), reference)
        case .settingsUnreadable(let reference):
            return withReference(String(localized: "diagnostics.detail.settings"), reference)
        case .purchasesNotConfigured:
            return String(localized: "diagnostics.detail.notConfigured")
        case .purchasesNothingToSell(let reference):
            return withReference(String(localized: "diagnostics.detail.nothingToSell"), reference)
        case .purchasesOffline:
            return String(localized: "diagnostics.detail.offline")
        case .purchasesFailed(let reference):
            return withReference(String(localized: "diagnostics.detail.purchasesFailed"), reference)
        }
    }

    private func withReference(_ text: String, _ reference: String?) -> String {
        guard let reference else { return text }
        return "\(text) (\(reference))"
    }

    // MARK: - MetricKit reports

    private var reportsSection: some View {
        FormSection(header: String(localized: "diagnostics.reports.header"), footer: String(localized: "diagnostics.reports.footer")) {
            if payloads.isEmpty {
                Text(String(localized: "diagnostics.reports.empty"))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.vertical, AppSpacing.lg)
            } else {
                ForEach(payloads) { payload in
                    UniversalRow(
                        leadingIcon: .sfSymbol(
                            payload.counts.crashes > 0 ? "exclamationmark.octagon" : "doc.text",
                            color: payload.counts.crashes > 0 ? AppColors.destructive : AppColors.accent,
                            size: AppIconSize.lg
                        )
                    ) {
                        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                            Text(payload.periodEnd.formatted(date: .abbreviated, time: .shortened))
                                .font(AppTypography.body)
                                .foregroundStyle(AppColors.textPrimary)
                            Text(countsLine(payload.counts))
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    } trailing: {
                        EmptyView()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    /// "Crashes: 1 · Hangs: 2", only the kinds present (all of them when every count is zero).
    private func countsLine(_ counts: DiagnosticPayloadSummary.Counts) -> String {
        let parts: [(Int, String.LocalizationValue)] = [
            (counts.crashes, "diagnostics.report.crashes"),
            (counts.hangs, "diagnostics.report.hangs"),
            (counts.diskWrites, "diagnostics.report.diskWrites"),
            (counts.cpuExceptions, "diagnostics.report.cpuExceptions"),
            (counts.slowLaunches, "diagnostics.report.slowLaunches"),
        ]
        let present = parts.filter { $0.0 > 0 }
        return (present.isEmpty ? parts : present)
            .map { String(format: String(localized: $0.1), $0.0) }
            .joined(separator: " · ")
    }
}

#Preview {
    NavigationStack {
        DiagnosticsView()
    }
}
