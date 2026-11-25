//
//  AssistantWardrobeView.swift
//  Tenra
//
//  Ten's wardrobe screen. The catalogue and its rules are AssistantWardrobe, the state
//  (what is worn, what is open, the record streak) TenWardrobeStore, both in Services/Agent.
//

import SwiftUI

/// Ten's wardrobe, from the assistant's home (the owner's review on a device): Ten trying on the
/// accessory in the middle of DesignKit's PickerCarousel (4.14.0) under it, its name and what
/// opens it, then the cards. Scrolling puts an open accessory on at once and only tries a locked
/// one on. The cards are all one size (Ten, still, with room for a two-line name, a lock when
/// closed).
struct AssistantWardrobeView: View {
    @Environment(AppCoordinator.self) private var coordinator
    /// The card in the middle of the carousel, by `key(_:)`; it starts on what Ten wears.
    @State private var focused: String?

    /// An accessory, or none, as a card of the carousel.
    private struct Option: Identifiable {
        let accessory: CreatureAccessory?
        var id: String { AssistantWardrobeView.key(accessory) }
    }

    private let options: [Option] = {
        let all: [CreatureAccessory?] = [nil] + CreatureAccessory.allCases
        return all.map { Option(accessory: $0) }
    }()

    init() {
        let worn = TenWardrobeStore.storedChoice()
        _focused = State(initialValue: Self.key(CreatureAccessory(rawValue: worn)))
    }

    /// A card's id in the carousel, and back.
    fileprivate static func key(_ accessory: CreatureAccessory?) -> String {
        accessory?.rawValue ?? "none"
    }

    private static func accessory(_ key: String?) -> CreatureAccessory? {
        key.flatMap(CreatureAccessory.init(rawValue:))
    }

    private var tryingOn: CreatureAccessory? { Self.accessory(focused) }

    private var wardrobe: TenWardrobeStore { coordinator.tenWardrobe }

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                ParticleCreature(mood: tryingOn == .sleepMask ? .asleep : .happy, isInteractive: true,
                                 accessory: tryingOn)
                    .frame(width: WardrobeMetrics.preview, height: WardrobeMetrics.preview)
                    .frame(maxWidth: .infinity)

                PickerCarousel(
                    items: options,
                    focused: $focused,
                    chosen: Self.key(CreatureAccessory(rawValue: wardrobe.choice)),
                    title: { AssistantWardrobe.name($0.accessory) },
                    condition: { option in
                        guard let accessory = option.accessory, !wardrobe.isOpen(accessory) else { return nil }
                        return Self.condition(accessory, progress: wardrobe.progress(accessory))
                    },
                    lockedLabel: String(localized: "assistant.wardrobe.locked")
                ) { option in
                    ParticleCreature(mood: option.accessory == .sleepMask ? .asleep : .idle, accessory: option.accessory)
                }

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
        .task {
            await coordinator.refreshTenWardrobe()
            // What is open now has been shown: the hanger's dot goes.
            wardrobe.markSeen()
        }
        .onChange(of: focused) { _, key in
            HapticManager.selection()
            wardrobe.choose(Self.accessory(key))
        }
    }

    /// What opens a locked accessory, and for a run of days how far the current run is
    /// ("7 days in a row with a record · 4 of 7").
    static func condition(_ accessory: CreatureAccessory, progress: (days: Int, of: Int)?) -> String {
        let condition = AssistantWardrobe.condition(accessory)
        guard let progress else { return condition }
        let count = String(format: String(localized: "assistant.wardrobe.progress"), progress.days, progress.of)
        return "\(condition) · \(count)"
    }
}

private enum WardrobeMetrics {
    /// Ten trying on, above the carousel.
    static let preview: CGFloat = 200
}

#Preview {
    NavigationStack {
        AssistantWardrobeView()
    }
}
