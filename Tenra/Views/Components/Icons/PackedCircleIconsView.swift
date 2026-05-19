//
//  PackedCircleIconsView.swift
//  Tenra
//
//  Packed circle layout for subscription/loan icon display.
//  Circle size reflects item cost; circles are tightly packed without overlap.
//

import SwiftUI

// MARK: - Data Model

struct PackedCircleItem: Identifiable {
    let id: String
    let iconSource: IconSource?
    let amount: Double
    /// Optional monochrome tint for SF symbol items (e.g. category color).
    /// Brand-service items always render with `.original` tint regardless.
    let tint: Color?

    init(id: String, iconSource: IconSource?, amount: Double, tint: Color? = nil) {
        self.id = id
        self.iconSource = iconSource
        self.amount = amount
        self.tint = tint
    }
}

// MARK: - Main View

struct PackedCircleIconsView: View {
    let items: [PackedCircleItem]
    var maxVisible: Int = 5
    var containerWidth: CGFloat = 120

    private let containerHeight: CGFloat = 100
    private let borderWidth: CGFloat = 1

    private var visible: [PackedCircleItem] {
        Array(items.prefix(maxVisible))
    }

    private var overflowCount: Int {
        max(0, items.count - maxVisible)
    }

    /// Packed layout — derived **synchronously** from `items`, not stored in `@State`.
    ///
    /// `CirclePackingLayout.pack` is pure geometry with no SwiftUI dependency and is
    /// cheap for ≤6 circles, so it is safe to compute in `body`. Doing it here (rather
    /// than mutating `@State` from a `.task`) means every render already has the final
    /// positions: icons are never inserted with one layout and then repositioned when
    /// balances / currency conversions finish loading. That async "insert → recompute →
    /// move" was what let the icon positions get caught in an ambient animation
    /// transaction and visibly slide across the card on every Finances-tab open.
    private var packedCircles: [PackedCircle] {
        var amounts = visible.map(\.amount)
        var ids = visible.map(\.id)

        // Add overflow badge as smallest circle
        if overflowCount > 0 {
            amounts.append(0) // Will get minDiameter
            ids.append("__overflow__")
        }

        let diameters: [CGFloat]
        if overflowCount > 0 {
            // Compute diameters for visible items, force badge to minDiameter
            var d = CirclePackingLayout.diameters(for: Array(amounts.dropLast()))
            d.append(CirclePackingLayout.minDiameter)
            diameters = d
        } else {
            diameters = CirclePackingLayout.diameters(for: amounts)
        }

        return CirclePackingLayout.pack(
            ids: ids,
            diameters: diameters,
            containerWidth: containerWidth,
            containerHeight: containerHeight
        )
    }

    var body: some View {
        ZStack {
            ForEach(Array(packedCircles.enumerated()), id: \.element.id) { index, circle in
                let target = CGSize(width: circle.x, height: circle.y)
                if index < visible.count {
                    PackedCircleIcon(
                        iconSource: visible[index].iconSource,
                        tintOverride: visible[index].tint,
                        diameter: circle.diameter,
                        borderWidth: borderWidth,
                        animationDelay: Double(index) * AppAnimation.facepileStagger,
                        targetOffset: target
                    )
                } else {
                    // Overflow badge
                    PackedOverflowBadge(
                        count: overflowCount,
                        diameter: circle.diameter,
                        borderWidth: borderWidth,
                        animationDelay: Double(index) * AppAnimation.facepileStagger,
                        targetOffset: target
                    )
                }
            }
        }
        .frame(width: containerWidth, height: containerHeight)
    }
}

// MARK: - Packed Circle Icon

private struct PackedCircleIcon: View {
    let iconSource: IconSource?
    let tintOverride: Color?
    let diameter: CGFloat
    let borderWidth: CGFloat
    let animationDelay: Double
    let targetOffset: CGSize

    @State private var hasAppeared = false

    /// Adaptive padding for packed-circle SF symbols. IconView's default curve
    /// gives ~10% on the 28-44pt bracket, which at our small packed diameters
    /// reads as no padding at all (especially with the 2pt outer stroke). We
    /// bump the curve so SF symbols always have visible breathing room inside
    /// their circle background, matching the spirit of IconView's padding rules.
    private var sfSymbolPadding: CGFloat {
        switch diameter {
        case ..<32:   return diameter * 0.18
        case 32..<48: return diameter * 0.22
        default:      return diameter * 0.26
        }
    }

    private var iconStyle: IconStyle {
        switch iconSource {
        case .sfSymbol:
            let tint: IconTint = tintOverride.map { .monochrome($0) } ?? .accentMonochrome
            return .circle(
                size: diameter,
                tint: tint,
                backgroundColor: AppColors.bgCard,
                padding: sfSymbolPadding
            )
        case .brandService, .none:
            // Brand logos render edge-to-edge by IconView convention — they
            // already include their own internal padding/whitespace.
            return .circle(size: diameter, tint: .original)
        }
    }

    var body: some View {
        IconView(source: iconSource, style: iconStyle)
            .overlay(Circle().strokeBorder(.background, lineWidth: borderWidth))
            // Entrance animates scale + opacity only — a staggered pop-in, no slide.
            .scaleEffect(hasAppeared ? 1 : AppAnimation.facepileHiddenScale)
            .opacity(hasAppeared ? 1 : 0)
            .animation(
                AppAnimation.isReduceMotionEnabled
                    ? .linear(duration: 0)
                    : AppAnimation.facepileSpring.delay(animationDelay),
                value: hasAppeared
            )
            .offset(targetOffset)
            // Position is layout, never animation. The packed layout is recomputed
            // when balances/conversions finish loading; without this, that recompute
            // gets caught in an ambient transaction and the icons visibly slide into
            // place every time the Finances tab opens.
            .animation(nil, value: targetOffset)
            .task { hasAppeared = true }
    }
}

// MARK: - Overflow Badge

private struct PackedOverflowBadge: View {
    let count: Int
    let diameter: CGFloat
    let borderWidth: CGFloat
    let animationDelay: Double
    let targetOffset: CGSize

    @State private var hasAppeared = false

    var body: some View {
        ZStack {
            Circle().fill(.quaternary)
            Text("+\(count)")
                .font(.system(size: diameter * 0.35, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(width: diameter, height: diameter)
        .overlay(Circle().stroke(.background, lineWidth: borderWidth))
        .scaleEffect(hasAppeared ? 1 : AppAnimation.facepileHiddenScale)
        .opacity(hasAppeared ? 1 : 0)
        .animation(
            AppAnimation.isReduceMotionEnabled
                ? .linear(duration: 0)
                : AppAnimation.facepileSpring.delay(animationDelay),
            value: hasAppeared
        )
        .offset(targetOffset)
        .animation(nil, value: targetOffset)
        .task { hasAppeared = true }
    }
}

// MARK: - Previews

#Preview("5 items, varying amounts") {
    let items: [PackedCircleItem] = [
        .init(id: "1", iconSource: .brandService("netflix.com"), amount: 15000),
        .init(id: "2", iconSource: .brandService("spotify.com"), amount: 4990),
        .init(id: "3", iconSource: .sfSymbol("cloud.fill"), amount: 2990),
        .init(id: "4", iconSource: .sfSymbol("gamecontroller.fill"), amount: 1500),
        .init(id: "5", iconSource: .sfSymbol("dumbbell.fill"), amount: 800),
    ]

    VStack(spacing: 20) {
        Text("5 items").font(.caption).foregroundStyle(.secondary)
        PackedCircleIconsView(items: items)
            .border(Color.red.opacity(0.3)) // Debug container bounds
    }
    .padding()
}

#Preview("8 items with overflow") {
    let items: [PackedCircleItem] = (1...8).map { i in
        PackedCircleItem(
            id: "s\(i)",
            iconSource: .sfSymbol(["star.fill","heart.fill","flame.fill","bolt.fill","leaf.fill","music.note","camera.fill","globe"][i - 1]),
            amount: Double(i) * 1000
        )
    }

    VStack(spacing: 20) {
        Text("8 items (+3 overflow)").font(.caption).foregroundStyle(.secondary)
        PackedCircleIconsView(items: items)
            .border(Color.red.opacity(0.3))
    }
    .padding()
}

#Preview("Equal amounts") {
    let items: [PackedCircleItem] = (1...4).map { i in
        PackedCircleItem(id: "e\(i)", iconSource: .sfSymbol("star.fill"), amount: 5000)
    }

    VStack(spacing: 20) {
        Text("Equal amounts (uniform size)").font(.caption).foregroundStyle(.secondary)
        PackedCircleIconsView(items: items)
            .border(Color.red.opacity(0.3))
    }
    .padding()
}

#Preview("Single item") {
    PackedCircleIconsView(items: [
        .init(id: "solo", iconSource: .brandService("netflix.com"), amount: 9990)
    ])
    .border(Color.red.opacity(0.3))
    .padding()
}
