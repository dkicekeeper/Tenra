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
    ///
    /// Returns exactly `document.pageCount` entries, one per page, in order.
    /// A `nil` entry means that page could not be rendered (`page(at:)`
    /// returned nil, or the renderer produced no `cgImage` — more likely now
    /// that scale 3.5 raises memory pressure on large multi-page
    /// statements). The 1:1 index alignment is load-bearing: the caller
    /// feeds this straight into per-page OCR, and a page silently dropped
    /// from the array would shift every later page's index, misattributing
    /// their recognized text to the wrong page number.
    static func renderPages(
        of document: PDFDocument,
        scale: CGFloat,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) -> [CGImage?] {
        var images: [CGImage?] = []
        let pageCount = document.pageCount

        for pageIndex in 0..<pageCount {
            progress?(pageIndex + 1, pageCount)
            guard let page = document.page(at: pageIndex) else {
                images.append(nil)
                continue
            }

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
            images.append(image.cgImage)
        }
        return images
    }
}

enum PDFError: LocalizedError {
    case invalidDocument
    case noTextFound
    case layoutNotRecognized
    case unsupportedFormat
    case ocrError(String)

    var errorDescription: String? {
        switch self {
        case .invalidDocument:
            return String(localized: "pdf.error.invalidDocument")
        case .noTextFound:
            return String(localized: "pdf.error.noTextFound")
        case .layoutNotRecognized:
            return String(localized: "pdf.error.layoutNotRecognized")
        case .unsupportedFormat:
            return String(localized: "pdf.error.unsupportedFormat")
        case .ocrError(let message):
            return String(localized: "pdf.error.ocr \(message)")
        }
    }
}
