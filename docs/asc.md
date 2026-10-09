# App Store Connect и TestFlight из облака

Как Claude в облачной сессии (без Mac) отправляет сборки в TestFlight и смотрит App Store Connect.
Устроено как в Dalada: ключ App Store Connect API живёт в секретах, а не в чате и не в репозитории.

| Что | Где работает | Как запускается |
|---|---|---|
| Сборка → App Store Connect → TestFlight | GitHub Actions, `.github/workflows/testflight.yml` | Actions → TestFlight → Run workflow, или Claude через GitHub API |
| Ждать обработки сборки, таблица сборок | второй job того же workflow | сам после загрузки |
| Версии, сборки, встроенные покупки, отзывы, доступность в странах (статус DSA в ЕС), сбои из TestFlight | GitHub Actions, `.github/workflows/asc.yml` | Actions → App Store Connect → Run workflow (выбрать команду) |
| Продажи и выручка по дням, плюс всё из строки выше | облачная сессия Claude, `appstore/asc.py` | Claude запускает сам, если ключ есть в переменных окружения |

Репозиторий Tenra публичный, поэтому логи Actions видны всем. Продажи и выручку `asc.py` в Actions
не показывает, их Claude смотрит только из облачной сессии.

## Один раз: настройка

### 1. Ключ App Store Connect API

App Store Connect → **Users and Access** → **Integrations** → **App Store Connect API** →
**Team Keys** → «+».

- **Для сборок (GitHub):** роль **Admin**. Она нужна облачной подписи: Xcode сам создаёт
  сертификат и профиль. Ключ Dalada подходит, команда та же (SY2L2VMQP7), если у тебя сохранился
  его файл `.p8`. Иначе создай новый, например «GitHub Actions Tenra».
- **Для облачной сессии Claude:** лучше отдельный ключ, например «Claude cloud», с ролями
  **App Manager** и **Sales**. Так Claude видит приложение, сборки, отзывы и продажи, но не
  трогает сертификаты, пользователей и договоры. Можно взять и Admin-ключ, но лучше не давать
  больше, чем нужно.

У каждого ключа запиши **Issuer ID** (над таблицей ключей) и **Key ID**, затем **Download**:
файл `AuthKey_XXXXXXXXXX.p8` скачивается **только один раз**. Отозвать ключ можно там же, в любой
момент.

### 2. Секреты в GitHub (для сборок и workflow «App Store Connect»)

github.com/dkicekeeper/Tenra → **Settings** → **Secrets and variables** → **Actions** →
**New repository secret**, три штуки:

| Имя | Значение |
|---|---|
| `ASC_KEY_ID` | Key ID |
| `ASC_ISSUER_ID` | Issuer ID |
| `ASC_KEY_P8` | весь текст `.p8`-файла вместе со строками `-----BEGIN PRIVATE KEY-----` и `-----END PRIVATE KEY-----` |

### 3. Переменные облачного окружения (для Claude)

В Claude: меню облачного окружения в заголовке сессии → **Edit** → переменные окружения (или
«Network secrets», если такой раздел есть). Три переменные с теми же именами: `ASC_KEY_ID`,
`ASC_ISSUER_ID`, `ASC_KEY_P8`. Если поле однострочное, вставь текст `.p8` как есть:
`asc.py` сам восстановит переносы строк (можно и base64 всего файла). Новая сессия подхватит
переменные. Сеть: `api.appstoreconnect.apple.com` из облака доступен.

### 4. TestFlight на телефоне

App Store Connect → Tenra → **TestFlight** → **Internal Testing** → группа с тобой, включить
**Automatic Distribution**: новые сборки придут в приложение TestFlight сами.

## Каждая сборка

Claude запускает TestFlight через GitHub API (или ты: Actions → TestFlight → Run workflow, ветка
`main`). Сборка и загрузка 15-25 минут, обработка в App Store Connect ещё 10-30 минут. Итог запуска
показывает номер сборки, Xcode и таблицу сборок после обработки.

- Номер сборки = номер запуска + 1 (сборка 1 новой версии остаётся для загрузки из Xcode); свой
  номер можно задать в поле `build_number`.
- **Xcode:** у GitHub пока только Xcode 26, поэтому в такой сборке нет интерфейса, который
  требует iOS 27 (он за `#if compiler(>=6.4)`). Для TestFlight это нормально; сборку для релиза
  в App Store собирай на Mac с Xcode 27, пока GitHub не добавит Xcode 27 (итог запуска
  предупреждает об этом).

## Команды `appstore/asc.py`

```bash
python3 appstore/asc.py status                  # версии, последние сборки, встроенные покупки
python3 appstore/asc.py builds [--limit 15]
python3 appstore/asc.py wait-build --build 12 --wait 40
python3 appstore/asc.py reviews [--limit 20]    # отзывы с текстом (оценки без текста API не отдаёт)
python3 appstore/asc.py availability            # в скольких странах доступно, статус DSA в ЕС
python3 appstore/asc.py crashes [--build 12]    # отчёты о сбоях из TestFlight, без данных тестировщика
python3 appstore/asc.py sales [--days 7]        # продажи и выручка по дням; только не в Actions
```

Нужны `pyjwt` и `cryptography` (в облачном контейнере уже есть; в Actions ставятся в venv).
Vendor number для отчётов о продажах — 94171379 (`ASC_VENDOR_NUMBER`, если изменится).

## Если что-то пошло не так

- **«Add the ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_P8 repository secrets»** — нет секретов
  (шаг 2), имена с учётом регистра.
- **«HTTP 401»** — неверный Key ID, Issuer ID или текст ключа, либо ключ отозван.
- **«HTTP 403»** — у ключа нет нужной роли (продажам нужна Sales, Finance или Admin).
- **Ошибка подписи / «Cloud signing permission error»** при сборке — у ключа в секретах роль ниже
  Admin.
