//
//  AssistantWardrobe.swift
//  Tenra
//
//  What Ten wears (DesignKit 4.12, the owner's plan: events and a wardrobe). On a holiday it
//  dresses up on its own: a party hat from New Year's Eve to 2 January, a taqiya for Nauryz
//  (21 to 23 March); on a day it celebrated a reply with the person it wears a crown. Any other
//  day it wears what the person chose in Settings → Assistant → Ten's wardrobe, or nothing.
//

import SwiftUI

enum AssistantWardrobe {
    /// The person's choice: a `CreatureAccessory`'s raw value, empty for nothing.
    static let choiceKey = "assistant.accessory"
    /// The day Ten last celebrated with the person, `yyyy-MM-dd` (AssistantChatter.dayKey).
    static let crownDayKey = "assistant.crownDay"

    /// What Ten wears at `date`.
    static func accessory(choice: String, crownDay: String, at date: Date,
                          calendar: Calendar = .current) -> CreatureAccessory? {
        if let holiday = holiday(at: date, calendar: calendar) { return holiday }
        if crownDay == AssistantChatter.dayKey(date, calendar: calendar) { return .crown }
        return CreatureAccessory(rawValue: choice)
    }

    /// The holiday's accessory, if `date` is one.
    static func holiday(at date: Date, calendar: Calendar = .current) -> CreatureAccessory? {
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        if (month == 12 && day == 31) || (month == 1 && day <= 2) { return .partyHat }
        if month == 3 && (21...23).contains(day) { return .taqiya }
        return nil
    }

    /// The accessory's name; "Nothing" for none.
    static func name(_ accessory: CreatureAccessory?) -> String {
        switch accessory {
        case .none: String(localized: "assistant.wardrobe.none")
        case .partyHat: String(localized: "assistant.wardrobe.partyHat")
        case .crown: String(localized: "assistant.wardrobe.crown")
        case .beanie: String(localized: "assistant.wardrobe.beanie")
        case .taqiya: String(localized: "assistant.wardrobe.taqiya")
        case .headphones: String(localized: "assistant.wardrobe.headphones")
        case .glasses: String(localized: "assistant.wardrobe.glasses")
        case .sunglasses: String(localized: "assistant.wardrobe.sunglasses")
        case .sleepMask: String(localized: "assistant.wardrobe.sleepMask")
        }
    }
}

/// Settings → Assistant → Ten's wardrobe: Ten in what it wears, and the choices under it, each
/// a still Ten wearing it.
struct AssistantWardrobeView: View {
    @AppStorage(AssistantWardrobe.choiceKey) private var choice = ""

    private let options: [CreatureAccessory?] = [nil] + CreatureAccessory.allCases

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                ParticleCreature(mood: .happy, isInteractive: true, accessory: CreatureAccessory(rawValue: choice))
                    .frame(width: WardrobeMetrics.preview, height: WardrobeMetrics.preview)
                    .frame(maxWidth: .infinity)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: AppSpacing.md), count: 3),
                          spacing: AppSpacing.md) {
                    ForEach(options, id: \.self) { option in
                        tile(option)
                    }
                }

                Text(String(localized: "assistant.wardrobe.footer"))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.Text.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(AppSpacing.lg)
        }
        .background(AppColors.Background.baseAlt)
        .navigationTitle(String(localized: "assistant.wardrobe.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func tile(_ option: CreatureAccessory?) -> some View {
        let isSelected = (option?.rawValue ?? "") == choice
        return Button {
            HapticManager.selection()
            withAnimation(AppAnimation.contentSpring) { choice = option?.rawValue ?? "" }
        } label: {
            VStack(spacing: AppSpacing.xs) {
                ParticleCreature(mood: option == .sleepMask ? .asleep : .idle, accessory: option)
                    .frame(width: WardrobeMetrics.tile, height: WardrobeMetrics.tile)
                    .designKitMotion(false)
                Text(AssistantWardrobe.name(option))
                    .font(AppTypography.caption)
                    .foregroundStyle(isSelected ? AppColors.accent : AppColors.Text.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(AppSpacing.sm)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: AppRadius.lg).fill(AppColors.Background.elevation1))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg)
                    .stroke(isSelected ? AppColors.accent : Color.clear, lineWidth: WardrobeMetrics.outline)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AssistantWardrobe.name(option))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

private enum WardrobeMetrics {
    /// Ten in what it wears, and Ten on each choice.
    static let preview: CGFloat = 180
    static let tile: CGFloat = 76
    /// The chosen tile's outline.
    static let outline: CGFloat = 2
}

#Preview {
    NavigationStack {
        AssistantWardrobeView()
    }
}
