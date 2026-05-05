//
//  ExportActivityView.swift
//  Tenra
//
//  Created on 2024
//

import SwiftUI
import UIKit
import OSLog

private let logger = Logger(subsystem: "Tenra", category: "ExportActivityView")

struct ExportActivityView: UIViewControllerRepresentable {
    let transactionsViewModel: TransactionsViewModel
    @Environment(\.dismiss) var dismiss

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let csvContent = CSVExporter.exportTransactions(
            transactionsViewModel.allTransactions,
            accounts: transactionsViewModel.accounts,
            subcategoryLinks: transactionsViewModel.transactionStore?.transactionSubcategoryLinks ?? [],
            subcategories: transactionsViewModel.transactionStore?.subcategories ?? []
        )

        let fileName = "transactions_export_\(DateFormatter.exportFileNameFormatter.string(from: Date())).csv"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        let activityItems: [Any]
        do {
            try csvContent.write(to: tempURL, atomically: true, encoding: .utf8)
            activityItems = [tempURL]
        } catch {
            logger.error("CSV file write failed: \(error.localizedDescription) — falling back to string share")
            activityItems = [csvContent]
        }

        let activityVC = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )

        activityVC.completionWithItemsHandler = { _, _, _, _ in
            try? FileManager.default.removeItem(at: tempURL)
            dismiss()
        }

        return activityVC
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    // Note: ExportActivityView is a UIViewControllerRepresentable, 
    // so it requires a real device/simulator to preview properly
    let coordinator = AppCoordinator()
    ExportActivityView(transactionsViewModel: coordinator.transactionsViewModel)
}
