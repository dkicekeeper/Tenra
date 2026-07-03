# Tenra — Локализация: Турецкий (tr)

> Статус: план + черновики. Приоритет №4, фаза 3 (см. [README.md](README.md)).
> Витрина ASC: `tr`. Локаль приложения: `tr`.
> ⚠️ Все турецкие тексты в этом файле — **AI-черновик, обязательна вычитка нейтивом** перед сабмитом
> (особенно метаданные витрины и голосовые ключевики).

## 1. Обзор рынка

**Турция — рынок с сильнейшим продуктовым фитом для Tenra среди всех фаз локализации.**

Ключевой факт: хроническая высокая инфляция и многолетнее обесценение лиры сформировали массовую
привычку — турки держат сбережения в долларах, евро и золоте, а зарабатывают и тратят в TL.
Это не нишевый сценарий, а бытовая норма («долларизация» сбережений). Для такого пользователя
главная боль — **«сколько у меня денег на самом деле?»**: часть в TL, часть в USD/EUR, курсы
меняются ежедневно. Мультивалютность Tenra с реальным FX и одним честным итогом в базовой валюте
решает ровно эту боль — и это должно быть в subtitle, промо-тексте, первом абзаце описания и на
hero-скриншоте (см. §3–4).

Прочие факторы рынка:

| Фактор | Оценка | Следствие |
|---|---|---|
| Продуктовый фит | **Сильнейший** (мультивалюта + подписки + бюджеты) | Мультивалютность — центр позиционирования |
| ASO-конкуренция | Умеренная: глобальные трекеры локализованы слабо, локальные (Bütçem и т.п.) просты | Реально выйти в топ по среднечастотникам |
| ARPU / покупательная способность | Низкая относительно US/EU; цены чувствительны | **Агрессивные цены вниз** от якоря (см. §6) |
| Привычка к подпискам | Растёт (Netflix, Spotify, BluTV, Getir Plus) | Модель Pro-подписки понятна рынку |
| Приватность | Недоверие к передаче банковских данных высоко | «Banka bağlantısı yok» — сильный аргумент |

Локальная особенность сбережений — **золото** (gram altın, çeyrek altın) наравне с USD/EUR.
⚠️ Проверить до запуска: поддерживает ли `CurrencyConverter` / провайдер курсов XAU (золото).
Если да — упоминать золото в описании и скриншотах; если нет — из витрины убрать
(в черновиках ниже золото упомянуто только в keywords как `altın` — это безопасно,
т.к. ловит и поисковый интент «учёт накоплений в золоте»).

## 2. ASO-ключевики (~12)

⚠️ Черновик на экспертной оценке. **Перед сабмитом валидировать реальные объёмы** через
ASA Search Popularity (витрина TR) или ASO-инструмент (Astro/AppTweak/Sensor Tower) — см. L4 в README.

| # | Ключевик | Перевод | Ожид. объём | Конкуренция | Куда кладём |
|---|---|---|---|---|---|
| 1 | bütçe | бюджет | Высокий | Средняя | Title |
| 2 | gider takibi | учёт расходов | Высокий | Средняя | Title |
| 3 | para yönetimi | управление деньгами | Средний | Средняя | Subtitle |
| 4 | harcama takibi | трекинг трат | Средний | Средняя | Keywords (`harcama` + `takibi` из Title) |
| 5 | birikim | накопления | Средний | Низкая | Keywords |
| 6 | dolar | доллар | **Высокий** (специфика рынка!) | Низкая в финансах-трекерах | Subtitle |
| 7 | döviz / döviz kuru | валюта / курс валют | Высокий | Средняя (много курсовых аппок) | Keywords (`döviz`, `kur`) |
| 8 | abonelik takibi | учёт подписок | Средний | Низкая | Keywords (`abonelik`) |
| 9 | fatura takibi | учёт счетов/платежей | Средний | Средняя | Keywords (`fatura`) |
| 10 | tasarruf | экономия/сбережения | Средний | Средняя | Keywords |
| 11 | cüzdan | кошелёк | Средний | Высокая (крипто-шум) | Keywords |
| 12 | kişisel finans | личные финансы | Низкий-средний | Низкая | Комбинация: `finans` не влез — покрывается брендовыми запросами и описанием; при валидации решить, менять ли на него `cüzdan` |

Дополнительно в Keywords-поле: `borç` (долг), `kredi` (кредит), `mevduat` (депозит),
`hesap` (счёт), `maaş` (зарплата), `altın` (золото), `gelir` (доход) — низкочастотный хвост
с прямым продуктовым покрытием.

Комбинаторика ASC: `dolar + kur`, `döviz + hesap`, `harcama + takibi (из Title)`,
`abonelik + takibi` — поле keywords матчится пословно, отдельные фразы не нужны.

## 3. Метаданные ASC (витрина tr)

### Title (26/30... вариант A; 28/30 вариант B)

- **Вариант A (рекомендуемый)**: `Tenra: Bütçe ve Gider Takibi` — **28/30**
  (естественная турецкая связка «ve» вместо кальки с запятой)
- Вариант B: `Tenra: Bütçe, Gider Takibi` — 26/30 (зеркалит US-паттерн)

### Subtitle — мультивалютный хук

`Para yönetimi: TL, dolar, euro` — **30/30**

Ключевик `para yönetimi` + прямое попадание в боль рынка: пользователь с долларовыми
сбережениями видит «TL, dolar, euro» и мгновенно понимает, что приложение — про его кейс.

Запасной: `Dolar, euro, TL — tek bakiye` (28/30) — эмоциональнее, но теряет ключевик
`para yönetimi`; выбрать после валидации объёмов.

### Keywords — **99/100**

```
harcama,birikim,döviz,kur,abonelik,fatura,cüzdan,borç,kredi,mevduat,hesap,maaş,altın,tasarruf,gelir
```

Не дублируют Title/Subtitle (bütçe, gider, takibi, para, yönetimi, dolar, euro — уже проиндексированы).
⚠️ Писать строчными **турецкими** буквами как здесь — `ı`/`i` в keywords должны совпадать
с тем, как реально пишут турки (см. §7 про İ/ı).

### Promotional Text — **163/170**

```
Birikimin dolarda, maaşın TL'de mi? Tenra tüm hesaplarını gerçek kurlarla tek dürüst bakiyede birleştirir. Bütçe, abonelikler ve analiz — banka bağlantısı olmadan.
```

(«Сбережения в долларах, а зарплата в лирах? Tenra объединяет все счета по реальным курсам
в один честный баланс. Бюджеты, подписки и аналитика — без привязки банка.») Хук про
двухвалютную жизнь — деликатно, без слов «инфляция»/«кризис».

### Description — **1705** символов (в диапазоне 1500–2500)

```
Türkiye'de para biriktirmek ekstra dikkat ister: maaş TL, birikim dolar ya da euro, harcamalar her yerde. Tenra tam bu gerçek için tasarlandı — tüm hesaplarını gerçek döviz kurlarıyla tek bir dürüst toplamda birleştirir. Paranın gerçek değerini her an bilirsin.

BÜTÇELER ANA EKRANDA
• Her kategori için aylık limit belirle
• Harcanan tutarı ve kalanı anında gör
• Ay sonunu sürprizsiz kapat

TÜM FİNANSLARIN TEK YERDE
• Hesaplar, nakit ve kartlar
• Vadeli mevduatlar — faiz tahakkuku otomatik hesaplanır
• Abonelikler — yenileme tarihleri ve aylık toplam maliyet
• Krediler ve borçlar — ödeme planıyla birlikte
• Banka bağlantısı yok: hesap bilgilerini kimseyle paylaşmazsın

ÇOK PARA BİRİMİ, TEK GERÇEK BAKİYE
• TL, dolar, euro ve 150'den fazla para birimi
• Güncel kurlarla otomatik çevrim
• Dolar hesabın da TL hesabın da aynı dürüst toplamda
• Baz para birimini istediğin an değiştir

ANALİZ VE FİNANSAL PUAN
• Paran nereye gidiyor — kategori kategori gör
• Aylık gelir, gider ve net akış grafikleri
• Finansal sağlığını tek bir puanla takip et: birikim, bütçe disiplini ve güvence fonu

HIZLI KAYIT
• Sesle ekle: "Markete 450 lira harcadım" de, işlem hazır
• PDF ve CSV banka ekstresi içe aktarımı
• Tekrarlayan işlemler otomatik oluşturulur

GİZLİLİK ÖNCE GELİR
• Verilerin cihazında ve kendi iCloud hesabında kalır
• Reklam yok, izleme yok, bankana erişim yok
• İstediğin an tüm verini CSV olarak dışa aktar

TENRA PRO
Günlük takip ve 3 hesap tamamen ücretsiz. Pro ile: sınırsız hesap, sesle giriş, PDF/CSV içe aktarma, mevduat ve kredi takibi. Yıllık planda 14 gün ücretsiz deneme.

Paranı yönetmek için bankanı değiştirmen gerekmez. Tenra'yı indir, bütçeni bugün kur — paranın değerini sen koru.
```

Первый абзац — инфляционная боль без слова «инфляция»: «зарплата в TL, сбережения в долларах
или евро, траты повсюду» — каждый турецкий пользователь узнаёт себя. Финальная строка
«paranın değerini sen koru» («сохрани ценность своих денег сам») — тот же мотив, деликатно.

### What's New (релиз tr-локали) — 191 символ

```
• Türkçe tam destek: arayüz, sesle giriş ve banka ekstresi içe aktarımı artık Türkçe
• Sesle kayıt: "Taksiye 200 lira verdim" de, işlem hazır
• Hata düzeltmeleri ve performans iyileştirmeleri
```

## 4. Скриншоты (8 подписей)

⚠️ **Рекомендация для витрины tr: мультивалютный фрейм (№8 в залоченном порядке) поставить
ПЕРВЫМ — это hero-кандидат №1.** Для этого рынка «один честный итог из TL + USD» продаёт
сильнее, чем бюджеты. Остальной порядок — как в README. Суммы в UI скриншотов: TRY + USD
(например, счёт «Maaş hesabı ₺84.500» + «Birikim $2.300»), базовая валюта TRY.

| # | Экран | Заголовок (TR) | Подзаголовок (TR) |
|---|---|---|---|
| 1 (hero) | Мультивалютность | **TL, dolar, euro — tek gerçek bakiye** | Tüm hesapların gerçek kurlarla tek dürüst toplamda |
| 2 | Главная (бюджеты) | Her kategori için ayrı bütçe | Limitler, harcamalar ve kalan — ana ekranda |
| 3 | Финансы | Tüm finansların tek yerde | Hesaplar, mevduatlar, abonelikler ve krediler — banka bağlantısı olmadan |
| 4 | Аналитика | Paran nereye gidiyor, gör | Bakiye, harcamalar ve aylık net akış — ilk bakışta |
| 5 | Финансовый скор | Finansal sağlığının tek puanı | Birikim, bütçeler ve güvence fonu — anlaşılır tek skorda |
| 6 | Топ категория | En büyük harcamalarını keşfet | Aylara göre net dağılımıyla harcama kategorileri |
| 7 | История | Her işlem kontrol altında | Harcamalar, gelirler ve mevduat faizleri — tek akışta |
| 8 | Голос | Harcamalarını sesle ekle | "Markete 450 lira harcadım" — de ve bitti |

Примеры операций внутри фреймов: Market ₺450, Taksi ₺200, Netflix ₺149,99, Kira ₺25.000,
Birikim hesabı $500 — смесь TRY и USD обязательна минимум на hero и «Финансы».

## 5. Адаптация фич

### 5.1 Голосовой ввод (VoiceInputParser + Segmenter)

⚠️ **Инженерное требование — матчинг по основе слова (prefix-match).** Турецкий —
агглютинативный язык: падежные суффиксы приклеиваются к существительному и меняют его форму:
`market` → `markete` (куда), `marketten` (откуда), `marketde/markette` (где);
`taksi` → `taksiye`, `taksiden`. Точный словарный матчинг словоформ не масштабируется —
парсер должен матчить **основу как префикс токена** (`token.hasPrefix(stem)`), с двумя защитами:
1) минимальная длина основы 3–4 символа (иначе `kir(a)` словит `kirli` и т.п. — для коротких
   основ держать явный список допустимых суффиксов: `-e/-a, -ye/-ya, -de/-da, -te/-ta, -den/-dan, -ten/-tan, -i/-ı/-u/-ü, -yi/-yı`);
2) нормализация регистра строго через `lowercased(with: Locale(identifier: "tr"))` — см. §7 про İ/ı.

Глаголы тоже спрягаются (`harcadım/harcadık/harcamışım`) — для глаголов матчить основу
(`harcad-`, `öded-`, `ald-`) тем же префикс-подходом.

**Глаголы трат (expenseKeywords, ~20):**

| Основа для матчинга | Полные формы | Значение |
|---|---|---|
| harcad- | harcadım, harcadık | потратил |
| ald- | aldım, aldık | купил ⚠️ омоним, см. ниже |
| satın ald- | satın aldım | купил (однозначно) |
| öded- | ödedim, ödedik | заплатил |
| ödeme yapt- | ödeme yaptım | сделал платёж |
| verd- | verdim (taksiye 200 verdim) | отдал/заплатил |
| yatırd- | yatırdım | внёс/вложил |
| gönderd- | gönderdim | отправил (перевод) |
| yollad- | yolladım | отправил (разг.) |
| alışveriş yapt- | alışveriş yaptım | сделал покупки |
| sipariş verd-/ett- | sipariş verdim, sipariş ettim | заказал |
| ısmarlad- | ısmarladım | угостил/заказал |
| yed- | yedik, yedim (dışarıda yedik) | поели (трата на еду) |
| içtik/içtim | kahve içtim | выпили (кофе и т.п.) |
| tuttu | 500 lira tuttu | «обошлось в» |
| gitti | 300 lira gitti | «ушло» (денег) |
| çektim | para çektim | снял наличные |
| bozdurdum | dolar bozdurdum | обменял валюту |
| abone old- | abone oldum | подписался |
| kestiler | fatura kestiler | выставили счёт (разг.) |

**Глаголы/маркеры дохода (incomeKeywords):**

| Маркер | Пример | Значение |
|---|---|---|
| maaş (+ ald-/yattı/geldi) | maaşım yattı, maaş aldım | зарплата пришла/получил |
| yattı | param yattı, 5000 yattı | «упало» на счёт |
| geldi | para geldi, iade geldi | пришло (деньги/возврат) |
| kazand- | kazandım | заработал |
| gelir | gelir, ek gelir | доход |
| prim | prim aldım | премия |
| iade | iade aldım, iade geldi | возврат |
| satt- | sattım (bisikleti sattım) | продал |
| burs | burs yattı | стипендия |
| harçlık | harçlık aldım | карманные деньги |

⚠️ **Омонимия `aldım`**: «ekmek aldım» = купил хлеб (трата), но «maaş aldım / para aldım /
prim aldım / iade aldım» = получил (доход). Разруливать **контекстом объекта**: сначала
проверять фразу на доходные маркеры-существительные (`maaş, para+ald, prim, iade, burs,
harçlık, bahşiş`) — при совпадении классифицировать как income; иначе `ald-` = expense.
Порядок проверки в парсере: income-маркеры → expense-глаголы (прецедент EN-парсера:
`plans/006-voice-english-date-and-type-keywords.md`).

**Даты (parseDate):**
- `bugün` (сегодня), `dün` (вчера), `evvelsi gün` / `önceki gün` / `dünden önceki gün` (позавчера)
- `geçen hafta` (на прошлой неделе), `salı günü` (во вторник) — второй приоритет
- числовые: `3 Temmuz`, `03.07`, `03.07.2026` (DD.MM.YYYY)

**Союзы-разделители мультиопераций (VoiceInputSegmenter, ~8):**
`ve` (и), `sonra` (потом), `ondan sonra` (после этого), `daha sonra` (позже),
`bir de` / `birde` (ещё и — разг. слитное написание тоже матчить), `ayrıca` (кроме того),
`artı` (плюс), `hem de` (да ещё и), `bir daha` (ещё раз).
Пример: «Markete 450 lira harcadım, sonra taksiye 200 verdim, bir de kahve içtim 90 lira» → 3 операции.

**Ключевики категорий (~30, маппинг на категории Tenra):**

| TR-основа | Словоформы (пример) | Категория |
|---|---|---|
| market | markete, marketten | Продукты |
| bakkal | bakkaldan | Продукты |
| manav | manavdan | Продукты (овощи-фрукты) |
| yemek | yemeğe ⚠️ чередование k→ğ | Еда вне дома |
| restoran | restoranda | Еда вне дома |
| kahve | kahveye | Кафе/кофе |
| taksi | taksiye, taksiden | Транспорт |
| otobüs | otobüse | Транспорт |
| metro | metroya | Транспорт |
| dolmuş | dolmuşa | Транспорт |
| benzin | benzine | Топливо |
| akaryakıt | akaryakıta | Топливо |
| kira | kirayı, kiraya | Жильё/аренда |
| aidat | aidatı | Жильё (взносы ЖК) |
| fatura | faturayı | Счета/платежи |
| elektrik | elektriğe ⚠️ k→ğ | Коммунальные |
| su | suya | Коммунальные |
| doğalgaz | doğalgaza | Коммунальные |
| internet | internete | Связь |
| telefon | telefona | Связь |
| eczane | eczaneden | Здоровье |
| doktor | doktora | Здоровье |
| hastane | hastaneye | Здоровье |
| spor | spora | Спорт |
| sinema | sinemaya | Развлечения |
| giyim / kıyafet | kıyafete | Одежда |
| kuaför / berber | kuaföre, berbere | Уход за собой |
| okul / kurs | okula, kursa | Образование |
| kitap | kitaba | Образование/книги |
| hediye | hediyeye | Подарки |
| uçak / bilet | uçağa ⚠️ k→ğ, bilete | Путешествия |
| otel | otele | Путешествия |

⚠️ Чередование согласных (k→ğ: `yemek→yemeğe`, `elektrik→elektriğe`, `uçak→uçağa`) ломает
наивный prefix-match. Решение: для основ на `k` добавлять вторую основу с `ğ`
(`yemek` + `yemeğ`), либо матчить укороченный префикс без последней согласной.

**Фонетические алиасы брендов (ServiceLogo, ~10):**

| Как распознаёт SFSpeechRecognizer | Канонический бренд |
|---|---|
| getir | Getir |
| trendyol | Trendyol |
| bip / be ip | BiP |
| yemek sepeti / yemeksepeti | Yemeksepeti |
| hepsi burada / hepsiburada | Hepsiburada |
| migros | Migros |
| bim | BİM |
| a yüz bir / a101 | A101 |
| şok / shok | Şok Market |
| türk hava yolları / T-H-Y | THY |
| papara | Papara |
| turkcell / türkcell | Turkcell |

`SFSpeechRecognizer` locale: `tr-TR`; contextual strings — из локальных названий категорий,
счетов и брендов выше.

### 5.2 Импорт выписок (StatementTextParser)

**Топ-банки для образцов PDF (5 банков + финтех):**

| Банк | Типичные заголовки колонок выписки |
|---|---|
| Ziraat Bankası | Tarih, Açıklama, Tutar, Bakiye |
| İş Bankası | İşlem Tarihi, Açıklama, Tutar, Bakiye |
| Garanti BBVA | Tarih, İşlem, Açıklama, Tutar |
| Akbank | Tarih, Açıklama, İşlem Tutarı, Bakiye |
| Yapı Kredi | İşlem Tarihi, Valör, Açıklama, Tutar |
| Papara (финтех) | Tarih, İşlem Açıklaması, Tutar |

Ключевые слова-маркеры секций (аналог «ТРАНЗАКЦИИ ПО СЧЕТУ»): `HESAP HAREKETLERİ`,
`HESAP ÖZETİ`, `İŞLEM DETAYI`, `TARİH`, `AÇIKLAMA`, `TUTAR`, `İŞLEM`, `BAKİYE`, `VALÖR`.
⚠️ В шапках банки пишут КАПСОМ — `İŞLEM` содержит `İ` (заглавная i с точкой) — сравнение
только через локале-зависимый lowercase (см. §7), иначе `İŞLEM`.lowercased() ≠ `işlem`.

**Форматы рынка:**
- Даты: `DD.MM.YYYY` (03.07.2026), встречается `DD/MM/YYYY`
- Числа: `1.234,56` — точка = разделитель тысяч, запятая = десятичный (как ru/de)
- Валюта: `TL`, `₺`, `TRY`; долларовые счета в тех же банках: `USD`, `$`
- Расход/приход в выписках часто знаком (`-1.234,56`) или колонками `Borç` (дебет) / `Alacak` (кредит) — покрыть оба варианта

Собрать 3–5 реальных образцов PDF на банк и покрыть тестами (L3 из README).

### 5.3 CSV (CSVColumnMapping)

Локальные значения типов операций → внутренние:

| TR | Внутренний тип |
|---|---|
| gider, harcama, para çıkışı, borç | expense |
| gelir, kazanç, para girişi, alacak | income |
| transfer, havale, EFT, virman | transfer |

Заголовки колонок: `Tarih` → date, `Açıklama` → description, `Tutar` → amount,
`Kategori` → category, `Hesap` → account, `Para Birimi` / `Döviz` → currency.
Экспорт из Tenra на tr-локали должен проходить round-trip (см. [domains/csv.md](../domains/csv.md)).

## 6. Цены (TRY)

Якорь (KZ): 1490₸ / 4990₸ / 11900₸ ≈ **$3 / $10 / $24**. Турция — рынок с низким ARPU и
высокой ценовой чувствительностью → **агрессивно вниз от якоря**:

| План | Якорь в TRY (грубо, по курсу) | Рекомендация TR | ≈ USD |
|---|---|---|---|
| Месяц | ~₺130 | **₺79,99** | ~$1,9 |
| Год (14 дней триал) | ~₺420 | **₺399,99** | ~$9,5 → эффективно ₺33/мес |
| Lifetime | ~₺1000 | **₺899,99** | ~$21 |

Логика: месячная цена — ниже психологического порога «одна чашка кофе в месяц» и ниже
Netflix/Spotify TR; годовая даёт скидку ~58% от месячной — главный планируемый SKU;
lifetime ≈ 2,25× годовой.

⚠️ Практические замечания:
- Точные price points выбирать из **актуальной сетки ASC для TRY** — Apple несколько раз
  перестраивала турецкую сетку из-за инфляции; значения выше могут не совпасть с доступными
  тиерами один-в-один, брать ближайший.
- В ASC зафиксировать цену TRY **вручную** (не автоконвертация от базовой цены) — иначе
  очередная глобальная коррекция Apple молча поднимет цену.
- **Инфляционная коррекция**: пересматривать TRY-цены каждые 1–2 квартала (по CPI и новой
  сетке Apple). Для действующих подписчиков повышение цены подписки требует согласия
  (Apple price increase consent flow) — планировать повышения редкими и крупными шагами,
  а не частыми мелкими.
- Продукты/entitlement — те же, что в [PremiumConfig](../../Tenra/Services/Premium/PremiumConfig.swift);
  в RevenueCat это не новые продукты, а territory-цены в ASC + перевод paywall-текстов в дашборде RC.

## 7. Культурные и языковые заметки

- **Обращение «sen»** (ты) — норма для мобильных приложений в Турции (Getir, Trendyol,
  Papara пишут на «sen»). Черновики выше используют sen-формы (`bilirsin`, `belirle`,
  `paylaşmazsın`). «Siz» звучало бы казённо-банковски — не наш тон.
- ⚠️ **Дотированная/недотированная i (İ/ı) — инженерная ловушка.** В турецком 4 буквы i:
  `i ↔ İ` и `ı ↔ I`. Инвариантный `"İŞLEM".lowercased()` даёт `i̇şlem` (i + combining dot,
  2 скаляра) и НЕ равен строке `işlem`; `"I".lowercased()` даёт `i`, а турецкий ждёт `ı`.
  Любой кейс-инсенситивный матчинг турецких ключевиков (VoiceInputParser,
  StatementTextParser, поиск по категориям) обязан использовать
  `lowercased(with: Locale(identifier: "tr"))` / `compare(_:options:.caseInsensitive, locale:)`.
  Добавить юнит-тест: `İŞLEM/IŞIK/Bakiye` матчатся с `işlem/ışık/bakiye` на tr-локали.
- **Плюрализация**: категории `one/other` (stringsdict — 2 plural-ключа, см. L1 README).
  Нюанс: после числительного существительное НЕ множится — `3 hesap`, не `3 hesaplar`;
  формы one/other в турецком часто совпадают («1 işlem», «5 işlem») — при переводе
  stringsdict это нормально, не «ошибка».
- Разделители чисел и дат в UI (`1.234,56 ₺`, `03.07.2026`) приходят из `Locale` автоматически —
  проверить, что кастомные форматтеры (`Formatting.formatCurrencySmart`) уважают локаль.
- Символ валюты: `₺` ставится ПЕРЕД суммой у Apple-форматтера (`₺450,00`), в разговорной
  записи турки пишут `450 TL` — в маркетинговых скриншотах допустимо `₺450`, в голосовых
  примерах использовать «lira».

## 8. Чек-лист запуска (tr)

Порядок по воркстримам README (L1–L5); релиз на витрину — только когда готово всё.

- [ ] **L1**: перевод `Localizable.strings` (1347 ключей) + `Localizable.stringsdict` (one/other)
- [ ] **L1**: `plutil -lint` + diff-паритет ключей (скрипт аудита 2026-07-03)
- [ ] **L1**: нейтив-вычитка UI-строк (тон «sen», термины: gider/harcama, hesap/bakiye)
- [ ] **L2**: `expenseKeywords`/`incomeKeywords` по §5.1, включая разрул омонимии `aldım`
- [ ] **L2**: **prefix-match по основам** + защита коротких основ + k→ğ-варианты (инженерное требование §5.1)
- [ ] **L2**: `parseDate` (bugün/dün/evvelsi gün + DD.MM.YYYY), союзы Segmenter (§5.1)
- [ ] **L2**: локале-зависимый lowercase (İ/ı) во всех матчерах + юнит-тест (§7)
- [ ] **L2**: `SFSpeechRecognizer(locale: tr-TR)` + contextual strings; алиасы брендов (§5.1)
- [ ] **L3**: образцы PDF-выписок 5 банков + Papara, тесты парсера (заголовки, `1.234,56`, Borç/Alacak)
- [ ] **L3**: `CSVColumnMapping` gider/gelir/transfer + round-trip тест
- [ ] **L4**: валидация ключевиков реальными объёмами (ASA TR) → финализировать Title/Subtitle/Keywords
- [ ] **L4**: залить метаданные §3, скриншоты §4 (мультивалюта — hero, суммы TRY+USD, UI на турецком)
- [ ] **L4**: цены TRY вручную в ASC по актуальной сетке (§6); paywall-тексты в RevenueCat — на турецком
- [ ] **L4**: проверить поддержку XAU (золото) — решить про упоминания золота в витрине (§1)
- [ ] **L5**: прогон приложения в tr-локали (Scheme → App Language), ключевые экраны
- [ ] **L5**: 10–15 голосовых тест-фраз (суммы, категории с падежами, даты, мультиоперации, `maaş aldım` vs `ekmek aldım`)
- [ ] **L5**: нейтив-ревью витрины и скриншотов перед сабмитом
