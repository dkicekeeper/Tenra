//
//  CSVColumnMappingView.swift
//  Tenra
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
            // DesignKit 8.0.0: glass sections on the page (a Form before).
            ScrollView {
                VStack(spacing: AppSpacing.xl) {
                    CSVImportSteps(current: CSVImportSteps.columns)
                    requiredFieldsSection
                    optionalFieldsSection
                }
                .screenPadding()
                .padding(.vertical, AppSpacing.md)
            }
            .navigationTitle(String(localized: "csvImport.mapping.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarContent
            }
        }
        .softScrollEdges()
    }

    // MARK: - Sections

    private var requiredFieldsSection: some View {
        FormSection(header: String(localized: "csvImport.mapping.required")) {
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
        FormSection(header: String(localized: "csvImport.mapping.optional")) {
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
                title: String(localized: "csvImport.mapping.convertedAmount"),
                binding: bindingFor(\.convertedAmountColumn)
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
        UniversalRow(
            title,
            accessory: .menu(
                Binding(
                    get: { binding.wrappedValue ?? "" },
                    set: { binding.wrappedValue = $0.isEmpty ? nil : $0 }
                ),
                options: [(label: String(localized: "csvImport.mapping.none"), value: "")]
                    + csvFile.headers.map { (label: $0, value: $0) }
            )
        )
    }

    private var dateFormatPicker: some View {
        UniversalRow(
            String(localized: "csvImport.mapping.dateFormat"),
            accessory: .menu(
                $mapping.dateFormat,
                options: DateFormatType.allCases.map { (label: $0.rawValue, value: $0) }
            )
        )
    }

    private var subcategoriesSeparatorPicker: some View {
        UniversalRow(
            String(localized: "csvImport.mapping.subcategoriesSeparator"),
            accessory: .menu(
                $mapping.subcategoriesSeparator,
                options: [
                    (label: "; " + String(localized: "csvImport.mapping.separator.semicolon"), value: ";"),
                    (label: ", " + String(localized: "csvImport.mapping.separator.comma"), value: ","),
                    (label: "| " + String(localized: "csvImport.mapping.separator.pipe"), value: "|"),
                ]
            )
        )
    }

    // MARK: - Toolbar

    private var toolbarContent: some ToolbarContent {
        Group {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if canProceed {
                        onComplete(mapping)
                    }
                } label: {
                    Image(systemName: "arrow.right")
                }
                .dsButton()
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
