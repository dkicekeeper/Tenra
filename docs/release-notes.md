# Tenra 1.7: What's New (ASC, 13 storefront locales)

Version 1.7, drafted 2026-10-20 from PR #80 (`claude/auto-capture`, in `main` since 2026-10-21),
updated 2026-10-21 with the new Settings and DesignKit 8.0 (PRs #84-#88, TestFlight build 49),
before the device check of [plan-auto-capture.md](plan-auto-capture.md) §8: change it with what
that check changes. `prepare-version` (Actions → App Store Connect, [asc.md](asc.md)) pastes each
block into App Store Connect → Tenra → 1.7 → the locale → "What's New in This Version". No em
dashes (user rule). Names of screens as the app shows them in each locale (`settings.siri.header`,
`walletReview.title`, `subscriptions.candidates.title`). When 1.7 ships, move this file to
`archive/release-notes-1.7.md`.

New since 1.6 (in the store since 2026-10-19):
- Apple Pay payments recorded without a question ("Log an Apple Pay payment" in the Wallet
  automation, the in-app setup guide), the category remembered per merchant and the account per
  card, guesses in To review with a notification.
- Merchant logos (on by default), a merchant's own page, names and logos of the user's own,
  merchants in History's search suggestions.
- "Looks like a subscription", the Top merchant and Average check is up insights.
- A bank PDF opened in Tenra: a statement or a receipt (import behind Tenra Pro, or Ten), a
  receipt repaying a personal debt; the statement reminder; Apple Pay payments missing from a
  statement.
- DesignKit 8.0: forms, lists, filters, History's days and Settings on glass sections; one set of
  actions on every list (tap opens, touch and hold for Edit and Delete, select several, drag to
  reorder; no swipes), reordering for deposits, loans, debts, goals and subscriptions (CoreData
  v16: an order on debts and subscriptions).
- Settings: Tenra Pro page (hero on the aurora), a Wallet section, the Wallet setup guide step by
  step with a picture of each Shortcuts screen; Siri's example phrases gone.
- The cloud builds compile with Xcode 27, so 1.7 is the first store build with the iOS 27 UI.
- In the build since 2026-10-22, not in What's New until the device check says it works: "Log a
  bank notification" for the iOS 27 notification automation (any bank's expenses and incomes,
  [plan-notification-capture.md](plan-notification-capture.md)), its guide in Settings with
  "Check a notification", and transfers between the person's own cards in two banks recorded as
  one transfer.
- From [plan-ads-readiness.md](plan-ads-readiness.md) (2026-10-22, the 1.8 scope shipped with
  1.7): the widgets (For today on the Home Screen and the Lock Screen, the medium one with four
  categories; Log an expense in Control Center; `tenra://` links), iCloud backups on for new
  installs and restore from the welcome screen, Kazakh (the 12th locale; App Store Connect has
  no Kazakh storefront locale, so What's New stays in these 13), Ten's failures that offer Retry,
  Ten's messages hiding amounts and leaving with their subject, German Ten on "Sie",
  Diagnostics counting auto-captured payments.
- Approved on 2026-10-23 from the mockups and in the build since: the onboarding's
  auto-capture step and second slide, the auto-capture card and the one-time iCloud ask on Home,
  Ten's message once after the first entries when the card was hidden.
- The founder's notes of 2026-10-23: For today on Analytics (off Home), a link to how it is
  reached; Settings a page of Home's stack (not a sheet) topped by a Tenra Pro hero with one
  button that opens the paywall (what Pro includes is the RevenueCat paywall's list); For today
  counts a deposit marked "Count in For today" and sets aside payments in other currencies at
  today's rate (a planned dollar expense on a tenge card was left out).

## en-US

```
What's new in Tenra 1.7:
• Apple Pay payments log themselves. Set up the Wallet automation once in Settings › Siri & Shortcuts, and every tap at a terminal is recorded with its merchant, amount, currency and card, without a single question.
• Tenra learns as you go: the category for each merchant, the account for each card. A payment it had to guess waits in To review, and a quiet notification lets you check it.
• Widgets: For today on the Home Screen and the Lock Screen shows how much you can spend a day until your next income and what went out today. The medium size adds your four most used categories, one tap from a new expense. And Log an expense in Control Center.
• Analytics shows For today: how much you can spend a day until your next income, with subscriptions and loan payments already set aside. Tap it to see how it adds up.
• Merchants get their logos and a page of their own: this month and this year, a monthly chart, visits and the average check. Give a merchant your own name or logo, and find it from search.
• Looks like a subscription: charges that come back every month show up in Subscriptions, ready to track with one tap.
• New insights: your top merchant, and a merchant whose average check keeps going up.
• Open a bank PDF in Tenra from any app: a statement is imported, a payment receipt becomes one expense, and a transfer to someone you owe can repay that debt (import with Tenra Pro).
• A statement reminder, every week or as you choose, and the statement check shows Apple Pay payments your bank does not list.
• A fresh look: screens, forms and lists on glass cards. Every list works the same way: touch and hold to edit or delete, select several at once, and drag deposits, loans, debts, goals and subscriptions into your own order.
• Settings, reorganized: a page with Tenra Pro on top, Apple Pay payments get their own Wallet section, and the Wallet setup guide goes step by step, with a picture of every screen.
• Setting up Tenra ends with a new step: turn on auto-capture, or read a bank statement right away.
• New installs back up to iCloud from the start, and on a new iPhone you can restore a backup right from the welcome screen.
• Tenra now speaks Kazakh.
```

## ru

```
Что нового в Tenra 1.7:
• Оплаты Apple Pay записываются сами. Один раз настройте автоматизацию Wallet в Настройках › Siri и команды, и каждая оплата на терминале запишется с продавцом, суммой, валютой и картой, без единого вопроса.
• Tenra учится по ходу: запоминает категорию для каждого продавца и счёт для каждой карты. Оплата, в которой пришлось угадывать, ждёт в разделе «На проверку», а тихое уведомление подскажет её проверить.
• Виджеты: «На сегодня» на экране «Домой» и на экране блокировки показывает, сколько можно тратить в день до следующего дохода и сколько ушло сегодня. Средний виджет добавляет четыре частые категории, нажатие сразу открывает новую трату. А в Пункте управления есть кнопка «Записать трату».
• В Аналитике появилось «На сегодня»: сколько можно тратить в день до следующего дохода, с уже отложенными подписками и платежами по кредитам. Нажмите, чтобы увидеть, из чего складывается сумма.
• У продавцов появились логотипы и своя страница: траты в этом месяце и за год, график по месяцам, визиты и средний чек. Дайте продавцу своё название или логотип и находите его через поиск.
• «Похоже на подписку»: списания, которые повторяются каждый месяц, появляются в Подписках, и их можно отслеживать одним нажатием.
• Новые инсайты: топ-продавец и продавец, у которого растёт средний чек.
• Откройте PDF банка в Tenra из любого приложения: выписка импортируется, чек об оплате станет одним расходом, а перевод тому, кому вы должны, может погасить долг (импорт в Tenra Pro).
• Напоминание о выписке, раз в неделю или как вам удобно, а сверка выписки покажет оплаты Apple Pay, которых нет у банка.
• Новый вид: экраны, формы и списки на стеклянных карточках. Все списки работают одинаково: удерживайте, чтобы изменить или удалить, выбирайте несколько сразу и расставляйте депозиты, кредиты, долги, цели и подписки в своём порядке.
• Настройки по-новому: страница с Tenra Pro наверху, у оплат Apple Pay свой раздел Wallet, а инструкция по автоматизации Wallet идёт по шагам, с картинкой каждого экрана.
• Настройка Tenra заканчивается новым шагом: включите автозапись или сразу загрузите выписку банка.
• Новые установки сразу сохраняют копии в iCloud, а на новом iPhone копию можно восстановить прямо с экрана приветствия.
• Tenra теперь говорит по-казахски.
```

## de-DE

```
Neu in Tenra 1.7:
• Apple Pay-Zahlungen tragen sich selbst ein. Richten Sie einmal die Wallet-Automation unter Einstellungen › Siri und Kurzbefehle ein, und jede Zahlung am Terminal wird mit Händler, Betrag, Währung und Karte erfasst, ohne eine einzige Frage.
• Tenra lernt mit: die Kategorie für jeden Händler, das Konto für jede Karte. Eine Zahlung, bei der Tenra raten musste, wartet unter „Zu prüfen“, und eine dezente Mitteilung erinnert Sie daran.
• Widgets: „Für heute“ auf dem Home-Bildschirm und dem Sperrbildschirm zeigt, wie viel Sie bis zur nächsten Einnahme pro Tag ausgeben können und was heute ausgegeben wurde. Das mittlere Widget zeigt dazu Ihre vier häufigsten Kategorien, ein Tippen öffnet die neue Ausgabe. Und im Kontrollzentrum: „Ausgabe erfassen“.
• Die Analyse zeigt „Für heute“: wie viel Sie bis zur nächsten Einnahme pro Tag ausgeben können, Abos und Kreditraten schon abgezogen. Ein Tippen zeigt, wie sich der Betrag ergibt.
• Händler haben jetzt Logos und eine eigene Seite: dieser Monat und dieses Jahr, ein Monatsdiagramm, Besuche und der durchschnittliche Bon. Geben Sie einem Händler einen eigenen Namen oder ein Logo, und finden Sie ihn über die Suche.
• „Sieht nach einem Abo aus“: Abbuchungen, die jeden Monat wiederkommen, erscheinen bei den Abos und lassen sich mit einem Tippen verfolgen.
• Neue Hinweise: Ihr Top-Händler und ein Händler, dessen durchschnittlicher Bon immer weiter steigt.
• Öffnen Sie ein Bank-PDF aus jeder App in Tenra: Ein Kontoauszug wird importiert, ein Zahlungsbeleg wird zu einer Ausgabe, und eine Überweisung an jemanden, dem Sie Geld schulden, kann diese Schuld tilgen (Import mit Tenra Pro).
• Eine Erinnerung an den Kontoauszug, jede Woche oder wie Sie möchten, und der Abgleich zeigt Apple Pay-Zahlungen, die Ihre Bank nicht aufführt.
• Ein frischer Look: Bildschirme, Formulare und Listen auf Glaskarten. Alle Listen funktionieren gleich: gedrückt halten zum Bearbeiten oder Löschen, mehrere auf einmal auswählen und Sparkonten, Kredite, Schulden, Sparziele und Abos in Ihre eigene Reihenfolge ziehen.
• Neu geordnete Einstellungen: eine Seite mit Tenra Pro ganz oben, Apple Pay-Zahlungen haben einen eigenen Wallet-Bereich, und die Anleitung zur Wallet-Automation führt Schritt für Schritt, mit einem Bild jedes Bildschirms.
• Die Einrichtung von Tenra endet mit einem neuen Schritt: automatische Erfassung einschalten oder gleich einen Kontoauszug einlesen.
• Neue Installationen sichern von Anfang an in iCloud, und auf einem neuen iPhone stellen Sie ein Backup direkt auf dem Begrüßungsbildschirm wieder her.
• Tenra spricht jetzt Kasachisch.
```

## es-ES

```
Novedades de Tenra 1.7:
• Los pagos con Apple Pay se registran solos. Configura una vez la automatización de Wallet en Ajustes › Siri y atajos, y cada pago en el datáfono se guarda con su comercio, importe, divisa y tarjeta, sin una sola pregunta.
• Tenra aprende sobre la marcha: la categoría de cada comercio y la cuenta de cada tarjeta. Un pago en el que tuvo que adivinar espera en «Por revisar», y una notificación discreta te avisa para comprobarlo.
• Widgets: «Para hoy» en la pantalla de inicio y en la pantalla bloqueada muestra cuánto puedes gastar al día hasta tu próximo ingreso y lo que ha salido hoy. El mediano añade tus cuatro categorías más usadas, a un toque de un gasto nuevo. Y en el centro de control, «Registrar un gasto».
• Análisis muestra «Para hoy»: cuánto puedes gastar al día hasta tu próximo ingreso, con las suscripciones y las cuotas de préstamos ya apartadas. Tócalo para ver cómo se calcula.
• Los comercios tienen logo y su propia página: este mes y este año, un gráfico mensual, visitas y el ticket medio. Ponle a un comercio tu propio nombre o logo, y encuéntralo desde la búsqueda.
• «Parece una suscripción»: los cargos que se repiten cada mes aparecen en Suscripciones, listos para seguirlos con un toque.
• Nuevos análisis: el comercio en el que más gastas, y un comercio cuyo ticket medio no deja de subir.
• Abre un PDF del banco en Tenra desde cualquier app: un extracto se importa, un recibo de pago se convierte en un gasto, y una transferencia a alguien a quien debes dinero puede saldar esa deuda (importación con Tenra Pro).
• Un recordatorio del extracto, cada semana o cuando prefieras, y la revisión del extracto muestra los pagos con Apple Pay que tu banco no incluye.
• Un aspecto renovado: pantallas, formularios y listas en tarjetas de cristal. Todas las listas funcionan igual: mantén pulsado para editar o eliminar, selecciona varios a la vez y ordena a tu manera depósitos, préstamos, deudas, metas y suscripciones arrastrándolos.
• Ajustes reorganizados: una página con Tenra Pro arriba, los pagos con Apple Pay en su propia sección Wallet, y la guía de la automatización de Wallet va paso a paso, con una imagen de cada pantalla.
• La configuración de Tenra termina con un paso nuevo: activa el registro automático o lee ya un extracto del banco.
• Las instalaciones nuevas guardan copias en iCloud desde el principio, y en un iPhone nuevo puedes restaurar una copia desde la pantalla de bienvenida.
• Tenra ya habla kazajo.
```

## es-MX

```
Novedades de Tenra 1.7:
• Los pagos con Apple Pay se registran solos. Configura una vez la automatización de Wallet en Configuración › Siri y atajos, y cada pago en la terminal se guarda con su comercio, monto, moneda y tarjeta, sin una sola pregunta.
• Tenra aprende sobre la marcha: la categoría de cada comercio y la cuenta de cada tarjeta. Un pago en el que tuvo que adivinar espera en «Por revisar», y una notificación discreta te avisa para revisarlo.
• Widgets: «Para hoy» en la pantalla de inicio y en la pantalla bloqueada muestra cuánto puedes gastar al día hasta tu próximo ingreso y lo que salió hoy. El mediano agrega tus cuatro categorías más usadas, a un toque de un gasto nuevo. Y en el centro de control, «Registrar un gasto».
• Análisis muestra «Para hoy»: cuánto puedes gastar al día hasta tu próximo ingreso, con las suscripciones y los pagos de préstamos ya apartados. Tócalo para ver cómo se calcula.
• Los comercios tienen logo y su propia página: este mes y este año, una gráfica mensual, visitas y el ticket promedio. Ponle a un comercio tu propio nombre o logo, y encuéntralo desde la búsqueda.
• «Parece una suscripción»: los cargos que se repiten cada mes aparecen en Suscripciones, listos para seguirlos con un toque.
• Nuevos análisis: el comercio en el que más gastas, y un comercio cuyo ticket promedio no deja de subir.
• Abre un PDF del banco en Tenra desde cualquier app: un estado de cuenta se importa, un comprobante de pago se convierte en un gasto, y una transferencia a alguien a quien le debes puede saldar esa deuda (importación con Tenra Pro).
• Un recordatorio del estado de cuenta, cada semana o cuando prefieras, y la revisión del estado de cuenta muestra los pagos con Apple Pay que tu banco no incluye.
• Un aspecto renovado: pantallas, formularios y listas en tarjetas de cristal. Todas las listas funcionan igual: mantén presionado para editar o eliminar, selecciona varios a la vez y ordena a tu manera depósitos, préstamos, deudas, metas y suscripciones arrastrándolos.
• Configuración reorganizada: una página con Tenra Pro arriba, los pagos con Apple Pay en su propia sección Wallet, y la guía de la automatización de Wallet va paso a paso, con una imagen de cada pantalla.
• La configuración de Tenra termina con un paso nuevo: activa el registro automático o lee ya un estado de cuenta.
• Las instalaciones nuevas guardan respaldos en iCloud desde el principio, y en un iPhone nuevo puedes restaurar un respaldo desde la pantalla de bienvenida.
• Tenra ya habla kazajo.
```

## fr-FR

```
Nouveautés de Tenra 1.7 :
• Les paiements Apple Pay s'enregistrent tout seuls. Configurez une fois l'automatisation Wallet dans Réglages › Siri et raccourcis, et chaque paiement au terminal est enregistré avec son commerçant, son montant, sa devise et sa carte, sans la moindre question.
• Tenra apprend au fil de l'eau : la catégorie de chaque commerçant, le compte de chaque carte. Un paiement pour lequel il a dû deviner attend dans « À vérifier », et une notification discrète vous invite à le vérifier.
• Widgets : « Pour aujourd’hui » sur l’écran d’accueil et l’écran verrouillé indique combien vous pouvez dépenser par jour jusqu’à votre prochain revenu et ce qui est sorti aujourd’hui. Le format moyen ajoute vos quatre catégories les plus utilisées, à un toucher d’une nouvelle dépense. Et dans le centre de contrôle, « Noter une dépense ».
• Analyse affiche « Pour aujourd’hui » : combien vous pouvez dépenser par jour jusqu’à votre prochain revenu, abonnements et mensualités de prêt déjà mis de côté. Touchez-le pour voir le détail du calcul.
• Les commerçants ont leur logo et leur propre page : ce mois-ci et cette année, un graphique mensuel, les visites et le panier moyen. Donnez à un commerçant votre propre nom ou logo, et retrouvez-le depuis la recherche.
• « Ressemble à un abonnement » : les prélèvements qui reviennent chaque mois apparaissent dans Abonnements, prêts à être suivis d'un geste.
• Nouveaux conseils : votre premier commerçant, et un commerçant dont le panier moyen ne cesse d'augmenter.
• Ouvrez un PDF de votre banque dans Tenra depuis n'importe quelle app : un relevé est importé, un reçu de paiement devient une dépense, et un virement à quelqu'un à qui vous devez de l'argent peut rembourser cette dette (import avec Tenra Pro).
• Un rappel de relevé, chaque semaine ou quand vous le souhaitez, et la vérification du relevé montre les paiements Apple Pay que votre banque n'affiche pas.
• Un nouveau look : écrans, formulaires et listes sur des cartes en verre. Toutes les listes fonctionnent de la même façon : maintenez le doigt pour modifier ou supprimer, sélectionnez-en plusieurs à la fois et faites glisser comptes épargne, prêts, dettes, objectifs et abonnements dans l'ordre de votre choix.
• Des réglages réorganisés : une page avec Tenra Pro en haut, les paiements Apple Pay dans leur propre section Wallet, et le guide de l'automatisation Wallet avance étape par étape, avec une image de chaque écran.
• La configuration de Tenra se termine par une nouvelle étape : activez l’enregistrement automatique ou importez tout de suite un relevé bancaire.
• Les nouvelles installations sauvegardent dans iCloud dès le départ, et sur un nouvel iPhone vous pouvez restaurer une sauvegarde directement depuis l’écran de bienvenue.
• Tenra parle désormais kazakh.
```

## fr-CA

```
Nouveautés de Tenra 1.7 :
• Les paiements Apple Pay s'enregistrent tout seuls. Configurez une fois l'automatisation Wallet dans Réglages › Siri et raccourcis, et chaque paiement au terminal est enregistré avec son commerçant, son montant, sa devise et sa carte, sans la moindre question.
• Tenra apprend au fur et à mesure : la catégorie de chaque commerçant, le compte de chaque carte. Un paiement pour lequel il a dû deviner attend dans « À vérifier », et une notification discrète vous invite à le vérifier.
• Widgets : « Pour aujourd’hui » sur l’écran d’accueil et l’écran verrouillé indique combien vous pouvez dépenser par jour jusqu’à votre prochain revenu et ce qui est sorti aujourd’hui. Le format moyen ajoute vos quatre catégories les plus utilisées, à un toucher d’une nouvelle dépense. Et dans le centre de contrôle, « Noter une dépense ».
• Analyse affiche « Pour aujourd’hui » : combien vous pouvez dépenser par jour jusqu’à votre prochain revenu, abonnements et versements de prêt déjà mis de côté. Touchez-le pour voir le détail du calcul.
• Les commerçants ont leur logo et leur propre page : ce mois-ci et cette année, un graphique mensuel, les visites et la facture moyenne. Donnez à un commerçant votre propre nom ou logo, et retrouvez-le depuis la recherche.
• « Ressemble à un abonnement » : les frais qui reviennent chaque mois apparaissent dans Abonnements, prêts à être suivis d'un toucher.
• Nouveaux conseils : votre premier commerçant, et un commerçant dont la facture moyenne ne cesse d'augmenter.
• Ouvrez un PDF de votre institution financière dans Tenra depuis n'importe quelle app : un relevé est importé, un reçu de paiement devient une dépense, et un virement à quelqu'un à qui vous devez de l'argent peut rembourser cette dette (importation avec Tenra Pro).
• Un rappel de relevé, chaque semaine ou quand vous le souhaitez, et la vérification du relevé montre les paiements Apple Pay que votre institution financière n'affiche pas.
• Un nouveau look : écrans, formulaires et listes sur des cartes en verre. Toutes les listes fonctionnent de la même façon : maintenez le doigt pour modifier ou supprimer, sélectionnez-en plusieurs à la fois et faites glisser comptes épargne, prêts, dettes, objectifs et abonnements dans l'ordre de votre choix.
• Des réglages réorganisés : une page avec Tenra Pro en haut, les paiements Apple Pay dans leur propre section Wallet, et le guide de l'automatisation Wallet avance étape par étape, avec une image de chaque écran.
• La configuration de Tenra se termine par une nouvelle étape : activez l’enregistrement automatique ou importez tout de suite un relevé bancaire.
• Les nouvelles installations sauvegardent dans iCloud dès le départ, et sur un nouvel iPhone vous pouvez restaurer une sauvegarde directement depuis l’écran de bienvenue.
• Tenra parle maintenant kazakh.
```

## tr

```
Tenra 1.7'deki yenilikler:
• Apple Pay ödemeleri kendiliğinden kaydedilir. Wallet otomasyonunu Ayarlar › Siri ve kısayollar'da bir kez kur; terminalde yaptığın her ödeme işyeri, tutar, para birimi ve kartıyla, tek bir soru sormadan kaydedilir.
• Tenra kullandıkça öğrenir: her işyerinin kategorisini, her kartın hesabını. Tahmin etmek zorunda kaldığı bir ödeme "Kontrol edilecekler"de bekler, sakin bir bildirim de kontrol etmeni hatırlatır.
• Widget'lar: Ana ekranda ve kilitli ekranda "Bugün için", bir sonraki gelirine kadar günde ne kadar harcayabileceğini ve bugün ne çıktığını gösterir. Orta boy widget en çok kullandığın dört kategoriyi ekler, yeni bir harcama tek dokunuş uzakta. Denetim Merkezi'nde de "Harcama kaydet" var.
• Analiz'de "Bugün için" var: bir sonraki gelirine kadar günde ne kadar harcayabileceğin, abonelikler ve kredi ödemeleri ayrılmış olarak. Dokununca nasıl hesaplandığını görürsün.
• İşyerlerinin artık logoları ve kendi sayfaları var: bu ay ve bu yıl, aylık grafik, ziyaretler ve ortalama sepet. Bir işyerine kendi adını ya da logosunu ver, aramadan bul.
• "Abonelik gibi görünüyor": her ay tekrarlanan ödemeler Abonelikler'de görünür, tek dokunuşla takip etmeye hazır.
• Yeni öngörüler: en çok harcadığın işyeri ve ortalama sepeti sürekli büyüyen bir işyeri.
• Herhangi bir uygulamadan bir banka PDF'ini Tenra'da aç: hesap özeti içe aktarılır, ödeme dekontu tek bir gidere dönüşür, borçlu olduğun birine yaptığın havale de o borcu kapatabilir (içe aktarma Tenra Pro ile).
• Haftalık ya da istediğin sıklıkta bir hesap özeti hatırlatıcısı; hesap özeti kontrolü de bankanın listelemediği Apple Pay ödemelerini gösterir.
• Yeni bir görünüm: ekranlar, formlar ve listeler cam kartlarda. Tüm listeler aynı şekilde çalışır: düzenlemek ya da silmek için basılı tut, birkaçını aynı anda seç; mevduatları, kredileri, borçları, hedefleri ve abonelikleri sürükleyerek kendi sırana koy.
• Yeniden düzenlenen Ayarlar: en üstte Tenra Pro olan bir sayfa, Apple Pay ödemelerinin kendi Wallet bölümü var; Wallet otomasyonu rehberi de her ekranın resmiyle adım adım ilerler.
• Tenra kurulumu yeni bir adımla bitiyor: otomatik kaydı aç ya da hemen bir banka ekstresi yükle.
• Yeni kurulumlar en baştan iCloud'a yedeklenir, yeni bir iPhone'da da yedeği doğrudan karşılama ekranından geri yükleyebilirsin.
• Tenra artık Kazakça konuşuyor.
```

## pt-BR

```
Novidades do Tenra 1.7:
• Os pagamentos com Apple Pay se registram sozinhos. Configure uma vez a automação da Wallet em Ajustes › Siri e atalhos, e cada pagamento na maquininha é salvo com o estabelecimento, o valor, a moeda e o cartão, sem nenhuma pergunta.
• O Tenra aprende com o uso: a categoria de cada estabelecimento e a conta de cada cartão. Um pagamento em que ele precisou adivinhar fica em "Para revisar", e uma notificação discreta lembra você de conferir.
• Widgets: "Para hoje" na tela de início e na tela bloqueada mostra quanto você pode gastar por dia até a próxima receita e o que saiu hoje. O médio adiciona suas quatro categorias mais usadas, a um toque de um novo gasto. E na Central de Controle, "Registrar um gasto".
• Análises mostra "Para hoje": quanto você pode gastar por dia até a próxima receita, com assinaturas e parcelas de empréstimo já separadas. Toque para ver como o valor é calculado.
• Os estabelecimentos ganharam logos e uma página própria: este mês e este ano, um gráfico mensal, as visitas e o tíquete médio. Dê ao estabelecimento um nome ou logo seu, e encontre-o pela busca.
• "Parece uma assinatura": cobranças que se repetem todo mês aparecem em Assinaturas, prontas para acompanhar com um toque.
• Novos insights: o estabelecimento com mais gastos e um estabelecimento cujo tíquete médio não para de subir.
• Abra um PDF do banco no Tenra a partir de qualquer app: um extrato é importado, um comprovante de pagamento vira uma despesa, e uma transferência para alguém a quem você deve pode quitar essa dívida (importação com o Tenra Pro).
• Um lembrete de extrato, toda semana ou como preferir, e a conferência do extrato mostra os pagamentos com Apple Pay que o seu banco não lista.
• Um visual renovado: telas, formulários e listas em cartões de vidro. Todas as listas funcionam do mesmo jeito: toque e segure para editar ou apagar, selecione vários de uma vez e arraste depósitos, empréstimos, dívidas, metas e assinaturas para a sua própria ordem.
• Ajustes reorganizados: uma página com o Tenra Pro no topo, os pagamentos com Apple Pay numa seção Wallet só deles, e o guia da automação da Wallet vai passo a passo, com uma imagem de cada tela.
• A configuração do Tenra termina com um passo novo: ative o registro automático ou leia um extrato do banco na hora.
• Novas instalações fazem backup no iCloud desde o início, e num iPhone novo você restaura um backup direto da tela de boas-vindas.
• O Tenra agora fala cazaque.
```

## it

```
Novità di Tenra 1.7:
• I pagamenti con Apple Pay si registrano da soli. Configura una volta l'automazione Wallet in Impostazioni › Siri e comandi rapidi, e ogni pagamento al POS viene salvato con esercente, importo, valuta e carta, senza nemmeno una domanda.
• Tenra impara strada facendo: la categoria di ogni esercente, il conto di ogni carta. Un pagamento in cui ha dovuto tirare a indovinare aspetta in «Da controllare», e una notifica discreta ti ricorda di verificarlo.
• Widget: «Per oggi» nella schermata Home e nella schermata di blocco mostra quanto puoi spendere al giorno fino alla prossima entrata e quanto è uscito oggi. Quello medio aggiunge le tue quattro categorie più usate, a un tocco da una nuova spesa. E nel Centro di Controllo, «Registra una spesa».
• Analisi mostra «Per oggi»: quanto puoi spendere al giorno fino alla prossima entrata, con abbonamenti e rate del prestito già messi da parte. Toccalo per vedere come si calcola.
• Gli esercenti hanno il loro logo e una pagina tutta loro: questo mese e quest'anno, un grafico mensile, le visite e lo scontrino medio. Dai a un esercente un nome o un logo tuo, e ritrovalo dalla ricerca.
• «Sembra un abbonamento»: gli addebiti che tornano ogni mese compaiono in Abbonamenti, pronti da seguire con un tocco.
• Nuovi suggerimenti: il tuo esercente principale e un esercente il cui scontrino medio continua a salire.
• Apri in Tenra un PDF della banca da qualsiasi app: un estratto conto viene importato, una ricevuta di pagamento diventa una spesa, e un bonifico a qualcuno a cui devi dei soldi può saldare quel debito (importazione con Tenra Pro).
• Un promemoria per l'estratto conto, ogni settimana o quando preferisci, e il controllo dell'estratto mostra i pagamenti Apple Pay che la tua banca non riporta.
• Un aspetto nuovo: schermate, moduli ed elenchi su schede di vetro. Tutti gli elenchi funzionano allo stesso modo: tieni premuto per modificare o eliminare, selezionane diversi insieme e trascina depositi, prestiti, debiti, obiettivi e abbonamenti nell'ordine che preferisci.
• Impostazioni riorganizzate: una pagina con Tenra Pro in cima, i pagamenti Apple Pay in una sezione Wallet dedicata, e la guida all'automazione Wallet procede passo dopo passo, con un'immagine di ogni schermata.
• La configurazione di Tenra finisce con un nuovo passo: attiva la registrazione automatica o leggi subito un estratto conto.
• Le nuove installazioni fanno il backup su iCloud fin dall’inizio, e su un nuovo iPhone puoi ripristinare un backup direttamente dalla schermata di benvenuto.
• Tenra ora parla kazako.
```

## uk

```
Що нового в Tenra 1.7:
• Оплати Apple Pay записуються самі. Один раз налаштуйте автоматизацію Wallet у Налаштуваннях › Siri та команди, і кожна оплата на терміналі запишеться з продавцем, сумою, валютою та карткою, без жодного запитання.
• Tenra вчиться по ходу: запам'ятовує категорію для кожного продавця і рахунок для кожної картки. Оплата, у якій довелося вгадувати, чекає в розділі «На перевірку», а тихе сповіщення підкаже її перевірити.
• Віджети: «На сьогодні» на початковому екрані та на екрані блокування показує, скільки можна витрачати на день до наступного доходу і скільки пішло сьогодні. Середній віджет додає чотири найчастіші категорії, дотик одразу відкриває нову витрату. А в Пункті керування є кнопка «Записати витрату».
• В Аналітиці з'явилося «На сьогодні»: скільки можна витрачати на день до наступного доходу, з уже відкладеними підписками та платежами за кредитами. Натисніть, щоб побачити, з чого складається сума.
• У продавців з'явилися логотипи й власна сторінка: витрати цього місяця і за рік, графік по місяцях, візити й середній чек. Дайте продавцеві свою назву чи логотип і знаходьте його через пошук.
• «Схоже на підписку»: списання, що повторюються щомісяця, з'являються в Підписках, і їх можна відстежувати одним дотиком.
• Нові інсайти: головний продавець і продавець, у якого зростає середній чек.
• Відкрийте PDF банку в Tenra з будь-якого застосунку: виписка імпортується, квитанція про оплату стане однією витратою, а переказ тому, кому ви винні, може погасити борг (імпорт у Tenra Pro).
• Нагадування про виписку, щотижня чи як вам зручно, а звірка виписки покаже оплати Apple Pay, яких немає в банку.
• Новий вигляд: екрани, форми та списки на скляних картках. Усі списки працюють однаково: утримуйте, щоб змінити чи видалити, вибирайте кілька одразу й розставляйте депозити, кредити, борги, цілі та підписки у своєму порядку.
• Налаштування по-новому: сторінка з Tenra Pro нагорі, в оплат Apple Pay свій розділ Wallet, а інструкція з автоматизації Wallet іде крок за кроком, з картинкою кожного екрана.
• Налаштування Tenra завершується новим кроком: увімкніть автозапис або одразу завантажте виписку банку.
• Нові встановлення одразу зберігають копії в iCloud, а на новому iPhone копію можна відновити просто з екрана привітання.
• Tenra тепер розмовляє казахською.
```

## ja

```
Tenra 1.7 の新機能:
• Apple Pay の支払いが自動で記録されます。設定 › Siri とショートカット で Wallet オートメーションを一度設定すれば、端末での支払いが店舗、金額、通貨、カードとともに、質問なしで記録されます。
• Tenra は使うほど覚えます。店舗ごとのカテゴリ、カードごとの口座。推測で記録した支払いは「確認待ち」に入り、控えめな通知でお知らせします。
• ウィジェット: ホーム画面とロック画面の「今日の予算」に、次の収入まで1日に使える金額と今日の支出が表示されます。中サイズにはよく使う4つのカテゴリが並び、タップするとすぐに支出を記録できます。コントロールセンターには「支出を記録」ボタンもあります。
• 「分析」に「今日の予算」を表示。サブスクやローンの返済を差し引いたうえで、次の収入まで1日に使える金額がわかります。タップすると計算の内訳を確認できます。
• 店舗にロゴと専用ページが付きました。今月と今年の支出、月別グラフ、来店回数、平均購入額。店舗に自分で名前やロゴを付けて、検索から探せます。
• 「サブスクリプションのようです」: 毎月くり返す支払いがサブスクリプションに表示され、ワンタップで管理を始められます。
• 新しいインサイト: 支出トップの店舗と、平均購入額が上がり続けている店舗。
• どのアプリからでも銀行の PDF を Tenra で開けます。明細書は読み込まれ、支払いのレシートは1件の支出になり、借りている相手への振込でその借りを返済できます(読み込みは Tenra Pro)。
• 毎週または好きな間隔で明細書のリマインダー。明細書のチェックでは、銀行の明細にない Apple Pay の支払いが分かります。
• 新しいデザイン: 画面、フォーム、リストがガラスのカードになりました。どのリストも同じ操作です。長押しで編集や削除、まとめて選択ができ、預金、ローン、貸し借り、貯金目標、サブスクリプションはドラッグで好きな順に並べ替えられます。
• 設定を整理しました。Tenra Pro がいちばん上にあるページになり、Apple Pay の支払いは Wallet セクションにまとまり、Wallet オートメーションの設定ガイドは各画面の図付きでステップごとに進みます。
• 初期設定の最後に新しいステップを追加。自動記録をオンにしたり、すぐに銀行の明細書を読み込んだりできます。
• 新しくインストールすると最初から iCloud にバックアップされ、新しい iPhone ではようこそ画面からそのままバックアップを復元できます。
• Tenra がカザフ語に対応しました。
```

## ko

```
Tenra 1.7의 새로운 기능:
• Apple Pay 결제가 저절로 기록돼요. 설정 › Siri 및 단축어에서 Wallet 자동화를 한 번만 설정하면, 단말기에서 결제할 때마다 가맹점, 금액, 통화, 카드와 함께 아무것도 묻지 않고 기록돼요.
• Tenra는 쓸수록 배워요. 가맹점마다 카테고리를, 카드마다 계좌를 기억해요. 추측해서 기록한 결제는 '확인할 결제'에서 기다리고, 조용한 알림으로 확인을 도와줘요.
• 위젯: 홈 화면과 잠금 화면의 '오늘의 예산'이 다음 수입까지 하루에 쓸 수 있는 금액과 오늘 쓴 돈을 보여 줘요. 중간 크기에는 자주 쓰는 카테고리 네 개가 있어 탭 한 번으로 지출을 기록할 수 있어요. 제어 센터에는 '지출 기록' 버튼도 있어요.
• '분석'에 '오늘의 예산'이 보여요. 구독과 대출 상환을 미리 빼고, 다음 수입까지 하루에 쓸 수 있는 금액을 알려 줘요. 누르면 어떻게 계산했는지 볼 수 있어요.
• 가맹점에 로고와 전용 페이지가 생겼어요. 이번 달과 올해 지출, 월별 차트, 방문 횟수, 평균 결제액. 가맹점에 나만의 이름이나 로고를 붙이고 검색으로 찾아보세요.
• '구독으로 보여요': 매달 반복되는 결제가 구독에 나타나고, 한 번의 탭으로 관리할 수 있어요.
• 새로운 인사이트: 지출이 가장 많은 가맹점과 평균 결제액이 계속 늘고 있는 가맹점.
• 어떤 앱에서든 은행 PDF를 Tenra로 열어 보세요. 명세서는 가져오고, 결제 영수증은 지출 한 건이 되고, 빚진 사람에게 보낸 이체로 그 빚을 갚을 수 있어요(가져오기는 Tenra Pro).
• 매주 또는 원하는 간격으로 명세서 알림을 받고, 명세서 확인에서 은행 내역에 없는 Apple Pay 결제를 볼 수 있어요.
• 새로운 디자인: 화면, 양식, 목록이 유리 카드로 바뀌었어요. 모든 목록이 똑같이 동작해요. 길게 눌러 편집하거나 삭제하고, 여러 개를 한 번에 선택하고, 예금, 대출, 빌린 돈, 저축 목표, 구독을 끌어서 원하는 순서로 정리할 수 있어요.
• 새로 정리한 설정: Tenra Pro가 맨 위에 있는 페이지가 되고, Apple Pay 결제는 Wallet 섹션에 모였어요. Wallet 자동화 설정 가이드는 화면마다 그림과 함께 단계별로 안내해요.
• 처음 설정의 마지막에 새 단계가 생겼어요. 자동 기록을 켜거나 바로 은행 명세서를 불러올 수 있어요.
• 새로 설치하면 처음부터 iCloud에 백업되고, 새 iPhone에서는 시작 화면에서 바로 백업을 복원할 수 있어요.
• Tenra가 이제 카자흐어를 지원해요.
```

## Submission checklist (1.7)

0. **Ready for ads:** P0 of [plan-ads-readiness.md](plan-ads-readiness.md) §2.2 has landed (ASA
   attribution, the Pro page names Ten, onboarding sells auto-capture, iCloud backups by default
   and restore on the welcome screen, Ten's capacity, the store page), P1 §2.3 as far as it fits;
   What's New below gets the lines for what the user sees, and the device check covers the new
   screens.
1. **Device check** of the newest TestFlight build (56 on 2026-10-23: everything of 1.7, the
   widgets, Kazakh, the screens from the approved mockups and the founder's notes of 2026-10-23)
   on the iOS 27 iPhone, then
   fix what it finds:
   - the Wallet automation ([plan-auto-capture.md](plan-auto-capture.md) §8 and the "not yet
     checked" list of PR #80), set up by the new step-by-step guide;
   - **the update from 1.6** (CoreData v15 → v16, lightweight): install the store's 1.6 with data,
     then the TestFlight build over it; debts and subscriptions keep their order, nothing lost;
   - the lists' one set of actions (touch and hold, select, reorder; no swipes left anywhere), the
     glass sections, Settings as a page with the Tenra Pro hero (free, subscriber, Founding User)
     in light and dark, the paywall from its button, For today on Analytics and its breakdown,
     the Wallet section;
   - the bank notification automation with Kaspi and Freedom (iOS 27,
     [plan-notification-capture.md](plan-notification-capture.md) §11): announce it in What's New
     and the App Review notes only if it works.
   The founder checked build 56 on 2026-10-24.
2. **The store build** is the TestFlight build from GitHub that passed step 1: built with Xcode 27,
   it has the iOS 27 code paths ([asc.md](asc.md)). Build 56 is selected for version 1.7
   (`prepare-version --build 56`, 2026-10-24).
3. **What's New**: this file, in version 1.7 since 2026-10-23 (`prepare-version`; en-GB took ru's
   with `push-metadata`). Bank notifications are not announced.
4. **Screenshots** of the main page from 1.7: done on 2026-10-23. The 14 sets (13 locales and kk
   for en-GB) were shot in two runs of seven, about 70 minutes each, approved by the founder and
   uploaded to version 1.7 in all 14 localizations (`push-version-screenshots`), en-GB with kk's.
   The store texts are applied (`push-metadata --apply`). Re-shoot only what changes:
   `frames: home` and the other partial modes ([asc.md](asc.md)).
5. **App Privacy**: unchanged. Logo lookups by a merchant's name (logo.dev, Apple Pay merchants
   only, never a sole proprietor) send only a company name, as the privacy policy already says
   (`docs/public/privacy-policy.html`, Logos).
6. **App Review notes** (App Store Connect → 1.7 → App Review Information → Notes), in English,
   set from this block by `asc.py review-notes --version 1.7 --apply` (done on 2026-10-24):

```
Apple Pay capture (new in 1.7) uses the Shortcuts "Wallet" personal automation, which fires only
on a real contactless payment. To try it without one: open Shortcuts, create a new shortcut, add
the Tenra action "Log an Apple Pay payment", fill in an amount (e.g. 1500) and a merchant
(e.g. "Coffee Boom") and run it. The payment appears in Tenra at once, under the category the app
guessed, and waits in Settings > Wallet > To review. The step-by-step setup guide for the real
automation is in Settings > Siri & Shortcuts.

Nothing about the payment leaves the device. The only network request is a logo lookup by the
shop's name (never a person's name), as described in the privacy policy.

Tenra Pro features can be tried with a sandbox purchase on the paywall: Settings, the
"Get Tenra Pro" button at the top.
```
