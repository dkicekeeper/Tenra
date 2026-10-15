# Tenra — Локализация: Португальский (Бразилия), витрина pt-BR

> Статус: план/черновик. Приоритет №5, фаза 3 (см. [README.md](README.md)).
> ⚠️ Все португальские тексты в этом файле — AI-черновик на бразильском португальском.
> Перед сабмитом обязательна вычитка нейтивом из Бразилии (не Португалии!) — тон, лексика,
> естественность ASO-формулировок.
> Витрина ASC: **pt-BR** (одна витрина, покрывает Бразилию; Португалия увидит pt-BR как fallback —
> это приемлемо, но учтено в культурных заметках).

---

## 1. Обзор рынка

**Масштаб.** Бразилия — крупнейший App Store-рынок Латинской Америки и один из крупнейших в мире
по загрузкам (топ-5 глобально по установкам iOS+Android). Финансовые приложения — стабильно
топ-категория: культура «controle de gastos» массовая, финансовая тревожность высокая
(инфляция, закредитованность, повсеместные рассрочки/parcelamento).

**Но: низкий ARPU.** Готовность платить за подписки заметно ниже, чем в US/EU. Конверсия
trial→paid будет ниже, LTV ниже — это рынок объёма, а не маржи. Цены надо ставить агрессивно
локальные (см. §6), иначе установок много, а выручки нет.

**Конкуренты — сильные и локальные:**

| Приложение | Позиционирование | Слабость для нас |
|---|---|---|
| **Mobills** | Лидер рынка, «controle financeiro», подключение банков через Open Finance, огромная база | Подписка сравнительно дорогая, реклама в free, требует аккаунт |
| **Organizze** | Простой учёт, sync банков, веб-версия | Тоже облако + банк-логины, слабая мультивалютность |
| **Minhas Economias** | Старожил, бесплатный, планирование | Устаревший UX, стагнация |
| Гиганты-банки (Nubank, Itaú) | Встроенная аналитика трат в банковских приложениях | Видят только «свой» банк, нет бюджетов/депозитов/мультивалютности |

**Наша дифференциация на этом рынке:**
1. **Приватность без привязки банка.** Open Finance приучил бразильцев к банк-логинам в
   финансовых приложениях — и именно это отпугивает заметный сегмент пользователей
   (страх утечек, недоверие к «ещё одному приложению с доступом к банку», травма от
   мошенничества/golpes). Позиционирование «sem conectar seu banco» — прямой контраст
   с Mobills/Organizze и главный месседж витрины.
2. **Депозиты и кредиты как первоклассные сущности.** Poupança/CDB с начислением процентов
   и empréstimos с графиком платежей — у локальных конкурентов это либо нет, либо
   поверхностно. В стране рассрочек учёт кредитов — реальная боль.
3. **Мультивалютность с честным FX** — ниша (фрилансеры на доллары, путешественники,
   держатели долларовых накоплений), но лояльная.

**Риск:** «sem conectar banco» = ручной ввод, а рынок избалован автосинком. Компенсируем
голосовым вводом и импортом выписок (PDF/CSV) — это надо явно продавать в описании как
«автоматизация без доступа к банку».

---

## 2. ASO-ключевики (pt-BR)

⚠️ Объёмы ниже — экспертная оценка (H/M/L). Перед финализацией метаданных обязательна
валидация реальными объёмами: ASA Search Popularity для витрины Бразилия или ASO-инструмент
(AppTweak/Astro/Sensor Tower). Порядок в Keywords-поле пересобрать по результатам.

| # | Ключевик | Оценка объёма | Конкуренция | Комментарий |
|---|---|---|---|---|
| 1 | controle de gastos | H | H | Главный запрос рынка; Mobills таргетит его же — берём в Title |
| 2 | finanças pessoais | H | H | Категорийный запрос — в Subtitle |
| 3 | orçamento | M–H | M | «Бюджет» — в Subtitle |
| 4 | controle financeiro | H | H | Синоним №1; покрывается кросс-комбинацией Title («controle») + Keywords |
| 5 | planilha de gastos | M | L–M | Люди ищут «таблицу расходов» — перехват аудитории Google Sheets; `planilha` в Keywords |
| 6 | economizar dinheiro | M | M | «Экономить деньги»; `economizar` + `dinheiro` в Keywords |
| 7 | gastos mensais | M | L | Комбинация из `gastos` (Title) + Keywords |
| 8 | assinaturas | M | L–M | Трекер подписок — наш фича-ключевик, низкая конкуренция; `assinatura` в Keywords |
| 9 | despesas | M | M | Синоним «gastos» — `despesa` в Keywords |
| 10 | carteira digital | M | H | «Кошелёк»; берём только `carteira`, «digital» слишком конкурентно (платёжные кошельки) |
| 11 | poupança | M | M | «Накопления/сберсчёт» — наш дифференциатор (депозиты); в Keywords |
| 12 | dívidas / cartão de crédito | M | M | Долги и кредитка — боль рынка; `dívida`, `cartão` в Keywords |

Дополнительно в поле Keywords: `salário`, `renda` (доход), `conta` (счёт/счета за услуги — двойное значение работает на нас).

---

## 3. Метаданные ASC (витрина pt-BR)

Референс структуры — US/KZ-метаданные из [README.md](README.md). Счётчики символов посчитаны
честно (акцентированные символы = 1 символ в ASC).

### Title — 25/30
```
Tenra: Controle de Gastos
```
Прямое попадание в запрос №1. Запас 5 символов оставлен сознательно — после валидации
объёмов можно рассмотреть `Tenra: Controle de Gastos +` только если инструмент покажет
пользу, иначе не трогать.

### Subtitle — 28/30
```
Orçamento, Finanças Pessoais
```
Закрывает запросы №2 и №3. Вместе с Title индексируются комбинации
«controle financeiro», «orçamento pessoal», «gastos pessoais».

### Keywords — 99/100
```
despesa,dinheiro,economizar,planilha,carteira,assinatura,conta,poupança,dívida,cartão,salário,renda
```
Правила соблюдены: без пробелов, без дублей слов из Title/Subtitle (`gastos`, `controle`,
`orçamento`, `finanças` уже индексируются оттуда), единственное число там, где ASC
матчит формы.

### Promotional Text — 147/170
```
Orçamento por categoria, assinaturas, contas em várias moedas e importação de extratos — tudo sem conectar seu banco. Seus dados ficam só com você.
```
Promo не индексируется — используем для главного дифференциатора (приватность) и меняем
без ревью при акциях.

### Description — 1866 символов (цель 1500–2500 ✓)

Тон: тёплый, прямой, на «você». Первый абзац — приватность (дифференциатор №1 для рынка),
дальше фичи в порядке важности из продуктового брифа.

```
Tenra é o gerenciador de finanças pessoais que respeita a sua privacidade: sem conectar banco, sem Open Finance, sem anúncios. Você anota seus gastos, o Tenra faz o resto — e seus dados ficam no seu iPhone e no seu iCloud, mais ninguém tem acesso.

ORÇAMENTO POR CATEGORIA, DIRETO NA TELA INICIAL
Defina um limite mensal para mercado, transporte, lazer — e veja na hora quanto já gastou e quanto ainda sobra. Sem planilha, sem conta de padaria no papel.

TODAS AS SUAS FINANÇAS EM UM SÓ LUGAR
Contas, poupança e investimentos com rendimento, assinaturas e empréstimos com cronograma de parcelas. Tudo organizado sem entregar a senha do seu banco a ninguém.

VEJA PARA ONDE SEU DINHEIRO VAI
Relatórios claros de saldo, despesas e fluxo do mês. Descubra suas maiores categorias de gasto com uma análise visual mês a mês.

NOTA DE SAÚDE FINANCEIRA
Poupança, orçamentos e reserva de emergência resumidos em uma única nota — para você saber exatamente onde melhorar.

VÁRIAS MOEDAS, UM TOTAL HONESTO
Contas em reais, dólares ou euros com câmbio real. O Tenra converte tudo para a sua moeda base e mostra um único total confiável.

ADICIONE GASTOS POR VOZ
Diga "gastei 50 reais no mercado" e pronto: a transação está registrada, com valor e categoria certos.

IMPORTE O EXTRATO DO SEU BANCO
Traga extratos em PDF ou CSV do Nubank, Itaú, Bradesco, Caixa e outros bancos. O Tenra reconhece as transações e organiza tudo por categoria.

PRIVACIDADE DE VERDADE
Sem cadastro obrigatório, sem acesso à sua conta bancária, sem venda de dados, sem anúncios. Seus números são seus.

O Tenra é grátis para o dia a dia: registro de gastos ilimitado e até 3 contas. O Tenra Pro libera contas ilimitadas, entrada por voz, importação de PDF/CSV, poupança com rendimento e empréstimos — com 14 dias de teste grátis no plano anual.

Baixe o Tenra e assuma o controle do seu dinheiro hoje.
```

### What's New (первый pt-BR релиз) — 157 символов
```
Agora o Tenra fala português! Interface completa em português do Brasil, entrada por voz adaptada e importação de extratos dos principais bancos brasileiros.
```

---

## 4. Подписи скриншотов (8 фреймов, порядок залочен)

UI на скриншотах — на португальском, суммы в **BRL (R$)**, формат `R$ 1.234,56`.
Примеры сумм — правдоподобные для рынка (аренда ~R$ 1.800, мерк. ~R$ 650/мес).

| # | Экран | Заголовок | Подзаголовок |
|---|---|---|---|
| 1 | Главная | **Orçamento para cada categoria** | Limites, gastos e quanto sobra no mês — direto na tela inicial |
| 2 | Финансы | **Todas as suas finanças em um só lugar** | Contas, poupança, assinaturas e empréstimos — sem conectar seu banco |
| 3 | Аналитика | **Veja para onde seu dinheiro vai** | Saldo, despesas e fluxo do mês — tudo em um olhar |
| 4 | Финансовый скор | **A nota da sua saúde financeira** | Poupança, orçamentos e reserva de emergência em uma única nota |
| 5 | Топ категория | **Descubra seus maiores gastos** | Categorias de despesas com análise clara mês a mês |
| 6 | История | **Cada transação sob controle** | Gastos, receitas e rendimentos da poupança — em uma só lista |
| 7 | Голос | **Adicione gastos por voz** | "Gastei 50 reais no mercado" — e pronto, está registrado |
| 8 | Мультивалютность | **BRL, USD, EUR — um total honesto** | Contas em várias moedas, um único saldo confiável |

---

## 5. Адаптация фич

### 5.1 Голосовой ввод (VoiceInputParser + Segmenter)

`SFSpeechRecognizer` locale: `pt-BR` (не `pt-PT` — модели распознавания различаются заметно).
Contextual strings — из локализованных названий категорий и имён счетов пользователя.

**`expenseKeywords` — глаголы/маркеры трат (~14):**

| pt-BR | Комментарий |
|---|---|
| gastei | «потратил» — базовый |
| comprei | «купил» |
| paguei | «заплатил» |
| pago / paguei a conta | оплата счёта |
| dei | «отдал» (dei 50 pro estacionamento) |
| torrei | разг. «спустил/просадил» |
| desembolsei | «выложил» |
| saiu | «ушло» (saiu 200 do mercado) |
| custou | «стоило» |
| assinei | «подписался» (подписка) |
| parcelei | «взял в рассрочку» — очень бразильское |
| mandei um pix | «отправил pix» (см. заметку про Pix ниже) |
| fiz um pix | то же |
| transferi | перевод (маркер transfer, не expense — маппить отдельно) |

**`incomeKeywords` — глаголы/маркеры дохода (~8):**

| pt-BR | Комментарий |
|---|---|
| recebi | «получил» — базовый |
| ganhei | «заработал/выиграл» |
| salário / caiu o salário | «зарплата упала» — устойчивое выражение |
| entrou | «пришло» (entrou 500 na conta) |
| faturei | разг. «заработал» |
| rendeu | «принесло проценты» (доход по депозиту) |
| recebi um pix | входящий pix |
| me pagaram | «мне заплатили» |

**`parseDate` — слова и форматы:**
- `hoje` (сегодня), `ontem` (вчера), `anteontem` (позавчера)
- `sexta passada` / `semana passada` — прошлая пятница/неделя (nice-to-have)
- Числовые даты: `DD/MM` и `DD/MM/YYYY` (`no dia 15/06`), словами: `dia quinze de junho`
- Голосовые суммы: `cinquenta reais`, `dois mil e quinhentos`, разг. `cinquenta conto`,
  `um real e cinquenta` — числительные + «reais/real/conto»

**`VoiceInputSegmenter` — союзы-разделители мультиопераций (~8):**

`e` (и), `depois` (потом), `também` (тоже), `mais` (ещё/плюс), `aí` (разг. «а потом»),
`e ainda` (и ещё), `além disso` (кроме того), `e então` (и затем).
⚠️ `e` и `mais` встречаются внутри числительных (`dois mil e quinhentos`, `um real e cinquenta`) —
сегментер должен резать только между распознанными операциями, не внутри суммы
(тот же паттерн, что решали для EN «and»).

**Ключевики категорий (~30) — маппинг на категории Tenra:**

| pt-BR ключевики | Категория |
|---|---|
| uber, táxi, 99, corrida | Транспорт/Такси |
| gasolina, combustível, posto, etanol | Транспорт/Топливо |
| ônibus, metrô, passagem, bilhete único | Транспорт/Общественный |
| estacionamento, pedágio | Транспорт |
| mercado, supermercado, compras do mês | Продукты |
| feira, padaria, açougue, hortifruti | Продукты |
| restaurante, almoço, jantar, lanche | Кафе/Еда вне дома |
| ifood, delivery, pizza | Доставка еды |
| café, cafeteria | Кофе |
| farmácia, remédio | Здоровье/Аптека |
| médico, consulta, dentista, plano de saúde | Здоровье |
| academia, personal | Спорт |
| aluguel | Жильё/Аренда |
| condomínio, IPTU | Жильё |
| luz, energia, conta de luz | Коммуналка/Электричество |
| água, gás | Коммуналка |
| internet, wi-fi | Связь/Интернет |
| celular, recarga | Связь/Мобильный |
| cinema, show, balada | Развлечения |
| streaming, netflix, spotify | Подписки |
| roupa, tênis, sapato | Одежда |
| presente | Подарки |
| cabeleireiro, salão, barbearia | Красота |
| escola, faculdade, curso, mensalidade | Образование |
| pet, ração, veterinário | Питомцы |
| viagem, passagem aérea, hotel | Путешествия |
| fatura do cartão | Кредитная карта (оплата счёта) |
| parcela, prestação | Кредит/Рассрочка |
| mercado livre, shopee, amazon | Покупки онлайн |
| poupança, investimento, cdb | Накопления |

**`ServiceLogo` — фонетические алиасы брендов (~12):**

| Распознанное | Канонический бренд |
|---|---|
| nubank, nu, nu bank | Nubank |
| ifood, ai food | iFood |
| mercado livre, meli | Mercado Livre |
| pix | Pix (маркер перевода, не бренд-логотип) |
| itaú, itau | Itaú |
| bradesco | Bradesco |
| caixa, caixa econômica | Caixa |
| banco do brasil, bb | Banco do Brasil |
| noventa e nove, 99 | 99 |
| picpay, pic pay | PicPay |
| magalu, magazine luiza | Magazine Luiza |
| shopee, xopi | Shopee |

### 5.2 Импорт выписок (StatementTextParser)

**Топ-банки для образцов PDF (5 + 1):** Nubank, Itaú, Bradesco, Caixa Econômica Federal,
Banco do Brasil; шестым — **Inter** (полностью цифровой, аудитория пересекается с нашей).
Собрать по 2–3 реальных образца PDF-выписки на банк и покрыть тестами
(аналог существующих KZ-парсеров).

**Типичные заголовки/маркеры в выписках:**

| pt-BR | Значение |
|---|---|
| Extrato / Extrato da conta | Выписка |
| Data | Дата |
| Descrição | Описание |
| Valor | Сумма |
| Lançamento / Lançamentos | Операция / Операции |
| Saldo | Остаток |
| Entrada / Saída | Приход / Расход |
| Débito / Crédito | Дебет / Кредит |
| Histórico | История (Itaú/BB так называют колонку описания) |

**Форматы:**
- Даты: `DD/MM/YYYY` (03/07/2026), встречается `DD/MM` и `DD MMM` (`03 JUL`).
- Числа: `1.234,56` — точка = разделитель тысяч, запятая = десятичный.
  Отрицательные суммы: `-1.234,56` или `1.234,56 D` (маркер дебета).
- Валюта: `R$ 1.234,56`.

**⚠️ Pix — отдельное правило маппинга.** В бразильских выписках Pix — доминирующий тип
операции (`Pix enviado`, `Pix recebido`, `Transferência Pix`, `Pix — João S.`).
Строки Pix-переводов надо мапить в тип **transfer**, а не expense/income по знаку суммы —
иначе каждый перевод самому себе или другу раздует расходы/доходы. Эвристика: маркер
`pix` + имя физлица/свой счёт → transfer; `pix` + название мерчанта — оставить expense
(в Бразилии Pix'ом платят и в магазинах). Пограничные случаи — на ручное подтверждение
в экране маппинга импорта.

Также распознавать: `TED`, `DOC` (старые типы переводов → transfer), `compra no débito`,
`compra no crédito` (покупки), `fatura` (оплата счёта карты), `rendimento` (проценты → interest).

### 5.3 CSV (`CSVColumnMapping`)

Локальные значения типов операций:

| pt-BR значение в CSV | Тип Tenra |
|---|---|
| despesa, gasto, saída, débito | expense |
| receita, renda, entrada, crédito | income |
| transferência, transf, pix | transfer |

Заголовки колонок для автодетекта: `Data`, `Descrição`, `Categoria`, `Valor`, `Conta`, `Tipo`.
Числа в CSV бразильских банков — тоже `1.234,56`; сепаратор CSV из-за запятой-десятичной
часто `;` (точка с запятой) — парсер должен пробовать оба.

### 5.4 Логотипы

`ServiceLogoRegistry`: проверить наличие локальных брендов в jsDelivr-источнике —
Nubank, Itaú, Bradesco, Caixa, Banco do Brasil, Inter, iFood, Mercado Livre, Magazine Luiza,
99, PicPay, Shopee, Rappi, Globoplay. Отсутствующие — добавить в реестр.

---

## 6. Цены (BRL)

Якорь (KZ): ≈ $3 / $10 / $24 (мес / год / lifetime). Прямая конвертация в BRL
(курс ~R$ 5,4/$): ≈ R$ 16 / R$ 54 / R$ 130. **Для Бразилии это дорого** — рынок остро
ценочувствителен, ARPU низкий, а якорь восприятия задаёт Mobills.

**Ориентир Mobills** (проверить актуальные цены в момент запуска — они меняются и
часто дисконтируются): Premium порядка R$ 12–15/мес и R$ 90–130/год по прайсу, но
фактически почти всегда продаётся с агрессивной скидкой на годовой (~R$ 60–80 в акциях).
Organizze — сопоставимо.

**Рекомендация — агрессивно вниз от якоря:**

| План | Цена pt-BR | ≈ USD | Логика |
|---|---|---|---|
| Месяц | **R$ 9,90** | ~$1.8 | Ниже психологического порога R$ 10 и ниже Mobills |
| Год | **R$ 39,90** (14 дней триал) | ~$7.4 | ≈ R$ 3,33/мес — «дешевле одного кофе в месяц»; заметно ниже даже акционного Mobills |
| Lifetime | **R$ 99,90** | ~$18.5 | Под порогом R$ 100; lifetime — сильный оффер для рынка, где не любят подписки |

Механика: отдельные price points для витрины Бразилия в ASC (не автоконвертация),
те же продукты `PremiumConfig` / RevenueCat-оффер `default`. Тексты paywall в RevenueCat
dashboard перевести (включая обязательный футер Terms/Privacy). В paywall-тексте
подчеркнуть годовой план как «менее R$ 3,50 por mês».

---

## 7. Культурные заметки

1. **`você`, не `tu`.** Весь UI, метаданные и paywall — на «você» (нейтрально-тёплое
   обращение, стандарт бразильских продуктов). `tu` жив в отдельных регионах (юг,
   часть северо-востока), но в интерфейсах не используется. Императивы — «Adicione»,
   «Veja», «Baixe» (форма на você).
2. **Бразильский вариант, не европейский PT.** Ключевые расхождения, на которых
   палятся машинные переводы:
   - `poupança` — в Бразилии это конкретно сберегательный счёт (наш маппинг для
     «депозита»); универсальное «накопления» — тоже poupança/reserva.
   - `extrato` (выписка) — BR-написание; европейское `extracto` с «c» — маркер не-BR текста.
   - `celular` (BR) vs `telemóvel` (PT); `tela` (BR) vs `ecrã` (PT); `aplicativo/app` (BR)
     vs `aplicação` (PT); `ônibus` (BR) vs `autocarro` (PT); `gerenciar` (BR) vs `gerir` (PT).
   - Гласные с циркумфлексом там, где PT-PT пишет острое ударение: `gênero/econômico` (BR)
     vs `género/económico` (PT) — по этому признаку легко проверить весь `Localizable.strings`.
3. **Плюрализация: one/other, и `one` покрывает 0 и 1.** По CLDR для `pt` категория
   `one` — это i = 0..1: строка «one» будет показана и для **нуля** («0 transação»).
   Формулировки plural-ключей в `Localizable.stringsdict` должны звучать нормально
   с нулём — либо нейтральная форма («0 transação» приемлемо, но лучше «nenhuma transação»
   через отдельную обработку нуля в коде, как уже сделано для fr).
4. **Pix — часть языка.** «fazer um pix» — обиходный глагол; в UI и голосе Pix должен
   узнаваться (см. §5.1, §5.2). Не переводить и не склонять.
5. **Деньги в речи:** `real/reais`, разговорное `conto` (= real), `pila` (юг).
   Формат отображения: `R$ 1.234,56` — пробел после R$, точка-тысячи, запятая-десятичные
   (наш `FormattedAmountText` берёт это из локали автоматически — проверить, что
   `pt_BR` locale даёт именно этот формат).
6. **Рассрочка (parcelamento) — культурная норма.** «em 12x sem juros» — привычная
   модель потребления. Учёт кредитов/рассрочек — говорить на этом языке:
   `parcela` (платёж по рассрочке), `prestação` (взнос), `fatura` (счёт по карте).
7. **Тон коммуникации** — тёплый, прямой, без канцелярита. Бразильский маркетинг
   дружелюбнее и эмоциональнее европейского; сухие формулировки читаются как перевод.

---

## 8. Чек-лист запуска pt-BR

Инженерные воркстримы — по общей схеме L1–L5 из [README.md](README.md).

- [ ] **L1. UI:** перевод `Localizable.strings` (1347 ключей) на pt-BR + `Localizable.stringsdict`
      (one/other; проверить формулировки `one` с нулём — §7.3)
- [ ] **L1:** `plutil -lint` + diff-проверка паритета ключей со скриптом аудита
- [ ] **L1:** вычитка нейтивом-бразильцем (UI + этот файл целиком); проверка на PT-PT-измы (§7.2)
- [ ] **L2. Голос:** `expenseKeywords`/`incomeKeywords` (§5.1), `parseDate`
      (hoje/ontem/anteontem + DD/MM), ключевики категорий (~30), союзы сегментера
      (осторожно с `e`/`mais` внутри числительных), алиасы брендов; locale `pt-BR`
      для `SFSpeechRecognizer`
- [ ] **L2:** 10–15 тестовых голосовых фраз на pt-BR (суммы словами, `conto`, мультиоперации, Pix)
- [ ] **L3. Выписки:** образцы PDF Nubank, Itaú, Bradesco, Caixa, Banco do Brasil, Inter;
      заголовки (§5.2), формат `1.234,56` + `DD/MM/YYYY`; **правило Pix → transfer** + тесты
- [ ] **L3:** `CSVColumnMapping` — despesa/receita/transferência (§5.3), сепаратор `;`
- [ ] **L3:** `ServiceLogoRegistry` — локальные бренды (§5.4)
- [ ] **L4. ASC:** валидация ключевиков реальными объёмами (ASA/ASO-инструмент), пересборка
      Keywords-поля при необходимости
- [ ] **L4:** метаданные из §3 на витрину pt-BR (после нейтив-ревью)
- [ ] **L4:** 8 скриншотов — UI на pt, подписи из §4, суммы в R$
- [ ] **L4:** price points BRL из §6 в ASC (проверить актуальные цены Mobills перед финализацией);
      paywall-тексты в RevenueCat dashboard (+ футер Terms/Privacy)
- [ ] **L5. Верификация:** прогон приложения в локали pt-BR (Scheme → App Language),
      ключевые экраны: главная, финансы, аналитика, история, paywall, онбординг
- [ ] **L5:** проверка формата `R$ 1.234,56` во всех money-виджетах (`FormattedAmountText`)
- [ ] **L5:** финальный native-review чек-лист перед сабмитом
- [ ] **Пост-запуск:** 6–8 недель метрик (установки, конверсия trial→paid в ASC + RevenueCat)
      перед решением о ценах/следующей фазе
