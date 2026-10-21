# План: Тэн на моделях Apple и Siri iOS 27

> Статус: не начат. Решение владельца 2026-10-15: пока только Claude, путь Apple позже. С
> 2026-10-21 код iOS 27 собирается и тестируется в облаке на Xcode 27 ([asc.md](asc.md)), так что
> начать можно в любой момент; первый шаг за владельцем (entitlement, §4). Как Тэн устроен сейчас:
> [domains/assistant.md](domains/assistant.md). Когда план реализуется, файл уходит в
> `archive/plans/`, а правила оседают в domains/assistant.md.

---

## 1. Зачем

- **Цена.** Модель Apple на Private Cloud Compute бесплатна для участников Small Business Program
  с менее чем 2 млн первых загрузок (Tenra подходит, комиссия 15%), есть квота на пользователя.
  Ответы, которые она тянет, не тратят бюджет Anthropic.
- **Приватность.** Apple-первый роутинг: на устройстве или в Private Cloud Compute, облако Claude
  только для того, что Apple не умеет.
- **Россия и Беларусь.** Anthropic API там не работает (сервер отвечает 451), а модели Apple могут.
- **Siri.** «Спроси Tenra, сколько осталось на еду» голосом, без открытия приложения.

## 2. Что известно (проверено по swiftinterface iOS 27 SDK 2026-10-15)

- `PrivateCloudComputeLanguageModel` есть и соответствует протоколу `LanguageModel`;
  `availability` (с `UnavailableReason`), `quotaUsage` (`belowLimit` / `limitReached`,
  `limitIncreaseSuggestion`), ошибки `networkFailure`, `quotaLimitReached` (с `resetDate`),
  `serviceUnavailable`.
- Протокол `LanguageModel` (iOS 27): облачные модели подключаются под тот же API сессий,
  инструментов и `@Generable`; Dynamic Profiles меняют модель и инструменты внутри сессии.
- `supportedLanguages` отдаётся во время работы: есть ли русский, покажет только телефон на iOS 27.
  По найденным источникам в Apple Intelligence (16 языков с iOS 26.1) русского и украинского нет,
  Siri AI в iOS 27 стартует с английского; около половины базы на iPhone без Apple Intelligence
  ([domains/import.md](domains/import.md), правило 2). Поэтому Claude остаётся основным мозгом, а
  Apple берёт то, что умеет.
- Минимальная iOS 26: путь Apple только на iOS 27, на iOS 26 Тэн остаётся на Claude.

## 3. Роутер

Между `AgentConversation` и сервером встаёт `AgentBrain`:

| Мозг | Когда | Цена | Приватность |
|---|---|---|---|
| FastPath (есть) | фраза разбирается парсером | 0 | на устройстве |
| AppleOnDevice (`SystemLanguageModel`, iOS 26+) | язык поддержан, вопрос простой, контекст маленький | 0 | на устройстве |
| ApplePCC (iOS 27+) | язык поддержан, вопрос сложнее, квота не исчерпана | 0 (квота Apple) | Private Cloud Compute |
| Claude через сервер (есть) | русский и другие языки без Apple, сложный анализ, планирование; после согласия | см. domains/assistant.md §11 | облако, без хранения на сервере |

Роутер решает по языку (`supportsLocale`), доступности, согласию на облако, квоте и типу запроса.
Инструменты остаются на телефоне: нужен адаптер схем сервера (`server/assistant/src/tools.ts`) в
`Tool` Foundation Models, ответ через `@Generable` вместо `render_reply` с теми же блоками
`AgentReply` и тем же правилом «цифры только по ссылке». Проверить, можно ли посадить Claude под
протокол `LanguageModel` и получить один путь кода на iOS 27.

## 4. Шаги

- [ ] **Владелец:** запросить entitlement Private Cloud Compute (форма на
      developer.apple.com/private-cloud-compute, точный путь проверить там).
- [ ] `AgentBrain` и роутер, ApplePCC первым мозгом Apple (iOS 27, за `#if compiler(>=6.4)` и
      `if #available(iOS 27, *)`).
- [ ] AppleOnDevice: только для поддержанных языков; на русском и украинском его нет.
- [ ] Бейдж «облако» на ответах Claude, когда мозгов станет больше одного (domains/assistant.md §10).
- [ ] Siri iOS 27: intent schemas и View Annotations («Спроси Tenra, сколько осталось на еду»),
      поверх существующих интентов ([domains/intents.md](domains/intents.md)).
- [ ] Россия и Беларусь: облако по витрине прятать, Тэна оставить на Apple там, где язык
      поддержан.
- [ ] Eval пути Apple (Evaluations framework iOS 27) на тех же синтетических кейсах.

## 5. Риски

| Риск | Чем закрываем |
|---|---|
| Русского в моделях Apple нет | Claude остаётся основным; Apple только для поддержанных языков |
| Два пути кода iOS 26 / 27 | Один `AgentBrain`; на iOS 26 тот же путь через сервер, что сейчас |
| Квота Apple кончается посреди месяца | Роутер переходит на Claude в пределах лимитов Pro и бесплатного (domains/assistant.md §11) |
| Ответы Apple слабее на анализе | Сложные вопросы и планирование идут к Claude; eval на обоих путях |
