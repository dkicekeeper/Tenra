//
//  DiagnosticsView.swift
//  Tenra
//
//  Settings → About → Diagnostics: the launch health check (database, saved settings, the
//  App Store's products) and the crash and performance reports MetricKit delivered, with a
//  share button for both. The owner's window into failures that would otherwise stay silent;
//  nothing leaves the device unless the user shares it.
//

import SwiftUI

struct DiagnosticsView: View {
    private let center = DiagnosticsCenter.shared

    @State private var payloads: [DiagnosticPayloadSummary] = []
    @State private var shareItems: [URL] = []

    var body: some View {
        List {
            launchCheckSection
            reportsSection
            Section {
                ShareLink(items: shareItems) {
                    UniversalRow(
                        config: .settings,
                        leadingIcon: .sfSymbol("square.and.arrow.up", color: AppColors.accent, size: AppIconSize.md)
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
        Section {
            if let report = center.lastReport {
                ForEach(report.results) { result in
                    checkRow(result)
                }
            } else {
                UniversalRow(config: .settings) {
                    Text(String(localized: "diagnostics.checking"))
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                } trailing: {
                    ProgressView()
                }
            }
            ActionSettingsRow(
                icon: "arrow.clockwise",
                title: String(localized: "diagnostics.runAgain"),
                action: { Task { await center.runHealthCheck() } }
            )
            .disabled(center.isChecking)
        } header: {
            SectionHeader(String(localized: "diagnostics.launchCheck.header"), style: .list)
        } footer: {
            if let report = center.lastReport {
                Text(String(
                    format: String(localized: "diagnostics.launchCheck.footer"),
                    report.finishedAt.formatted(date: .abbreviated, time: .shortened)
                ))
            }
        }
    }

    private func checkRow(_ result: LaunchHealthCheck.Result) -> some View {
        UniversalRow(
            config: .settings,
            leadingIcon: .sfSymbol(icon(for: result.item), color: AppColors.accent, size: AppIconSize.md)
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
            Image(systemName: "checkmark.circle.fill")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.success)
                .accessibilityLabel(String(localized: "diagnostics.status.passed"))
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.destructive)
                .accessibilityLabel(String(localized: "diagnostics.status.failed"))
        case .skipped:
            Image(systemName: "minus.circle")
                .font(AppTypography.body)
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
        Section {
            if payloads.isEmpty {
                Text(String(localized: "diagnostics.reports.empty"))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
            } else {
                ForEach(payloads) { payload in
                    UniversalRow(
                        config: .settings,
                        leadingIcon: .sfSymbol(
                            payload.counts.crashes > 0 ? "exclamationmark.octagon" : "doc.text",
                            color: payload.counts.crashes > 0 ? AppColors.destructive : AppColors.accent,
                            size: AppIconSize.md
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
        } header: {
            SectionHeader(String(localized: "diagnostics.reports.header"), style: .list)
        } footer: {
            Text(String(localized: "diagnostics.reports.footer"))
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
