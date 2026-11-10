# Аудит безопасности открытых репозиториев (2026-11-10)

> Срез: `main` Tenra на d25dba4 и ветки по умолчанию остальных репозиториев на 2026-11-10.
> Повод: решали, закрыть ли репозитории; владелец оставил их открытыми
> ([backlog.md](../backlog.md), Decisions). Правило про секреты, которое отсюда следует:
> [CLAUDE.md](../../CLAUDE.md), Don't. Значений ключей и персональных данных в этом файле нет.

## 1. Что проверено

Шесть открытых репозиториев: Tenra, Dalada, DesignKit, tenra-assets, lottie-files, paws-world
(AutoParts4x4 и CatPaw закрыты). Вся история: все ветки и ветки PR (`refs/pull/*`), в Tenra
2 170 коммитов.

1. **gitleaks 8.28** по всей истории каждого репозитория.
2. **Свой поиск по всем добавленным строкам истории** (`git log --all -p`): ключи Anthropic,
   OpenAI, Google (`AIza…`), RevenueCat (`sk_…`, `appl_…`), Logo.dev (`pk_…`), Supabase (JWT,
   `sb_secret_…`), GitHub, Slack, AWS, Telegram, приватные ключи, `AGE-SECRET-KEY`, строки
   подключения к базе с паролем; персональное: IBAN `KZ…` (с проверкой контрольной суммы), ИИН,
   телефоны +7, номера карт, почты.
3. **Пути всех файлов, когда-либо бывших в истории**: `.p8`, `.p12`, профили подписи, `.env`,
   `Secrets.xcconfig`, `.sqlite`, `.xcresult`, выписки (`.pdf`, `.csv`).
4. **GitHub Actions**: триггеры (`pull_request_target`, `issue_comment`, `workflow_run`),
   подстановка `github.event.*` в `run:`, секреты в workflow, которые запускаются на PR, свои
   раннеры, что попадает в публичные логи, итоги и артефакты.
5. **Сервер Тэна** (`server/assistant`): чем защищён каждый запрос, раз код открыт.

## 2. Находки

| # | Что | Где | Решение |
|---|---|---|---|
| 1 | Ключ Gemini API | история Tenra: `AIFinanceManager/Info.plist`, добавлен в 5c43ccf2 (2026-01-07), удалён в 4cb72def (2026-01-10) | владелец отозвал ключ 2026-11-10; историю не переписывали |
| 2 | Настоящий IBAN из выписки (контрольная сумма сходится) | `ColumnRoleResolverTests.swift`, архивный план распознавания документов; раньше комментарий в старом `StatementTextParser` | в коде заменён на выдуманный; в истории остаётся (решение владельца): по IBAN можно только перевести деньги |
| 3 | Цифры бизнеса | [promotion-plan.md](../promotion-plan.md): установки, пробные, MRR, кампании Apple Ads с бюджетами, CPT и ключевыми словами | остаются открытыми (решение владельца) |
| 4 | Почта владельца | автор коммитов, страницы поддержки | владелец включил скрытие почты в GitHub; коммиты с Mac переводятся на адрес noreply (`git config --global user.email`) |
| 5 | Анимации, похожие на банковское приложение | lottie-files | остаются (решение владельца) |

Владелец включил в репозиториях Secret scanning и Push protection: GitHub отклоняет push с
ключом известного формата.

## 3. В порядке

- Ключи, которые и так лежат в приложении и рассчитаны на это: публичный ключ RevenueCat
  (`appl_…`), publishable-ключ Logo.dev (`pk_…`). Ключ `anon` Supabase в старой истории Tenra
  ведёт в удалённый проект.
- Серверные секреты (ключи App Store Connect и Apple Ads, секретный ключ RevenueCat, Anthropic,
  R2, база Supabase) только в секретах GitHub. Файлов ключей, сертификатов и профилей в истории
  нет; в Dalada `Secrets.xcconfig` и `.env` закрыты `.gitignore`.
- Остальное, что нашёл поиск, ложные срабатывания: тестовый сертификат App Attest
  (`server/assistant/test/fixtures/appattest.json`, свой тестовый CA), регулярное выражение в
  `appstore/asc.py`, UUID в старых заметках, выдуманные токены и номера в тестах, телефоны мест из
  OpenStreetMap в Dalada, локальный Supabase (`127.0.0.1`) в строках подключения, пароль
  аккаунта для App Review в Dalada передаётся из секретов, а не хранится.
- GitHub Actions: нет `pull_request_target`, `issue_comment` и `workflow_run`, текст из PR не
  подставляется в команды, workflow на PR из форков не используют секреты, своих раннеров нет.
  `asc.py`, `ads.py` и `revenuecat.yml` не печатают в публичный лог выручку, траты, ставки и id
  покупателя.
- Сервер Тэна: каждый запрос подписан ключом App Attest, квоты на ключ и на покупателя, общий
  дневной лимит; открытый код не даёт пользоваться им бесплатно.
- Старые `build/capture_all.log` и `.xcresult` скриншотов в истории Tenra: только имя пользователя
  Mac и модель симулятора.
- DesignKit, tenra-assets, paws-world: ничего.

## 4. Как повторить

```bash
go install github.com/zricethezav/gitleaks/v8@v8.28.0   # или brew install gitleaks
git fetch origin '+refs/pull/*:refs/remotes/pull/*' '+refs/heads/*:refs/remotes/origin/*'
gitleaks git . --log-opts="--all" --redact -r leaks.json
```

Чужие репозитории проверялись так же, по `git clone --mirror`. gitleaks не знает ключей
отдельных сервисов и не ищет персональные данные: их проверяли регулярными выражениями из
пункта 2 по выводу `git log --all -p`.
