# ✅ Manual Testing Checklist
## AI Finance Manager - Post-Refactoring Testing

**Date**: 15 января 2026
**Status**: ⏳ **Ready for Testing**
**Priority**: P2 (High)
**Estimated Time**: 4-6 hours

---

## 🎯 Testing Goals

После завершения ViewModel Refactoring (99% complete) необходимо протестировать:
1. ✅ Все критические user flows работают корректно
2. ✅ Новая архитектура (AppCoordinator + 5 ViewModels) работает без ошибок
3. ✅ Локализация (EN + RU) отображается правильно
4. ✅ VoiceOver accessibility работает корректно
5. ✅ Нет регрессий после рефакторинга

---

## 📱 Testing Environments

### Required Testing:
- [ ] **iOS Simulator** (iPhone 15 Pro) - для быстрого тестирования
- [ ] **Real Device** (iPhone) - для финального тестирования
- [ ] **English Language** - все флоу на английском
- [ ] **Russian Language** - все флоу на русском
- [ ] **Dark Mode** - переключение темы
- [ ] **VoiceOver** - accessibility тестирование

### Optional Testing:
- [ ] iPad (разные размеры экранов)
- [ ] Older devices (performance testing)
- [ ] Different iOS versions

---

## 🔍 Testing Methodology

### Для каждого флоу:
1. ✅ **Happy Path** - основной сценарий использования
2. ✅ **Edge Cases** - граничные случаи (пустые данные, максимальные значения)
3. ✅ **Error Handling** - некорректные данные, валидация
4. ✅ **Localization** - проверка на обоих языках
5. ✅ **Accessibility** - VoiceOver навигация

---

## 📋 Critical User Flows (Must Test)

### 1. Add Transaction (QuickAdd) ⏳

**Files**: `QuickAddTransactionView.swift`, `TransactionsViewModel.swift`, `CategoriesViewModel.swift`, `AccountsViewModel.swift`

**Test Steps**:
- [ ] Open app → ContentView отображается корректно
- [ ] Tap on category chip → Modal открывается
- [ ] **Amount validation**:
  - [ ] Enter valid amount (e.g., "100.50") → Success
  - [ ] Enter invalid amount (e.g., "abc") → Error message показывается
  - [ ] Enter zero amount (e.g., "0") → Error message показывается
  - [ ] Leave amount empty → Error message показывается
- [ ] **Account selection**:
  - [ ] Select account → Account выбран корректно
  - [ ] No account selected → Error message показывается
- [ ] **Description**: Enter description → Сохраняется
- [ ] **Recurring**:
  - [ ] Toggle recurring ON → Frequency picker появляется
  - [ ] Select frequency (Daily/Weekly/Monthly/Yearly) → Выбор сохраняется
  - [ ] Toggle recurring OFF → Frequency picker скрывается
- [ ] **Subcategories**:
  - [ ] If category has subcategories → List показывается
  - [ ] Select subcategory → Checkmark появляется
  - [ ] Search subcategories → Поиск работает
  - [ ] Link subcategory to transaction → Связь сохраняется
- [ ] **Save transaction**:
  - [ ] Tap "Сохранить сегодня" → Transaction добавляется
  - [ ] Tap "Выбрать дату" → Date picker открывается
  - [ ] Select past date → Transaction добавляется с выбранной датой
  - [ ] Select future date → Transaction добавляется как запланированная
- [ ] **Verify**:
  - [ ] Transaction appears in HistoryView
  - [ ] Account balance updates correctly
  - [ ] Category total updates in QuickAdd grid
  - [ ] Recurring series created if recurring was enabled

**Localization**:
- [ ] Test in English - all labels correct
- [ ] Test in Russian - все метки корректны

**Accessibility**:
- [ ] VoiceOver reads all labels
- [ ] All buttons accessible
- [ ] Form fields accessible

**Expected Issues**: None (refactored to use TransactionsViewModel, CategoriesViewModel, AccountsViewModel)

---

### 2. Voice Input Transaction ⏳

**Files**: `VoiceInputView.swift`, `VoiceInputService.swift`, `VoiceInputParser.swift`

**Test Steps**:
- [ ] Tap mic button (floating) → VoiceInputView opens
- [ ] **Permissions**:
  - [ ] First time → Microphone permission requested
  - [ ] Permission granted → Recording starts automatically
  - [ ] Permission denied → Error alert показывается
- [ ] **Recording**:
  - [ ] Red dot indicator animating → Recording active
  - [ ] Speak transaction (e.g., "Bought coffee for 5 dollars") → Transcription появляется live
  - [ ] Tap stop button → Recording stops
- [ ] **Parsing**:
  - [ ] Transaction parsed correctly → VoiceInputConfirmationView opens
  - [ ] Amount detected correctly
  - [ ] Description detected correctly
  - [ ] Category auto-assigned (if rule exists)
- [ ] **Confirmation**:
  - [ ] Edit amount → Changes saved
  - [ ] Edit description → Changes saved
  - [ ] Change category → Changes saved
  - [ ] Tap "Сохранить" → Transaction added
  - [ ] Tap "Отмена" → Returns to ContentView
- [ ] **Verify**:
  - [ ] Transaction appears in HistoryView
  - [ ] Account balance updates

**Localization**:
- [ ] Test in English - voice recognition works
- [ ] Test in Russian - голосовое распознавание работает

**Accessibility**:
- [ ] VoiceOver reads recording status
- [ ] Stop button accessible

**Expected Issues**: None (localization complete)

---

### 3. View Transaction History ⏳

**Files**: `HistoryView.swift`, `TransactionsViewModel.swift`, `AccountsViewModel.swift`, `CategoriesViewModel.swift`

**Test Steps**:
- [ ] Navigate to History screen → HistoryView отображается
- [ ] **Empty state**:
  - [ ] No transactions → Empty state message показывается
- [ ] **With transactions**:
  - [ ] Transactions grouped by date → Группировка корректна
  - [ ] DateSectionHeader показывается для каждого дня
  - [ ] Transaction cards отображают правильные данные:
    - [ ] Amount
    - [ ] Description
    - [ ] Category
    - [ ] Account
    - [ ] Date
- [ ] **Time Filter**:
  - [ ] Tap calendar button → Filter menu открывается
  - [ ] Select "Сегодня" → Shows today's transactions
  - [ ] Select "Эта неделя" → Shows this week's transactions
  - [ ] Select "Этот месяц" → Shows this month's transactions
  - [ ] Select "Этот год" → Shows this year's transactions
  - [ ] Select "Всё время" → Shows all transactions
  - [ ] Select "Custom" → Date picker открывается
  - [ ] Select custom date range → Filters correctly
- [ ] **Category Filter**:
  - [ ] Tap category filter button → Category chips появляются
  - [ ] Select category → Filters by category
  - [ ] Select multiple categories → Shows transactions from all selected
  - [ ] Deselect all → Shows all transactions
- [ ] **Account Filter**:
  - [ ] Tap account filter → Account list появляется
  - [ ] Select account → Filters by account
  - [ ] Select multiple accounts → Shows transactions from all selected
  - [ ] Deselect all → Shows all transactions
- [ ] **Summary**:
  - [ ] Summary card показывает правильные данные:
    - [ ] Total income
    - [ ] Total expenses
    - [ ] Net (income - expenses)
  - [ ] Summary updates when filters change
- [ ] **Transaction Actions**:
  - [ ] Tap transaction → EditTransactionView opens
  - [ ] Edit transaction → Changes saved
  - [ ] Delete transaction → Confirmation alert, then deleted
  - [ ] Swipe to delete → Transaction deleted

**Localization**:
- [ ] Test in English - all labels correct
- [ ] Test in Russian - все метки корректны

**Accessibility**:
- [ ] VoiceOver reads all transactions
- [ ] Filter buttons accessible
- [ ] Swipe actions accessible

**Expected Issues**: None (refactored to use multiple ViewModels)

---

### 4. Manage Accounts ⏳

**Files**: `AccountsManagementView.swift`, `AccountActionView.swift`, `AccountsViewModel.swift`

**Test Steps**:
- [ ] Navigate to Settings → Accounts → AccountsManagementView открывается
- [ ] **Empty state**:
  - [ ] No accounts → "Добавьте первый счёт" показывается
- [ ] **Add Account**:
  - [ ] Tap "+" button → AccountActionView (Add mode) открывается
  - [ ] Enter account name → Validates correctly
  - [ ] Enter initial balance → Validates correctly
  - [ ] Select currency → Currency picker работает
  - [ ] Tap "Сохранить" → Account added
  - [ ] Account appears in list
- [ ] **Edit Account**:
  - [ ] Tap existing account → AccountActionView (Edit mode) открывается
  - [ ] Change name → Updates correctly
  - [ ] Change initial balance → Updates balance correctly
  - [ ] Change currency → Updates currency
  - [ ] Tap "Сохранить" → Changes saved
- [ ] **Delete Account**:
  - [ ] Tap "Удалить" → Confirmation alert показывается
  - [ ] Confirm deletion → Account deleted
  - [ ] Related transactions deleted → Verify in HistoryView
- [ ] **Account Card**:
  - [ ] Shows correct balance (initial + transactions)
  - [ ] Shows currency symbol
  - [ ] Balance updates when transaction added/deleted
- [ ] **Multiple Accounts**:
  - [ ] Create 2-3 accounts → All display correctly
  - [ ] Add transactions to different accounts → Balances update separately
  - [ ] Transfer between accounts → Both balances update

**Localization**:
- [ ] Test in English - all labels correct
- [ ] Test in Russian - все метки корректны

**Accessibility**:
- [ ] VoiceOver reads account cards
- [ ] All buttons accessible

**Expected Issues**: None (refactored to use AccountsViewModel)

---

### 5. Manage Categories ⏳

**Files**: `CategoriesManagementView.swift`, `CategoriesViewModel.swift`

**Test Steps**:
- [ ] Navigate to Settings → Categories → CategoriesManagementView открывается
- [ ] **View Categories**:
  - [ ] All custom categories display → List корректен
  - [ ] Default categories (if any) display
- [ ] **Add Category**:
  - [ ] Tap "+" button → Add category modal открывается
  - [ ] Enter category name → Validates correctly
  - [ ] Select type (Expense/Income) → Type сохраняется
  - [ ] Select icon (optional) → Icon сохраняется
  - [ ] Tap "Сохранить" → Category added
  - [ ] Category appears in list
- [ ] **Edit Category**:
  - [ ] Tap existing category → Edit modal открывается
  - [ ] Change name → Updates correctly
  - [ ] Change icon → Updates correctly
  - [ ] Tap "Сохранить" → Changes saved
- [ ] **Delete Category**:
  - [ ] Tap "Удалить" → Confirmation alert показывается
  - [ ] Confirm deletion → Category deleted
  - [ ] Transactions with this category → Still exist (category name preserved)
- [ ] **Subcategories**:
  - [ ] Tap category → Subcategories list открывается
  - [ ] Add subcategory → Subcategory added
  - [ ] Edit subcategory → Changes saved
  - [ ] Delete subcategory → Subcategory deleted
  - [ ] Link subcategory to transaction → Verify in transaction details
- [ ] **Category Rules**:
  - [ ] Create rule (if keyword contains X → assign category Y)
  - [ ] Add transaction with keyword → Category auto-assigned
  - [ ] Edit rule → Updates correctly
  - [ ] Delete rule → Rule removed

**Localization**:
- [ ] Test in English - all labels correct
- [ ] Test in Russian - все метки корректны

**Accessibility**:
- [ ] VoiceOver reads categories
- [ ] All buttons accessible

**Expected Issues**: None (refactored to use CategoriesViewModel)

---

### 6. Manage Subscriptions ⏳

**Files**: `SubscriptionsListView.swift`, `SubscriptionDetailView.swift`, `SubscriptionEditView.swift`, `SubscriptionsViewModel.swift`

**Test Steps**:
- [ ] Navigate to Subscriptions → SubscriptionsListView открывается
- [ ] **Empty state**:
  - [ ] No subscriptions → "Нет подписок" показывается
  - [ ] Tap "Добавить подписку" → SubscriptionEditView opens
- [ ] **Add Subscription**:
  - [ ] Tap "+" button → SubscriptionEditView (Add mode) открывается
  - [ ] Enter description (e.g., "Netflix") → Validates
  - [ ] Enter amount (e.g., "9.99") → Validates
  - [ ] Select currency → Currency picker работает
  - [ ] Select category → Category assigned
  - [ ] Select account → Account assigned
  - [ ] Select frequency (Daily/Weekly/Monthly/Yearly) → Frequency saved
  - [ ] Select start date → Date saved
  - [ ] Select brand logo (optional) → Logo saved
  - [ ] Configure reminders (optional) → Reminders saved
  - [ ] Tap "Сохранить" → Subscription created
  - [ ] Subscription appears in list
  - [ ] Recurring transactions generated → Verify in HistoryView
- [ ] **View Subscription Details**:
  - [ ] Tap subscription card → SubscriptionDetailView открывается
  - [ ] Info card shows:
    - [ ] Brand logo (if set)
    - [ ] Description
    - [ ] Amount + currency
    - [ ] Category
    - [ ] Frequency
    - [ ] Next charge date
    - [ ] Account
    - [ ] Status (Active/Paused/Archived)
  - [ ] Transaction history section shows:
    - [ ] Past transactions (from this subscription)
    - [ ] Planned transactions (future, with clock icon, blue background)
    - [ ] Transactions sorted: nearest first, furthest last
- [ ] **Edit Subscription**:
  - [ ] Tap "Edit" (pencil icon) → SubscriptionEditView (Edit mode) открывается
  - [ ] Change amount → Updates correctly
  - [ ] Change frequency → Recurring transactions regenerated
  - [ ] Tap "Сохранить" → Changes saved
- [ ] **Pause/Resume Subscription**:
  - [ ] Tap "Приостановить" → Status changes to Paused
  - [ ] Future transactions NOT generated
  - [ ] Tap "Возобновить" → Status changes to Active
  - [ ] Future transactions generated
- [ ] **Delete Subscription**:
  - [ ] Tap "Удалить" → Confirmation alert показывается
  - [ ] Confirm deletion → Subscription deleted
  - [ ] Related transactions deleted → Verify in HistoryView
- [ ] **Subscription Card**:
  - [ ] Shows brand logo
  - [ ] Shows description
  - [ ] Shows amount
  - [ ] Shows next charge date
  - [ ] Shows status badge (Active/Paused)
- [ ] **Time Filter Integration**:
  - [ ] Change time filter in HistoryView → Planned transactions in SubscriptionDetailView update accordingly
  - [ ] Select "Этот месяц" → Shows only this month's planned transactions
  - [ ] Select "Этот год" → Shows this year's planned transactions (up to 2 years max)

**Localization**:
- [ ] Test in English - all labels correct
- [ ] Test in Russian - все метки корректны

**Accessibility**:
- [ ] VoiceOver reads subscription cards
- [ ] All buttons accessible

**Expected Issues**: None (refactored to use SubscriptionsViewModel)

---

### 7. Manage Deposits ⏳

**Files**: `DepositDetailView.swift`, `DepositEditView.swift`, `DepositsViewModel.swift`

**Test Steps**:
- [ ] Navigate to Accounts → Select deposit account → DepositDetailView открывается
- [ ] **View Deposit Details**:
  - [ ] Shows principal amount
  - [ ] Shows interest rate
  - [ ] Shows start date
  - [ ] Shows maturity date
  - [ ] Shows accrued interest (calculated)
  - [ ] Shows total value (principal + interest)
- [ ] **Edit Deposit**:
  - [ ] Tap "Edit" → DepositEditView открывается
  - [ ] Change principal → Updates correctly
  - [ ] Change interest rate → Recalculates interest
  - [ ] Change dates → Updates correctly
  - [ ] Tap "Сохранить" → Changes saved
- [ ] **Interest Rate Changes**:
  - [ ] Add rate change → New rate applied
  - [ ] View rate history → All changes listed
  - [ ] Delete rate change → Reverts to previous rate
- [ ] **Reconcile Interest**:
  - [ ] Tap "Reconcile" → Interest transaction created
  - [ ] Transaction appears in HistoryView
  - [ ] Account balance increases by interest amount
- [ ] **Reconcile All Deposits** (from Settings):
  - [ ] Tap "Reconcile All" → All deposit interest reconciled
  - [ ] All interest transactions created

**Localization**:
- [ ] Test in English - all labels correct
- [ ] Test in Russian - все метки корректны

**Accessibility**:
- [ ] VoiceOver reads deposit details
- [ ] All buttons accessible

**Expected Issues**: None (refactored to use DepositsViewModel)

---

### 8. CSV Import/Export ⏳

**Files**: `CSVImportService.swift`, `CSVPreviewView.swift`, `CSVColumnMappingView.swift`, `CSVEntityMappingView.swift`

**Test Steps**:
- [ ] **CSV Export**:
  - [ ] Navigate to Settings → Export Data → CSV
  - [ ] Tap "Export" → Share sheet открывается
  - [ ] Save CSV file → File saved
  - [ ] Open CSV in Excel/Numbers → Data correct:
    - [ ] All columns present
    - [ ] Data formatted correctly
    - [ ] Unicode characters (RU) display correctly
- [ ] **CSV Import**:
  - [ ] Navigate to Settings → Import Data → CSV
  - [ ] Tap "Import" → File picker открывается
  - [ ] Select CSV file → CSVPreviewView открывается
  - [ ] Preview shows first 5 rows → Data preview correct
  - [ ] Tap "Next" → CSVColumnMappingView открывается
  - [ ] Map columns:
    - [ ] Date → Date column
    - [ ] Amount → Amount column
    - [ ] Description → Description column
    - [ ] Category → Category column (optional)
    - [ ] Account → Account column (optional)
  - [ ] Tap "Next" → CSVEntityMappingView открывается
  - [ ] Map entities:
    - [ ] Unknown categories → Select existing or create new
    - [ ] Unknown accounts → Select existing or create new
  - [ ] Tap "Import" → Transactions imported
  - [ ] Verify imported transactions in HistoryView
  - [ ] Account balances updated correctly
- [ ] **Error Handling**:
  - [ ] Invalid CSV format → Error message показывается
  - [ ] Missing required columns → Error message показывается
  - [ ] Invalid date format → Error message показывается
  - [ ] Invalid amount format → Error message показывается

**Localization**:
- [ ] Test in English - all labels correct
- [ ] Test in Russian - все метки корректны

**Expected Issues**: CSV service updated for new ViewModels

---

### 9. Settings & Data Management ⏳

**Files**: `SettingsView.swift`, `TransactionsViewModel.swift`

**Test Steps**:
- [ ] Navigate to Settings → SettingsView открывается
- [ ] **General Settings**:
  - [ ] Change base currency → Currency updated
  - [ ] Change language (via iOS Settings) → App relaunches in new language
  - [ ] Change theme (if supported) → Theme updates
- [ ] **Data Management**:
  - [ ] Tap "Export Data" → Export options appear (CSV, JSON)
  - [ ] Tap "Import Data" → Import options appear (CSV)
  - [ ] Tap "Clear All Data" → Confirmation alert показывается
  - [ ] Confirm clear → All data deleted
  - [ ] Verify: All transactions, accounts, categories deleted
- [ ] **About Section**:
  - [ ] Shows app version
  - [ ] Shows build number
  - [ ] Links to Privacy Policy (if available)
  - [ ] Links to Terms of Service (if available)

**Localization**:
- [ ] Test in English - all labels correct
- [ ] Test in Russian - все метки корректны

**Accessibility**:
- [ ] VoiceOver reads all settings
- [ ] All buttons accessible

**Expected Issues**: None (localization complete)

---

## 🌍 Localization Testing

### English (EN) ⏳
- [ ] **All screens show English text**:
  - [ ] ContentView
  - [ ] HistoryView
  - [ ] QuickAddTransactionView
  - [ ] VoiceInputView
  - [ ] AccountsManagementView
  - [ ] CategoriesManagementView
  - [ ] SubscriptionsListView
  - [ ] SubscriptionDetailView
  - [ ] DepositDetailView
  - [ ] SettingsView
- [ ] **No Russian text leaking through**
- [ ] **All validation errors in English**
- [ ] **All alerts in English**
- [ ] **All buttons in English**

### Russian (RU) ⏳
- [ ] **Переключить язык**: Settings → General → Language & Region → Russian → Restart app
- [ ] **Все экраны показывают русский текст**:
  - [ ] ContentView
  - [ ] HistoryView
  - [ ] QuickAddTransactionView
  - [ ] VoiceInputView
  - [ ] AccountsManagementView
  - [ ] CategoriesManagementView
  - [ ] SubscriptionsListView
  - [ ] SubscriptionDetailView
  - [ ] DepositDetailView
  - [ ] SettingsView
- [ ] **Нет английского текста**
- [ ] **Все ошибки валидации на русском**
- [ ] **Все алерты на русском**
- [ ] **Все кнопки на русском**

### Mixed Language Testing ⏳
- [ ] Switch language while app is running → App adapts correctly
- [ ] User data (transaction descriptions, categories) preserve language
- [ ] Numbers formatted correctly for locale (1,000.00 vs 1 000,00)
- [ ] Currency symbols display correctly ($ vs ₽ vs €)

---

## ♿ Accessibility (VoiceOver) Testing

### Setup ⏳
- [ ] Enable VoiceOver: Settings → Accessibility → VoiceOver → ON
- [ ] Practice gestures:
  - Swipe right: Next element
  - Swipe left: Previous element
  - Double tap: Activate element
  - Two-finger swipe down: Read all from current position

### Critical Screens ⏳

#### ContentView:
- [ ] All category chips readable
- [ ] Floating mic button: "Voice Input" + hint
- [ ] Floating import button: "Import Statement" + hint
- [ ] Analytics card readable
- [ ] Subscriptions card readable

#### HistoryView:
- [ ] Calendar button: "Filter by date"
- [ ] Settings button: "Settings"
- [ ] Filter chips announce selection state
- [ ] Each transaction card readable:
  - [ ] Amount
  - [ ] Description
  - [ ] Category
  - [ ] Date
- [ ] Swipe actions announced

#### QuickAddTransactionView:
- [ ] All form fields labeled
- [ ] Amount field: "Amount"
- [ ] Description field: "Description"
- [ ] Account selection announced
- [ ] Recurring toggle announced
- [ ] Save buttons accessible

#### SubscriptionsListView:
- [ ] Each subscription card readable
- [ ] "+" button: "Add Subscription"
- [ ] Empty state readable

#### Settings:
- [ ] All sections readable
- [ ] All buttons accessible
- [ ] Destructive actions announced

---

## 🌓 Dark Mode Testing

### Switch Theme ⏳
- [ ] Settings → Display & Brightness → Dark Mode → ON

### Verify All Screens ⏳
- [ ] ContentView → Colors adapt correctly
- [ ] HistoryView → Text readable
- [ ] QuickAddTransactionView → Form readable
- [ ] All cards → Background/text contrast good
- [ ] Buttons → Colors adapt
- [ ] Alerts → Readable

### Common Issues to Check:
- [ ] Text color contrast (WCAG AA: 4.5:1 minimum)
- [ ] Card backgrounds visible
- [ ] Dividers visible
- [ ] Icons visible
- [ ] Charts/graphs readable (if any)

---

## 📊 Performance Testing (Optional)

### Metrics to Check ⏳
- [ ] **App Launch Time**: < 2 seconds (cold start)
- [ ] **QuickAdd Open**: < 0.5 seconds
- [ ] **HistoryView Load**: < 1 second (with 100+ transactions)
- [ ] **Filter Change**: < 0.5 seconds
- [ ] **Add Transaction**: < 0.5 seconds
- [ ] **Memory Usage**: < 100 MB (idle), < 200 MB (heavy use)
- [ ] **Battery Usage**: Normal (no excessive drain)

### Test with Large Dataset:
- [ ] Import 500+ transactions
- [ ] Navigate through HistoryView → Smooth scrolling
- [ ] Apply filters → Fast response
- [ ] Add new transaction → No lag

---

## 🐛 Bug Tracking

### Critical Bugs (Must Fix Before Release):
| # | Screen | Description | Status |
|---|--------|-------------|--------|
| 1 | | | ⏳ |
| 2 | | | ⏳ |

### Medium Priority Bugs (Fix in v1.1):
| # | Screen | Description | Status |
|---|--------|-------------|--------|
| 1 | | | ⏳ |

### Low Priority / Enhancement Ideas:
| # | Screen | Description | Status |
|---|--------|-------------|--------|
| 1 | | | ⏳ |

---

## ✅ Testing Summary

### Completion Status:
- [ ] **Critical Flows**: 0/9 completed
- [ ] **Localization (EN)**: 0/10 screens
- [ ] **Localization (RU)**: 0/10 screens
- [ ] **Accessibility**: 0/5 screens
- [ ] **Dark Mode**: 0/6 screens
- [ ] **Performance**: Not tested

### Estimated Time:
- **Critical Flows**: ~3-4 hours
- **Localization**: ~1 hour
- **Accessibility**: ~30-45 minutes
- **Dark Mode**: ~15-30 minutes
- **Performance**: ~15-30 minutes (optional)
- **Total**: ~4-6 hours

---

## 🎯 Next Steps After Testing

### If All Tests Pass ✅:
1. ✅ Mark all tests as completed
2. ✅ Document any minor issues (non-blocking)
3. ✅ Proceed to App Store screenshots
4. ✅ Create Privacy Policy + ToS
5. ✅ Submit to App Store

### If Critical Bugs Found ❌:
1. ⚠️ Document bugs in Bug Tracking section
2. ⚠️ Fix critical bugs immediately
3. ⚠️ Re-test affected flows
4. ⚠️ Mark as complete when all critical bugs fixed

### If Medium/Low Priority Bugs Found:
1. 📝 Document in Bug Tracking section
2. 📝 Plan for v1.1 release
3. ✅ Proceed with App Store submission

---

## 📚 Related Documentation

- `project-status-report.md` - Overall project status
- `viewmodel-refactoring-final-complete.md` - Refactoring completion report
- `localization-quick-reference.md` - Localization testing guide
- `initial-technical-audit.md` - Technical audit report

---

**Created by**: Claude Sonnet 4.5
**Date**: 15 января 2026
**Status**: ⏳ Ready for Testing
**Priority**: P2 (High)
