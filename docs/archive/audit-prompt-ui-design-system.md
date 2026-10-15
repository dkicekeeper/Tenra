# UI & Design System Deep Audit — Prompt Template

> Copy this prompt into a new Claude Code session to run the full audit.
> Estimated scope: ~2-3 hours of agent work. Run with `/ship` or directly.

---

## The Prompt

```
Проведи полный глубокий аудит UI и дизайн-системы проекта Tenra. Аудит должен быть систематичным, с конкретными находками (файл:строка), severity (critical/warning/info) и рекомендациями по исправлению.

Прочитай CLAUDE.md и docs/UI_COMPONENTS_GUIDE.md перед началом.

---

### 1. АУДИТ ДИЗАЙН-ТОКЕНОВ

**Цель**: Убедиться, что все UI-значения идут через токены, а не захардкожены.

Проверить:
- [ ] **Цвета**: Найти все `.foregroundColor(Color.gray)`, `.foregroundColor(.red)`, `Color(hex:)`, `Color(red:green:blue:)` и другие raw color values. Должны использоваться `AppColors.*` токены.
- [ ] **Отступы**: Найти все `.padding(8)`, `.padding(12)`, `.padding(.horizontal, 20)` и другие числовые padding. Должны использоваться `AppSpacing.*` токены (xs/sm/md/lg/xl).
- [ ] **Скругления**: Найти все `.cornerRadius(8)`, `.clipShape(RoundedRectangle(cornerRadius: 12))` с числовыми значениями. Должны использоваться `AppRadius.*` токены.
- [ ] **Размеры иконок**: Найти все `.frame(width: 24, height: 24)` рядом с Image/IconView. Должны использоваться `AppIconSize.*` токены.
- [ ] **Типографика**: Найти все `.font(.system(size: 14))`, `.font(.headline)` и другие raw font values. Должны использоваться `AppTypography.*` токены.
- [ ] **Анимации**: Найти все `.animation(.spring(response:dampingFraction:))`, `.withAnimation(.easeInOut)` и другие inline анимации. Должны использоваться `AppAnimation.*` токены.

**Формат вывода для каждой находки:**
```
[severity] файл.swift:строка — описание проблемы
  Текущее: `.padding(16)`
  Должно быть: `.padding(AppSpacing.lg)`
```

---

### 2. АУДИТ ПЕРЕИСПОЛЬЗОВАНИЯ UI-КОМПОНЕНТОВ

**Цель**: Найти дублирование UI-паттернов, которые должны использовать shared-компоненты.

Проверить:
- [ ] **UniversalRow**: Найти кастомные HStack-строки в Form/List, которые дублируют функциональность UniversalRow (icon + title + subtitle + trailing). Особенно внутри FormSection.
- [ ] **MessageBanner**: Найти кастомные alert/banner/toast реализации, которые должны использовать MessageBanner.
- [ ] **IconView vs Image(systemName:)**: Найти места, где для entity/category иконок (аккаунты, категории, подписки) используется raw Image(systemName:) вместо IconView.
- [ ] **FormSection**: Найти кастомные Section-обёртки с cardStyle(), которые дублируют FormSection(.card).
- [ ] **UniversalFilterButton**: Найти кастомные filter chip реализации.
- [ ] **UniversalCarousel**: Найти кастомные горизонтальные скролл-списки.
- [ ] **AppEmptyState**: Найти кастомные empty state views.
- [ ] **TransactionCard**: Найти дублирование карточки транзакции.
- [ ] **AmountInput/AmountDigitDisplay**: Найти кастомные amount input реализации.
- [ ] **StatusBadge**: Найти inline status badge реализации (active/paused/archived).
- [ ] **PrimaryButtonStyle/SecondaryButtonStyle**: Найти кастомные стили кнопок.

**Формат вывода:**
```
[warning] файл.swift:строки — Кастомная строка формы дублирует UniversalRow
  Рекомендация: Заменить на UniversalRow(config: .standard, title: ..., icon: .sfSymbol(...))
```

---

### 3. АУДИТ ЛОКАЛИЗАЦИИ

**Цель**: Найти все захардкоженные строки, которые должны быть локализованы.

Проверить:
- [ ] **Text() со строковыми литералами**: Найти все `Text("слово")` где строка — пользовательский текст (не SF Symbol name). Должно быть `Text(String(localized: "key"))`.
- [ ] **Label() со строками**: Аналогично для Label.
- [ ] **Button() со строками**: Найти `Button("Cancel")`, `Button("Save")` — должны использовать локализованные строки.
- [ ] **Alert/confirmation dialog**: Найти захардкоженные title/message в .alert() и .confirmationDialog().
- [ ] **navigationTitle**: Найти захардкоженные .navigationTitle("Settings").
- [ ] **placeholder**: Найти захардкоженные placeholder в TextField/TextEditor.
- [ ] **Строки в ViewModel**: Найти строковые литералы в VM, которые попадают в UI (error messages, status text, etc).
- [ ] **Форматированные строки**: Найти string interpolation `"Total: \(amount)"` — должны использовать String(localized:) с подстановкой.
- [ ] **Полнота Localizable.strings**: Сравнить ключи в en.lproj и ru.lproj — найти отсутствующие переводы.
- [ ] **Неиспользуемые ключи**: Найти ключи в Localizable.strings, которые не используются в коде.

**Формат вывода:**
```
[warning] LoanDetailView.swift:45 — Захардкоженная строка в UI
  Текущее: Text("Monthly Payment")
  Должно быть: Text(String(localized: "loan.monthlyPayment"))
  + добавить ключ в en.lproj/Localizable.strings и ru.lproj/Localizable.strings
```

---

### 4. АУДИТ КОНСИСТЕНТНОСТИ UI

**Цель**: Убедиться в визуальной и поведенческой консистентности.

Проверить:
- [ ] **Padding contract**: Проверить, что cardStyle() НЕ включает padding, а контент добавляет .padding(AppSpacing.lg) явно.
- [ ] **Divider alignment**: Проверить, что dividers внутри card используют .padding(.leading, AppSpacing.lg).
- [ ] **Sheet presentation**: Проверить единообразие sheet'ов (NavigationStack, dismiss button, title).
- [ ] **Delete confirmation**: Проверить, что все destructive actions имеют confirmation dialog.
- [ ] **Loading states**: Проверить, что все async-операции показывают ProgressView или loading state.
- [ ] **Error handling в UI**: Проверить, что ошибки показываются через MessageBanner, а не alert.
- [ ] **Empty states**: Проверить, что все списки имеют empty state.
- [ ] **Navigation patterns**: Проверить, что навигация единообразна (NavigationLink vs .sheet vs .fullScreenCover).
- [ ] **Haptics**: Проверить, что destructive actions и success states имеют соответствующие haptics.
- [ ] **Reduce Motion**: Проверить, что декоративные анимации respect `UIAccessibility.isReduceMotionEnabled`.

---

### 5. АУДИТ ACCESSIBILITY

**Цель**: Проверить базовую доступность.

Проверить:
- [ ] **VoiceOver labels**: Найти интерактивные элементы без accessibilityLabel.
- [ ] **Contrast**: Проверить, что текст на цветных фонах имеет достаточный контраст (особенно textSecondary на card backgrounds).
- [ ] **Touch targets**: Проверить, что кнопки имеют минимум 44x44pt touch target.
- [ ] **Dynamic Type**: Проверить, что используются relative fonts, не фиксированные размеры.
- [ ] **accessibilityHidden**: Проверить, что декоративные элементы скрыты от VoiceOver.

---

### 6. АУДИТ PERFORMANCE UI

**Цель**: Найти UI-паттерны, которые вредят производительности.

Проверить:
- [ ] **List с 500+ sections**: Проверить наличие slicing (visibleSectionLimit) для длинных списков.
- [ ] **ForEach identity**: Найти `ForEach(..., id: \.self)` на non-trivial типах или `UUID()` как identity.
- [ ] **Pre-resolve в ForEach**: Найти передачу [Account]/[CustomCategory] массивов в row views вместо pre-resolved скаляров.
- [ ] **DateFormatter в ForEach**: Найти создание DateFormatter/NumberFormatter внутри циклов.
- [ ] **GeometryReader в List**: Найти использование GeometryReader внутри List rows.
- [ ] **Лишние @State**: Найти @State для данных, которые должны жить в ViewModel.
- [ ] **.onAppear vs .task**: Найти `.onAppear { Task {} }` которые должны быть `.task {}`.

---

### 7. АУДИТ iOS 26 / LIQUID GLASS

**Цель**: Проверить adoption Liquid Glass и iOS 26 API.

Проверить:
- [ ] **GlassEffectContainer / glassEffect**: Где используется, где стоит добавить.
- [ ] **Deprecated API**: Найти использование deprecated iOS API.
- [ ] **NavigationStack**: Проверить, что не используется deprecated NavigationView.
- [ ] **Task.sleep**: Найти `.sleep(nanoseconds:)` — должно быть `.sleep(for: .milliseconds())`.

---

## ФОРМАТ ИТОГОВОГО ОТЧЁТА

Создай файл `docs/UI_AUDIT_REPORT_YYYY_MM_DD.md` с:

1. **Executive Summary** — общее состояние, ключевые метрики
2. **Статистика** — сколько находок по severity (critical/warning/info) и категории
3. **Critical Findings** — требуют немедленного исправления
4. **Warning Findings** — важно исправить, но не блокер
5. **Info Findings** — рекомендации по улучшению
6. **Action Plan** — приоритизированный список задач для исправления

Каждая находка должна содержать:
- Severity (critical/warning/info)
- Категория аудита (1-7)
- Файл и строка
- Описание проблемы
- Текущий код
- Рекомендуемый код
- Оценка сложности исправления (trivial/moderate/complex)
```

---

## Варианты запуска

### Полный аудит (все 7 секций)
Скопировать весь промпт выше.

### Быстрый аудит (только critical)
Добавить в конец: `Сфокусируйся только на critical findings. Пропусти info-level рекомендации.`

### Аудит одной секции
Скопировать только нужную секцию (1-7) с шапкой и форматом отчёта.

### Аудит конкретного экрана
Добавить: `Проведи аудит только для файлов в Views/Loans/ и связанных VM/сервисов.`
