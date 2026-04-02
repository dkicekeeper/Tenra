//
//  CSVColumnMappingView.swift
//  AIFinanceManager
//
//  Created on 2024
//  Refactored: 2026-02-03 (Phase 4 - Props + Callbacks)
//

import SwiftUI

/// Column mapping configuration view for CSV import
/// Refactored to use Props + Callbacks pattern (no ViewModel dependencies)
struct CSVColumnMappingView: View {
    // MARK: - Props

    let csvFile: CSVFile
    let onComplete: (CSVColumnMapping) -> Void
    let onCancel: () -> Void

    // MARK: - State

    @State private var mapping = CSVColumnMapping()

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                requiredFieldsSection
                optionalFieldsSection
            }
            .navigationTitle(String(localized: "csvImport.mapping.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarContent
            }
        }
    }

    // MARK: - Sections

    private var requiredFieldsSection: some View {
        Section(header: Text(String(localized: "csvImport.mapping.required"))) {
            columnPicker(
                title: String(localized: "csvImport.mapping.date"),
                binding: bindingFor(\.dateColumn)
            )

            if mapping.dateColumn != nil {
                dateFormatPicker
            }

            columnPicker(
                title: String(localized: "csvImport.mapping.type"),
                binding: bindingFor(\.typeColumn)
            )

            columnPicker(
                title: String(localized: "csvImport.mapping.category"),
                binding: bindingFor(\.categoryColumn)
            )

            columnPicker(
                title: String(localized: "csvImport.mapping.account"),
                binding: bindingFor(\.accountColumn)
            )

            columnPicker(
                title: String(localized: "csvImport.mapping.currency"),
                binding: bindingFor(\.currencyColumn)
            )

            columnPicker(
                title: String(localized: "csvImport.mapping.amount"),
                binding: bindingFor(\.amountColumn)
            )
        }
    }

    private var optionalFieldsSection: some View {
        Section(header: Text(String(localized: "csvImport.mapping.optional"))) {
            columnPicker(
                title: String(localized: "csvImport.mapping.targetAccount"),
                binding: bindingFor(\.targetAccountColumn)
            )

            columnPicker(
                title: String(localized: "csvImport.mapping.targetCurrency"),
                binding: bindingFor(\.targetCurrencyColumn)
            )

            columnPicker(
                title: String(localized: "csvImport.mapping.targetAmount"),
                binding: bindingFor(\.targetAmountColumn)
            )

            columnPicker(
                title: String(localized: "csvImport.mapping.subcategories"),
                binding: bindingFor(\.subcategoriesColumn)
            )

            if mapping.subcategoriesColumn != nil {
                subcategoriesSeparatorPicker
            }

            columnPicker(
                title: String(localized: "csvImport.mapping.note"),
                binding: bindingFor(\.noteColumn)
            )
        }
    }

    // MARK: - Pickers

    private func columnPicker(
        title: String,
        binding: Binding<String?>
    ) -> some View {
        Picker(title, selection: Binding(
            get: { binding.wrappedValue ?? "" },
            set: { binding.wrappedValue = $0.isEmpty ? nil : $0 }
        )) {
            Text(String(localized: "csvImport.mapping.none")).tag("")
            ForEach(csvFile.headers, id: \.self) { header in
                Text(header).tag(header)
            }
        }
    }

    private var dateFormatPicker: some View {
        Picker(String(localized: "csvImport.mapping.dateFormat"), selection: $mapping.dateFormat) {
            ForEach(DateFormatType.allCases, id: \.self) { format in
                Text(format.rawValue).tag(format)
            }
        }
    }

    private var subcategoriesSeparatorPicker: some View {
        Picker(
            String(localized: "csvImport.mapping.subcategoriesSeparator"),
            selection: $mapping.subcategoriesSeparator
        ) {
            Text("; " + String(localized: "csvImport.mapping.separator.semicolon")).tag(";")
            Text(", " + String(localized: "csvImport.mapping.separator.comma")).tag(",")
            Text("| " + String(localized: "csvImport.mapping.separator.pipe")).tag("|")
        }
    }

    // MARK: - Toolbar

    private var toolbarContent: some ToolbarContent {
        Group {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark")
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    if canProceed {
                        onComplete(mapping)
                    }
                } label: {
                    Image(systemName: "arrow.right")
                }
                .glassProminentButton()
                .disabled(!canProceed)
            }
        }
    }

    // MARK: - Validation

    private var canProceed: Bool {
        mapping.dateColumn != nil &&
        mapping.typeColumn != nil &&
        mapping.amountColumn != nil
    }

    // MARK: - Helpers

    private func bindingFor(_ keyPath: WritableKeyPath<CSVColumnMapping, String?>) -> Binding<String?> {
        Binding(
            get: { mapping[keyPath: keyPath] },
            set: { mapping[keyPath: keyPath] = $0 }
        )
    }
}
