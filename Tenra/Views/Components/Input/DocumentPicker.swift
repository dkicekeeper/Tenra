//
//  DocumentPicker.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI
import UniformTypeIdentifiers

struct DocumentPicker: UIViewControllerRepresentable {
    let onDocumentPicked: (URL) -> Void
    
    let contentTypes: [UTType]
    
    init(contentTypes: [UTType] = [.pdf], onDocumentPicked: @escaping (URL) -> Void) {
        self.contentTypes = contentTypes
        self.onDocumentPicked = onDocumentPicked
    }
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onDocumentPicked: onDocumentPicked)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onDocumentPicked: (URL) -> Void
        
        init(onDocumentPicked: @escaping (URL) -> Void) {
            self.onDocumentPicked = onDocumentPicked
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            
            // На реальных устройствах нужно начать доступ к файлу
            let isAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if isAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            // Копируем файл во временную директорию для безопасного доступа
            let tempURL = copyToTemporaryDirectory(sourceURL: url)
            onDocumentPicked(tempURL ?? url)
        }
        
        private func copyToTemporaryDirectory(sourceURL: URL) -> URL? {
            let fileManager = FileManager.default
            let tempDir = fileManager.temporaryDirectory
            let fileName = sourceURL.lastPathComponent
            let destinationURL = tempDir.appendingPathComponent(fileName)
            
            // Удаляем старый файл, если существует
            try? fileManager.removeItem(at: destinationURL)
            
            do {
                // Копируем файл во временную директорию
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
                return destinationURL
            } catch {
                return nil
            }
        }
    }
}
