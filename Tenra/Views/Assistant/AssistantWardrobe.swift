//
//  AssistantWardrobe.swift
//  Tenra
//
//  What Ten wears (DesignKit 4.12, the owner's plan: events and a wardrobe). On a holiday it
//  dresses up on its own: a party hat from New Year's Eve to 2 January, a taqiya for Nauryz
//  (21 to 23 March); on a day it celebrated a reply with the person it wears a crown. Any other
//  day it wears what the person chose in Ten's wardrobe (a hanger at the top right of the
//  assistant's home), or nothing.
//
//  Unlocking (the owner's scheme): glasses, headphones and the beanie from the start; sunglasses
//  for 7 days in a row in Tenra and the sleep mask for 30 (AppStreak); the party hat for a first
//  goal, the crown for a goal reached; the taqiya on Nauryz. Once open, an accessory stays open
//  (a deleted goal does not lock it again). The holidays and the crown day dress Ten whatever is
//  open; the wardrobe shows the rest dim, with a lock and what opens it.
//

import SwiftUI

enum AssistantWardrobe {
    /// The person's choice: a `CreatureAccessory`'s raw value, empty for nothing.
    static let choiceKey = "assistant.accessory"
    /// The day Ten last celebrated with the person, `yyyy-MM-dd` (AssistantChatter.dayKey).
    static let crownDayKey = "assistant.crownDay"
    /// The accessories already opened, their raw values joined by commas.
    static let unlockedKey = "assistant.wardrobe.unlocked"

    /// What opens an accessory.
    enum Requirement: Equatable {
        case open
        case streak(Int)
        case firstGoal
        case goalReached
        case nauryz
    }

    static func requirement(_ accessory: CreatureAccessory) -> Requirement {
        switch accessory {
        case .glasses, .headphones, .beanie: .open
        case .sunglasses: .streak(7)
        case .sleepMask: .streak(30)
        case .partyHat: .firstGoal
        case .crown: .goalReached
        case .taqiya: .nauryz
        }
    }

    /// What is open now, given what was opened before: newly met requirements join it.
    static func unlocked(remembered: Set<String>, bestStreak: Int, hasGoal: Bool, hasReachedGoal: Bool,
                         at date: Date, calendar: Calendar = .current) -> Set<String> {
        var open = remembered
        for accessory in CreatureAccessory.allCases {
            let met: Bool
            switch requirement(accessory) {
            case .open: met = true
            case .streak(let days): met = bestStreak >= days
            case .firstGoal: met = hasGoal
            case .goalReached: met = hasReachedGoal
            case .nauryz: met = holiday(at: date, calendar: calendar) == .taqiya
            }
            if met { open.insert(accessory.rawValue) }
        }
        return open
    }

    /// The stored set, and back.
    static func decode(_ stored: String) -> Set<String> {
        Set(stored.split(separator: ",").map(String.init))
    }

    static func encode(_ open: Set<String>) -> String {
        open.sorted().joined(separator: ",")
    }

    /// What opens a locked accessory, for its tile.
    static func condition(_ accessory: CreatureAccessory) -> String {
        switch requirement(accessory) {
        case .open: ""
        case .streak(7): String(localized: "assistant.wardrobe.lock.streak7")
        case .streak: String(localized: "assistant.wardrobe.lock.streak30")
        case .firstGoal: String(localized: "assistant.wardrobe.lock.firstGoal")
        case .goalReached: String(localized: "assistant.wardrobe.lock.goalReached")
        case .nauryz: String(localized: "assistant.wardrobe.lock.nauryz")
        }
    }

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

/// Ten's wardrobe, from the assistant's home (the owner's review on a device): Ten trying on the
/// accessory in the middle of a carousel under it, its name and what opens it, then the
/// carousel. Scrolling puts an open accessory on at once and only tries a locked one on. The
/// condition sits under Ten, not on a card, so a long one wraps in full; the cards are all one
/// size (Ten, room for a two-line name, a lock when closed).
struct AssistantWardrobeView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @AppStorage(AssistantWardrobe.choiceKey) private var choice = ""
    @AppStorage(AssistantWardrobe.unlockedKey) private var unlockedStored = ""
    @AppStorage(AppStreak.bestKey) private var bestStreak = 0
    /// The card in the middle of the carousel, by `key(_:)`; it starts on what Ten wears.
    @State private var focused: String?
    @State private var carouselWidth: CGFloat = 0

    private let options: [CreatureAccessory?] = [nil] + CreatureAccessory.allCases

    init() {
        let worn = UserDefaults.standard.string(forKey: AssistantWardrobe.choiceKey) ?? ""
        _focused = State(initialValue: Self.key(CreatureAccessory(rawValue: worn)))
    }

    /// A card's id in the carousel, and back.
    private static func key(_ accessory: CreatureAccessory?) -> String {
        accessory?.rawValue ?? "none"
    }

    private static func accessory(_ key: String?) -> CreatureAccessory? {
        key.flatMap(CreatureAccessory.init(rawValue:))
    }

    private var tryingOn: CreatureAccessory? { Self.accessory(focused) }

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                ParticleCreature(mood: tryingOn == .sleepMask ? .asleep : .happy, isInteractive: true,
                                 accessory: tryingOn)
                    .frame(width: WardrobeMetrics.preview, height: WardrobeMetrics.preview)
                    .frame(maxWidth: .infinity)

                details
                    .padding(.horizontal, AppSpacing.lg)

                carousel

                Text(String(localized: "assistant.wardrobe.footer"))
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.Text.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppSpacing.lg)
            }
            .padding(.vertical, AppSpacing.lg)
        }
        .background(AppColors.Background.baseAlt)
        .navigationTitle(String(localized: "assistant.wardrobe.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshUnlocked() }
        .onChange(of: focused) { _, key in
            HapticManager.selection()
            let accessory = Self.accessory(key)
            if isOpen(accessory) { choice = accessory?.rawValue ?? "" }
        }
    }

    /// The name of what Ten tries on and, when it is locked, what opens it: large, in the
    /// accent, wrapping in full however long it is. Two lines are kept for it, so a short one
    /// does not move the carousel.
    private var details: some View {
        VStack(spacing: AppSpacing.xs) {
            Text(AssistantWardrobe.name(tryingOn))
                .font(AppTypography.h4)
                .foregroundStyle(AppColors.Text.primary)
                .multilineTextAlignment(.center)
            ZStack(alignment: .top) {
                Self.reservedLines(WardrobeMetrics.lines, font: AppTypography.bodyEmphasis)
                if let tryingOn, !isOpen(tryingOn) {
                    Label(AssistantWardrobe.condition(tryingOn), systemImage: "lock.fill")
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(AppColors.accent)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// The cards side by side, the one in the middle full size, the others a little smaller
    /// and paler.
    private var carousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: AppSpacing.md) {
                ForEach(options, id: \.self) { option in
                    card(option)
                        .id(Self.key(option))
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            content
                                .scaleEffect(phase.isIdentity ? 1 : WardrobeMetrics.sideScale)
                                .opacity(phase.isIdentity ? 1 : WardrobeMetrics.sideOpacity)
                        }
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, max(0, (carouselWidth - WardrobeMetrics.cardWidth) / 2), for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $focused, anchor: .center)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { carouselWidth = $0 }
    }

    private func card(_ option: CreatureAccessory?) -> some View {
        let isWorn = (option?.rawValue ?? "") == choice
        let isOpen = isOpen(option)
        return Button {
            withAnimation(AppAnimation.contentSpring) { focused = Self.key(option) }
        } label: {
            VStack(spacing: AppSpacing.sm) {
                ParticleCreature(mood: option == .sleepMask ? .asleep : .idle, accessory: option)
                    .frame(width: WardrobeMetrics.cardMascot, height: WardrobeMetrics.cardMascot)
                    .designKitMotion(false)
                    .opacity(isOpen ? 1 : WardrobeMetrics.lockedOpacity)
                ZStack(alignment: .top) {
                    Self.reservedLines(WardrobeMetrics.lines, font: AppTypography.bodyEmphasis)
                    Text(AssistantWardrobe.name(option))
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(isWorn ? AppColors.accent : AppColors.Text.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(WardrobeMetrics.lines)
                }
            }
            .padding(AppSpacing.md)
            .frame(width: WardrobeMetrics.cardWidth)
            .background(RoundedRectangle(cornerRadius: AppRadius.lg).fill(AppColors.Background.elevation1))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg)
                    .stroke(isWorn ? AppColors.accent : Color.clear, lineWidth: WardrobeMetrics.outline)
            )
            .overlay(alignment: .topTrailing) {
                if !isOpen {
                    Image(systemName: "lock.fill")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.Text.secondary)
                        .padding(AppSpacing.sm)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AssistantWardrobe.name(option))
        .accessibilityValue(option.map { isOpen ? "" : String(localized: "assistant.wardrobe.locked") + ", " + AssistantWardrobe.condition($0) } ?? "")
        .accessibilityAddTraits(isWorn ? [.isButton, .isSelected] : .isButton)
    }

    /// Room for `count` lines of `font`, empty: the text over it never makes its box taller or
    /// shorter than that.
    private static func reservedLines(_ count: Int, font: Font) -> some View {
        Text(verbatim: Array(repeating: " ", count: count).joined(separator: "\n"))
            .font(font)
            .hidden()
            .accessibilityHidden(true)
    }

    /// What is open: what was opened before, the person's choice (kept open), and what the
    /// streak and the goals open now, remembered for next time.
    private func refreshUnlocked() async {
        let goals = coordinator.goalStore
        await goals.load()
        var remembered = AssistantWardrobe.decode(unlockedStored)
        if !choice.isEmpty { remembered.insert(choice) }
        let open = AssistantWardrobe.unlocked(
            remembered: remembered,
            bestStreak: bestStreak,
            hasGoal: !goals.goals.isEmpty,
            hasReachedGoal: goals.goals.contains { $0.reachedAt != nil },
            at: .now
        )
        let stored = AssistantWardrobe.encode(open)
        if stored != unlockedStored { unlockedStored = stored }
    }

    private func isOpen(_ option: CreatureAccessory?) -> Bool {
        guard let option else { return true }
        return option.rawValue == choice
            || AssistantWardrobe.requirement(option) == .open
            || AssistantWardrobe.decode(unlockedStored).contains(option.rawValue)
    }
}

private enum WardrobeMetrics {
    /// Ten trying on, and Ten on each card.
    static let preview: CGFloat = 200
    static let cardMascot: CGFloat = 96
    /// A card's width; two lines kept for its name and for the condition under Ten.
    static let cardWidth: CGFloat = 150
    static let lines = 2
    /// The cards beside the middle one.
    static let sideScale: CGFloat = 0.9
    static let sideOpacity: Double = 0.75
    /// The worn card's outline.
    static let outline: CGFloat = 2
    /// Ten in a locked accessory on its card.
    static let lockedOpacity: Double = 0.4
}

#Preview {
    NavigationStack {
        AssistantWardrobeView()
    }
}
