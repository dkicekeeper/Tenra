//
//  BrandLogoView.swift
//  AIFinanceManager
//
//  SwiftUI component for displaying brand logos via provider chain
//

import SwiftUI

/// Displays a brand logo loaded through the LogoService provider chain.
/// No longer uses AsyncImage — relies entirely on the chain result.
/// Uses .task(id:) for automatic cancellation on brandName change.
struct BrandLogoView: View {
    let brandName: String?
    let size: CGFloat

    @State private var logoImage: UIImage?
    @State private var isLoading = false

    init(brandName: String?, size: CGFloat = 32) {
        self.brandName = brandName
        self.size = size
    }

    var body: some View {
        Group {
            if let logoImage {
                Image(uiImage: logoImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
            } else if isLoading {
                ProgressView()
                    .frame(width: size, height: size)
            } else {
                fallbackIcon
            }
        }
        .task(id: brandName) {
            guard let brandName,
                  !brandName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                logoImage = nil
                isLoading = false
                return
            }

            isLoading = true
            let image = await LogoService.shared.logoImage(brandName: brandName)
            logoImage = image
            isLoading = false
        }
    }

    private var fallbackIcon: some View {
        Image(systemName: "creditcard")
            .font(.system(size: size * 0.6))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .background(AppColors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
    }
}

#Preview {
    VStack(spacing: 20) {
        BrandLogoView(brandName: "netflix.com", size: 40)
        BrandLogoView(brandName: "spotify.com", size: 32)
        BrandLogoView(brandName: nil, size: 32)
    }
    .padding()
}
