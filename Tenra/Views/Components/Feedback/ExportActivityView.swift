//
//  ExportActivityView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI
import UIKit

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
        
        // Создаем временный файл
        let fileName = "transactions_export_\(DateFormatter.exportFileNameFormatter.string(from: Date())).csv"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            try csvContent.write(to: tempURL, atomically: true, encoding: .utf8)
        } catch {
        }
        
        let activityVC = UIActivityViewController(
            activityItems: [tempURL],
            applicationActivities: nil
        )
        
        activityVC.completionWithItemsHandler = { _, _, _, _ in
            // Удаляем временный файл после экспорта
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
