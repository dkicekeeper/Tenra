# Charts on DesignKit 8.3.0 and the "By day" insight

Status (2026-10-30): in `main`, on DesignKit 8.3 (dkicekeeper/DesignKit#91), version 1.8,
together with the assets (PR #105, #109, #110), "на сегодня" in Russian (#107) and the options off
by default (#108). TestFlight: 1.8 build 62 (2026-10-30) has all of it; the owner's check on the
phone found the 15 points of "After the device check" below, fixed in #113 with DesignKit 8.4.0
(dkicekeeper/DesignKit#95), both in `main` since 2026-10-30; 1.8 build 63 (2026-10-30) has them
and waits on the owner's check on the phone. The What's New below
goes into 1.8's `release-notes.md` once 1.7.1's notes move to the archive; then this file moves to
`archive/plans/`.

## What it does

- DesignKit 8.3.0's charts: the current period selected in the middle of the window, marked as
  not over ("so far"); the banner names the series and gives the change from the period before
  (green the better way); a long press and a drag sum up a stretch; the axis always labels its
  periods
  ([domains/charts.md](domains/charts.md)).
- The chart options menu by every chart's zoom (`ChartOptionsHost`): the spending forecast, the
  same period a year ago, the average line, highs and lows, a ruler the chart scrolls under, kept
  for every chart; all off until the person turns one on.
- The category screen: its months as bars with a monthly budget as a line, and from the
  menu the same month a year ago and this month's forecast (`CategoryDetailView.monthlyChart`). The
  merchant screen's and Ten's charts mark this month as not over.
- The "By day" insight in Spending (`spending_by_day`, [domains/insights.md](domains/insights.md)).

## After the device check (2026-10-30)

The owner's list from build 62, each point and what changed:

1. Points of one brand ("ZARA MEGA", "ZARA DOSTYK PLAZA") merge into one merchant
   (`MerchantGroupStore`, "Combine points" in the merchant's menu, `MerchantMergeView`); its
   screen counts every point and filters by point with chips under the hero; Insights' top
   merchant counts the brand ([domains/intents.md](domains/intents.md) §6.1).
2. Payments entered by hand link to a merchant ("Link payments", `LinkPaymentsView` with
   `.merchant`); a link glyph on the row unlinks one.
3. The merchant's chart opens on this month in the middle: two years of months, the category
   screen's rules (`CategoryMonthHistory`: a year ago, the forecast).
4. The merchant's edit sheet: the category and subcategory carousels without headers.
5. The X axis (DesignKit 8.4.0): no label runs into another, nothing under the empty months
   after the current one; the merchant's and the category's charts follow the same rules.
6. The ruler option: the period under the ruler drawn as a finger selects it (DesignKit 8.4.0).
7. The calendar's ring is not cut at the edges (DesignKit 8.4.0).
8. "By day" reads the last 52 weeks.
9. The orb's slice names on two lines (DesignKit 8.4.0, net worth's accounts).
10. Net worth's bar named its parts by their raw keys ("insights.formula.netWorth.row.money"):
    an interpolated `String.LocalizationValue` looked up `row.%@`.
11. The period records: a chart that scrolls (`ChartSwitcher`, bars, highs and lows always on)
    in place of the hero of the whole history.
12. Every chart of Insights and Analytics is DesignKit's (no `import Charts` in Tenra); the
    merchant's was the one behind the category's.
13. Monthly recurring (and net worth): no tone colour behind a hero in colours of its own.
14. An asset's rent and upkeep take several subcategories (`AssetCategoryLink.subcategoryIds`).
15. On the assets' coloured hero the selected value is in the text's colour (DesignKit 8.4.0).

Device check on build 63: the points above on the phone, in light and dark. The owner's
second look (2026-10-31) found four more, fixed for the next build:

1. The keyboard hides on a tap off a text field, everywhere (`KeyboardDismissal`,
   [design-system.md](design-system.md) §5 "The keyboard").
2. The ruler option: 8.4.0 drew the selection over the plot at the ruler, so it rode with the
   ruler, off the line and the bar; DesignKit 8.4.1 selects the period on the chart once the
   scroll rests.
3. "Combine points" finds a merchant by the name the person gave it and by its brand's name, and
   keeps the ones picked on top.
4. Its rows are the Wallet merchants list's (`UniversalRow`, `SelectionIndicator`): the form
   row with a hint under the title was too tall.

## Device check

In light and dark, Russian and English: the charts on Analytics (the current period in the
middle, "so far", in Russian «на сегодня»; the options menu with everything off until it is
changed, then the forecast, a year ago and a ruler the chart scrolls under turned on), a
category's months with its budget line, and "By day" (the feed card's bars, the calendar, the
weekday chart opening on the busiest day and its categories, what stands out). Everything off is
from build 62 (the owner's call, 2026-10-30); build 60 opened with the forecast and a year ago on.

## What's New (draft, 13 storefront locales)

No em dashes. en-GB takes ru's text, as in [release-notes.md](release-notes.md).

### en-US

```
What's new in Tenra <version>:
• Charts open on the current period in the middle of the screen. A new menu next to the zoom adds the forecast, the same period a year ago, the average line and the highs and lows, or lets the chart scroll under a ruler; your choice applies to every chart.
• Each category now has a chart by month, with its budget as a line: months over it turn orange.
• New insight, By day: on which days of the week you spend the most and on what, every day of the past year on a calendar, and what stands out, like weekends or the start of the month.
• A merchant can combine the points of one brand, like the same shop in two malls: one screen with every payment, the chart and a filter by point. Payments you entered by hand can be linked to a merchant too.
```

### ru

```
Что нового в Tenra <version>:
• Графики открываются на текущем периоде посередине экрана. Новое меню рядом с лупами добавляет прогноз, тот же период год назад, линию среднего, максимум и минимум или прокрутку под линейкой, и выбор действует на всех графиках.
• У каждой категории появился график по месяцам с бюджетом в виде линии: месяцы выше него окрашиваются оранжевым.
• Новый инсайт «По дням»: в какие дни недели вы тратите больше всего и на что, каждый день последнего года в календаре и закономерности, например выходные или начало месяца.
• Точки одного бренда, например один магазин в двух торговых центрах, можно объединить в одного продавца: один экран со всеми платежами, графиком и фильтром по точке. К продавцу можно привязать и платежи, внесённые вручную.
```

### de-DE

```
Neu in Tenra <version>:
• Diagramme öffnen sich mit dem aktuellen Zeitraum in der Bildschirmmitte. Ein neues Menü neben dem Zoom fügt die Prognose, denselben Zeitraum vor einem Jahr, die Durchschnittslinie sowie Höchst- und Tiefstwerte hinzu oder lässt das Diagramm unter einem Lineal scrollen; Ihre Wahl gilt für alle Diagramme.
• Jede Kategorie hat jetzt ein Diagramm nach Monaten mit ihrem Budget als Linie: Monate darüber werden orange.
• Neuer Insight „Nach Tagen“: an welchen Wochentagen Sie am meisten ausgeben und wofür, jeder Tag des letzten Jahres in einem Kalender und was auffällt, etwa Wochenenden oder der Monatsanfang.
• Filialen einer Marke, etwa derselbe Laden in zwei Einkaufszentren, lassen sich zu einem Händler zusammenführen: ein Bildschirm mit allen Zahlungen, dem Diagramm und einem Filter nach Filiale. Auch von Hand erfasste Zahlungen lassen sich einem Händler zuordnen.
```

### es-ES

```
Novedades de Tenra <version>:
• Los gráficos se abren en el periodo actual, en el centro de la pantalla. Un nuevo menú junto al zoom añade la previsión, el mismo periodo de hace un año, la línea de promedio y los máximos y mínimos, o hace que el gráfico se desplace bajo una regla; tu elección se aplica a todos los gráficos.
• Cada categoría tiene ahora un gráfico por meses con su presupuesto como línea: los meses que lo superan se ven en naranja.
• Nuevo análisis, Por días: qué días de la semana gastas más y en qué, cada día del último año en un calendario y lo que destaca, como los fines de semana o el inicio de mes.
• Puedes unir los puntos de venta de una marca, como la misma tienda en dos centros comerciales, en un solo comercio: una pantalla con todos los pagos, el gráfico y un filtro por punto. También puedes vincular a un comercio los pagos que añadiste a mano.
```

### es-MX

```
Novedades de Tenra <version>:
• Las gráficas se abren en el periodo actual, en el centro de la pantalla. Un nuevo menú junto al zoom agrega la previsión, el mismo periodo de hace un año, la línea de promedio y los máximos y mínimos, o hace que la gráfica se desplace bajo una regla; tu elección se aplica a todas las gráficas.
• Cada categoría tiene ahora una gráfica por meses con su presupuesto como línea: los meses que lo superan se ven en naranja.
• Nuevo análisis, Por días: qué días de la semana gastas más y en qué, cada día del último año en un calendario y lo que destaca, como los fines de semana o el inicio de mes.
• Puedes unir los puntos de venta de una marca, como la misma tienda en dos plazas comerciales, en un solo comercio: una pantalla con todos los pagos, la gráfica y un filtro por punto. También puedes vincular a un comercio los pagos que agregaste a mano.
```

### fr-FR

```
Nouveautés de Tenra <version> :
• Les graphiques s'ouvrent sur la période en cours, au milieu de l'écran. Un nouveau menu à côté du zoom ajoute la prévision, la même période il y a un an, la ligne de moyenne et les plus hauts et plus bas, ou fait défiler le graphique sous une règle ; votre choix s'applique à tous les graphiques.
• Chaque catégorie a désormais un graphique par mois, avec son budget en ligne : les mois au-dessus passent en orange.
• Nouvel aperçu, Par jour : les jours de la semaine où vous dépensez le plus et pour quoi, chaque jour de la dernière année dans un calendrier, et ce qui ressort, comme les week-ends ou le début du mois.
• Les points de vente d'une même enseigne, comme une boutique dans deux centres commerciaux, se regroupent en un seul commerçant : un écran avec tous les paiements, le graphique et un filtre par point de vente. Les paiements saisis à la main peuvent aussi être associés à un commerçant.
```

### fr-CA

```
Nouveautés de Tenra <version> :
• Les graphiques s'ouvrent sur la période en cours, au milieu de l'écran. Un nouveau menu à côté du zoom ajoute la prévision, la même période il y a un an, la ligne de moyenne et les plus hauts et plus bas, ou fait défiler le graphique sous une règle ; votre choix s'applique à tous les graphiques.
• Chaque catégorie a maintenant un graphique par mois, avec son budget en ligne : les mois au-dessus passent en orange.
• Nouvel aperçu, Par jour : les jours de la semaine où vous dépensez le plus et pour quoi, chaque jour de la dernière année dans un calendrier, et ce qui ressort, comme les fins de semaine ou le début du mois.
• Les points de vente d'une même enseigne, comme une boutique dans deux centres commerciaux, se regroupent en un seul commerçant : un écran avec tous les paiements, le graphique et un filtre par point de vente. Les paiements saisis à la main peuvent aussi être associés à un commerçant.
```

### tr

```
Tenra <version>'deki yenilikler:
• Grafikler mevcut dönemi ekranın ortasında açıyor. Yakınlaştırmanın yanındaki yeni menü tahmini, bir yıl önceki aynı dönemi, ortalama çizgisini, en yüksek ve en düşük değerleri ekliyor ya da grafiğin bir cetvelin altında kaymasını sağlıyor; seçiminiz tüm grafiklere uygulanır.
• Her kategorinin artık aylık bir grafiği var, bütçesi bir çizgi olarak gösteriliyor: bütçeyi aşan aylar turuncu olur.
• Yeni içgörü, Günlere göre: haftanın hangi günlerinde neye en çok harcadığınız, son bir yılın her günü bir takvimde ve öne çıkanlar, örneğin hafta sonları ya da ay başı.
• Bir markanın şubeleri, örneğin iki alışveriş merkezindeki aynı mağaza, tek bir işyerinde birleştirilebilir: tüm ödemeler, grafik ve şubeye göre filtre tek ekranda. Elle girdiğiniz ödemeler de bir işyerine bağlanabilir.
```

### pt-BR

```
Novidades do Tenra <version>:
• Os gráficos abrem no período atual, no meio da tela. Um novo menu ao lado do zoom adiciona a previsão, o mesmo período há um ano, a linha da média e os máximos e mínimos, ou faz o gráfico rolar sob uma régua; sua escolha vale para todos os gráficos.
• Cada categoria agora tem um gráfico por mês com o orçamento como linha: os meses acima dele ficam laranja.
• Novo insight, Por dia: em quais dias da semana você gasta mais e com o quê, cada dia do último ano em um calendário e o que se destaca, como os fins de semana ou o início do mês.
• As unidades de uma marca, como a mesma loja em dois shoppings, podem virar um só estabelecimento: uma tela com todos os pagamentos, o gráfico e um filtro por unidade. Pagamentos lançados à mão também podem ser vinculados a um estabelecimento.
```

### it

```
Novità di Tenra <version>:
• I grafici si aprono sul periodo in corso, al centro dello schermo. Un nuovo menu accanto allo zoom aggiunge la previsione, lo stesso periodo di un anno fa, la linea della media e i massimi e minimi, oppure fa scorrere il grafico sotto un righello; la scelta vale per tutti i grafici.
• Ogni categoria ha ora un grafico per mese con il suo budget come linea: i mesi oltre il budget diventano arancioni.
• Nuovo insight, Per giorno: in quali giorni della settimana spendi di più e per cosa, ogni giorno dell'ultimo anno in un calendario e cosa spicca, come i fine settimana o l'inizio del mese.
• I punti vendita di un marchio, come lo stesso negozio in due centri commerciali, si possono unire in un solo esercente: una schermata con tutti i pagamenti, il grafico e un filtro per punto vendita. Anche i pagamenti inseriti a mano si possono collegare a un esercente.
```

### uk

```
Що нового в Tenra <version>:
• Графіки відкриваються на поточному періоді посередині екрана. Нове меню поруч із лупами додає прогноз, той самий період рік тому, лінію середнього, максимум і мінімум або прокручування під лінійкою, і вибір діє на всіх графіках.
• Кожна категорія має графік за місяцями із бюджетом у вигляді лінії: місяці понад нього стають помаранчевими.
• Новий інсайт «За днями»: у які дні тижня ви витрачаєте найбільше і на що, кожен день останнього року в календарі та закономірності, наприклад вихідні чи початок місяця.
• Точки одного бренду, наприклад той самий магазин у двох торгових центрах, можна об'єднати в одного продавця: один екран з усіма платежами, графіком і фільтром за точкою. До продавця можна прив'язати й платежі, внесені вручну.
```

### ja

```
Tenra <version>の新機能：
• グラフは現在の期間を画面中央にして開きます。ズームの横の新しいメニューで、予測、1年前の同じ期間、平均線、最高・最低を追加したり、ルーラーの下でスクロールしたりできます。選択はすべてのグラフに適用されます。
• 各カテゴリに月別のグラフが加わり、予算が線で表示されます。予算を超えた月はオレンジになります。
• 新しいインサイト「曜日別」：どの曜日に何に最も多く使っているか、直近1年間の毎日をカレンダーで、週末や月初など目立つ傾向も表示します。
• 同じブランドの店舗（2つのショッピングモールにある同じ店など）をひとつにまとめられます。すべての支払い、グラフ、店舗ごとの絞り込みをひとつの画面で確認できます。手動で入力した支払いも店舗に紐づけられます。
```

### ko

```
Tenra <version>의 새로운 기능:
• 차트가 현재 기간을 화면 가운데에 두고 열립니다. 확대 옆의 새 메뉴에서 예측, 1년 전 같은 기간, 평균선과 최고·최저를 추가하거나 눈금자 아래로 차트를 스크롤할 수 있으며, 선택은 모든 차트에 적용됩니다.
• 각 카테고리에 예산을 선으로 표시한 월별 차트가 생겼습니다. 예산을 넘은 달은 주황색으로 표시됩니다.
• 새 인사이트 '요일별': 어느 요일에 무엇에 가장 많이 쓰는지, 최근 1년의 매일을 달력으로, 주말이나 월초처럼 눈에 띄는 패턴을 보여줍니다.
• 같은 브랜드의 지점(두 쇼핑몰에 있는 같은 매장 등)을 하나의 가맹점으로 합칠 수 있습니다. 모든 결제, 차트, 지점별 필터를 한 화면에서 볼 수 있습니다. 직접 입력한 결제도 가맹점에 연결할 수 있습니다.
```
