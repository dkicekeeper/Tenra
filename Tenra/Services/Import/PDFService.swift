//
//  PDFService.swift
//  Tenra
//
//  Page rasterisation only. Extraction moved to VisionDocumentExtractor /
//  PDFTextLayerExtractor; orchestration moved to DocumentImportService.
//

import Foundation
import PDFKit
import UIKit

nonisolated enum PDFService {

    /// Renders each page to a CGImage for OCR.
    ///
    /// `scale` 3.5 puts an A4 page at roughly 250 dpi. The previous 2.0 gave
    /// about 144 dpi, below what small statement type needs.
    static func renderPages(
        of document: PDFDocument,
        scale: CGFloat,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) -> [CGImage] {
        var images: [CGImage] = []
        let pageCount = document.pageCount

        for pageIndex in 0..<pageCount {
            progress?(pageIndex + 1, pageCount)
            guard let page = document.page(at: pageIndex) else { continue }

            let pageRect = page.bounds(for: .mediaBox)
            let size = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
            let renderer = UIGraphicsImageRenderer(size: size)

            let image = renderer.image { context in
                context.cgContext.saveGState()
                context.cgContext.translateBy(x: 0, y: size.height)
                context.cgContext.scaleBy(x: scale, y: -scale)
                page.draw(with: .mediaBox, to: context.cgContext)
                context.cgContext.restoreGState()
            }
            if let cgImage = image.cgImage { images.append(cgImage) }
        }
        return images
    }
}

enum PDFError: LocalizedError {
    case invalidDocument
    case noTextFound
    case unsupportedFormat
    case ocrError(String)

    var errorDescription: String? {
        switch self {
        case .invalidDocument:
            return String(localized: "pdf.error.invalidDocument")
        case .noTextFound:
            return String(localized: "pdf.error.noTextFound")
        case .unsupportedFormat:
            return String(localized: "pdf.error.unsupportedFormat")
        case .ocrError(let message):
            return String(localized: "pdf.error.ocr \(message)")
        }
    }
}
