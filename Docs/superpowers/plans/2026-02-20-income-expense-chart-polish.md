# IncomeExpenseChart Visual Polish Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Улучшить внешний вид обоих chart-компонентов в `IncomeExpenseChart.swift`: добавить glow столбикам, capsule corner radius, trailing padding от Y-оси, и компактные X-метки (3 chars + год если не текущий).

**Architecture:** Все изменения — в одном файле `IncomeExpenseChart.swift`. Два struct — `IncomeExpenseChart` (legacy, `MonthlyDataPoint` + `Date` X-ось) и `PeriodIncomeExpenseChart` (основной, `PeriodDataPoint` + `String` X-ось). Оба получают одинаковые визуальные улучшения. Compact-режим (`compact: true`) изменений не получает (только full-size).

**Tech Stack:** Swift Charts (`import Charts`), SwiftUI, `AppRadius.circle` (= `.infinity`), `AppSpacing.md` (= 12pt), `AppColors.success/destructive`.

---

### Task 1: `IncomeExpenseChart` — гlоw + corner radius + trailing padding + compact date labels

**Files:**
- Modify: `AIFinanceManager/Views/Insights/Charts/IncomeExpenseChart.swift`

**Step 1: Добавить glow и cornerRadius к BarMark-ам**

В `chartContent` (строки 27-43) изменить оба BarMark, добавив `.cornerRadius(AppRadius.circle)` и `.shadow(...)`:

```swift
Chart(dataPoints) { point in
    BarMark(
        x: .value("Month", point.month),
        y: .value("Amount", point.income),
        width: compact ? 6 : 12
    )
    .cornerRadius(AppRadius.circle)
    .foregroundStyle(AppColors.success.opacity(0.85))
    .shadow(color: AppColors.success.opacity(0.35), radius: 4, x: 0, y: 2)
    .position(by: .value("Type", "Income"))

    BarMark(
        x: .value("Month", point.month),
        y: .value("Amount", point.expenses),
        width: compact ? 6 : 12
    )
    .cornerRadius(AppRadius.circle)
    .foregroundStyle(AppColors.destructive.opacity(0.85))
    .shadow(color: AppColors.destructive.opacity(0.35), radius: 4, x: 0, y: 2)
    .position(by: .value("Type", "Expenses"))
}
```

Порядок модификаторов: `.cornerRadius` → `.foregroundStyle` → `.shadow` → `.position`. `.position` всегда последний.

**Step 2: Добавить trailing padding к plot area (только non-compact)**

После `.chartLegend(...)` в `chartContent` добавить:

```swift
.chartPlotStyle { content in
    if compact {
        content
    } else {
        content.padding(.trailing, AppSpacing.md)
    }
}
```

Место вставки — после `.chartLegend(compact ? .hidden : .automatic)`, перед `.frame(...)`.

**Step 3: Добавить helper `formatAxisDate`**

В конец struct `IncomeExpenseChart` (после `formatCompact`) добавить приватный метод:

```swift
/// Форматирует дату для X-оси: 3 chars uppercase + год если не текущий.
/// Пример: "ЯНВ" (текущий год), "ЯНВ'24" (другой год).
private func formatAxisDate(_ date: Date) -> String {
    let calendar = Calendar.current
    let currentYear = calendar.component(.year, from: Date())
    let dateYear = calendar.component(.year, from: date)

    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.dateFormat = "MMM"
    let month = String(formatter.string(from: date).uppercased().prefix(3))

    if dateYear == currentYear {
        return month
    } else {
        return "\(month)'\(String(format: "%02d", dateYear % 100))"
    }
}
```

**Step 4: Заменить X-axis label format на кастомный**

В `.chartXAxis` заменить:
```swift
// ДО:
AxisMarks(values: .stride(by: .month)) { _ in
    AxisValueLabel(format: .dateTime.month(.abbreviated))
}

// ПОСЛЕ:
AxisMarks(values: .stride(by: .month)) { value in
    AxisValueLabel {
        if let date = value.as(Date.self) {
            Text(formatAxisDate(date))
                .font(AppTypography.caption2)
        }
    }
}
```

---

### Task 2: `PeriodIncomeExpenseChart` — glow + corner radius + trailing padding + compact period labels

**Files:**
- Modify: `AIFinanceManager/Views/Insights/Charts/IncomeExpenseChart.swift`

**Step 1: Добавить glow и cornerRadius к BarMark-ам**

В `chartContent` (строки 135-150) изменить оба BarMark:

```swift
Chart(dataPoints) { point in
    BarMark(
        x: .value("Period", point.label),
        y: .value("Income", point.income),
        width: .fixed(compact ? 6 : max(8, pointWidth * 0.38))
    )
    .cornerRadius(AppRadius.circle)
    .foregroundStyle(AppColors.success.opacity(0.85))
    .shadow(color: AppColors.success.opacity(0.35), radius: 4, x: 0, y: 2)
    .position(by: .value("Type", "Income"))

    BarMark(
        x: .value("Period", point.label),
        y: .value("Expenses", point.expenses),
        width: .fixed(compact ? 6 : max(8, pointWidth * 0.38))
    )
    .cornerRadius(AppRadius.circle)
    .foregroundStyle(AppColors.destructive.opacity(0.85))
    .shadow(color: AppColors.destructive.opacity(0.35), radius: 4, x: 0, y: 2)
    .position(by: .value("Type", "Expenses"))
}
```

**Step 2: Добавить trailing padding к plot area (только non-compact)**

После `.chartLegend(compact ? .hidden : .automatic)` в `chartContent` добавить:

```swift
.chartPlotStyle { content in
    if compact {
        content
    } else {
        content.padding(.trailing, AppSpacing.md)
    }
}
```

**Step 3: Добавить computed property `axisLabelMap` и helper `compactPeriodLabel`**

Добавить два вычисляемых члена в struct `PeriodIncomeExpenseChart` (после `formatCompact`):

```swift
/// Маппинг полный label → компактный label для X-оси.
/// Вычисляется из dataPoints один раз при создании View-структуры.
/// Гранулярность берётся из каждого PeriodDataPoint.
private var axisLabelMap: [String: String] {
    let calendar = Calendar.current
    let currentYear = calendar.component(.year, from: Date())
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.dateFormat = "MMM"
    return Dictionary(
        uniqueKeysWithValues: dataPoints.map { point in
            (point.label, compactPeriodLabel(point: point,
                                             calendar: calendar,
                                             currentYear: currentYear,
                                             formatter: formatter))
        }
    )
}

/// Возвращает компактный лейбл для X-оси в зависимости от гранулярности.
/// .month  → "ЯНВ" / "ЯНВ'25"
/// .week   → "W07" / "W07'25"
/// .quarter → "Q1" / "Q1'25"
/// .year   → "2025" (полный)
/// .allTime → оригинал
private func compactPeriodLabel(
    point: PeriodDataPoint,
    calendar: Calendar,
    currentYear: Int,
    formatter: DateFormatter
) -> String {
    let pointYear = calendar.component(.year, from: point.periodStart)
    let shortYear = String(format: "%02d", pointYear % 100)

    switch point.granularity {
    case .month:
        let month = String(formatter.string(from: point.periodStart).uppercased().prefix(3))
        return pointYear == currentYear ? month : "\(month)'\(shortYear)"

    case .week:
        let weekNum = calendar.component(.weekOfYear, from: point.periodStart)
        return pointYear == currentYear
            ? String(format: "W%02d", weekNum)
            : String(format: "W%02d'\(shortYear)", weekNum)

    case .quarter:
        let month = calendar.component(.month, from: point.periodStart)
        let quarter = (month - 1) / 3 + 1
        return pointYear == currentYear ? "Q\(quarter)" : "Q\(quarter)'\(shortYear)"

    case .year:
        return "\(pointYear)"

    case .allTime:
        return point.label
    }
}
```

**Step 4: Заменить X-axis labels на компактные**

В `.chartXAxis` заменить:
```swift
// ДО:
AxisMarks { value in
    AxisValueLabel {
        if let label = value.as(String.self) {
            Text(label)
                .font(AppTypography.caption2)
                .lineLimit(1)
        }
    }
}

// ПОСЛЕ:
AxisMarks { value in
    AxisValueLabel {
        if let label = value.as(String.self) {
            Text(axisLabelMap[label] ?? label)
                .font(AppTypography.caption2)
                .lineLimit(1)
        }
    }
}
```

---

### Итог изменений

| Что | Где | Константа |
|-----|-----|-----------|
| Corner radius infinite | BarMark (оба чарта) | `AppRadius.circle` |
| Glow income | BarMark income (оба чарта) | `AppColors.success.opacity(0.35)`, radius 4 |
| Glow expenses | BarMark expenses (оба чарта) | `AppColors.destructive.opacity(0.35)`, radius 4 |
| Trailing padding | chartPlotStyle (non-compact) | `AppSpacing.md` (12pt) |
| Compact date X-label | IncomeExpenseChart | `formatAxisDate(_:)` |
| Compact period X-label | PeriodIncomeExpenseChart | `axisLabelMap` + `compactPeriodLabel(...)` |
| Локализация дат | Оба чарта | `DateFormatter(locale: .current)` |

### Проверка

После реализации убедиться визуально (Xcode Preview):
1. `#Preview("Full income/expense chart (legacy)")` — столбики capsule, с glow, дата без года "ЯНВ"/"JAN"
2. `#Preview("PeriodIncomeExpenseChart — Monthly")` — то же + компактные метки
3. Compact preview — без изменений (glow/radius должны быть, padding/labels — нет)
4. Собрать проект: `xcodebuild build -scheme AIFinanceManager -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
