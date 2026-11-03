//
//  CSVImportResultView.swift
//  Tenra
//
//  Created on 2024
//  Refactored: 2026-02-03 (Phase 4 - ImportStatistics + Props + Callbacks)
//

import SwiftUI

/// Import result display with comprehensive statistics and performance metrics
/// Refactored to use ImportStatistics instead of ImportResult
struct CSVImportResultView: View {
    // MARK: - Props

    let statistics: ImportStatistics
    let onDone: () -> Void
    let onViewErrors: (() -> Void)?

    // MARK: - Environment

    @Environment(\.dismiss) var dismiss

    // MARK: - Body

    var body: some View {
        NavigationStack {
            // A scroll view: the sections' rows pad themselves 12 pt (DesignKit 8.6.0), and the
            // results with every count, the timing and the errors outgrow a small screen.
            ScrollView {
                VStack(spacing: AppSpacing.xxl) {
                    CSVImportSteps(current: CSVImportSteps.done)

                    // Persistence failure banner — shown above everything else
                    if let persistenceError = statistics.persistenceError {
                        StatusBanner(
                            String(localized: "csvImport.error.persistenceFailed") + " \(persistenceError)",
                            status: .negative
                        )
                    }

                    // Result icon
                    resultIcon

                    // Statistics section
                    statisticsSection

                    // Performance metrics section
                    performanceSection

                    // Errors section
                    if statistics.hasErrors {
                        errorsSection
                    }
                }
                .screenPadding()
            }
            // Done button, at the bottom of the screen as before
            .safeAreaInset(edge: .bottom) {
                doneButton
                    .screenPadding()
            }
            .navigationTitle(String(localized: "csvImport.result.title"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .softScrollEdges()
        .onAppear {
            if statistics.persistenceError != nil {
                HapticManager.error()
            } else if statistics.successRate > 0.8 {
                HapticManager.success()
            } else {
                HapticManager.warning()
            }
        }
    }

    // MARK: - Sections

    /// "Import finished": the symbol draws itself on a pale disc (DesignKit's HeroSymbol).
    private var resultIcon: some View {
        let succeeded = statistics.successRate > 0.8
        return HeroSymbol(
            systemImage: succeeded ? "checkmark" : "exclamationmark.triangle",
            size: AppIconSize.Tile.xl * 2,
            tint: succeeded ? AppColors.success : AppColors.warning
        )
    }

    /// The counts in `FormSection`s (DesignKit 8.6.0): what was imported, then what was created,
    /// each row padded 12 pt, the section's divider between them.
    private var statisticsSection: some View {
        VStack(spacing: AppSpacing.lg) {
            FormSection {
                StatRow(
                    label: String(format: String(localized: "csvImport.result.imported"), statistics.importedCount),
                    value: "",
                    color: AppColors.success,
                    icon: "checkmark.circle"
                )

                if statistics.duplicatesSkipped > 0 {
                    StatRow(
                        label: String(format: String(localized: "csvImport.result.duplicates"), statistics.duplicatesSkipped),
                        value: "",
                        color: .purple,
                        icon: "arrow.triangle.2.circlepath"
                    )
                }

                if statistics.skippedCount - statistics.duplicatesSkipped > 0 {
                    StatRow(
                        label: String(format: String(localized: "csvImport.result.skipped"), statistics.skippedCount - statistics.duplicatesSkipped),
                        value: "",
                        color: AppColors.warning,
                        icon: "exclamationmark.circle"
                    )
                }
            }

            if statistics.createdAccounts > 0 || statistics.createdCategories > 0 || statistics.createdSubcategories > 0 {
                FormSection {
                    if statistics.createdAccounts > 0 {
                        StatRow(
                            label: String(format: String(localized: "csvImport.result.createdAccounts"), statistics.createdAccounts),
                            value: "",
                            color: AppColors.accent,
                            icon: "plus.circle"
                        )
                    }

                    if statistics.createdCategories > 0 {
                        StatRow(
                            label: String(format: String(localized: "csvImport.result.createdCategories"), statistics.createdCategories),
                            value: "",
                            color: AppColors.accent,
                            icon: "plus.circle"
                        )
                    }

                    if statistics.createdSubcategories > 0 {
                        StatRow(
                            label: String(format: String(localized: "csvImport.result.createdSubcategories"), statistics.createdSubcategories),
                            value: "",
                            color: AppColors.accent,
                            icon: "plus.circle"
                        )
                    }
                }
            }
        }
    }

    /// The timing in a `FormSection` (DesignKit 8.6.0): the header 12 pt above, detail rows.
    private var performanceSection: some View {
        FormSection(header: String(localized: "csvImport.result.performance")) {
            UniversalRow(
                String(localized: "csvImport.result.duration"),
                config: .info,
                accessory: .info(String(format: "%.1fs", statistics.duration))
            )
            UniversalRow(
                String(localized: "csvImport.result.speed"),
                config: .info,
                accessory: .info(String(format: "%.0f rows/s", statistics.rowsPerSecond))
            )
            UniversalRow(config: .info) {
                InfoRowLayout(label: String(localized: "csvImport.result.successRate")) {
                    Text("\(statistics.successPercentage)%")
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(statistics.successRate > 0.8 ? AppColors.success : AppColors.warning)
                }
            }
        }
    }

    private var errorsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Text(String(localized: "csvImport.result.errors"))
                    .font(AppTypography.h4)

                Spacer()

                if let onViewErrors = onViewErrors {
                    Button(action: onViewErrors) {
                        Text(String(localized: "csvImport.button.viewErrors"))
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.accent)
                    }
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    ForEach(Array(statistics.errors.prefix(10).enumerated()), id: \.offset) { _, error in
                        Text("• \(error.localizedDescription)")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.destructive)
                    }

                    if statistics.validationErrorCount > 10 {
                        Text(String(
                            format: String(localized: "csvImport.result.moreErrors"),
                            statistics.validationErrorCount - 10
                        ))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
            .frame(maxHeight: 150)
        }
        .cardContentPadding()
        .background(AppColors.bgCard)
        .clipShape(.rect(cornerRadius: AppRadius.card))
    }

    private var doneButton: some View {
        Button(action: {
            onDone()
            dismiss()
        }) {
            Text(String(localized: "button.done"))
                .frame(maxWidth: .infinity)
                .padding(AppSpacing.md)
                .background(AppColors.accent)
                .foregroundStyle(.white)
                .clipShape(.rect(cornerRadius: AppRadius.button))
        }
        .cardContentPadding()
    }
}

// MARK: - StatRow Component

/// Reusable statistics row component
struct StatRow: View {
    let label: String
    let value: String
    let color: Color
    let icon: String?

    init(label: String, value: String, color: Color, icon: String? = nil) {
        self.label = label
        self.value = value
        self.color = color
        self.icon = icon
    }

    /// A row of a `FormSection`: it pads itself 12 pt and starts the divider at its text.
    var body: some View {
        HStack(spacing: AppSpacing.md) {
            if let icon = icon {
                Icon(icon, size: AppIconSize.md)
                    .foregroundStyle(color)
            }
            Text(label)
                .font(AppTypography.body)
            Spacer()
            Text(value)
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(color)
        }
        .padding(.vertical, AppSpacing.md)
        .rowDividerInset(icon == nil ? 0 : AppIconSize.md + AppSpacing.md)
    }
}
