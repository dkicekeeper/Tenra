# Tenra 1.8.3: What's New (ASC, 13 storefront locales and en-GB)

Version 1.8.3, in the store since 2026-11-13/14 (App Store Connect showed READY_FOR_DISTRIBUTION on
2026-11-14) with TestFlight build 90 (from the cloud, `main` at fa3bf62). Sent for review on
2026-11-13 on the founder's word (`prepare-review --submit`), released after approval. Builds 77
to 89 (2026-11-11 to 13) were earlier states of the same version; 85 failed at signing and was
never uploaded. The assistant's server was deployed the same day with prompt 2026-11-13.11 (eval
on Haiku at low effort: 100 of 104). The phone checks of the checklist were not marked done
before the release; they moved to [release-notes.md](../release-notes.md).
`prepare-version` (Actions → App Store Connect, [asc.md](../asc.md)) pasted each block into App
Store Connect; en-GB (search in Kazakhstan) carries ru's text. No em dashes (user rule).

What the version brought: Ten as a helper for the app ([plan-ten-agent.md](../plan-ten-agent.md):
forms opened with their fields filled in, the state of the app, help with a complaint, editing
and deleting records, moving a merchant's records, goals and debts, a subscription's pause, the
loan payment form, loans' and deposits' terms, subscriptions found in the history), order in the
data (payments on review, the category audit with rename, merge and delete, subcategories,
duplicates, budgets from what is spent, the subscription audit, merchant rules and brands, an
account's balance, the monthly tidy-up), Ten's home with a card that always offers an action,
feedback through Ten, and a paywall per gate (RevenueCat placements).

## en-US

```
What's new in Tenra:
• Ten now does things for you: opens the form for a new deposit, loan, account or category with what you said already filled in, corrects or deletes an operation, moves a merchant's operations to another category, changes a goal or a debt, pauses a subscription. You confirm each change on a card and can undo it.
• Ten knows the app: ask how to do something and get a button to the right screen. It finds payments in your history that look like subscriptions and tells you the terms of your loans and deposits.
• Ten keeps your data in order: it goes through the payments waiting for review, suggests changes to your categories and merges them, finds records entered twice, offers budgets based on what you really spend, checks your subscriptions and remembers a category for a merchant.
• Something not working? Tell Ten what went wrong and it will try to fix it right away. Ten's home screen is simpler too.
```

## ru

```
Что нового в Tenra:
• Тэн теперь делает сам: открывает форму нового депозита, кредита, счёта или категории с уже заполненными полями, исправляет и удаляет операции, переносит операции продавца в другую категорию, меняет цель или долг, ставит подписку на паузу. Каждое изменение вы подтверждаете на карточке и можете отменить.
• Тэн знает приложение: спросите, как что-то сделать, и получите кнопку на нужный экран. Он находит в истории платежи, похожие на подписки, и рассказывает условия ваших кредитов и депозитов.
• Тэн наводит порядок: разбирает платежи на проверке, предлагает правки категорий и объединяет их, находит записи, внесённые дважды, подбирает лимиты по вашим реальным тратам, проверяет подписки и запоминает категорию для продавца.
• Что-то не получается? Напишите Тэну, что пошло не так, и он попробует решить это сразу. Главный экран Тэна стал проще.
```

## en-GB

```
Что нового в Tenra:
• Тэн теперь делает сам: открывает форму нового депозита, кредита, счёта или категории с уже заполненными полями, исправляет и удаляет операции, переносит операции продавца в другую категорию, меняет цель или долг, ставит подписку на паузу. Каждое изменение вы подтверждаете на карточке и можете отменить.
• Тэн знает приложение: спросите, как что-то сделать, и получите кнопку на нужный экран. Он находит в истории платежи, похожие на подписки, и рассказывает условия ваших кредитов и депозитов.
• Тэн наводит порядок: разбирает платежи на проверке, предлагает правки категорий и объединяет их, находит записи, внесённые дважды, подбирает лимиты по вашим реальным тратам, проверяет подписки и запоминает категорию для продавца.
• Что-то не получается? Напишите Тэну, что пошло не так, и он попробует решить это сразу. Главный экран Тэна стал проще.
```

## de-DE

```
Neu in Tenra:
• Ten erledigt jetzt Dinge für Sie: öffnet das Formular für eine neue Einlage, einen Kredit, ein Konto oder eine Kategorie mit bereits ausgefüllten Angaben, korrigiert oder löscht eine Buchung, verschiebt die Buchungen eines Händlers in eine andere Kategorie, ändert ein Sparziel oder eine Schuld, pausiert ein Abo. Jede Änderung bestätigen Sie auf einer Karte und können sie rückgängig machen.
• Ten kennt die App: Fragen Sie, wie etwas geht, und Sie bekommen eine Taste zum richtigen Bildschirm. Ten findet in Ihrem Verlauf Zahlungen, die wie Abos aussehen, und nennt die Konditionen Ihrer Kredite und Einlagen.
• Ten hält Ihre Daten in Ordnung: Er geht die Zahlungen zur Prüfung durch, schlägt Änderungen an Ihren Kategorien vor und führt sie zusammen, findet doppelt erfasste Einträge, schlägt Budgets nach Ihren tatsächlichen Ausgaben vor, prüft Ihre Abos und merkt sich die Kategorie eines Händlers.
• Etwas klappt nicht? Schreiben Sie Ten, was schiefgelaufen ist, und Ten versucht, es sofort zu lösen. Tens Startbildschirm ist außerdem einfacher geworden.
```

## es-ES

```
Novedades en Tenra:
• Ten ahora hace cosas por ti: abre el formulario de un nuevo depósito, préstamo, cuenta o categoría con lo que dijiste ya rellenado, corrige o elimina una operación, mueve las operaciones de un comercio a otra categoría, cambia un objetivo o una deuda y pausa una suscripción. Confirmas cada cambio en una tarjeta y puedes deshacerlo.
• Ten conoce la app: pregunta cómo hacer algo y recibe un botón a la pantalla correcta. Encuentra en tu historial pagos que parecen suscripciones y te dice las condiciones de tus préstamos y depósitos.
• Ten pone orden en tus datos: repasa los pagos pendientes de revisión, propone cambios en tus categorías y las une, encuentra registros introducidos dos veces, sugiere presupuestos según lo que gastas de verdad, revisa tus suscripciones y recuerda la categoría de un comercio.
• ¿Algo no funciona? Cuéntale a Ten qué ha fallado e intentará resolverlo al momento. La pantalla de inicio de Ten también es más sencilla.
```

## es-MX

```
Novedades en Tenra:
• Ten ahora hace cosas por ti: abre el formulario de un nuevo depósito, préstamo, cuenta o categoría con lo que dijiste ya llenado, corrige o elimina una operación, mueve las operaciones de un comercio a otra categoría, cambia una meta o una deuda y pausa una suscripción. Confirmas cada cambio en una tarjeta y puedes deshacerlo.
• Ten conoce la app: pregunta cómo hacer algo y recibe un botón a la pantalla correcta. Encuentra en tu historial pagos que parecen suscripciones y te dice las condiciones de tus préstamos y depósitos.
• Ten pone orden en tus datos: repasa los pagos pendientes de revisión, propone cambios en tus categorías y las une, encuentra registros introducidos dos veces, sugiere presupuestos según lo que gastas de verdad, revisa tus suscripciones y recuerda la categoría de un comercio.
• ¿Algo no funciona? Cuéntale a Ten qué salió mal e intentará resolverlo al momento. La pantalla de inicio de Ten también es más sencilla.
```

## fr-FR

```
Nouveautés de Tenra :
• Ten agit désormais pour vous : il ouvre le formulaire d’un nouveau dépôt, prêt, compte ou d’une nouvelle catégorie avec ce que vous avez dit déjà rempli, corrige ou supprime une opération, déplace les opérations d’un commerçant vers une autre catégorie, modifie un objectif ou une dette, met un abonnement en pause. Vous confirmez chaque changement sur une carte et pouvez l’annuler.
• Ten connaît l’app : demandez comment faire quelque chose et recevez un bouton vers le bon écran. Il trouve dans votre historique les paiements qui ressemblent à des abonnements et vous donne les conditions de vos prêts et dépôts.
• Ten met de l’ordre dans vos données : il passe en revue les paiements à vérifier, propose des changements de catégories et les fusionne, trouve les opérations saisies deux fois, suggère des budgets selon vos dépenses réelles, vérifie vos abonnements et retient la catégorie d’un commerçant.
• Quelque chose ne marche pas ? Dites à Ten ce qui ne va pas et il essaiera de le résoudre tout de suite. L’écran d’accueil de Ten est aussi plus simple.
```

## fr-CA

```
Nouveautés de Tenra :
• Ten agit désormais pour vous : il ouvre le formulaire d’un nouveau dépôt, prêt, compte ou d’une nouvelle catégorie avec ce que vous avez dit déjà rempli, corrige ou supprime une opération, déplace les opérations d’un commerçant vers une autre catégorie, modifie un objectif ou une dette, met un abonnement en pause. Vous confirmez chaque changement sur une carte et pouvez l’annuler.
• Ten connaît l’app : demandez comment faire quelque chose et recevez un bouton vers le bon écran. Il trouve dans votre historique les paiements qui ressemblent à des abonnements et vous donne les conditions de vos prêts et dépôts.
• Ten met de l’ordre dans vos données : il passe en revue les paiements à vérifier, propose des changements de catégories et les fusionne, trouve les opérations saisies deux fois, suggère des budgets selon vos dépenses réelles, vérifie vos abonnements et retient la catégorie d’un commerçant.
• Quelque chose ne fonctionne pas? Dites à Ten ce qui ne va pas et il essaiera de le régler tout de suite. L’écran d’accueil de Ten est aussi plus simple.
```

## tr

```
Tenra'daki yenilikler:
• Ten artık sizin yerinize yapıyor: yeni bir mevduat, kredi, hesap veya kategori formunu söyledikleriniz doldurulmuş olarak açar, bir işlemi düzeltir veya siler, bir satıcının işlemlerini başka bir kategoriye taşır, bir hedefi veya borcu değiştirir, bir aboneliği duraklatır. Her değişikliği bir kartta onaylarsınız ve geri alabilirsiniz.
• Ten uygulamayı biliyor: bir şeyin nasıl yapıldığını sorun, doğru ekrana giden bir düğme alın. Geçmişinizde aboneliğe benzeyen ödemeleri bulur ve kredi ile mevduatlarınızın koşullarını söyler.
• Ten verilerini düzenli tutar: kontrol bekleyen ödemeleri gözden geçirir, kategorilerin için değişiklik önerir ve onları birleştirir, iki kez girilen kayıtları bulur, gerçek harcamalarına göre bütçe önerir, aboneliklerini kontrol eder ve bir satıcının kategorisini hatırlar.
• Bir şey mi çalışmıyor? Ten'e neyin ters gittiğini yazın, hemen çözmeye çalışsın. Ten'in ana ekranı da sadeleşti.
```

## pt-BR

```
Novidades no Tenra:
• O Ten agora faz por você: abre o formulário de um novo depósito, empréstimo, conta ou categoria com o que você disse já preenchido, corrige ou exclui uma operação, move as operações de um estabelecimento para outra categoria, altera uma meta ou uma dívida e pausa uma assinatura. Você confirma cada mudança em um cartão e pode desfazer.
• O Ten conhece o app: pergunte como fazer algo e receba um botão para a tela certa. Ele encontra no seu histórico pagamentos que parecem assinaturas e informa as condições dos seus empréstimos e depósitos.
• Ten põe ordem nos seus dados: revisa os pagamentos pendentes, sugere mudanças nas suas categorias e as une, encontra registros lançados duas vezes, propõe orçamentos com base no que você realmente gasta, confere suas assinaturas e lembra a categoria de um estabelecimento.
• Algo não funciona? Conte ao Ten o que deu errado e ele tentará resolver na hora. A tela inicial do Ten também ficou mais simples.
```

## it

```
Novità in Tenra:
• Ten ora fa le cose per te: apre il modulo di un nuovo deposito, prestito, conto o categoria con ciò che hai detto già compilato, corregge o elimina un'operazione, sposta le operazioni di un esercente in un'altra categoria, modifica un obiettivo o un debito, mette in pausa un abbonamento. Confermi ogni modifica su una scheda e puoi annullarla.
• Ten conosce l'app: chiedi come fare qualcosa e ricevi un pulsante per la schermata giusta. Trova nella cronologia i pagamenti che sembrano abbonamenti e ti dice le condizioni dei tuoi prestiti e depositi.
• Ten tiene in ordine i tuoi dati: passa in rassegna i pagamenti da controllare, propone modifiche alle categorie e le unisce, trova i movimenti inseriti due volte, suggerisce budget in base a quanto spendi davvero, controlla gli abbonamenti e ricorda la categoria di un esercente.
• Qualcosa non funziona? Scrivi a Ten cosa è andato storto e proverà a risolverlo subito. Anche la schermata iniziale di Ten è più semplice.
```

## uk

```
Що нового в Tenra:
• Тен тепер робить сам: відкриває форму нового депозиту, кредиту, рахунку чи категорії з уже заповненими полями, виправляє і видаляє операції, переносить операції продавця в іншу категорію, змінює ціль або борг, ставить підписку на паузу. Кожну зміну ви підтверджуєте на картці й можете скасувати.
• Тен знає застосунок: запитайте, як щось зробити, і отримайте кнопку на потрібний екран. Він знаходить в історії платежі, схожі на підписки, і розповідає умови ваших кредитів і депозитів.
• Тен наводить лад: розбирає платежі на перевірці, пропонує зміни категорій і об’єднує їх, знаходить записи, внесені двічі, підбирає ліміти за вашими реальними витратами, перевіряє підписки й запам’ятовує категорію для продавця.
• Щось не виходить? Напишіть Тену, що пішло не так, і він спробує вирішити це одразу. Головний екран Тена став простішим.
```

## ja

```
Tenraの新機能:
• テンが代わりに操作します。新しい預金、ローン、口座、カテゴリのフォームを、話した内容が入力された状態で開きます。取引の修正と削除、店舗の取引を別のカテゴリへまとめて移動、目標や貸し借りの変更、サブスクリプションの一時停止もできます。変更はカードで確認してから保存され、取り消せます。
• テンはアプリの使い方を知っています。やり方をたずねると、その画面へのボタンが届きます。履歴からサブスクリプションらしい支払いを見つけ、ローンや預金の条件も答えます。
• Tenがデータを整理します。確認待ちの支払いを見直し、カテゴリの変更や統合を提案し、二重に入力された記録を見つけ、実際の支出に合わせた予算を提案し、サブスクリプションを確認し、店舗ごとのカテゴリを覚えます。
• うまくいかないときは、何が起きたかをテンに伝えてください。その場で解決を試みます。テンのホーム画面もすっきりしました。
```

## ko

```
Tenra의 새로운 기능:
• 텐이 대신 처리합니다. 새 예금, 대출, 계좌, 카테고리 양식을 말씀하신 내용이 채워진 상태로 열고, 거래를 수정하거나 삭제하고, 한 가맹점의 거래를 다른 카테고리로 옮기고, 목표나 빚을 변경하고, 구독을 일시 중지합니다. 모든 변경은 카드에서 확인한 뒤 저장되며 되돌릴 수 있습니다.
• 텐은 앱 사용법을 압니다. 방법을 물으면 해당 화면으로 가는 버튼을 드립니다. 내역에서 구독처럼 보이는 결제를 찾아 주고 대출과 예금의 조건도 알려 줍니다.
• Ten이 데이터를 정리합니다. 확인 대기 중인 결제를 살펴보고, 카테고리 변경과 병합을 제안하고, 두 번 입력된 기록을 찾고, 실제 지출에 맞는 예산을 제안하고, 구독을 점검하고, 가맹점의 카테고리를 기억합니다.
• 잘 안 되는 것이 있나요? 무엇이 문제인지 텐에게 알려 주시면 바로 해결을 시도합니다. 텐의 홈 화면도 더 단순해졌습니다.
```

## Submission checklist

1. **CI green**, then a TestFlight build (done: build 90 from fa3bf62, 2026-11-13; CI green on
   that code).
2. **The phone checks** (not done before the release; they are in
   [release-notes.md](../release-notes.md)).
3. **What's New** in this file (written 2026-11-13), then `prepare-version --version 1.8.3 --build <N>`
   (done 2026-11-13: version created, 14 locales updated, build 90 selected).
4. **App Review notes**, in English, set from this block by
   `asc.py review-notes --version 1.8.3 --apply` (done 2026-11-13):

```
New in 1.8.3, the assistant (Ten, the middle tab). It answers through Claude by Anthropic only after the person turns cloud answers on in the consent screen shown before the first question (Settings > Assistant has the same switch and screen). Ten can now prepare changes to the person's own records: correct or delete a transaction, move a merchant's transactions to another category, change a savings goal or a personal debt, pause a subscription. Nothing is changed until the person taps Save or Delete on the card Ten shows, and Undo puts it back. To try it: on Home add two expenses, open Ten, allow cloud answers and type "delete my last expense"; a card lists the record with a Delete button. Asked how to do something ("how do I add a deposit?"), Ten answers with a button that opens the app's own form or screen. Ten's message "How do you like Tenra?" on Home opens a short talk whose answer goes to the developer; when cloud answers are on and the answer says something is wrong, Ten then tries to help with it (the privacy policy says so).

Bank notification capture (announced in 1.8) uses the Shortcuts personal automation "When I get a notification from an app" (iOS 27), which runs the Tenra action "Log a bank notification" with the notification's Title, Subtitle, Text, App and Date. To try it without a bank app: open Shortcuts, create a new shortcut, add the Tenra action "Log a bank notification", set Text to "Card ending 4321 was charged $25.00 at COFFEE SHOP" and App to "My Bank", and run it. The expense appears in Tenra at once and waits in Settings > Wallet > To review. Settings > Siri & Shortcuts > Set up bank notifications has the step-by-step guide and "Check a notification", which shows what Tenra reads from a pasted notification without saving anything. The notification's text never leaves the device.

Apple Pay capture uses the Shortcuts "Wallet" personal automation, which fires only on a real contactless payment. To try it without one: create a shortcut with the Tenra action "Log an Apple Pay payment", fill in an amount (e.g. 1500) and a merchant (e.g. "Coffee Boom") and run it. The step-by-step setup guide is in Settings > Siri & Shortcuts.

Tenra Pro features can be tried with a sandbox purchase on the paywall: Settings, the "Get Tenra Pro" button at the top.

Assets (Finances > Assets) are a Tenra Pro feature: adding one opens the paywall without Pro. The estimate from listings (an asset's screen, the menu, "Estimate from listings") is Pro only, 10 a month: it sends the asset's kind and the characteristics filled in its form (city, district, area, rooms, year; for a car make, model, year, mileage) to Tenra's server, where Claude searches the web for similar listings and returns the middle asking price, the range and the listings with links. No name, address number, VIN or plate is sent. To try it: buy Pro in the sandbox, add a car (Toyota Camry, 2019, 110000 km, Almaty, Kazakhstan), open it and choose Estimate from listings.
```

5. **One submission**: `asc.py prepare-review --version 1.8.3 --build 90 --submit` on the
   founder's word (done 2026-11-13: "Submitted for review: 1 of 1 item(s)").
