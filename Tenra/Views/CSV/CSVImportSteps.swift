//
//  CSVImportSteps.swift
//  Tenra
//
//  Where the CSV import is, on top of each of its sheets (DesignKit's StepTracker): the file's
//  preview, its columns, the import. The result shows every step done. The progress sheet in
//  between is DesignKit's own (ImportProgressSheet) and shows the rows instead.
//

import SwiftUI

struct CSVImportSteps: View {
    /// The step on screen, 0-based; `CSVImportSteps.done` on the result.
    let current: Int

    static let preview = 0
    static let columns = 1
    static let done = 3

    var body: some View {
        StepTracker(
            steps: [
                String(localized: "csvImport.step.preview"),
                String(localized: "csvImport.step.columns"),
                String(localized: "csvImport.step.import"),
            ],
            current: current
        )
    }
}
