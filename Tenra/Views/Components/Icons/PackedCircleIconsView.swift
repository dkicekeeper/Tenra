//
//  PackedCircleIconsView.swift
//  AIFinanceManager
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
}

// MARK: - Main View

struct PackedCircleIconsView: View {
    let items: [PackedCircleItem]
    var maxVisible: Int = 5
    var containerWidth: CGFloat = AppSize.subscriptionCardWidth

    @State private var packedCircles: [PackedCircle] = []
    @State private var isBreathing = false

    private let containerHeight: CGFloat = 100
    private let borderWidth: CGFloat = 2

    private var visible: [PackedCircleItem] {
        Array(items.prefix(maxVisible))
    }

    private var overflowCount: Int {
        max(0, items.count - maxVisible)
    }

    /// Key for recalculation when items change.
    private var layoutKey: String {
        visible.map { "\($0.id):\($0.amount)" }.joined(separator: ",")
        + (overflowCount > 0 ? ",+\(overflowCount)" : "")
    }

    var body: some View {
        ZStack {
            ForEach(Array(packedCircles.enumerated()), id: \.element.id) { index, circle in
                if index < visible.count {
                    PackedCircleIcon(
                        iconSource: visible[index].iconSource,
                        diameter: circle.diameter,
                        borderWidth: borderWidth,
                        isBreathing: isBreathing,
                        breathingIndex: index,
                        animationDelay: Double(index) * AppAnimation.facepileStagger
                    )
                    .offset(x: circle.x, y: circle.y)
                } else {
                    // Overflow badge
                    PackedOverflowBadge(
                        count: overflowCount,
                        diameter: circle.diameter,
                        borderWidth: borderWidth,
                        animationDelay: Double(index) * AppAnimation.facepileStagger
                    )
                    .offset(x: circle.x, y: circle.y)
                }
            }
        }
        .frame(width: containerWidth, height: containerHeight)
        .task(id: layoutKey) {
            recalculateLayout()
            // Start breathing after entrance animations settle
            if !AppAnimation.isReduceMotionEnabled {
                try? await Task.sleep(for: .milliseconds(
                    Int(Double(packedCircles.count) * AppAnimation.facepileStagger * 1000 + 400)
                ))
                isBreathing = true
            }
        }
    }

    // MARK: - Layout

    private func recalculateLayout() {
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

        packedCircles = CirclePackingLayout.pack(
            ids: ids,
            diameters: diameters,
            containerWidth: containerWidth,
            containerHeight: containerHeight
        )
        isBreathing = false
    }
}

// MARK: - Packed Circle Icon

private struct PackedCircleIcon: View {
    let iconSource: IconSource?
    let diameter: CGFloat
    let borderWidth: CGFloat
    let isBreathing: Bool
    let breathingIndex: Int
    let animationDelay: Double

    private var iconStyle: IconStyle {
        switch iconSource {
        case .sfSymbol:
            return .circle(size: diameter, tint: .accentMonochrome, backgroundColor: AppColors.surface)
        case .brandService, .none:
            return .circle(size: diameter, tint: .original)
        }
    }

    var body: some View {
        IconView(source: iconSource, style: iconStyle)
            .overlay(Circle().stroke(.background, lineWidth: borderWidth))
            .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
            .scaleEffect(isBreathing ? AppAnimation.breathingScale : 1.0)
            .animation(
                isBreathing
                    ? AppAnimation.breathingAnimation(index: breathingIndex)
                    : .default,
                value: isBreathing
            )
            .staggeredEntrance(delay: animationDelay)
    }
}

// MARK: - Overflow Badge

private struct PackedOverflowBadge: View {
    let count: Int
    let diameter: CGFloat
    let borderWidth: CGFloat
    let animationDelay: Double

    var body: some View {
        ZStack {
            Circle().fill(.quaternary)
            Text("+\(count)")
                .font(.system(size: diameter * 0.35, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(width: diameter, height: diameter)
        .overlay(Circle().stroke(.background, lineWidth: borderWidth))
        .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
        .staggeredEntrance(delay: animationDelay)
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
