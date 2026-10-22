# App Store Connect и TestFlight из облака

Как Claude в облачной сессии (без Mac) отправляет сборки в TestFlight и смотрит App Store Connect.
Устроено как в Dalada: ключ App Store Connect API живёт в секретах, а не в чате и не в репозитории.

| Что | Где работает | Как запускается |
|---|---|---|
| Сборка → App Store Connect → TestFlight | GitHub Actions, `.github/workflows/testflight.yml` | Actions → TestFlight → Run workflow, или Claude через GitHub API |
| Ждать обработки сборки, таблица сборок | второй job того же workflow | сам после загрузки |
| Версии, сборки, встроенные покупки, отзывы, доступность в странах (статус DSA в ЕС), сбои из TestFlight | GitHub Actions, `.github/workflows/asc.yml` | Actions → App Store Connect → Run workflow (выбрать команду) |
| Создать версию в App Store, вставить What's New из `docs/release-notes.md` (заметки версии, которая готовится) во все локали, выбрать сборку после обработки (на ревью не отправляет) | GitHub Actions, `.github/workflows/asc.yml` | Actions → App Store Connect → `prepare-version`, поля `version` и `build`; или Claude через GitHub API |
| Специальные страницы продукта и тест страницы (скриншоты, промо-текст, ключевые слова) из `appstore/product-pages.json` | GitHub Actions, `.github/workflows/asc.yml` | `push-custom-pages`, `push-experiment` (поле `args`: `--submit`, `--start`) |
| Выдать или забрать Tenra Pro (`pro`) одному покупателю, посмотреть, что о нём знает RevenueCat | GitHub Actions, `.github/workflows/revenuecat.yml`, секрет `REVENUECAT_SECRET_KEY` | Actions → RevenueCat: `grant` / `revoke` / `status`, `app_user_id`, `days`; id в логе скрыт |
| Исходные скриншоты стора на симуляторе без Mac | GitHub Actions, `.github/workflows/screenshots.yml` (macOS) | Actions → Screenshots: языки, `frames` = `all`, `cpp` или `ten`; `art` рисует Тэна для шапки |
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
- **Xcode:** с 21.10.2026 все workflow на macOS (TestFlight, CI, DesignKit update, Screenshots)
  идут на раннере GitHub `xcode-27` (образ Xcode 27 на macOS 27, у GitHub пока в статусе
  preview) с Xcode 27.0. Поэтому сборка из облака содержит интерфейс iOS 27 (код за
  `#if compiler(>=6.4)`) и годится для App Store: Mac для релиза больше не нужен. Итог запуска
  пишет, каким Xcode собрано, и предупреждает, если Xcode старше 27.
- **Версия Xcode закреплена** (`xcode-version: "27.0"`), а не `latest-stable`: в образе рядом
  лежат 27.1 RC и 27.2 beta. Новую версию ставить сразу во все четыре workflow, вместе с Xcode
  на Mac. Раннер `xcode-27-xlarge` быстрее, но его минуты платные даже для публичного репозитория,
  поэтому не используется.
- **Время:** образ `xcode-27` примерно вдвое медленнее `macos-26`: CI около 40 минут (20 сборка,
  20 тесты), поэтому таймаут CI и DesignKit update 90 минут, Screenshots 180. Архив TestFlight
  без тестов укладывается в 60.
- **Симуляторы:** в образе только iOS 27.0 (iPhone 17, 17e, Air, 18 Pro, 18 Pro Max). CI берёт
  iPhone с новейшего рантайма по id; Screenshots сам создаёт iPhone 17 Pro (устройство кадров
  стора) на iOS 27, если его нет.

## Команды `appstore/asc.py`

```bash
python3 appstore/asc.py status                  # версии, последние сборки, встроенные покупки
python3 appstore/asc.py builds [--limit 15]
python3 appstore/asc.py wait-build --build 12 --version 1.5 --wait 40
python3 appstore/asc.py prepare-version --version 1.5 --build 6 [--wait 30]
                                                # создать версию (выпуск после одобрения), What's New
                                                # из docs/release-notes.md, выбрать сборку; без отправки
python3 appstore/asc.py keywords --locale ru,en-US   # слова из поля Keywords: к ним привязываются спец. страницы
python3 appstore/asc.py metadata [--version 1.7]
                                                # по локалям: название, подзаголовок, Promotional Text,
                                                # длины описания и ключей, основной язык; сами ключи
                                                # только вне Actions (лог публичный)
python3 appstore/asc.py custom-pages            # специальные страницы и состояние их версий
python3 appstore/asc.py push-custom-pages [--submit]
                                                # создать/обновить страницы из appstore/product-pages.json
python3 appstore/asc.py push-experiment [--submit | --start]
                                                # тест страницы из того же файла; --start после одобрения
python3 appstore/asc.py reviews [--limit 20]    # отзывы с текстом (оценки без текста API не отдаёт)
python3 appstore/asc.py availability            # в скольких странах доступно, статус DSA в ЕС
python3 appstore/asc.py crashes [--build 12]    # отчёты о сбоях из TestFlight, без данных тестировщика
python3 appstore/asc.py sales [--days 7]        # продажи и выручка по дням; только не в Actions
```

Нужны `pyjwt` и `cryptography` (в облачном контейнере уже есть; в Actions ставятся в venv).
Vendor number для отчётов о продажах — 94171379 (`ASC_VENDOR_NUMBER`, если изменится).

## Скриншоты, специальные страницы и тест страницы

1. **Снять экраны:** Actions → Screenshots (`frames`: `all` снимает 01-19, `cpp` только 02 и
   09-12 для специальных страниц, `ten` только кадры Тэна 07, 13, 14, 17-19). Workflow держит один запуск и одну
   очередь: новый запуск, пока один ждёт, отменяет ждущий. Шаг Тэна, который ничего не нашёл,
   кладёт рядом `90-debug-<шаг>` (экран) и `90-debug-<шаг>-tree` (дерево доступности, текст). Артефакт `raw-screenshots` кладётся в `screenshots/raw/<локаль>/`.
   Все 13 локалей помещаются в один запуск (около 80 минут). Перед сборкой просмотреть кадры:
   у первой локали запуска логотипы подписок могут не успеть загрузиться (квадраты с буквами
   вместо Netflix и YouTube), сумма или строка истории может попасть в кадр посреди анимации.
   Такие локали переснять отдельным запуском, первой поставив другую. Бывает и хуже: первая
   локаль приходит без части данных демо (без подписок, бюджетов и сообщения Тэна на главной,
   19.10 так вышло у de-DE), её переснять так же. У tr таб-бар на 05 свёрнут,
   а заголовок долгов (16) мелкий: длинные строки прокручивают экран, это норма.
   В режиме ScreenshotDemo Тэн доступен и в симуляторе: ответы играет
   `ScreenshotDemoTransport` без сети, а сид добавляет цели, долги и подписку со списанием
   завтра (сообщение Тэна на главной). Кадры 13-16: ответ Тэна на карточках, черновик из
   голоса, цель, долги; 07 теперь голосовой экран Тэна. Кадры 17-19 для специальных страниц:
   ответы Тэна про подписки, деньги во всех валютах и досрочный платёж по кредиту. В демо у Тэна
   четыре готовых вопроса (этот месяц, подписки, валюты, кредит), тест нажимает их по порядку,
   и на каждый `ScreenshotDemoTransport` вызывает свой инструмент; слова ответов и вопросы без
   своего пресета лежат в `ScreenshotDemoTenLines`.
2. **Собрать кадры:** `python3 scripts/compose_screenshots.py [локали] [--frames 13-ten-answer …]`
   кладёт 1320×2868 в `screenshots/final/<локаль>/`. Фон и iPhone берутся из шести шаблонов
   `screenshots/templates/background-a…f.png` (сняты с макетов Figma, файл Tenra, страница
   «Screenshots L10n»), экран вставляется в дисплей модели с Dynamic Island поверх, подпись из
   `scripts/screenshot_captions.json`: заголовок Inter SemiBold 98, подзаголовок Inter Medium 58
   (ja и ko: Noto Sans JP/KR), не больше двух строк каждый, строки выровнены по длине; `\n` в
   подписи ставит перенос руками. Какой кадр на каком фоне: `FRAMES` в скрипте (в порядке
   магазина один фон не стоит два раза подряд). Нужны Pillow и numpy; шрифты скрипт берёт из
   системы или скачивает в `~/.cache/tenra-fonts`. Новый дизайн фона или модели: экспортировать
   шаблон из Figma без подписи, экран залить чёрным, положить в `screenshots/templates/`.
3. **Отправить:** скриншоты версии: `push-version-screenshots` с `version` (кадры из
   `defaultOrder` в `scripts/screenshot_captions.json`, у tr свой `order`, не больше 10);
   специальные страницы: `push-custom-pages --submit`; тест страницы: `push-experiment --submit`,
   потом после одобрения `push-experiment --start`. Повторный запуск не перезаливает
   неизменённые скриншоты.
4. **Шапка и кадр для поиска (iOS 27):** `python3 scripts/compose_store_art.py [локали]
   [--preview <папка>]` собирает в `screenshots/art/<локаль>/` шапку `header.png` (3840×1646:
   Тэн и фраза `header` из `scripts/screenshot_captions.json`) и кадр поиска `search.png`
   (3840×2560: заголовок и один экран в iPhone, ответ Тэна 13), для каждой специальной
   страницы `search-<страница>.png` по её `searchFrame` в `product-pages.json`. Тэн берётся из
   `screenshots/art/ten/` (Actions → Screenshots с `art`: тест `StoreArtRenderTests` рисует его
   через `ParticleCreature.image`). Всё важное держать в безопасных зонах Apple (`SAFE` в
   скрипте): на iPhone видна только середина шапки, а поиск показывает кадр шириной около
   365 pt, `--preview` кладёт копию в 384 px, по ней проверять, что заголовок читается.
   Отправка: `push-creatives` (по умолчанию на вышедшую версию, новая версия не нужна),
   `--pages` ставит их и на специальные страницы (после `push-custom-pages` без `--submit`),
   `--submit` отправляет новые картинки и версии страниц на проверку. Вышедшая версия берёт только
   одобренную картинку: такие строки помечены «after review», и после одобрения картинок команду
   запустить ещё раз без `--submit`, она поставит их на версию. Специальные страницы в подготовке
   берут картинки сразу и уходят на проверку вместе с ними. Что на самом деле ушло на проверку и в
   каком состоянии, показывает `review-submissions` (отправки, их элементы, картинки библиотеки). Картинка загружается в
   библиотеку один раз: в её `referenceName` md5 файла; размещение с другой картинкой
   заменяется (изменить размещение API не даёт).
5. **Возрастной рейтинг:** `age-rating` показывает ответы анкеты против ответов Tenra в
   `asc.py`, `age-rating` с `args` `--apply` ставит их на версию в подготовке. Анкету App
   Privacy API не умеет: только веб-форма.

Ключевые слова специальной страницы берутся только из поля Keywords этой локали (`keywords`),
одно слово принадлежит одной странице. Тест страницы идёт на версии, которая сейчас в магазине,
один за раз, до 90 дней; иконку в нём не проверить, пока альтернативных иконок нет в сборке.

## Макеты экранов

Как выглядит экран до того, как он попадёт в сборку, без Mac: Actions → **Mockups**
(`mockups.yml`). Он же запускается сам при пуше в ветку `claude/**`, если пуш меняет
`TenraTests/Mockups/` или сам workflow. Набор `ScreenMockupTests` рисует экраны в окне
симулятора (`drawHierarchy`: стекло, панели и прокрутка выходят как на телефоне) на каждом языке
из входа `languages` (по умолчанию `ru en`), в светлой и тёмной теме, и кладёт PNG в артефакт
`mockups` (`<язык>/<экран>-light.png`). В обычном CI набор пропускается: он включается
переменной `MOCKUP_DIR`. Макет экрана живёт в наборе, пока его вид на утверждении, потом удаляется.

## Если что-то пошло не так

- **«Add the ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_P8 repository secrets»** — нет секретов
  (шаг 2), имена с учётом регистра.
- **«HTTP 401»** — неверный Key ID, Issuer ID или текст ключа, либо ключ отозван.
- **«HTTP 403»** — у ключа нет нужной роли (продажам нужна Sales, Finance или Admin).
- **Ошибка подписи / «Cloud signing permission error»** при сборке — у ключа в секретах роль ниже
  Admin.
