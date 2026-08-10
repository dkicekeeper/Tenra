//
//  ImportDiagnosticsView.swift
//  Tenra
//
//  Makes skipped rows visible. The previous importer silently discarded any
//  row it could not parse, so a user could import 20 of 60 operations and
//  never find out. Everything the parser rejected is listed here with its
//  reason.
//

import SwiftUI

struct ImportDiagnosticsView: View {
    let statement: ParsedStatement
    let intelligenceStatus: IntelligenceStatus

    var body: some View {
        List {
            Section {
                LabeledContent(
                    String(localized: "import.diagnostics.recognized"),
                    value: "\(statement.transactions.count)"
                )
                LabeledContent(
                    String(localized: "import.diagnostics.skipped"),
                    value: "\(statement.skipped.count)"
                )
            }

            if let explanationKey = intelligenceStatus.explanationKey {
                Section {
                    Text(String(localized: String.LocalizationValue(explanationKey)))
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !statement.skipped.isEmpty {
                Section(String(localized: "import.diagnostics.skippedRows")) {
                    ForEach(statement.skipped, id: \.rowIndex) { row in
                        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                            Text(row.cells.filter { !$0.isEmpty }.joined(separator: "  "))
                                .font(AppTypography.caption)
                                .lineLimit(2)
                            Text(String(localized: String.LocalizationValue(row.reason)))
                                .font(AppTypography.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(String(localized: "import.diagnostics.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        ImportDiagnosticsView(
            statement: ParsedStatement(
                transactions: [],
                skipped: [
                    SkippedRow(rowIndex: 3, cells: ["12.05.2026", "", "Grocery"], reason: "import.skip.noAmount"),
                    SkippedRow(rowIndex: 7, cells: ["", "1200", "Coffee"], reason: "import.skip.noDate")
                ],
                resolvedRoles: nil
            ),
            intelligenceStatus: .notEnabled
        )
    }
}
