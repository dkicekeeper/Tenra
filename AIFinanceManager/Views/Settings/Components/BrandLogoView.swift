//
//  BrandLogoView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

/// SwiftUI компонент для отображения логотипа бренда с загрузкой из logo.dev
struct BrandLogoView: View {
    let brandName: String?
    let size: CGFloat
    
    @State private var logoURL: URL?
    @State private var cachedImage: UIImage?
    @State private var isLoading = false
    
    init(brandName: String?, size: CGFloat = 32) {
        self.brandName = brandName
        self.size = size
    }
    
    var body: some View {
        Group {
            if let cachedImage = cachedImage {
                Image(uiImage: cachedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
            } else if let url = logoURL {
                // Используем AsyncImage для быстрого отображения, пока LogoService кеширует
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(width: size, height: size)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: size, height: size)
                            .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
                    case .failure(_):
                        // Fallback: SF Symbol
                        fallbackIcon
                    @unknown default:
                        fallbackIcon
                    }
                }
            } else {
                // Fallback: SF Symbol (если нет URL)
                fallbackIcon
            }
        }
        .onAppear {
            updateURL()
            loadLogoIfNeeded()
        }
        .onChange(of: brandName) { _, _ in
            updateURL()
            loadLogoIfNeeded()
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
    
    private func updateURL() {
        guard let brandName = brandName,
              !brandName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              LogoDevConfig.isAvailable else {
            logoURL = nil
            cachedImage = nil
            return
        }
        
        logoURL = LogoDevConfig.logoURL(for: brandName)
    }

    private func loadLogoIfNeeded() {
        guard let brandName = brandName,
              !brandName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              LogoDevConfig.isAvailable else {
            return
        }

        guard !isLoading else { return }
        isLoading = true

        Task { @MainActor in
            let image = try? await LogoService.shared.logoImage(brandName: brandName)
            cachedImage = image
            isLoading = false
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        BrandLogoView(brandName: "Netflix", size: 40)
        BrandLogoView(brandName: "Spotify", size: 32)
        BrandLogoView(brandName: nil, size: 32)
    }
    .padding()
}
