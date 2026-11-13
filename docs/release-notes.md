# Tenra 1.8.3: What's New and the checklist

Version 1.8.3 in the project since 2026-11-11 (the founder's call: a small update now; 1.9 is
kept for the update the featuring nomination promises in the last week of December,
[plan-growth.md](plan-growth.md) stage 4). 1.8.2 is in the store since 2026-11-10/11 (build 76;
its notes and checklist: [archive/release-notes-1.8.2.md](archive/release-notes-1.8.2.md)).
**Status 2026-11-12:** the changes below are in `main` (Tenra#160, Tenra#161, then Ten's forms,
state line, help with complaints, the entries and editing and deleting records, at f3900c7),
TestFlight build
87 is processed (from the cloud, `main` at 87ba234; 85 failed at signing and was never uploaded) and selected for version 1.8.3 in App Store Connect (created 2026-11-13 with the What's New below and the App Review notes), the server with `POST /v1/feedback` and
prompt 2026-11-13.1 is deployed and the owner's Telegram chat is linked (`telegram-link`, a test line arrived 12.11), the What's New blocks for the 13 storefronts and en-GB are written (2026-11-13), the phone checks are not done.

When the blocks are written: one `## <locale>` heading per storefront (en-US, ru, en-GB, de-DE,
es-ES, es-MX, fr-FR, fr-CA, tr, pt-BR, it, uk, ja, ko), which `prepare-version` (Actions → App
Store Connect, [asc.md](asc.md)) pastes into App Store Connect; en-GB (search in Kazakhstan)
carries ru's text. No em dashes (user rule). `prepare-version` refuses notes whose title names
another version.

## en-US

```
What's new in Tenra:
• Ten now does things for you: opens the form for a new deposit, loan, account or category with what you said already filled in, corrects or deletes an operation, moves a merchant's operations to another category, changes a goal or a debt, pauses a subscription. You confirm each change on a card and can undo it.
• Ten knows the app: ask how to do something and get a button to the right screen. It finds payments in your history that look like subscriptions and tells you the terms of your loans and deposits.
• Something not working? Tell Ten what went wrong and it will try to fix it right away. Ten's home screen is simpler too.
```

## ru

```
Что нового в Tenra:
• Тэн теперь делает сам: открывает форму нового депозита, кредита, счёта или категории с уже заполненными полями, исправляет и удаляет операции, переносит операции продавца в другую категорию, меняет цель или долг, ставит подписку на паузу. Каждое изменение вы подтверждаете на карточке и можете отменить.
• Тэн знает приложение: спросите, как что-то сделать, и получите кнопку на нужный экран. Он находит в истории платежи, похожие на подписки, и рассказывает условия ваших кредитов и депозитов.
• Что-то не получается? Напишите Тэну, что пошло не так, и он попробует решить это сразу. Главный экран Тэна стал проще.
```

## en-GB

```
Что нового в Tenra:
• Тэн теперь делает сам: открывает форму нового депозита, кредита, счёта или категории с уже заполненными полями, исправляет и удаляет операции, переносит операции продавца в другую категорию, меняет цель или долг, ставит подписку на паузу. Каждое изменение вы подтверждаете на карточке и можете отменить.
• Тэн знает приложение: спросите, как что-то сделать, и получите кнопку на нужный экран. Он находит в истории платежи, похожие на подписки, и рассказывает условия ваших кредитов и депозитов.
• Что-то не получается? Напишите Тэну, что пошло не так, и он попробует решить это сразу. Главный экран Тэна стал проще.
```

## de-DE

```
Neu in Tenra:
• Ten erledigt jetzt Dinge für Sie: öffnet das Formular für eine neue Einlage, einen Kredit, ein Konto oder eine Kategorie mit bereits ausgefüllten Angaben, korrigiert oder löscht eine Buchung, verschiebt die Buchungen eines Händlers in eine andere Kategorie, ändert ein Sparziel oder eine Schuld, pausiert ein Abo. Jede Änderung bestätigen Sie auf einer Karte und können sie rückgängig machen.
• Ten kennt die App: Fragen Sie, wie etwas geht, und Sie bekommen eine Taste zum richtigen Bildschirm. Ten findet in Ihrem Verlauf Zahlungen, die wie Abos aussehen, und nennt die Konditionen Ihrer Kredite und Einlagen.
• Etwas klappt nicht? Schreiben Sie Ten, was schiefgelaufen ist, und Ten versucht, es sofort zu lösen. Tens Startbildschirm ist außerdem einfacher geworden.
```

## es-ES

```
Novedades en Tenra:
• Ten ahora hace cosas por ti: abre el formulario de un nuevo depósito, préstamo, cuenta o categoría con lo que dijiste ya rellenado, corrige o elimina una operación, mueve las operaciones de un comercio a otra categoría, cambia un objetivo o una deuda y pausa una suscripción. Confirmas cada cambio en una tarjeta y puedes deshacerlo.
• Ten conoce la app: pregunta cómo hacer algo y recibe un botón a la pantalla correcta. Encuentra en tu historial pagos que parecen suscripciones y te dice las condiciones de tus préstamos y depósitos.
• ¿Algo no funciona? Cuéntale a Ten qué ha fallado e intentará resolverlo al momento. La pantalla de inicio de Ten también es más sencilla.
```

## es-MX

```
Novedades en Tenra:
• Ten ahora hace cosas por ti: abre el formulario de un nuevo depósito, préstamo, cuenta o categoría con lo que dijiste ya llenado, corrige o elimina una operación, mueve las operaciones de un comercio a otra categoría, cambia una meta o una deuda y pausa una suscripción. Confirmas cada cambio en una tarjeta y puedes deshacerlo.
• Ten conoce la app: pregunta cómo hacer algo y recibe un botón a la pantalla correcta. Encuentra en tu historial pagos que parecen suscripciones y te dice las condiciones de tus préstamos y depósitos.
• ¿Algo no funciona? Cuéntale a Ten qué salió mal e intentará resolverlo al momento. La pantalla de inicio de Ten también es más sencilla.
```

## fr-FR

```
Nouveautés de Tenra :
• Ten agit désormais pour vous : il ouvre le formulaire d’un nouveau dépôt, prêt, compte ou d’une nouvelle catégorie avec ce que vous avez dit déjà rempli, corrige ou supprime une opération, déplace les opérations d’un commerçant vers une autre catégorie, modifie un objectif ou une dette, met un abonnement en pause. Vous confirmez chaque changement sur une carte et pouvez l’annuler.
• Ten connaît l’app : demandez comment faire quelque chose et recevez un bouton vers le bon écran. Il trouve dans votre historique les paiements qui ressemblent à des abonnements et vous donne les conditions de vos prêts et dépôts.
• Quelque chose ne marche pas ? Dites à Ten ce qui ne va pas et il essaiera de le résoudre tout de suite. L’écran d’accueil de Ten est aussi plus simple.
```

## fr-CA

```
Nouveautés de Tenra :
• Ten agit désormais pour vous : il ouvre le formulaire d’un nouveau dépôt, prêt, compte ou d’une nouvelle catégorie avec ce que vous avez dit déjà rempli, corrige ou supprime une opération, déplace les opérations d’un commerçant vers une autre catégorie, modifie un objectif ou une dette, met un abonnement en pause. Vous confirmez chaque changement sur une carte et pouvez l’annuler.
• Ten connaît l’app : demandez comment faire quelque chose et recevez un bouton vers le bon écran. Il trouve dans votre historique les paiements qui ressemblent à des abonnements et vous donne les conditions de vos prêts et dépôts.
• Quelque chose ne fonctionne pas? Dites à Ten ce qui ne va pas et il essaiera de le régler tout de suite. L’écran d’accueil de Ten est aussi plus simple.
```

## tr

```
Tenra'daki yenilikler:
• Ten artık sizin yerinize yapıyor: yeni bir mevduat, kredi, hesap veya kategori formunu söyledikleriniz doldurulmuş olarak açar, bir işlemi düzeltir veya siler, bir satıcının işlemlerini başka bir kategoriye taşır, bir hedefi veya borcu değiştirir, bir aboneliği duraklatır. Her değişikliği bir kartta onaylarsınız ve geri alabilirsiniz.
• Ten uygulamayı biliyor: bir şeyin nasıl yapıldığını sorun, doğru ekrana giden bir düğme alın. Geçmişinizde aboneliğe benzeyen ödemeleri bulur ve kredi ile mevduatlarınızın koşullarını söyler.
• Bir şey mi çalışmıyor? Ten'e neyin ters gittiğini yazın, hemen çözmeye çalışsın. Ten'in ana ekranı da sadeleşti.
```

## pt-BR

```
Novidades no Tenra:
• O Ten agora faz por você: abre o formulário de um novo depósito, empréstimo, conta ou categoria com o que você disse já preenchido, corrige ou exclui uma operação, move as operações de um estabelecimento para outra categoria, altera uma meta ou uma dívida e pausa uma assinatura. Você confirma cada mudança em um cartão e pode desfazer.
• O Ten conhece o app: pergunte como fazer algo e receba um botão para a tela certa. Ele encontra no seu histórico pagamentos que parecem assinaturas e informa as condições dos seus empréstimos e depósitos.
• Algo não funciona? Conte ao Ten o que deu errado e ele tentará resolver na hora. A tela inicial do Ten também ficou mais simples.
```

## it

```
Novità in Tenra:
• Ten ora fa le cose per te: apre il modulo di un nuovo deposito, prestito, conto o categoria con ciò che hai detto già compilato, corregge o elimina un'operazione, sposta le operazioni di un esercente in un'altra categoria, modifica un obiettivo o un debito, mette in pausa un abbonamento. Confermi ogni modifica su una scheda e puoi annullarla.
• Ten conosce l'app: chiedi come fare qualcosa e ricevi un pulsante per la schermata giusta. Trova nella cronologia i pagamenti che sembrano abbonamenti e ti dice le condizioni dei tuoi prestiti e depositi.
• Qualcosa non funziona? Scrivi a Ten cosa è andato storto e proverà a risolverlo subito. Anche la schermata iniziale di Ten è più semplice.
```

## uk

```
Що нового в Tenra:
• Тен тепер робить сам: відкриває форму нового депозиту, кредиту, рахунку чи категорії з уже заповненими полями, виправляє і видаляє операції, переносить операції продавця в іншу категорію, змінює ціль або борг, ставить підписку на паузу. Кожну зміну ви підтверджуєте на картці й можете скасувати.
• Тен знає застосунок: запитайте, як щось зробити, і отримайте кнопку на потрібний екран. Він знаходить в історії платежі, схожі на підписки, і розповідає умови ваших кредитів і депозитів.
• Щось не виходить? Напишіть Тену, що пішло не так, і він спробує вирішити це одразу. Головний екран Тена став простішим.
```

## ja

```
Tenraの新機能:
• テンが代わりに操作します。新しい預金、ローン、口座、カテゴリのフォームを、話した内容が入力された状態で開きます。取引の修正と削除、店舗の取引を別のカテゴリへまとめて移動、目標や貸し借りの変更、サブスクリプションの一時停止もできます。変更はカードで確認してから保存され、取り消せます。
• テンはアプリの使い方を知っています。やり方をたずねると、その画面へのボタンが届きます。履歴からサブスクリプションらしい支払いを見つけ、ローンや預金の条件も答えます。
• うまくいかないときは、何が起きたかをテンに伝えてください。その場で解決を試みます。テンのホーム画面もすっきりしました。
```

## ko

```
Tenra의 새로운 기능:
• 텐이 대신 처리합니다. 새 예금, 대출, 계좌, 카테고리 양식을 말씀하신 내용이 채워진 상태로 열고, 거래를 수정하거나 삭제하고, 한 가맹점의 거래를 다른 카테고리로 옮기고, 목표나 빚을 변경하고, 구독을 일시 중지합니다. 모든 변경은 카드에서 확인한 뒤 저장되며 되돌릴 수 있습니다.
• 텐은 앱 사용법을 압니다. 방법을 물으면 해당 화면으로 가는 버튼을 드립니다. 내역에서 구독처럼 보이는 결제를 찾아 주고 대출과 예금의 조건도 알려 줍니다.
• 잘 안 되는 것이 있나요? 무엇이 문제인지 텐에게 알려 주시면 바로 해결을 시도합니다. 텐의 홈 화면도 더 단순해졌습니다.
```

## In this version (main since 2026-11-10)

- Ten opens the app's own forms: asked to add an account, a deposit, a loan or a category (or
  how to), it answers with a button that opens the form with what was said already filled in
  (the bank, the amount, the rate, the term), and with buttons to the lists of Finances, a
  goal, a debt, Settings, the backups and the Wallet guide. After build 77; needs the server
  with prompt 2026-11-12.3 or later (2026-11-12.4 is deployed).
- Ten knows how the app is set up for the person (the plan, the free accounts used, automatic
  capture, backups, the spending reminder, budgets), so its help is about them: "the weekly
  backup is on, but the copies stay on this phone". After build 78; same server.
- Ten helps with a complaint: after "Not really" in the feedback talk, once the words are with
  the developer, Ten tries to settle the problem itself (opens the form, checks the data, names
  the nearest thing Tenra has), then asks whether it helped. With cloud answers off it offers to
  help first. Needs the server with prompt 2026-11-12.4 (deployed 2026-11-12).
- Ten changes what is saved: "the freelance income on the 24th was 170 000, fix it" or "delete
  the Steam purchase" gets a card with the record as it is and as it becomes (or the records
  that go), saved or deleted with one tap and undone with another. Transfers and loan or deposit
  records stay in History. Needs the server with prompt 2026-11-12.5 (deployed 2026-11-12). In build 80.
- "Put everything from Glovo under Groceries": Ten moves all records of a merchant (up to 50)
  to another category with one card. In build 81.
- Ten changes a goal (name, target, deadline) and a debt (due date, note, settled) with a card
  that shows what it is and what it becomes. In build 82.
- "Put Spotify on hold": Ten pauses or resumes a subscription with a card. In build 83.
- "I paid the loan today": Ten's button opens the loan with its payment form already open.
  In build 84.
- Ten knows the terms of loans and deposits: the rate, the monthly payment and its day, the
  payments left, the interest accrued on a deposit. Needs the server with prompt 2026-11-12.7
  (deployed 2026-11-12). In build 81.
- "Find my subscriptions in the history": Ten looks through the last year for payments that
  repeat like a subscription and offers to add them. In build 87.
- The chats page lists the whole kept history (the latest 100 chats, five before) under one
  title. After build 87.
- Ten's messages get a one-tap button: "Pause" on a subscription charged tomorrow, "Mark
  settled" on a debt due tomorrow; the draft opens in Ten's chat to confirm (DesignKit 8.11.0). In build 87.
- Ten's home is one thing at a time: Ten, large, with the message it wrote first (or its
  greeting) under it; three chips over the field, "Record", "Ask" and "How to"; the chats behind
  a button at the top. In build 86 (build 84 had an earlier, busier arrangement).
- Settings › Assistant has "Ask Ten about the app", and Ten's home puts first the "how to"
  questions for what the person has not set up yet (automatic capture, a first budget, a backup
  in iCloud). After build 79.
- Ten's chat: the three typing dots are gone; while Ten works, the step it is on shimmers.
- Converting an account to a deposit from the account's own screen asks for Tenra Pro, as the
  accounts list already did.
- A gate's paywall comes from its own RevenueCat placement (the identifier is the gate's
  `paywall_source`, [promotion-plan.md](promotion-plan.md) §2). Set up on 2026-11-13: loans,
  deposits, accounts, personal debts, assets, voice, statement import and Ten each open a copy of
  the paywall with their own headline and their feature first; onboarding, Analytics and Settings
  keep the general one, and the app in Kazakh keeps its one paywall.
- Settings › Assistant: turning cloud answers on shows the same consent screen as the chat's
  first question (App Review 5.1.2(i)); before, the switch turned the cloud on without it.
- Ten in Russia and Belarus (no cloud there): the first question gets Ten's message once,
  questions not answered here, expenses recorded as usual with an example; after that Ten offers
  no questions, the field asks for an expense, "Ask Ten" is gone from the screens, and a question
  typed anyway does not go to the server. Checked again a week later.
- Ten's privacy: a fact Ten forgot leaves the chats that mention it (they can still be read; a
  question from one starts a new chat, "Ten forgot something from this chat"); expenses typed
  before cloud answers were allowed are never described to the AI later.
- The evening reminder: a transfer between your own banks merged when Tenra opens no longer
  counts as recording that day (it keeps the expense's creation time); the next day's line about
  yesterday's category survives a time-zone change.
- The evening reminder: no banner while Tenra is open at its time; "Remind me" with
  notifications already off for Tenra opens Tenra's page in iOS Settings (before, the tap did
  nothing visible).
- Fixes nobody should notice (release audit 1.6 races): a chat deleted while its reply is
  written stays deleted, and two saves of a chat or a fact keep one copy; a goal, a debt or an
  asset added right after launch no longer vanishes until the next one; "New chat" while Ten
  drafts a typed expense keeps the expense in its chat, and a message sent then stays in the
  field. Voice input lost an audio silence detector it never used (auto-stop is the 5-second
  pause, as before).

- Feedback through Ten (in `main` since 2026-11-11): Ten asks on Home "How do you like
  Tenra?" from the third day with five entries, then every 45 days while the person records.
  "Write" opens Ten's chat, where Ten asks and two chips answer ("I like it", "Not really"); Ten
  then asks what else to add, or what went wrong and how to fix it, and the person's words go to
  the developer, not to the AI. The rating survey's "not really" opens the same talk (it opened an
  e-mail). "I like it" asks Apple for the rating prompt after sending. Needs the server with
  `POST /v1/feedback` deployed first (Actions → Assistant server → deploy), and the privacy
  policy's line (on the site once merged).

Not for the user's notes, already live on Ten's server (no release needed): free users' share
of the day (900 of 1 200 calls) with 300 kept for Pro and trials, a call the model never
started is given back, a 5-second RevenueCat timeout, and the model stops when the app leaves
mid-answer.

**On the phone before this version goes out** (from the PRs' test plans, Tenra#150, #151, #153):
1. The paywall opens from every gate as before (no placements set up yet).
2. Settings › Assistant: switching cloud answers on shows the consent screen; off is immediate.
3. "Remind me" on Ten's offer with notifications off for Tenra opens iOS Settings; at the
   reminder's time with Tenra open, no banner.
4. With a VPN to Russia: the first question gets Ten's one message, then no ready-made
   questions, the field reads "Запишите трату, например «кофе 1500»", "Спросить Ten" is gone from
   the screens' menus, and "кофе 1500" is recorded.
5. Forget a fact Ten used in a chat (What Ten knows about me): that chat shows "Тэн забыл
   кое-что из этого чата", and a question from it opens a new chat; "Forget all" marks every
   chat in the history.
6. Two own banks' pushes merged into a transfer the next morning: that day's evening reminder
   still comes if nothing else was recorded.
7. Feedback through Ten: Ten's message "Как вам Tenra?" on Home (a phone with five entries,
   installed three days ago or more), "Написать" opens Ten's chat with Ten's question and the
   chips "Нравится" and "Не очень" over the field; a chip becomes your message, Ten asks the next
   question after a moment; your answer shows "Спасибо! Передал разработчику…", the Home message
   leaves, and the message arrives in Telegram; after "Нравится" Apple's rating prompt may follow;
   with no network Ten says "Не получилось отправить" and the next message is tried again. The
   rating survey ("Нравится ли вам Tenra?") must not come up over the talk (build 77 showed it
   while the answer was being typed), and Apple's prompt comes only after Ten's thanks. The
   rating survey's "not really" opens the chat with "Что именно не понравилось…" at once.
   **App Privacy** in App Store Connect: updated by the founder on 2026-11-11 for a message to
   the developer (user content for app functionality, not linked to the person, no tracking).
8. Ten as a helper (build 79, cloud answers on): "Как открыть депозит в Halyk на 2 млн под
   14,5%?" answers with "Создать депозит"; the button opens the deposits list and the form
   opens over it by itself with the bank, the amount and the rate filled in (a free person gets
   the paywall first, then the form). The same for "добавь счёт Freedom в долларах", a loan and
   a category. "У меня включена резервная копия?" answers about this phone (automatic or not,
   iCloud or not, the last copy) with a button to the backups. While Ten works there are no
   three dots, only the shimmering step.
9. A complaint in the feedback talk (build 79): "Не очень", then "не понял, как завести
   депозит": Ten thanks, says it will look, and answers with the form's button; then the chips
   "Помогло" and "Не помогло"; either arrives in Telegram as the same words with "Ten helped"
   or "Ten did not help". The help spends no free answer. With cloud answers off: the thanks,
   then the chip "Помоги разобраться", which opens the consent screen and goes on after "Turn
   on". After "Нравится" nothing changes.
10. "Convert to deposit" in an account's "…" menu as a free person opens the paywall; after a
    purchase the conversion form opens.
11. Ten changes what is saved (build 80): "Вчерашний кофе был на 1 800, исправь" finds the
    record and shows a card with "Было" and "Станет"; "Сохранить" changes it in History, "Отмена"
    puts it back. "Удали вчерашний кофе" shows the record and "Удалить"; "Отмена" returns it
    with its subcategory. A transfer or a loan payment is refused with a button to History.
    Balances of the account move with the change and back with the undo.
12. Settings › Assistant, "Спросить Тэна о приложении" opens Ten with three how-to questions;
    Ten's home starts with the questions for what is not set up (automatic capture, a first
    budget, a backup in iCloud).
13. Build 81: "Перенеси всё из Glovo в Продукты" shows one card with the number of records and
    the records as they will be; "Сохранить" moves them, "Отмена" puts them back. "Какая ставка
    по кредиту и сколько платежей осталось?" and "Сколько процентов набежало по депозиту?" are
    answered with the app's own figures.

14. Ten's home (build 86): Ten is large; under it the card "Тэн пишет" when a message
    waits ("Разобрать" starts its chat), else one line of greeting; over the field the chips
    "Записать" (the keyboard comes up), "Спросить" and "Как сделать" (their questions replace the
    chips, "Назад" brings the three back, a question starts a chat); the bubble at the top right
    opens the chats, a long press deletes one; nothing is cut off on a small phone and in the
    largest text size. "Поставь Spotify на паузу" (build 83)
    shows the subscription and "Встанет на паузу"; "Отмена" resumes it. "Сегодня заплатил по
    кредиту" gives a button that opens the loan with its payment form already open.

15. Build 87: a message about a subscription charged tomorrow has "Пауза" next to "Разобрать",
    one about a debt due tomorrow "Долг закрыт"; a tap opens Ten's chat with the draft's card,
    "Сохранить" does it and "Отмена" takes it back. "Найди в истории платежи, похожие на
    подписки" names what repeats and offers to add it. As a free person, each gate (a 4th
    account, a deposit, a loan, a debt, an asset, voice, a statement, Ten past its allowance)
    opens the paywall with its own headline.

16. Build 88: Ten's home always has a card under the greeting: "Тэн пишет" with the insight that
    matters most (a problem first) when no message waits, "Разобрать" starts a chat about it, ✕
    shows the next one; on an empty install the automatic capture card. The chats page has no
    section title under the navigation one and lists every kept chat, not six.

17. Payments on review (next build): with a few payments in Settings › Wallet › To review,
    "Разбери платежи на проверке" names them and shows one card with them and the button
    "Верно"; it empties the list and "Отмена" brings them back. "Glovo это продукты, а не кафе"
    drafts the change, and saving it takes the payment off review.

**On the phone, left from the versions already in the store** (not marked done before 1.8.2 went
out; the store build is the one to check):

1. **1.8.2** (in the store, build 76): a fresh install as a free person reaches the paywall
   after the last onboarding step, ✕ lands on Home with the account and categories saved; after a
   purchase or restore too. Analytics' paywall appears after the 3rd entry, not on the day of the
   onboarding offer. With real bank pushes: a subscription's charge lands on its planned charge
   (one transaction, the bank's amount and date) or asks "Looks like X" in To review; a transfer
   from one of your banks to another becomes one transfer (asked in To review when only the
   amount and time match), "Not a transfer" puts both back; Transfer and top-up list no loans.
2. **Carried over from 1.8.1** (the Simulator covered the rest,
   [archive/release-notes-1.8.1.md](archive/release-notes-1.8.1.md) item 2): the evening push at the
   set time on a day with nothing recorded and none after an entry (manual, Ten's draft, Apple Pay
   capture); a tap opens Ten; VoiceOver reads amounts in "1’234.56" and "1.234,56"; the widget
   shows a chosen format.
3. **Actions** (1.8.2): long press a deposit, a loan and a
   subscription on their lists and open their menus: "Изменить" first, "Удалить" last; delete an
   account from its own screen (both choices), a loan (both choices) and a transaction (alert, not
   a sheet); the transaction menu of a recurring payment shows "Прекратить повторение".
   "Спросить Ten" on an account, a deposit, a loan and a subscription opens a new empty chat with
   two questions over the field; the previous chat is in the home's list; a question tapped goes
   (the consent sheet first on a fresh install).

## Submission checklist

1. **CI green**, then a TestFlight build (done: build 87 from 87ba234, 2026-11-13; CI green on
   that code).
2. **The phone checks above.**
3. **What's New** in this file (written 2026-11-13), then `prepare-version --version 1.8.3 --build <N>`
   (done 2026-11-13: version created, 14 locales updated, build 87 selected).
4. **App Review notes**, in English, set from this block by
   `asc.py review-notes --version 1.8.3 --apply` (done 2026-11-13):

```
New in 1.8.3, the assistant (Ten, the middle tab). It answers through Claude by Anthropic only after the person turns cloud answers on in the consent screen shown before the first question (Settings > Assistant has the same switch and screen). Ten can now prepare changes to the person's own records: correct or delete a transaction, move a merchant's transactions to another category, change a savings goal or a personal debt, pause a subscription. Nothing is changed until the person taps Save or Delete on the card Ten shows, and Undo puts it back. To try it: on Home add two expenses, open Ten, allow cloud answers and type "delete my last expense"; a card lists the record with a Delete button. Asked how to do something ("how do I add a deposit?"), Ten answers with a button that opens the app's own form or screen. Ten's message "How do you like Tenra?" on Home opens a short talk whose answer goes to the developer; when cloud answers are on and the answer says something is wrong, Ten then tries to help with it (the privacy policy says so).

Bank notification capture (announced in 1.8) uses the Shortcuts personal automation "When I get a notification from an app" (iOS 27), which runs the Tenra action "Log a bank notification" with the notification's Title, Subtitle, Text, App and Date. To try it without a bank app: open Shortcuts, create a new shortcut, add the Tenra action "Log a bank notification", set Text to "Card ending 4321 was charged $25.00 at COFFEE SHOP" and App to "My Bank", and run it. The expense appears in Tenra at once and waits in Settings > Wallet > To review. Settings > Siri & Shortcuts > Set up bank notifications has the step-by-step guide and "Check a notification", which shows what Tenra reads from a pasted notification without saving anything. The notification's text never leaves the device.

Apple Pay capture uses the Shortcuts "Wallet" personal automation, which fires only on a real contactless payment. To try it without one: create a shortcut with the Tenra action "Log an Apple Pay payment", fill in an amount (e.g. 1500) and a merchant (e.g. "Coffee Boom") and run it. The step-by-step setup guide is in Settings > Siri & Shortcuts.

Tenra Pro features can be tried with a sandbox purchase on the paywall: Settings, the "Get Tenra Pro" button at the top.

Assets (Finances > Assets) are a Tenra Pro feature: adding one opens the paywall without Pro. The estimate from listings (an asset's screen, the menu, "Estimate from listings") is Pro only, 10 a month: it sends the asset's kind and the characteristics filled in its form (city, district, area, rooms, year; for a car make, model, year, mileage) to Tenra's server, where Claude searches the web for similar listings and returns the middle asking price, the range and the listings with links. No name, address number, VIN or plate is sent. To try it: buy Pro in the sandbox, add a car (Toyota Camry, 2019, 110000 km, Almaty, Kazakhstan), open it and choose Estimate from listings.
```

5. **One submission**: `asc.py prepare-review --version 1.8.3`; the founder sends it, or
   `--submit` on the founder's word.
