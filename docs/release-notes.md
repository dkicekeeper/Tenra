# Tenra 1.8: What's New (ASC, 13 storefront locales and en-GB)

Version 1.8, drafted 2026-11-03. 1.7.1 was never submitted: by the owner's decision (2026-11-03)
its changes go out with 1.8 (the 1.7.1 notes are in this file's history). `prepare-version`
(Actions → App Store Connect, [asc.md](asc.md)) pastes each block into App Store Connect → Tenra →
1.8 → the locale → "What's New in This Version"; en-GB (search in Kazakhstan) carries ru's text
in its own block. No em dashes (user rule). Names of screens as the app shows them in each locale
(`tab.analytics`, `insights.netWorth.title`, `settings.siri.header`, `bankSetup.title`). No bank
or listing-site names in store texts (App Review 2.3.7). When 1.8 ships, move this file to
`archive/release-notes-1.8.md`.

New since 1.7 (in the store since 2026-10-24):
- Assets and net worth ([domains/assets.md](domains/assets.md),
  [plan-assets-roadmap.md](plan-assets-roadmap.md)): homes, land, cars and other things with
  their value, growth, rent and upkeep, depreciation with the value in three years, the sale's
  money, the loan's asset; net worth in Analytics; Ten sees assets and drafts them. Adding
  assets is Pro.
- The estimate from listings: Pro only, 10 a month (the server's `POST /v1/valuation`, on since
  2026-11-03).
- Charts on DesignKit 8.4 (the current period in the middle, the options menu), a category's
  months with its budget, the "By day" insight for a year, merchants that join a brand's points
  ([plan-charts-by-day.md](archive/plans/plan-charts-by-day.md)).
- From 1.7.1: bank notification capture announced (iOS 27, in the app since 1.7), goals follow
  rates and the day, debts' repayment above what is left asks, Ten's drafts checked again at
  Save, the permission texts name Ten, quicker deposit and loan edits.

## en-US

```
What's new in Tenra 1.8:
• Assets: add your flat, house, land or car and see what it is worth today, how much it has grown since you bought it, what the rent brings in and the upkeep costs. A car can lose value by a rule you set, with what it will be worth in three years, and Ten reminds you when a valuation gets old. After a sale, Tenra offers to record the money in an account. Net Worth in Analytics adds it all up: your money, assets and what you are owed, minus loans and debts. Adding assets is part of Tenra Pro.
• With Tenra Pro, Ten estimates an asset from listings of similar ones for sale: the middle of their asking prices, the range and the listings themselves, up to 10 times a month.
• On iOS 27, your bank's notifications log themselves: card and QR payments, online purchases, transfers and money coming in, from any bank, without a single question. A transfer between your own cards in two banks becomes one transfer. Set it up once in Settings › Siri & Shortcuts › Set up bank notifications. The text never leaves your iPhone.
• Charts open on the current period in the middle of the screen. A new menu next to the zoom adds the forecast, the same period a year ago, the average line and the highs and lows, or lets the chart scroll under a ruler; your choice applies to every chart.
• Each category now has a chart by month, with its budget as a line: months over it turn orange.
• New insight, By day: on which days of the week you spend the most and on what, every day of the past year on a calendar, and what stands out, like weekends or the start of the month.
• A merchant can combine the points of one brand, like the same shop in two malls: one screen with every payment, the chart and a filter by point. Payments you entered by hand can be linked to a merchant too.
• Goals keep up with exchange rates and the calendar: what is left, the monthly amount and the overdue mark update on their own, and a goal your account carried past the target remembers the day it got there.
• Debts: a repayment above what is left asks whether to record all of it or only the rest, a due date can't come before the day you lent or borrowed, and Ten checks its draft once more when you save it.
```

## ru

```
Что нового в Tenra 1.8:
• Активы: добавьте квартиру, дом, участок или машину и смотрите, сколько они стоят сегодня, насколько выросли с покупки, сколько приносит аренда и стоит содержание. Машина может дешеветь по вашему правилу, и видно, сколько она будет стоить через три года, а Тэн напомнит, когда оценка устарела. После продажи Tenra предложит записать деньги на счёт. «Чистый капитал» в «Аналитике» складывает всё: деньги, активы и долги вам минус кредиты и ваши долги. Добавление активов входит в Tenra Pro.
• С Tenra Pro Тэн оценит актив по объявлениям о продаже похожих: середина цен, диапазон и сами объявления, до 10 раз в месяц.
• На iOS 27 уведомления банка записываются сами: оплаты картой и по QR, покупки в интернете, переводы и поступления от любого банка, без единого вопроса. Перевод между своими картами в двух банках станет одним переводом. Один раз настройте в Настройках › Siri и команды › Настроить уведомления банка. Текст уведомлений не покидает iPhone.
• Графики открываются на текущем периоде посередине экрана. Новое меню рядом с лупами добавляет прогноз, тот же период год назад, линию среднего, максимум и минимум или прокрутку под линейкой, и выбор действует на всех графиках.
• У каждой категории появился график по месяцам с бюджетом в виде линии: месяцы выше него окрашиваются оранжевым.
• Новый инсайт «По дням»: в какие дни недели вы тратите больше всего и на что, каждый день последнего года в календаре и закономерности, например выходные или начало месяца.
• Точки одного бренда, например один магазин в двух торговых центрах, можно объединить в одного продавца: один экран со всеми платежами, графиком и фильтром по точке. К продавцу можно привязать и платежи, внесённые вручную.
• Цели следят за курсом и календарём: остаток, сумма в месяц и отметка о просрочке обновляются сами, а цель, которую счёт довёл до нужной суммы, запоминает день, когда она достигнута.
• Долги: если возврат больше остатка, Tenra спросит, записать всю сумму или только остаток; срок нельзя поставить раньше дня, когда вы дали или взяли в долг, а Тэн ещё раз проверяет свой черновик, когда вы его сохраняете.
```

## en-GB

```
Что нового в Tenra 1.8:
• Активы: добавьте квартиру, дом, участок или машину и смотрите, сколько они стоят сегодня, насколько выросли с покупки, сколько приносит аренда и стоит содержание. Машина может дешеветь по вашему правилу, и видно, сколько она будет стоить через три года, а Тэн напомнит, когда оценка устарела. После продажи Tenra предложит записать деньги на счёт. «Чистый капитал» в «Аналитике» складывает всё: деньги, активы и долги вам минус кредиты и ваши долги. Добавление активов входит в Tenra Pro.
• С Tenra Pro Тэн оценит актив по объявлениям о продаже похожих: середина цен, диапазон и сами объявления, до 10 раз в месяц.
• На iOS 27 уведомления банка записываются сами: оплаты картой и по QR, покупки в интернете, переводы и поступления от любого банка, без единого вопроса. Перевод между своими картами в двух банках станет одним переводом. Один раз настройте в Настройках › Siri и команды › Настроить уведомления банка. Текст уведомлений не покидает iPhone.
• Графики открываются на текущем периоде посередине экрана. Новое меню рядом с лупами добавляет прогноз, тот же период год назад, линию среднего, максимум и минимум или прокрутку под линейкой, и выбор действует на всех графиках.
• У каждой категории появился график по месяцам с бюджетом в виде линии: месяцы выше него окрашиваются оранжевым.
• Новый инсайт «По дням»: в какие дни недели вы тратите больше всего и на что, каждый день последнего года в календаре и закономерности, например выходные или начало месяца.
• Точки одного бренда, например один магазин в двух торговых центрах, можно объединить в одного продавца: один экран со всеми платежами, графиком и фильтром по точке. К продавцу можно привязать и платежи, внесённые вручную.
• Цели следят за курсом и календарём: остаток, сумма в месяц и отметка о просрочке обновляются сами, а цель, которую счёт довёл до нужной суммы, запоминает день, когда она достигнута.
• Долги: если возврат больше остатка, Tenra спросит, записать всю сумму или только остаток; срок нельзя поставить раньше дня, когда вы дали или взяли в долг, а Тэн ещё раз проверяет свой черновик, когда вы его сохраняете.
```

## de-DE

```
Neu in Tenra 1.8:
• Vermögenswerte: Fügen Sie Ihre Wohnung, Ihr Haus, Grundstück oder Auto hinzu und sehen Sie, was es heute wert ist, wie stark es seit dem Kauf gestiegen ist, was die Miete einbringt und was der Unterhalt kostet. Ein Auto kann nach einer Regel, die Sie festlegen, an Wert verlieren, samt seinem Wert in drei Jahren, und Ten erinnert Sie, wenn eine Bewertung veraltet. Nach einem Verkauf bietet Tenra an, das Geld auf einem Konto zu erfassen. Das Nettovermögen in der Analyse rechnet alles zusammen: Ihr Geld, Ihre Vermögenswerte und was man Ihnen schuldet, abzüglich Krediten und Schulden. Vermögenswerte hinzuzufügen ist Teil von Tenra Pro.
• Mit Tenra Pro schätzt Ten einen Vermögenswert anhand von Inseraten ähnlicher Angebote: die Mitte der Angebotspreise, die Spanne und die Inserate selbst, bis zu 10-mal im Monat.
• Unter iOS 27 tragen sich Ihre Bankmitteilungen selbst ein: Karten- und QR-Zahlungen, Onlinekäufe, Überweisungen und Geldeingänge jeder Bank, ohne eine einzige Frage. Eine Überweisung zwischen Ihren eigenen Karten bei zwei Banken wird zu einer Umbuchung. Richten Sie das einmal unter Einstellungen › Siri und Kurzbefehle › Bankmitteilungen einrichten ein. Der Text verlässt Ihr iPhone nie.
• Diagramme öffnen sich mit dem aktuellen Zeitraum in der Bildschirmmitte. Ein neues Menü neben dem Zoom fügt die Prognose, denselben Zeitraum vor einem Jahr, die Durchschnittslinie sowie Höchst- und Tiefstwerte hinzu oder lässt das Diagramm unter einem Lineal scrollen; Ihre Wahl gilt für alle Diagramme.
• Jede Kategorie hat jetzt ein Diagramm nach Monaten mit ihrem Budget als Linie: Monate darüber werden orange.
• Neuer Insight „Nach Tagen“: an welchen Wochentagen Sie am meisten ausgeben und wofür, jeder Tag des letzten Jahres in einem Kalender und was auffällt, etwa Wochenenden oder der Monatsanfang.
• Filialen einer Marke, etwa derselbe Laden in zwei Einkaufszentren, lassen sich zu einem Händler zusammenführen: ein Bildschirm mit allen Zahlungen, dem Diagramm und einem Filter nach Filiale. Auch von Hand erfasste Zahlungen lassen sich einem Händler zuordnen.
• Sparziele halten mit Wechselkursen und Kalender Schritt: Restbetrag, Monatsbetrag und die Markierung „überfällig“ aktualisieren sich von selbst, und ein Sparziel, das Ihr Konto erreicht hat, merkt sich den Tag.
• Schulden: Ist eine Rückzahlung höher als der Rest, fragt Tenra, ob der ganze Betrag oder nur der Rest erfasst wird, ein Fälligkeitsdatum liegt nie vor dem Tag, an dem Sie Geld verliehen oder geliehen haben, und Ten prüft seinen Entwurf beim Speichern noch einmal.
```

## es-ES

```
Novedades de Tenra 1.8:
• Activos: añade tu piso, casa, terreno o coche y mira cuánto vale hoy, cuánto ha subido desde que lo compraste, cuánto te da el alquiler y cuánto cuesta mantenerlo. Un coche puede perder valor según la regla que elijas, con lo que valdrá dentro de tres años, y Ten te avisa cuando una valoración se queda antigua. Tras una venta, Tenra te ofrece registrar el dinero en una cuenta. El patrimonio neto en Análisis lo suma todo: tu dinero, tus activos y lo que te deben, menos préstamos y deudas. Añadir activos forma parte de Tenra Pro.
• Con Tenra Pro, Ten valora un activo con anuncios de otros parecidos en venta: el precio central, el rango y los propios anuncios, hasta 10 veces al mes.
• En iOS 27, las notificaciones de tu banco se registran solas: pagos con tarjeta y con QR, compras por internet, transferencias y dinero que entra, de cualquier banco, sin una sola pregunta. Una transferencia entre tus propias tarjetas de dos bancos se convierte en una sola. Configúralo una vez en Ajustes › Siri y atajos › Configurar las notificaciones del banco. El texto nunca sale de tu iPhone.
• Los gráficos se abren en el periodo actual, en el centro de la pantalla. Un nuevo menú junto al zoom añade la previsión, el mismo periodo de hace un año, la línea de promedio y los máximos y mínimos, o hace que el gráfico se desplace bajo una regla; tu elección se aplica a todos los gráficos.
• Cada categoría tiene ahora un gráfico por meses con su presupuesto como línea: los meses que lo superan se ven en naranja.
• Nuevo análisis, Por días: qué días de la semana gastas más y en qué, cada día del último año en un calendario y lo que destaca, como los fines de semana o el inicio de mes.
• Puedes unir los puntos de venta de una marca, como la misma tienda en dos centros comerciales, en un solo comercio: una pantalla con todos los pagos, el gráfico y un filtro por punto. También puedes vincular a un comercio los pagos que añadiste a mano.
• Las metas siguen el tipo de cambio y el calendario: lo que falta, el importe mensual y el aviso de retraso se actualizan solos, y una meta que tu cuenta alcanzó recuerda el día en que lo hizo.
• Deudas: si un pago supera lo que falta, Tenra pregunta si registrar todo o solo lo que falta, la fecha de vencimiento no puede ser anterior al día del préstamo y Ten vuelve a comprobar su borrador al guardarlo.
```

## es-MX

```
Novedades de Tenra 1.8:
• Activos: agrega tu departamento, casa, terreno o auto y mira cuánto vale hoy, cuánto ha subido desde que lo compraste, cuánto te deja la renta y cuánto cuesta mantenerlo. Un auto puede perder valor según la regla que elijas, con lo que valdrá en tres años, y Ten te avisa cuando una valuación ya es vieja. Después de una venta, Tenra te ofrece registrar el dinero en una cuenta. El patrimonio neto en Análisis lo suma todo: tu dinero, tus activos y lo que te deben, menos préstamos y deudas. Agregar activos es parte de Tenra Pro.
• Con Tenra Pro, Ten valúa un activo con anuncios de otros parecidos en venta: el precio central, el rango y los anuncios mismos, hasta 10 veces al mes.
• En iOS 27, las notificaciones de tu banco se registran solas: pagos con tarjeta y con QR, compras en línea, transferencias y dinero que entra, de cualquier banco, sin una sola pregunta. Una transferencia entre tus propias tarjetas de dos bancos se convierte en una sola. Configúralo una vez en Ajustes › Siri y atajos › Configurar las notificaciones del banco. El texto nunca sale de tu iPhone.
• Las gráficas se abren en el periodo actual, en el centro de la pantalla. Un nuevo menú junto al zoom agrega la previsión, el mismo periodo de hace un año, la línea de promedio y los máximos y mínimos, o hace que la gráfica se desplace bajo una regla; tu elección se aplica a todas las gráficas.
• Cada categoría tiene ahora una gráfica por meses con su presupuesto como línea: los meses que lo superan se ven en naranja.
• Nuevo análisis, Por días: qué días de la semana gastas más y en qué, cada día del último año en un calendario y lo que destaca, como los fines de semana o el inicio de mes.
• Puedes unir los puntos de venta de una marca, como la misma tienda en dos plazas comerciales, en un solo comercio: una pantalla con todos los pagos, la gráfica y un filtro por punto. También puedes vincular a un comercio los pagos que agregaste a mano.
• Las metas siguen el tipo de cambio y el calendario: lo que falta, el monto mensual y el aviso de retraso se actualizan solos, y una meta que tu cuenta alcanzó recuerda el día en que lo hizo.
• Deudas: si un pago supera lo que falta, Tenra pregunta si registrar todo o solo lo que falta, la fecha de vencimiento no puede ser anterior al día del préstamo y Ten vuelve a revisar su borrador al guardarlo.
```

## fr-FR

```
Nouveautés de Tenra 1.8 :
• Actifs : ajoutez votre appartement, maison, terrain ou voiture et voyez ce qu'il vaut aujourd'hui, de combien il a pris de la valeur depuis l'achat, ce que rapporte le loyer et ce que coûte l'entretien. Une voiture peut perdre de la valeur selon une règle que vous fixez, avec ce qu'elle vaudra dans trois ans, et Ten vous prévient quand une estimation devient ancienne. Après une vente, Tenra propose d'enregistrer l'argent sur un compte. Le patrimoine net dans Analyse additionne tout : votre argent, vos actifs et ce qu'on vous doit, moins les prêts et les dettes. Ajouter des actifs fait partie de Tenra Pro.
• Avec Tenra Pro, Ten estime un actif d'après les annonces de biens semblables à vendre : le prix médian, la fourchette et les annonces elles-mêmes, jusqu'à 10 fois par mois.
• Sous iOS 27, les notifications de votre banque s'enregistrent toutes seules : paiements par carte et par QR, achats en ligne, virements et argent reçu, quelle que soit la banque, sans une seule question. Un virement entre vos propres cartes dans deux banques devient un seul virement. Configurez-le une fois dans Réglages › Siri et raccourcis › Configurer les notifications bancaires. Le texte ne quitte jamais votre iPhone.
• Les graphiques s'ouvrent sur la période en cours, au milieu de l'écran. Un nouveau menu à côté du zoom ajoute la prévision, la même période il y a un an, la ligne de moyenne et les plus hauts et plus bas, ou fait défiler le graphique sous une règle ; votre choix s'applique à tous les graphiques.
• Chaque catégorie a désormais un graphique par mois, avec son budget en ligne : les mois au-dessus passent en orange.
• Nouvel aperçu, Par jour : les jours de la semaine où vous dépensez le plus et pour quoi, chaque jour de la dernière année dans un calendrier, et ce qui ressort, comme les week-ends ou le début du mois.
• Les points de vente d'une même enseigne, comme une boutique dans deux centres commerciaux, se regroupent en un seul commerçant : un écran avec tous les paiements, le graphique et un filtre par point de vente. Les paiements saisis à la main peuvent aussi être associés à un commerçant.
• Les objectifs suivent les taux de change et le calendrier : le reste, le montant mensuel et la mention « en retard » se mettent à jour seuls, et un objectif atteint grâce à votre compte retient le jour où il l'a été.
• Dettes : si un remboursement dépasse ce qui reste, Tenra demande s'il faut tout enregistrer ou seulement le reste, une échéance ne peut pas précéder le jour du prêt, et Ten vérifie à nouveau son brouillon quand vous l'enregistrez.
```

## fr-CA

```
Nouveautés de Tenra 1.8 :
• Actifs : ajoutez votre condo, maison, terrain ou auto et voyez ce qu'il vaut aujourd'hui, de combien il a pris de la valeur depuis l'achat, ce que rapporte le loyer et ce que coûte l'entretien. Une auto peut perdre de la valeur selon une règle que vous fixez, avec ce qu'elle vaudra dans trois ans, et Ten vous avertit quand une évaluation devient ancienne. Après une vente, Tenra propose d'enregistrer l'argent dans un compte. Le patrimoine net dans Analyse additionne tout : votre argent, vos actifs et ce qu'on vous doit, moins les prêts et les dettes. Ajouter des actifs fait partie de Tenra Pro.
• Avec Tenra Pro, Ten évalue un actif d'après les annonces de biens semblables à vendre : le prix médian, la fourchette et les annonces elles-mêmes, jusqu'à 10 fois par mois.
• Sous iOS 27, les notifications de votre banque s'enregistrent toutes seules : paiements par carte et par QR, achats en ligne, virements et argent reçu, quelle que soit la banque, sans une seule question. Un virement entre vos propres cartes dans deux banques devient un seul virement. Configurez-le une fois dans Réglages › Siri et raccourcis › Configurer les notifications bancaires. Le texte ne quitte jamais votre iPhone.
• Les graphiques s'ouvrent sur la période en cours, au milieu de l'écran. Un nouveau menu à côté du zoom ajoute la prévision, la même période il y a un an, la ligne de moyenne et les plus hauts et plus bas, ou fait défiler le graphique sous une règle ; votre choix s'applique à tous les graphiques.
• Chaque catégorie a maintenant un graphique par mois, avec son budget en ligne : les mois au-dessus passent en orange.
• Nouvel aperçu, Par jour : les jours de la semaine où vous dépensez le plus et pour quoi, chaque jour de la dernière année dans un calendrier, et ce qui ressort, comme les fins de semaine ou le début du mois.
• Les points de vente d'une même enseigne, comme une boutique dans deux centres commerciaux, se regroupent en un seul commerçant : un écran avec tous les paiements, le graphique et un filtre par point de vente. Les paiements saisis à la main peuvent aussi être associés à un commerçant.
• Les objectifs suivent les taux de change et le calendrier : le reste, le montant mensuel et la mention « en retard » se mettent à jour seuls, et un objectif atteint grâce à votre compte retient le jour où il l'a été.
• Dettes : si un remboursement dépasse ce qui reste, Tenra demande s'il faut tout enregistrer ou seulement le reste, une échéance ne peut pas précéder le jour du prêt, et Ten vérifie à nouveau son brouillon quand vous l'enregistrez.
```

## tr

```
Tenra 1.8'deki yenilikler:
• Varlıklar: daireni, evini, arsanı ya da arabanı ekle; bugün ne ettiğini, aldığından beri ne kadar değerlendiğini, kiranın ne getirdiğini ve bakımının neye mal olduğunu gör. Araba belirlediğin bir kurala göre değer kaybedebilir ve üç yıl sonra ne edeceği görünür; bir değerleme eskiyince Ten hatırlatır. Satıştan sonra Tenra parayı bir hesaba kaydetmeyi önerir. Analiz'deki Net varlık hepsini toplar: paran, varlıkların ve sana olan borçlar, eksi krediler ve borçların. Varlık eklemek Tenra Pro'nun bir parçası.
• Tenra Pro ile Ten, bir varlığı satıştaki benzerlerinin ilanlarından değerler: ortadaki fiyat, aralık ve ilanların kendisi, ayda 10 defaya kadar.
• iOS 27'de bankanın bildirimleri kendiliğinden kaydedilir: kartla ve QR ile ödemeler, internet alışverişleri, havaleler ve gelen paralar, hangi banka olursa olsun, tek bir soru sormadan. İki bankadaki kendi kartların arasındaki bir havale tek bir transfer olur. Ayarlar › Siri ve kısayollar › Banka bildirimlerini kur bölümünden bir kez kur. Bildirim metni iPhone'undan hiç çıkmaz.
• Grafikler mevcut dönemi ekranın ortasında açıyor. Yakınlaştırmanın yanındaki yeni menü tahmini, bir yıl önceki aynı dönemi, ortalama çizgisini, en yüksek ve en düşük değerleri ekliyor ya da grafiğin bir cetvelin altında kaymasını sağlıyor; seçiminiz tüm grafiklere uygulanır.
• Her kategorinin artık aylık bir grafiği var, bütçesi bir çizgi olarak gösteriliyor: bütçeyi aşan aylar turuncu olur.
• Yeni içgörü, Günlere göre: haftanın hangi günlerinde neye en çok harcadığınız, son bir yılın her günü bir takvimde ve öne çıkanlar, örneğin hafta sonları ya da ay başı.
• Bir markanın şubeleri, örneğin iki alışveriş merkezindeki aynı mağaza, tek bir işyerinde birleştirilebilir: tüm ödemeler, grafik ve şubeye göre filtre tek ekranda. Elle girdiğiniz ödemeler de bir işyerine bağlanabilir.
• Hedefler döviz kurlarına ve takvime ayak uydurur: kalan tutar, aylık tutar ve gecikme işareti kendiliğinden güncellenir; hesabının hedefe ulaştırdığı bir hedef, ulaşıldığı günü hatırlar.
• Borçlar: geri ödeme kalan tutarı aşarsa Tenra tamamını mı yoksa yalnızca kalanı mı kaydedeceğini sorar, vade tarihi borcun verildiği ya da alındığı günden önce olamaz ve Ten taslağını kaydederken bir kez daha kontrol eder.
```

## pt-BR

```
Novidades do Tenra 1.8:
• Bens: adicione seu apartamento, casa, terreno ou carro e veja quanto vale hoje, quanto valorizou desde a compra, quanto rende o aluguel e quanto custa a manutenção. Um carro pode perder valor por uma regra que você define, com quanto vai valer em três anos, e o Ten avisa quando uma avaliação fica antiga. Depois de uma venda, o Tenra oferece registrar o dinheiro em uma conta. O Patrimônio líquido em Análises soma tudo: seu dinheiro, seus bens e o que devem a você, menos empréstimos e dívidas. Adicionar bens faz parte do Tenra Pro.
• Com o Tenra Pro, o Ten avalia um bem pelos anúncios de outros parecidos à venda: o preço do meio, a faixa e os próprios anúncios, até 10 vezes por mês.
• No iOS 27, as notificações do seu banco se registram sozinhas: pagamentos no cartão e por QR, compras on-line, transferências e dinheiro que entra, de qualquer banco, sem uma única pergunta. Uma transferência entre seus próprios cartões em dois bancos vira uma só. Configure uma vez em Ajustes › Siri e atalhos › Configurar notificações do banco. O texto nunca sai do seu iPhone.
• Os gráficos abrem no período atual, no meio da tela. Um novo menu ao lado do zoom adiciona a previsão, o mesmo período há um ano, a linha da média e os máximos e mínimos, ou faz o gráfico rolar sob uma régua; sua escolha vale para todos os gráficos.
• Cada categoria agora tem um gráfico por mês com o orçamento como linha: os meses acima dele ficam laranja.
• Novo insight, Por dia: em quais dias da semana você gasta mais e com o quê, cada dia do último ano em um calendário e o que se destaca, como os fins de semana ou o início do mês.
• As unidades de uma marca, como a mesma loja em dois shoppings, podem virar um só estabelecimento: uma tela com todos os pagamentos, o gráfico e um filtro por unidade. Pagamentos lançados à mão também podem ser vinculados a um estabelecimento.
• As metas acompanham o câmbio e o calendário: o que falta, o valor mensal e o aviso de atraso se atualizam sozinhos, e uma meta que sua conta alcançou lembra o dia em que isso aconteceu.
• Dívidas: se um pagamento passar do que falta, o Tenra pergunta se registra tudo ou só o que falta, o vencimento não pode ser antes do dia do empréstimo e o Ten confere o rascunho de novo quando você salva.
```

## it

```
Novità di Tenra 1.8:
• Beni: aggiungi il tuo appartamento, la casa, un terreno o l'auto e vedi quanto vale oggi, quanto è cresciuto dall'acquisto, quanto rende l'affitto e quanto costa la manutenzione. Un'auto può perdere valore secondo una regola che scegli tu, con quanto varrà tra tre anni, e Ten ti avvisa quando una stima diventa vecchia. Dopo una vendita, Tenra ti propone di registrare il denaro su un conto. Il Patrimonio netto in Analisi somma tutto: i tuoi soldi, i tuoi beni e quello che ti devono, meno prestiti e debiti. Aggiungere beni fa parte di Tenra Pro.
• Con Tenra Pro, Ten stima un bene dagli annunci di altri simili in vendita: il prezzo centrale, la forbice e gli annunci stessi, fino a 10 volte al mese.
• Su iOS 27 le notifiche della tua banca si registrano da sole: pagamenti con carta e con QR, acquisti online, bonifici e soldi in entrata, da qualsiasi banca, senza una sola domanda. Un bonifico tra le tue carte in due banche diventa un unico trasferimento. Configuralo una volta in Impostazioni › Siri e comandi rapidi › Configura le notifiche della banca. Il testo non lascia mai il tuo iPhone.
• I grafici si aprono sul periodo in corso, al centro dello schermo. Un nuovo menu accanto allo zoom aggiunge la previsione, lo stesso periodo di un anno fa, la linea della media e i massimi e minimi, oppure fa scorrere il grafico sotto un righello; la scelta vale per tutti i grafici.
• Ogni categoria ha ora un grafico per mese con il suo budget come linea: i mesi oltre il budget diventano arancioni.
• Nuovo insight, Per giorno: in quali giorni della settimana spendi di più e per cosa, ogni giorno dell'ultimo anno in un calendario e cosa spicca, come i fine settimana o l'inizio del mese.
• I punti vendita di un marchio, come lo stesso negozio in due centri commerciali, si possono unire in un solo esercente: una schermata con tutti i pagamenti, il grafico e un filtro per punto vendita. Anche i pagamenti inseriti a mano si possono collegare a un esercente.
• Gli obiettivi seguono i cambi e il calendario: quanto manca, la cifra mensile e il segno di ritardo si aggiornano da soli, e un obiettivo che il tuo conto ha raggiunto ricorda il giorno in cui è successo.
• Debiti: se un rimborso supera quanto resta, Tenra chiede se registrare tutto o solo quanto resta, la scadenza non può essere prima del giorno del prestito e Ten ricontrolla la sua bozza quando la salvi.
```

## uk

```
Що нового в Tenra 1.8:
• Активи: додайте квартиру, будинок, ділянку чи автомобіль і дивіться, скільки вони коштують сьогодні, наскільки подорожчали з купівлі, скільки приносить оренда і скільки коштує утримання. Автомобіль може дешевшати за вашим правилом, і видно, скільки він коштуватиме через три роки, а Тен нагадає, коли оцінка застаріла. Після продажу Tenra запропонує записати гроші на рахунок. «Чистий капітал» в «Аналітиці» складає все: гроші, активи й борги вам мінус кредити та ваші борги. Додавання активів входить у Tenra Pro.
• З Tenra Pro Тен оцінить актив за оголошеннями про продаж схожих: середина цін, діапазон і самі оголошення, до 10 разів на місяць.
• На iOS 27 сповіщення банку записуються самі: оплати карткою і за QR, покупки в інтернеті, перекази та надходження від будь-якого банку, без жодного питання. Переказ між власними картками у двох банках стане одним переказом. Один раз налаштуйте в Налаштуваннях › Siri та команди › Налаштувати сповіщення банку. Текст сповіщень не залишає iPhone.
• Графіки відкриваються на поточному періоді посередині екрана. Нове меню поруч із лупами додає прогноз, той самий період рік тому, лінію середнього, максимум і мінімум або прокручування під лінійкою, і вибір діє на всіх графіках.
• Кожна категорія має графік за місяцями із бюджетом у вигляді лінії: місяці понад нього стають помаранчевими.
• Новий інсайт «За днями»: у які дні тижня ви витрачаєте найбільше і на що, кожен день останнього року в календарі та закономірності, наприклад вихідні чи початок місяця.
• Точки одного бренду, наприклад той самий магазин у двох торгових центрах, можна об'єднати в одного продавця: один екран з усіма платежами, графіком і фільтром за точкою. До продавця можна прив'язати й платежі, внесені вручну.
• Цілі стежать за курсом і календарем: залишок, сума на місяць і позначка про прострочення оновлюються самі, а ціль, яку рахунок довів до потрібної суми, запам'ятовує день, коли її досягнуто.
• Борги: якщо повернення більше за залишок, Tenra спитає, записати всю суму чи лише залишок; строк не можна поставити раніше дня, коли ви дали або взяли в борг, а Тен ще раз перевіряє свою чернетку, коли ви її зберігаєте.
```

## ja

```
Tenra 1.8 の新機能:
• 資産: マンション、家、土地、車を追加すると、今の価値、購入時からの値上がり、家賃収入と維持費がわかります。車は設定したルールで価値が下がり、3 年後の価値も表示されます。評価が古くなるとテンがお知らせします。売却後は、代金を口座に記録するよう Tenra が提案します。分析 の 純資産 では、お金、資産、貸しているお金から、ローンと借りているお金を引いたすべてを合計します。資産の追加は Tenra Pro の機能です。
• Tenra Pro では、テンが売りに出ている似たものの掲載から資産を評価します。中央の価格、価格帯、掲載そのものを、月 10 回まで。
• iOS 27 では、銀行の通知が自動で記録されます。カードや QR での支払い、オンラインでの買い物、振込、入金を、どの銀行でも質問なしで記録します。2 つの銀行にある自分のカード間の振込は 1 件の振替になります。設定 › Siri とショートカット › 銀行の通知を設定 で一度設定するだけです。通知の文面が iPhone の外に出ることはありません。
• グラフは現在の期間を画面中央にして開きます。ズームの横の新しいメニューで、予測、1年前の同じ期間、平均線、最高・最低を追加したり、ルーラーの下でスクロールしたりできます。選択はすべてのグラフに適用されます。
• 各カテゴリに月別のグラフが加わり、予算が線で表示されます。予算を超えた月はオレンジになります。
• 新しいインサイト「曜日別」：どの曜日に何に最も多く使っているか、直近1年間の毎日をカレンダーで、週末や月初など目立つ傾向も表示します。
• 同じブランドの店舗（2つのショッピングモールにある同じ店など）をひとつにまとめられます。すべての支払い、グラフ、店舗ごとの絞り込みをひとつの画面で確認できます。手動で入力した支払いも店舗に紐づけられます。
• 貯金目標が為替レートと日付に合わせて更新されます。残り、毎月の金額、期限切れの表示が自動で変わり、口座の残高で達成した目標は達成した日を覚えています。
• 貸し借り: 返済額が残りを超えると、全額を記録するか残りだけにするかを確認します。期日を貸し借りした日より前にはできません。テンは下書きを保存するときにもう一度確認します。
```

## ko

```
Tenra 1.8의 새로운 기능:
• 자산: 아파트, 주택, 토지, 자동차를 추가하면 지금 가치, 산 뒤로 얼마나 올랐는지, 임대 수입과 유지비를 볼 수 있어요. 자동차는 정한 규칙에 따라 가치가 줄고, 3년 뒤 가치도 보여요. 평가가 오래되면 텐이 알려 줘요. 판매한 뒤에는 Tenra가 그 돈을 계좌에 기록하자고 제안해요. 분석의 순자산은 돈, 자산, 받을 돈에서 대출과 갚을 돈을 빼서 모두 더해요. 자산 추가는 Tenra Pro 기능이에요.
• Tenra Pro에서는 텐이 판매 중인 비슷한 매물로 자산을 평가해요. 중간 가격, 범위, 매물 자체를 한 달에 10번까지 볼 수 있어요.
• iOS 27에서는 은행 알림이 저절로 기록돼요. 카드·QR 결제, 온라인 구매, 송금, 입금을 어느 은행이든 아무것도 묻지 않고 기록해요. 두 은행에 있는 내 카드끼리의 송금은 한 건의 이체가 돼요. 설정 › Siri 및 단축어 › 은행 알림 설정에서 한 번만 설정하세요. 알림 내용은 iPhone 밖으로 나가지 않아요.
• 차트가 현재 기간을 화면 가운데에 두고 열립니다. 확대 옆의 새 메뉴에서 예측, 1년 전 같은 기간, 평균선과 최고·최저를 추가하거나 눈금자 아래로 차트를 스크롤할 수 있으며, 선택은 모든 차트에 적용됩니다.
• 각 카테고리에 예산을 선으로 표시한 월별 차트가 생겼습니다. 예산을 넘은 달은 주황색으로 표시됩니다.
• 새 인사이트 '요일별': 어느 요일에 무엇에 가장 많이 쓰는지, 최근 1년의 매일을 달력으로, 주말이나 월초처럼 눈에 띄는 패턴을 보여줍니다.
• 같은 브랜드의 지점(두 쇼핑몰에 있는 같은 매장 등)을 하나의 가맹점으로 합칠 수 있습니다. 모든 결제, 차트, 지점별 필터를 한 화면에서 볼 수 있습니다. 직접 입력한 결제도 가맹점에 연결할 수 있습니다.
• 저축 목표가 환율과 날짜에 맞춰 업데이트돼요. 남은 금액, 매달 모을 금액, 기한 지남 표시가 저절로 바뀌고, 계좌 잔액으로 달성한 목표는 달성한 날을 기억해요.
• 빌린 돈: 상환 금액이 남은 금액보다 많으면 전부 기록할지 남은 금액만 기록할지 물어봐요. 기한은 빌려주거나 빌린 날보다 앞설 수 없어요. 텐은 초안을 저장할 때 한 번 더 확인해요.
```

## Submission checklist (1.8)

1. **CI green** on the branch, then a TestFlight build from `main` (Actions → TestFlight,
   [asc.md](asc.md)).
2. **Device check**: builds 66-69 checked by the founder (2026-11-03: everything is fine). The
   store build adds the Pro gate of the estimate: without Pro, the asset menu's "Estimate from
   listings" opens the paywall; with Pro, it finds listings (the server is on).
3. **The store build**: `prepare-version --version 1.8 --build N` (the build of step 1).
4. **What's New**: this file (`prepare-version`), en-GB included.
5. **Screenshots**: unchanged from 1.7 (a new version takes the previous version's screenshots);
   an assets screenshot is roadmap item 1.3, later.
6. **App Privacy**: the label lists what Ten sends (since 1.6). An estimate also sends an asset's
   characteristics (Other User Content, app functionality, not linked to the user): check the
   label covers it before sending. The privacy policy says so since 2026-11-03.
7. **App Review notes**, in English, set from this block by
   `asc.py review-notes --version 1.8 --apply`:

```
Bank notification capture (announced in 1.8) uses the Shortcuts personal automation "When I get a notification from an app" (iOS 27), which runs the Tenra action "Log a bank notification" with the notification's Title, Subtitle, Text, App and Date. To try it without a bank app: open Shortcuts, create a new shortcut, add the Tenra action "Log a bank notification", set Text to "Card ending 4321 was charged $25.00 at COFFEE SHOP" and App to "My Bank", and run it. The expense appears in Tenra at once and waits in Settings > Wallet > To review. Settings > Siri & Shortcuts > Set up bank notifications has the step-by-step guide and "Check a notification", which shows what Tenra reads from a pasted notification without saving anything. The notification's text never leaves the device.

Apple Pay capture uses the Shortcuts "Wallet" personal automation, which fires only on a real contactless payment. To try it without one: create a shortcut with the Tenra action "Log an Apple Pay payment", fill in an amount (e.g. 1500) and a merchant (e.g. "Coffee Boom") and run it. The step-by-step setup guide is in Settings > Siri & Shortcuts.

Tenra Pro features can be tried with a sandbox purchase on the paywall: Settings, the "Get Tenra Pro" button at the top.

Assets (Finances > Assets) are a Tenra Pro feature: adding one opens the paywall without Pro. The estimate from listings (an asset's screen, the menu, "Estimate from listings") is Pro only, 10 a month: it sends the asset's kind and the characteristics filled in its form (city, district, area, rooms, year; for a car make, model, year, mileage) to Tenra's server, where Claude searches the web for similar listings and returns the middle asking price, the range and the listings with links. No name, address number, VIN or plate is sent. To try it: buy Pro in the sandbox, add a car (Toyota Camry, 2019, 110000 km, Almaty, Kazakhstan), open it and choose Estimate from listings.
```

8. **RevenueCat paywall**: the item "Assets and net worth" (and the estimate from listings) in the
   paywall's list, 12 locales, in the RevenueCat dashboard (roadmap 0.2; not in the API).
9. **One submission**: `asc.py prepare-review --version 1.8` puts the version into a draft review
   submission, never submitted; the founder sends it: App Store Connect → Tenra → Distribution →
   the draft submission → Submit for Review.
