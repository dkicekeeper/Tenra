//
//  AnimatedTitleInput.swift
//  Tenra
//
//  Created: Phase 16 - AnimatedHeroInput
//
//  Hero-style name input with contentTransition interpolate animation.
//  Amount input merged into AmountInput (AnimatedInputComponents.swift).
//

import SwiftUI

// MARK: - AnimatedTitleInput

/// Hero-style name/title input with soft scale+fade character animations.
/// Renders animated text display over a hidden TextField.
///
/// Usage:
/// ```swift
/// AnimatedTitleInput(text: $title, placeholder: String(localized: "account.namePlaceholder"))
/// AnimatedTitleInput(text: $title, placeholder: "...", font: AppTypography.h2)
/// ```
struct AnimatedTitleInput: View {
    @Binding var text: String
    let placeholder: String
    var font: Font = AppTypography.h2
    var color: Color = AppColors.textPrimary
    var alignment: TextAlignment = .center
    /// When `true`, the underlying TextField receives focus on first appear.
    var autoFocus: Bool = false

    @FocusState private var isFocused: Bool

    // Placeholder скрывается когда есть текст ИЛИ поле сфокусировано
    private var showPlaceholder: Bool {
        text.isEmpty && !isFocused
    }

    // Курсор виден при фокусе (в том числе при пустом тексте)
    private var showCursor: Bool {
        isFocused
    }

    var body: some View {
        ZStack {
            // Placeholder — hidden when focused or text is present
            if showPlaceholder {
                Text(placeholder)
                    .font(font)
                    .foregroundStyle(AppColors.textTertiary)
                    .multilineTextAlignment(alignment)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }

            // Animated text + cursor
            HStack(spacing: 0) {
                if alignment == .center { Spacer() }
                HStack(spacing: 1) {
                    Text(text.isEmpty ? "" : text)
                        .font(font)
                        .foregroundStyle(color)

                    // Conditional mount — see AnimatedInputComponents.BlinkingCursor note:
                    // hiding via parent opacity fights the cursor's internal repeatForever,
                    // so it never settles to hidden on blur. Removing it from the hierarchy
                    // tears the animation down. Typing no longer morphs the whole string
                    // (dropped .contentTransition(.interpolate) — it animated every keystroke).
                    if showCursor {
                        BlinkingCursor(height: 44)
                            .transition(.opacity.animation(.easeInOut(duration: 0.15)))
                    }
                }
                if alignment == .center { Spacer() }
            }
            .allowsHitTesting(false)

            // Hidden TextField — actual input source
            TextField("", text: $text)
                .font(font)
                .multilineTextAlignment(alignment)
                .focused($isFocused)
                .foregroundStyle(.clear)
                .tint(.clear)
                .submitLabel(.done)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            HapticManager.light()
            isFocused = true
        }
        .animation(AppAnimation.fastAnimation, value: showPlaceholder)
        .onAppear {
            guard autoFocus else { return }
            // Brief delay so the field exists in the responder chain before we
            // request focus — without this the keyboard sometimes refuses to
            // raise on push-driven appearances.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isFocused = true
            }
        }
    }
}

// MARK: - Previews

#Preview("Animated Title Input") {
    struct Demo: View {
        @State private var title = ""
        var body: some View {
            VStack(spacing: AppSpacing.xl) {
                AnimatedTitleInput(
                    text: $title,
                    placeholder: String(localized: "account.namePlaceholder")
                )
                .padding(.horizontal, AppSpacing.xl)

                AnimatedTitleInput(
                    text: $title,
                    placeholder: String(localized: "category.namePlaceholder"),
                    font: AppTypography.h2,
                    color: AppColors.accent
                )
                .padding(.horizontal, AppSpacing.xl)
            }
            .padding(AppSpacing.xl)
        }
    }
    return Demo()
}

#Preview("Hero Section Combined") {
    struct Demo: View {
        @State private var title = "Kaspi Gold"
        @State private var amount = "125000"
        var body: some View {
            VStack(spacing: AppSpacing.lg) {
                Image(systemName: "creditcard.fill")
                    .font(.system(size: AppIconSize.ultra))
                    .foregroundStyle(AppColors.accent)

                AnimatedTitleInput(
                    text: $title,
                    placeholder: String(localized: "account.namePlaceholder")
                )

                AmountInput(amount: $amount, baseFontSize: 48)

                Text("KZT")
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(AppSpacing.xl)
        }
    }
    return Demo()
}
