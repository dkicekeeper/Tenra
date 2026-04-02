//
//  UniversalCarousel.swift
//  AIFinanceManager
//
//  Created: 2026-02-16
//  Universal horizontal carousel component
//
//  Consolidates 10+ carousel implementations into a single, configurable component
//  with Design System integration and centralized localization.
//
//  Usage:
//  ```swift
//  // Simple carousel
//  UniversalCarousel(config: .standard) {
//      ForEach(items) { item in
//          ItemView(item: item)
//      }
//  }
//
//  // With auto-scroll support
//  UniversalCarousel(
//      config: .standard,
//      scrollToId: $selectedItemId
//  ) {
//      ForEach(items) { item in
//          ItemView(item: item)
//              .id(item.id)
//      }
//  }
//  ```
//

import SwiftUI

/// Universal horizontal carousel component
/// Provides consistent scrolling behavior across the app with configurable presets
struct UniversalCarousel<Content: View>: View {
    // MARK: - Properties

    /// Configuration preset (standard, compact, filter, cards, csvPreview)
    let config: CarouselConfiguration

    /// Content builder for carousel items
    @ViewBuilder let content: () -> Content

    /// Optional binding for auto-scroll to specific item ID
    /// When set, the carousel will automatically scroll to center the item with this ID
    let scrollToId: Binding<AnyHashable?>?

    /// Optional VoiceOver label for the carousel container.
    ///
    /// When provided, VoiceOver announces this label before the individual child elements,
    /// giving screen-reader users context about what the carousel contains
    /// (e.g. `"Period filter"`, `"Account selector"`, `"CSV column preview"`).
    ///
    /// When `nil` (default), VoiceOver traverses child elements directly without a
    /// container announcement — suitable when the surrounding UI already provides context.
    let accessibilityLabel: String?

    // MARK: - Initializer

    /// Creates a universal carousel with specified configuration
    /// - Parameters:
    ///   - config: Configuration preset (default: .standard)
    ///   - scrollToId: Optional binding for auto-scroll to item ID
    ///   - accessibilityLabel: Optional VoiceOver container label. Pass a localised string when
    ///     the carousel has semantic meaning (e.g. "Period filter", "Account selector").
    ///     Omit (default `nil`) when surrounding UI already conveys context.
    ///   - content: ViewBuilder for carousel items
    init(
        config: CarouselConfiguration = .standard,
        scrollToId: Binding<AnyHashable?>? = nil,
        accessibilityLabel: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.config = config
        self.scrollToId = scrollToId
        self.accessibilityLabel = accessibilityLabel
        self.content = content
    }

    // MARK: - Body

    var body: some View {
        if let scrollBinding = scrollToId {
            // ScrollViewReader version for auto-scroll support
            ScrollViewReader { proxy in
                scrollViewContent
                    .onAppear {
                        guard let id = scrollBinding.wrappedValue else { return }
                        // Immediate scroll without animation on initial appear
                        proxy.scrollTo(id, anchor: .center)
                    }
                    .onChange(of: scrollBinding.wrappedValue) { _, newId in
                        guard let newId else { return }
                        withAnimation(config.scrollAnimation) {
                            proxy.scrollTo(newId, anchor: .center)
                        }
                    }
            }
        } else {
            // Standard version without auto-scroll
            scrollViewContent
        }
    }

    // MARK: - Private Views

    /// Base ScrollView without an accessibility container label.
    @ViewBuilder
    private var baseScrollView: some View {
        switch config.snapBehavior {
        case .viewAligned:
            ScrollView(.horizontal, showsIndicators: config.showsIndicators) {
                HStack(spacing: config.spacing) {
                    content()
                }
                .padding(.horizontal, config.horizontalPadding)
                .padding(.vertical, config.verticalPadding)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled(config.clipDisabled)

        case .none:
            ScrollView(.horizontal, showsIndicators: config.showsIndicators) {
                HStack(spacing: config.spacing) {
                    content()
                }
                .padding(.horizontal, config.horizontalPadding)
                .padding(.vertical, config.verticalPadding)
            }
            .scrollClipDisabled(config.clipDisabled)
        }
    }

    /// ScrollView with optional VoiceOver container label applied.
    ///
    /// When `accessibilityLabel` is set the scroll container is announced by VoiceOver
    /// so users understand what type of items the carousel holds before swiping through them.
    @ViewBuilder
    private var scrollViewContent: some View {
        if let label = accessibilityLabel {
            baseScrollView
                .accessibilityLabel(label)
        } else {
            baseScrollView
        }
    }
}

// MARK: - Previews

private struct CarouselPreviewItem: Identifiable {
    let id = UUID()
    let title: String
    let color: Color
}

private let carouselPreviewItems = [
    CarouselPreviewItem(title: "Item 1", color: .red),
    CarouselPreviewItem(title: "Item 2", color: .blue),
    CarouselPreviewItem(title: "Item 3", color: .green),
    CarouselPreviewItem(title: "Item 4", color: .orange),
    CarouselPreviewItem(title: "Item 5", color: .purple)
]

#Preview("Standard & Compact") {
    VStack(spacing: AppSpacing.xl) {
        VStack(alignment: .leading) {
            Text("Standard").font(AppTypography.h4).padding(.horizontal, AppSpacing.lg)
            UniversalCarousel(config: .standard) {
                ForEach(carouselPreviewItems) { item in
                    RoundedRectangle(cornerRadius: AppRadius.md)
                        .fill(item.color)
                        .frame(width: 120, height: 80)
                        .overlay { Text(item.title).foregroundStyle(.white) }
                }
            }
        }

        VStack(alignment: .leading) {
            Text("Compact").font(AppTypography.h4).padding(.horizontal, AppSpacing.lg)
            UniversalCarousel(config: .compact) {
                ForEach(carouselPreviewItems) { item in
                    Circle().fill(item.color).frame(width: 50, height: 50)
                }
            }
        }
    }
    .padding(.top, AppSpacing.xl)
}

#Preview("Filter & CSV Preview") {
    VStack(spacing: AppSpacing.xl) {
        VStack(alignment: .leading) {
            Text("Filter").font(AppTypography.h4).padding(.horizontal, AppSpacing.lg)
            UniversalCarousel(config: .filter) {
                ForEach(carouselPreviewItems) { item in
                    Text(item.title)
                        .font(AppTypography.body)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.sm)
                        .background(item.color.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
        }

        VStack(alignment: .leading) {
            Text("CSV Preview (with indicators)").font(AppTypography.h4).padding(.horizontal, AppSpacing.lg)
            UniversalCarousel(config: .csvPreview) {
                ForEach(carouselPreviewItems) { item in
                    VStack {
                        Text("Header").font(AppTypography.caption).foregroundStyle(.secondary)
                        Text(item.title).font(AppTypography.body)
                    }
                    .padding(AppSpacing.sm)
                    .background(AppColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs))
                }
            }
        }
    }
    .padding(.top, AppSpacing.xl)
}
