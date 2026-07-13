# Design: Views/Components Reorganization

**Date:** 2026-03-11
**Status:** Approved

## Goal

Reorganize all reusable UI components into `Views/Components/` with 9 logical subfolders. Improves Xcode navigation and makes architecture self-documenting.

## Scope

**60 files total** moved into `Views/Components/` with subdirectory structure.

Sources:
- `Views/Components/` — 36 existing files (restructured into subfolders)
- `Views/Transactions/Components/` — 4 files
- `Views/Subscriptions/Components/` — 4 files
- `Views/Subscriptions/` — 1 file (SubscriptionsCardView)
- `Views/Insights/Components/` — 15 files

Not moved: full screens, modals, coordinators in feature folders (AccountEditView, TransactionEditView, etc.)

## Target Structure

```
Views/Components/
├── Cards/           (8 files)  — standalone visual card blocks
├── Rows/            (9 files)  — list and form row views
├── Forms/           (5 files)  — form containers and layout helpers
├── Icons/           (4 files)  — icon display and picking
├── Input/           (13 files) — interactive input, pickers, filters, carousels
├── Charts/          (5 files)  — data visualization and progress indicators
├── Headers/         (5 files)  — section headers and hero displays
├── Feedback/        (7 files)  — banners, badges, status text
└── Skeleton/        (3 files)  — loading state infrastructure
```

## File Mapping

### Cards/
| File | Source |
|------|--------|
| AnalyticsCard.swift | Components/ |
| InsightsCardView.swift | Insights/Components/ |
| PeriodComparisonCard.swift | Insights/Components/ |
| SubscriptionCard.swift | Subscriptions/Components/ |
| SubscriptionsCardView.swift | Subscriptions/ |
| TransactionCard.swift | Transactions/Components/ |
| TransactionCardComponents.swift | Transactions/Components/ |
| TransactionsSummaryCard.swift | Components/ |

### Rows/
| File | Source |
|------|--------|
| BudgetProgressRow.swift | Insights/Components/ |
| ColorPickerRow.swift | Components/ |
| DatePickerRow.swift | Components/ |
| FormLabeledRow.swift | Components/ |
| InfoRow.swift | Components/ |
| InsightsTotalsRow.swift | Insights/Components/ |
| MenuPickerRow.swift | Components/ |
| PeriodBreakdownRow.swift | Insights/Components/ |
| UniversalRow.swift | Components/ |

### Forms/
| File | Source |
|------|--------|
| BudgetSettingsSection.swift | Components/ |
| EditSheetContainer.swift | Components/ |
| EditableHeroSection.swift | Components/ |
| FormSection.swift | Components/ |
| FormTextField.swift | Components/ |

### Icons/
| File | Source |
|------|--------|
| IconPickerView.swift | Components/ |
| IconView.swift | Components/ |
| IconView+Previews.swift | Components/ |
| StaticSubscriptionIconsView.swift | Subscriptions/Components/ |

### Input/
| File | Source |
|------|--------|
| AmountInputView.swift | Transactions/Components/ |
| AnimatedAmountInput.swift | Components/ |
| AnimatedInputComponents.swift | Components/ |
| CategoryGridView.swift | Components/ |
| CurrencySelectorView.swift | Components/ |
| DateButtonsView.swift | Components/ |
| FormattedAmountText.swift | Components/ |
| FormattedAmountView.swift | Transactions/Components/ |
| InsightsGranularityPicker.swift | Insights/Components/ |
| SegmentedPickerView.swift | Components/ |
| SubscriptionCalendarView.swift | Subscriptions/Components/ |
| UniversalCarousel.swift | Components/ |
| UniversalFilterButton.swift | Components/ |

### Charts/
| File | Source |
|------|--------|
| BudgetProgressBar.swift | Insights/Components/ |
| BudgetProgressCircle.swift | Components/ |
| DonutChart.swift | Insights/Components/ |
| PeriodBarChart.swift | Insights/Components/ |
| PeriodLineChart.swift | Insights/Components/ |

### Headers/
| File | Source |
|------|--------|
| DateSectionHeaderView.swift | Components/ |
| HeroSection.swift | Components/ |
| InsightsSectionView.swift | Insights/Components/ |
| InsightsSummaryHeader.swift | Insights/Components/ |
| SectionHeaderView.swift | Components/ |

### Feedback/
| File | Source |
|------|--------|
| HealthScoreBadge.swift | Insights/Components/ |
| HighlightedText.swift | Components/ |
| InlineStatusText.swift | Components/ |
| InsightTrendBadge.swift | Insights/Components/ |
| MessageBanner.swift | Components/ |
| NotificationPermissionView.swift | Subscriptions/Components/ |
| StatusIndicatorBadge.swift | Components/ |

### Skeleton/
| File | Source |
|------|--------|
| InsightsSkeletonComponents.swift | Components/ |
| SkeletonLoadingModifier.swift | Components/ |
| SkeletonView.swift | Components/ |

## Technical Notes

- **Swift imports**: No changes needed — files are in the same module target
- **Xcode project file**: `.xcodeproj/project.pbxproj` must be updated — file group references change for all 60 files
- **File content**: No code changes required (file paths don't affect Swift compilation within same target)
- **CLAUDE.md**: Update `Views/Components/` description to list 9 subfolders, remove "no extra nesting" note

## What Stays in Feature Folders

Full screens, modals, coordinators remain untouched:
- `Accounts/`: AccountEditView, AccountsManagementView, AccountActionView
- `Transactions/`: TransactionAddModal, TransactionEditView, coordinators
- `Subscriptions/`: SubscriptionDetailView, SubscriptionEditView, SubscriptionsListView
- `Insights/`: InsightsView, InsightDetailView, CategoryDeepDiveView, InsightsSummaryDetailView
- `Categories/`, `Deposits/`, `Loans/`, `History/`, `Settings/`, `VoiceInput/`, `CSV/`, `Import/`, `Home/`
