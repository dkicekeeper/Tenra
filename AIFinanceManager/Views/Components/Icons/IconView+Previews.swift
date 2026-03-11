//
//  IconView+Previews.swift
//  AIFinanceManager
//
//  Xcode previews for IconView — extracted for maintainability.
//  Phase C: File split.
//

import SwiftUI

// MARK: - Previews

#Preview("Design System Presets") {
    ScrollView {
        VStack(alignment: .leading, spacing: AppSpacing.xxl) {
            PresetSection(
                title: "Category Icons",
                examples: [
                    (.sfSymbol("star.fill"), IconStyle.categoryIcon()),
                    (.sfSymbol("cart.fill"), IconStyle.categoryIcon()),
                    (.sfSymbol("heart.fill"), IconStyle.categoryCoin())
                ]
            )

            PresetSection(
                title: "Bank Logos",
                examples: [
                    (.bankLogo(.kaspi), IconStyle.bankLogo()),
                    (.bankLogo(.halykBank), IconStyle.bankLogo(size: AppIconSize.avatar)),
                    (.bankLogo(.tbank), IconStyle.bankLogoLarge())
                ]
            )

            PresetSection(
                title: "Service Logos",
                examples: [
                    (.brandService("netflix"), IconStyle.serviceLogo()),
                    (.brandService("spotify"), IconStyle.serviceLogo(size: AppIconSize.avatar)),
                    (.brandService("notion"), IconStyle.serviceLogoLarge())
                ]
            )

            PresetSection(
                title: "Utility Icons",
                examples: [
                    (.sfSymbol("gear"), IconStyle.toolbar()),
                    (.sfSymbol("plus"), IconStyle.inline()),
                    (.sfSymbol("photo"), IconStyle.emptyState())
                ]
            )

            PlaceholderSection()
        }
        .padding(AppSpacing.lg)
    }
}

#Preview("Shapes") {
    VStack(spacing: AppSpacing.xl) {
        ShapeRow(
            title: String(localized: "iconStyle.shape.circle"),
            style: .circle(size: AppIconSize.xl, tint: .accentMonochrome)
        )

        ShapeRow(
            title: String(localized: "iconStyle.shape.roundedSquare"),
            style: .roundedSquare(size: AppIconSize.xl, tint: .accentMonochrome)
        )

        ShapeRow(
            title: String(localized: "iconStyle.shape.square"),
            style: .square(size: AppIconSize.xl, tint: .accentMonochrome)
        )
    }
    .padding(AppSpacing.lg)
}

#Preview("Tints") {
    VStack(spacing: AppSpacing.xl) {
        TintRow(
            title: String(localized: "iconStyle.tint.monochrome"),
            style: .circle(size: AppIconSize.xl, tint: .accentMonochrome)
        )

        TintRow(
            title: String(localized: "iconStyle.tint.hierarchical"),
            style: .circle(size: AppIconSize.xl, tint: .hierarchical(AppColors.accent))
        )

        if #available(iOS 15, *) {
            TintRow(
                title: String(localized: "iconStyle.tint.palette"),
                style: .circle(size: AppIconSize.xl, tint: .palette([.blue, .green, .red]))
            )
        }
    }
    .padding(AppSpacing.lg)
}

#Preview("Size Comparison") {
    VStack(spacing: AppSpacing.xl) {
        HStack(spacing: AppSpacing.lg) {
            VStack(spacing: AppSpacing.xs) {
                IconView(source: .sfSymbol("star.fill"), size: AppIconSize.sm)
                Text("Small")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }

            VStack(spacing: AppSpacing.xs) {
                IconView(source: .sfSymbol("star.fill"), size: AppIconSize.md)
                Text("Medium")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }

            VStack(spacing: AppSpacing.xs) {
                IconView(source: .sfSymbol("star.fill"), size: AppIconSize.lg)
                Text("Large")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }

            VStack(spacing: AppSpacing.xs) {
                IconView(source: .sfSymbol("star.fill"), size: AppIconSize.xl)
                Text("XL")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }
    .padding(AppSpacing.lg)
}

#Preview("Automatic Padding") {
    ScrollView {
        VStack(alignment: .leading, spacing: AppSpacing.xxl) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("SF Symbols (Adaptive padding)")
                    .font(AppTypography.h4)
                    .foregroundStyle(AppColors.textPrimary)

                HStack(spacing: AppSpacing.lg) {
                    VStack(spacing: AppSpacing.xs) {
                        IconView(source: .sfSymbol("star.fill"), size: 60)
                            .background(AppColors.surface)
                        Text("star.fill")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    VStack(spacing: AppSpacing.xs) {
                        IconView(source: .sfSymbol("heart.fill"), size: 60)
                            .background(AppColors.surface)
                        Text("heart.fill")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    VStack(spacing: AppSpacing.xs) {
                        IconView(source: .sfSymbol("cart.fill"), size: 60)
                            .background(AppColors.surface)
                        Text("cart.fill")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("Bank Logos (No padding - Fill)")
                    .font(AppTypography.h4)
                    .foregroundStyle(AppColors.textPrimary)

                HStack(spacing: AppSpacing.lg) {
                    VStack(spacing: AppSpacing.xs) {
                        IconView(source: .bankLogo(.kaspi), size: 60)
                            .background(AppColors.surface)
                        Text("Kaspi")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    VStack(spacing: AppSpacing.xs) {
                        IconView(source: .bankLogo(.halykBank), size: 60)
                            .background(AppColors.surface)
                        Text("Halyk")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    VStack(spacing: AppSpacing.xs) {
                        IconView(source: .bankLogo(.tbank), size: 60)
                            .background(AppColors.surface)
                        Text("T-Bank")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("Brand Services (No padding - Fill)")
                    .font(AppTypography.h4)
                    .foregroundStyle(AppColors.textPrimary)

                HStack(spacing: AppSpacing.lg) {
                    VStack(spacing: AppSpacing.xs) {
                        IconView(source: .brandService("netflix"), size: 60)
                            .background(AppColors.surface)
                        Text("Netflix")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    VStack(spacing: AppSpacing.xs) {
                        IconView(source: .brandService("spotify"), size: 60)
                            .background(AppColors.surface)
                        Text("Spotify")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    VStack(spacing: AppSpacing.xs) {
                        IconView(source: .brandService("notion"), size: 60)
                            .background(AppColors.surface)
                        Text("Notion")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("Placeholder (Auto 10% padding)")
                    .font(AppTypography.h4)
                    .foregroundStyle(AppColors.textPrimary)

                HStack(spacing: AppSpacing.lg) {
                    VStack(spacing: AppSpacing.xs) {
                        IconView(source: nil, size: 60)
                            .background(AppColors.surface)
                        Text("nil source")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("Override (Explicit padding: 5pt)")
                    .font(AppTypography.h4)
                    .foregroundStyle(AppColors.textPrimary)

                HStack(spacing: AppSpacing.lg) {
                    VStack(spacing: AppSpacing.xs) {
                        IconView(
                            source: .sfSymbol("star.fill"),
                            style: .circle(size: 60, tint: .accentMonochrome, padding: 5)
                        )
                        .background(AppColors.surface)
                        Text("Custom 5pt")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    VStack(spacing: AppSpacing.xs) {
                        IconView(
                            source: .bankLogo(.kaspi),
                            style: .roundedSquare(size: 60, padding: 10)
                        )
                        .background(AppColors.surface)
                        Text("Logo + 10pt")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
        }
        .padding(AppSpacing.lg)
    }
}

#Preview("Glass Effect") {
    if #available(iOS 18.0, *) {
        VStack(spacing: AppSpacing.xxl) {
            VStack(spacing: AppSpacing.md) {
                Text("Glass Hero (Circle)")
                    .font(AppTypography.h4)

                HStack(spacing: AppSpacing.lg) {
                    IconView(source: .sfSymbol("tv.fill"), style: .glassHero())
                    IconView(source: .sfSymbol("music.note"), style: .glassHero())
                    IconView(source: .sfSymbol("cloud.fill"), style: .glassHero())
                }
            }

            VStack(spacing: AppSpacing.md) {
                Text("Glass Service (Rounded Square)")
                    .font(AppTypography.h4)

                HStack(spacing: AppSpacing.lg) {
                    IconView(source: .brandService("netflix"), style: .glassService())
                    IconView(source: .brandService("spotify"), style: .glassService())
                    IconView(source: .brandService("notion"), style: .glassService())
                }
            }

            VStack(spacing: AppSpacing.md) {
                Text("Custom Glass Effect")
                    .font(AppTypography.h4)

                HStack(spacing: AppSpacing.lg) {
                    IconView(
                        source: .sfSymbol("star.fill"),
                        style: .circle(size: AppIconSize.xl, tint: .accentMonochrome, hasGlassEffect: true)
                    )
                    IconView(
                        source: .sfSymbol("heart.fill"),
                        style: .roundedSquare(size: AppIconSize.xl, tint: .destructiveMonochrome, hasGlassEffect: true)
                    )
                }
            }
        }
        .padding(AppSpacing.lg)
    } else {
        Text("Glass Effect requires iOS 18.0+")
            .font(AppTypography.body)
            .foregroundStyle(AppColors.textSecondary)
            .padding(AppSpacing.lg)
    }
}

// MARK: - Preview Helpers

private struct PresetSection: View {
    let title: String
    let examples: [(IconSource, IconStyle)]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text(title)
                .font(AppTypography.h4)
                .foregroundStyle(AppColors.textPrimary)

            HStack(spacing: AppSpacing.lg) {
                ForEach(0..<examples.count, id: \.self) { index in
                    let (source, style) = examples[index]

                    VStack(spacing: AppSpacing.xs) {
                        IconView(source: source, style: style)

                        if let presetName = style.localizedPresetName {
                            Text(presetName)
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
            }
        }
    }
}

private struct PlaceholderSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Placeholder")
                .font(AppTypography.h4)
                .foregroundStyle(AppColors.textPrimary)

            HStack(spacing: AppSpacing.lg) {
                IconView(source: nil, style: .placeholder(size: AppIconSize.xl))
                IconView(source: nil, style: .placeholder(size: AppIconSize.avatar))
                IconView(source: nil, style: .placeholder(size: AppIconSize.coin))
            }
        }
    }
}

private struct ShapeRow: View {
    let title: String
    let style: IconStyle

    var body: some View {
        HStack(spacing: AppSpacing.lg) {
            IconView(source: .sfSymbol("star.fill"), style: style)
            Text(title)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textPrimary)
            Spacer()
        }
    }
}

private struct TintRow: View {
    let title: String
    let style: IconStyle

    var body: some View {
        HStack(spacing: AppSpacing.lg) {
            IconView(source: .sfSymbol("paintpalette.fill"), style: style)
            Text(title)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textPrimary)
            Spacer()
        }
    }
}
