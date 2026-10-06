//
//  IconPickerView.swift
//  Tenra
//
//  Adapter over DesignKit's IconPicker (1.10.0). The SF Symbol catalog moved to DesignKit
//  (IconCatalog); Tenra's brand registry feeds the logos tab through DesignKitLogoCatalog
//  (wired in DesignKitBridge).
//

import SwiftUI

struct IconPickerView: View {
    @Binding var selectedSource: IconSource?
    var allowLogos: Bool = true

    var body: some View {
        IconPicker(selection: $selectedSource, allowsLogos: allowLogos)
    }
}

// MARK: - Previews

#Preview("Icons Tab") {
    @Previewable @State var source: IconSource? = .sfSymbol("star.fill")
    return IconPickerView(selectedSource: $source)
}

#Preview("Logos Tab") {
    @Previewable @State var source: IconSource? = .brandService("kaspi.kz")
    return IconPickerView(selectedSource: $source)
}
