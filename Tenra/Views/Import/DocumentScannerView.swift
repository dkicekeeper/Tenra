//
//  DocumentScannerView.swift
//  Tenra
//
//  VisionKit document camera. It handles edge detection, perspective
//  correction, and multi-page capture for us, which is exactly the
//  preprocessing OCR quality depends on most.
//

import SwiftUI
import VisionKit
import CoreGraphics

struct DocumentScannerView: UIViewControllerRepresentable {
    let onScan: ([CGImage]) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController,
                                context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onCancel: onCancel)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let onScan: ([CGImage]) -> Void
        private let onCancel: () -> Void

        init(onScan: @escaping ([CGImage]) -> Void, onCancel: @escaping () -> Void) {
            self.onScan = onScan
            self.onCancel = onCancel
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            var images: [CGImage] = []
            for pageIndex in 0..<scan.pageCount {
                if let cgImage = scan.imageOfPage(at: pageIndex).cgImage {
                    images.append(cgImage)
                }
            }
            onScan(images)
        }

        func documentCameraViewControllerDidCancel(
            _ controller: VNDocumentCameraViewController
        ) {
            onCancel()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: any Error
        ) {
            onCancel()
        }
    }
}
