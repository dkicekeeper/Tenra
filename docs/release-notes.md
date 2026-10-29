# Tenra 1.7.1: What's New (ASC, 13 storefront locales and en-GB)

Version 1.7.1, drafted 2026-10-29. `prepare-version` (Actions → App Store Connect,
[asc.md](asc.md)) pastes each block into App Store Connect → Tenra → 1.7.1 → the locale →
"What's New in This Version"; en-GB (search in Kazakhstan, decision D9) carries ru's text in its
own block, since App Store Connect has had the en-GB localization since 1.7. No em dashes (user
rule). Names of screens as the app shows them in each locale (`settings.siri.header`,
`bankSetup.title`). No bank names in store texts (App Review 2.3.7). When 1.7.1 ships, move this
file to `archive/release-notes-1.7.1.md`.

New since 1.7 (in the store since 2026-10-24):
- Bank notification capture announced: in the app since 1.7 (iOS 27, "Log a bank notification",
  its guide and "Check a notification" in Settings › Siri & Shortcuts), checked on the founder's
  phone with two banks after 1.7 was submitted
  ([plan-notification-capture.md](plan-notification-capture.md)).
- Goals: the list and the goal screen follow exchange-rate refreshes and a new day; a goal's
  reached date is noted after the goals load and whenever the app comes to the front, not only
  while its screen is open ([domains/goals-and-debts.md](domains/goals-and-debts.md)).
- Debts: "Repay" saves at most what is left; a due date is never before the debt's date; Ten's
  debt and repayment drafts are checked again at Save (Pro, what is left).
- The microphone and speech permission texts name Ten (12 locales).
- Editing a deposit or a loan and deleting a loan recalculate only the accounts they touch.

## en-US

```
What's new in Tenra 1.7.1:
• On iOS 27, your bank's notifications log themselves: card and QR payments, online purchases, transfers and money coming in, from any bank, without a single question. A transfer between your own cards in two banks becomes one transfer. Set it up once in Settings › Siri & Shortcuts › Set up bank notifications. The text never leaves your iPhone.
• Goals keep up with exchange rates and the calendar: what is left, the monthly amount and the overdue mark update on their own, and a goal your account carried past the target remembers the day it got there.
• Debts: a repayment is never more than what is left, a due date can't come before the day you lent or borrowed, and Ten checks its draft once more when you save it.
• Editing a deposit or deleting a loan is quicker: only the accounts it touches are recounted.
```

## ru

```
Что нового в Tenra 1.7.1:
• На iOS 27 уведомления банка записываются сами: оплаты картой и по QR, покупки в интернете, переводы и поступления от любого банка, без единого вопроса. Перевод между своими картами в двух банках станет одним переводом. Один раз настройте в Настройках › Siri и команды › Настроить уведомления банка. Текст уведомлений не покидает iPhone.
• Цели следят за курсом и календарём: остаток, сумма в месяц и отметка о просрочке обновляются сами, а цель, которую счёт довёл до нужной суммы, запоминает день, когда она достигнута.
• Долги: возврат не больше остатка, срок нельзя поставить раньше дня, когда вы дали или взяли в долг, а Тэн ещё раз проверяет свой черновик, когда вы его сохраняете.
• Правка депозита и удаление кредита работают быстрее: пересчитываются только затронутые счета.
```

## en-GB

```
Что нового в Tenra 1.7.1:
• На iOS 27 уведомления банка записываются сами: оплаты картой и по QR, покупки в интернете, переводы и поступления от любого банка, без единого вопроса. Перевод между своими картами в двух банках станет одним переводом. Один раз настройте в Настройках › Siri и команды › Настроить уведомления банка. Текст уведомлений не покидает iPhone.
• Цели следят за курсом и календарём: остаток, сумма в месяц и отметка о просрочке обновляются сами, а цель, которую счёт довёл до нужной суммы, запоминает день, когда она достигнута.
• Долги: возврат не больше остатка, срок нельзя поставить раньше дня, когда вы дали или взяли в долг, а Тэн ещё раз проверяет свой черновик, когда вы его сохраняете.
• Правка депозита и удаление кредита работают быстрее: пересчитываются только затронутые счета.
```

## de-DE

```
Neu in Tenra 1.7.1:
• Unter iOS 27 tragen sich Ihre Bankmitteilungen selbst ein: Karten- und QR-Zahlungen, Onlinekäufe, Überweisungen und Geldeingänge jeder Bank, ohne eine einzige Frage. Eine Überweisung zwischen Ihren eigenen Karten bei zwei Banken wird zu einer Umbuchung. Richten Sie das einmal unter Einstellungen › Siri und Kurzbefehle › Bankmitteilungen einrichten ein. Der Text verlässt Ihr iPhone nie.
• Sparziele halten mit Wechselkursen und Kalender Schritt: Restbetrag, Monatsbetrag und die Markierung „überfällig“ aktualisieren sich von selbst, und ein Sparziel, das Ihr Konto erreicht hat, merkt sich den Tag.
• Schulden: Eine Rückzahlung ist nie höher als der Rest, ein Fälligkeitsdatum liegt nie vor dem Tag, an dem Sie Geld verliehen oder geliehen haben, und Ten prüft seinen Entwurf beim Speichern noch einmal.
• Ein Sparkonto bearbeiten oder einen Kredit löschen geht schneller: Nur die betroffenen Konten werden neu berechnet.
```

## es-ES

```
Novedades de Tenra 1.7.1:
• En iOS 27, las notificaciones de tu banco se registran solas: pagos con tarjeta y con QR, compras por internet, transferencias y dinero que entra, de cualquier banco, sin una sola pregunta. Una transferencia entre tus propias tarjetas de dos bancos se convierte en una sola. Configúralo una vez en Ajustes › Siri y atajos › Configurar las notificaciones del banco. El texto nunca sale de tu iPhone.
• Las metas siguen el tipo de cambio y el calendario: lo que falta, el importe mensual y el aviso de retraso se actualizan solos, y una meta que tu cuenta alcanzó recuerda el día en que lo hizo.
• Deudas: un pago nunca supera lo que falta, la fecha de vencimiento no puede ser anterior al día del préstamo y Ten vuelve a comprobar su borrador al guardarlo.
• Editar un depósito o eliminar un préstamo es más rápido: solo se recalculan las cuentas afectadas.
```

## es-MX

```
Novedades de Tenra 1.7.1:
• En iOS 27, las notificaciones de tu banco se registran solas: pagos con tarjeta y con QR, compras en línea, transferencias y dinero que entra, de cualquier banco, sin una sola pregunta. Una transferencia entre tus propias tarjetas de dos bancos se convierte en una sola. Configúralo una vez en Ajustes › Siri y atajos › Configurar las notificaciones del banco. El texto nunca sale de tu iPhone.
• Las metas siguen el tipo de cambio y el calendario: lo que falta, el monto mensual y el aviso de retraso se actualizan solos, y una meta que tu cuenta alcanzó recuerda el día en que lo hizo.
• Deudas: un pago nunca supera lo que falta, la fecha de vencimiento no puede ser anterior al día del préstamo y Ten vuelve a revisar su borrador al guardarlo.
• Editar un depósito o eliminar un préstamo es más rápido: solo se recalculan las cuentas afectadas.
```

## fr-FR

```
Nouveautés de Tenra 1.7.1 :
• Sous iOS 27, les notifications de votre banque s'enregistrent toutes seules : paiements par carte et par QR, achats en ligne, virements et argent reçu, quelle que soit la banque, sans une seule question. Un virement entre vos propres cartes dans deux banques devient un seul virement. Configurez-le une fois dans Réglages › Siri et raccourcis › Configurer les notifications bancaires. Le texte ne quitte jamais votre iPhone.
• Les objectifs suivent les taux de change et le calendrier : le reste, le montant mensuel et la mention « en retard » se mettent à jour seuls, et un objectif atteint grâce à votre compte retient le jour où il l'a été.
• Dettes : un remboursement ne dépasse jamais ce qui reste, une échéance ne peut pas précéder le jour du prêt, et Ten vérifie à nouveau son brouillon quand vous l'enregistrez.
• Modifier un compte épargne ou supprimer un crédit est plus rapide : seuls les comptes concernés sont recalculés.
```

## fr-CA

```
Nouveautés de Tenra 1.7.1 :
• Sous iOS 27, les notifications de votre banque s'enregistrent toutes seules : paiements par carte et par QR, achats en ligne, virements et argent reçu, quelle que soit la banque, sans une seule question. Un virement entre vos propres cartes dans deux banques devient un seul virement. Configurez-le une fois dans Réglages › Siri et raccourcis › Configurer les notifications bancaires. Le texte ne quitte jamais votre iPhone.
• Les objectifs suivent les taux de change et le calendrier : le reste, le montant mensuel et la mention « en retard » se mettent à jour seuls, et un objectif atteint grâce à votre compte retient le jour où il l'a été.
• Dettes : un remboursement ne dépasse jamais ce qui reste, une échéance ne peut pas précéder le jour du prêt, et Ten vérifie à nouveau son brouillon quand vous l'enregistrez.
• Modifier un compte épargne ou supprimer un crédit est plus rapide : seuls les comptes concernés sont recalculés.
```

## tr

```
Tenra 1.7.1'deki yenilikler:
• iOS 27'de bankanın bildirimleri kendiliğinden kaydedilir: kartla ve QR ile ödemeler, internet alışverişleri, havaleler ve gelen paralar, hangi banka olursa olsun, tek bir soru sormadan. İki bankadaki kendi kartların arasındaki bir havale tek bir transfer olur. Ayarlar › Siri ve kısayollar › Banka bildirimlerini kur bölümünden bir kez kur. Bildirim metni iPhone'undan hiç çıkmaz.
• Hedefler döviz kurlarına ve takvime ayak uydurur: kalan tutar, aylık tutar ve gecikme işareti kendiliğinden güncellenir; hesabının hedefe ulaştırdığı bir hedef, ulaşıldığı günü hatırlar.
• Borçlar: bir geri ödeme kalan tutarı asla aşmaz, vade tarihi borcun verildiği ya da alındığı günden önce olamaz ve Ten taslağını kaydederken bir kez daha kontrol eder.
• Bir mevduatı düzenlemek ya da bir krediyi silmek daha hızlı: yalnızca etkilenen hesaplar yeniden hesaplanır.
```

## pt-BR

```
Novidades do Tenra 1.7.1:
• No iOS 27, as notificações do seu banco se registram sozinhas: pagamentos no cartão e por QR, compras on-line, transferências e dinheiro que entra, de qualquer banco, sem uma única pergunta. Uma transferência entre seus próprios cartões em dois bancos vira uma só. Configure uma vez em Ajustes › Siri e atalhos › Configurar notificações do banco. O texto nunca sai do seu iPhone.
• As metas acompanham o câmbio e o calendário: o que falta, o valor mensal e o aviso de atraso se atualizam sozinhos, e uma meta que sua conta alcançou lembra o dia em que isso aconteceu.
• Dívidas: um pagamento nunca passa do que falta, o vencimento não pode ser antes do dia do empréstimo e o Ten confere o rascunho de novo quando você salva.
• Editar um depósito ou excluir um empréstimo ficou mais rápido: só as contas afetadas são recalculadas.
```

## it

```
Novità di Tenra 1.7.1:
• Su iOS 27 le notifiche della tua banca si registrano da sole: pagamenti con carta e con QR, acquisti online, bonifici e soldi in entrata, da qualsiasi banca, senza una sola domanda. Un bonifico tra le tue carte in due banche diventa un unico trasferimento. Configuralo una volta in Impostazioni › Siri e comandi rapidi › Configura le notifiche della banca. Il testo non lascia mai il tuo iPhone.
• Gli obiettivi seguono i cambi e il calendario: quanto manca, la cifra mensile e il segno di ritardo si aggiornano da soli, e un obiettivo che il tuo conto ha raggiunto ricorda il giorno in cui è successo.
• Debiti: un rimborso non supera mai quanto resta, la scadenza non può essere prima del giorno del prestito e Ten ricontrolla la sua bozza quando la salvi.
• Modificare un deposito o eliminare un prestito è più veloce: vengono ricalcolati solo i conti coinvolti.
```

## uk

```
Що нового в Tenra 1.7.1:
• На iOS 27 сповіщення банку записуються самі: оплати карткою і за QR, покупки в інтернеті, перекази та надходження від будь-якого банку, без жодного питання. Переказ між власними картками у двох банках стане одним переказом. Один раз налаштуйте в Налаштуваннях › Siri та команди › Налаштувати сповіщення банку. Текст сповіщень не залишає iPhone.
• Цілі стежать за курсом і календарем: залишок, сума на місяць і позначка про прострочення оновлюються самі, а ціль, яку рахунок довів до потрібної суми, запам'ятовує день, коли її досягнуто.
• Борги: повернення не більше за залишок, строк не можна поставити раніше дня, коли ви дали або взяли в борг, а Тен ще раз перевіряє свою чернетку, коли ви її зберігаєте.
• Редагування депозиту й видалення кредиту працюють швидше: перераховуються лише зачеплені рахунки.
```

## ja

```
Tenra 1.7.1 の新機能:
• iOS 27 では、銀行の通知が自動で記録されます。カードや QR での支払い、オンラインでの買い物、振込、入金を、どの銀行でも質問なしで記録します。2 つの銀行にある自分のカード間の振込は 1 件の振替になります。設定 › Siri とショートカット › 銀行の通知を設定 で一度設定するだけです。通知の文面が iPhone の外に出ることはありません。
• 貯金目標が為替レートと日付に合わせて更新されます。残り、毎月の金額、期限切れの表示が自動で変わり、口座の残高で達成した目標は達成した日を覚えています。
• 貸し借り: 返済額が残りを超えることはなく、期日を貸し借りした日より前にはできません。テンは下書きを保存するときにもう一度確認します。
• 預金の編集やローンの削除が速くなりました。関係する口座だけを再計算します。
```

## ko

```
Tenra 1.7.1의 새로운 기능:
• iOS 27에서는 은행 알림이 저절로 기록돼요. 카드·QR 결제, 온라인 구매, 송금, 입금을 어느 은행이든 아무것도 묻지 않고 기록해요. 두 은행에 있는 내 카드끼리의 송금은 한 건의 이체가 돼요. 설정 › Siri 및 단축어 › 은행 알림 설정에서 한 번만 설정하세요. 알림 내용은 iPhone 밖으로 나가지 않아요.
• 저축 목표가 환율과 날짜에 맞춰 업데이트돼요. 남은 금액, 매달 모을 금액, 기한 지남 표시가 저절로 바뀌고, 계좌 잔액으로 달성한 목표는 달성한 날을 기억해요.
• 빌린 돈: 상환 금액은 남은 금액을 넘지 않고, 기한은 빌려주거나 빌린 날보다 앞설 수 없어요. 텐은 초안을 저장할 때 한 번 더 확인해요.
• 예금 편집과 대출 삭제가 빨라졌어요. 관련된 계좌만 다시 계산해요.
```

## Submission checklist (1.7.1)

1. **CI green** on the branch (build and TenraTests on Xcode 27), then a TestFlight build from
   `main` (Actions → TestFlight, [asc.md](asc.md)).
2. **Device check** of that build on the iOS 27 iPhone:
   - a goal following an account: move money into the account past the target, return to the
     app, open the goal: "Reached" shows today's date (no need to have had the goal open);
   - a goal in another currency and a goal with a deadline: the list and the screen redraw after
     a rate refresh and after midnight;
   - a debt: "Repay" with more than is left saves only what is left and settles the debt; the
     due date picker does not go before the debt's date;
   - Ten: draft two repayments for one debt, save both: the second fails; draft a debt, then
     Save as a free user (or after Pro ends): it fails;
   - the microphone and speech permission prompts on a fresh install (they name Ten);
   - deleting a loan both ways and editing a deposit: the paying accounts' balances are right.
3. **The store build**: the TestFlight build that passed step 2, `prepare-version --version 1.7.1
   --build N`.
4. **What's New**: this file (`prepare-version`), en-GB included.
5. **Screenshots**: unchanged from 1.7 (a new version takes the previous version's screenshots in
   App Store Connect); no re-shoot.
6. **App Privacy**: unchanged. The notification text is read on the device and never sent.
7. **App Review notes**, in English, set from this block by
   `asc.py review-notes --version 1.7.1 --apply`:

```
Bank notification capture (announced in 1.7.1) uses the Shortcuts personal automation "When I get a notification from an app" (iOS 27), which runs the Tenra action "Log a bank notification" with the notification's Title, Subtitle, Text, App and Date. To try it without a bank app: open Shortcuts, create a new shortcut, add the Tenra action "Log a bank notification", set Text to "Card ending 4321 was charged $25.00 at COFFEE SHOP" and App to "My Bank", and run it. The expense appears in Tenra at once and waits in Settings > Wallet > To review. Settings > Siri & Shortcuts > Set up bank notifications has the step-by-step guide and "Check a notification", which shows what Tenra reads from a pasted notification without saving anything. The notification's text never leaves the device.

Apple Pay capture uses the Shortcuts "Wallet" personal automation, which fires only on a real contactless payment. To try it without one: create a shortcut with the Tenra action "Log an Apple Pay payment", fill in an amount (e.g. 1500) and a merchant (e.g. "Coffee Boom") and run it. The step-by-step setup guide is in Settings > Siri & Shortcuts.

Tenra Pro features can be tried with a sandbox purchase on the paywall: Settings, the "Get Tenra Pro" button at the top.
```

8. **One submission**: `asc.py prepare-review --version 1.7.1` puts the version into a draft
   review submission (the custom pages are unchanged), never submitted; the founder sends it:
   App Store Connect → Tenra → Distribution → the draft submission → Submit for Review.
