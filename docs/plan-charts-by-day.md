# Charts on DesignKit 8.3.0 and the "By day" insight

Status (2026-10-30): in `main`, on DesignKit 8.3.0 (dkicekeeper/DesignKit#91), version 1.8;
PR #105 (assets) has main merged in and goes into the same 1.8. TestFlight: 1.8 build 59
(2026-10-30), without the assets (build 58 is #105's, without the charts). The What's New below
goes into 1.8's `release-notes.md` once 1.7.1's notes move to the archive; then this file moves to
`archive/plans/`.

## What it does

- DesignKit 8.3.0's charts: the current period selected in the middle of the window, marked as
  not over ("so far"), with the spending forecast and the same period a year ago; the banner
  names the series and gives the change from the period before (green the better way); a long
  press and a drag sum up a stretch; the axis always labels its periods
  ([domains/charts.md](domains/charts.md)).
- The chart options menu by every chart's zoom (`ChartOptionsHost`): the average line, highs and
  lows, the forecast, a year ago, a ruler the chart scrolls under, kept for every chart.
- The category screen: its last 12 months as bars with the same month a year ago, this month's
  forecast and a monthly budget as a line (`CategoryDetailView.monthlyChart`). The merchant
  screen's and Ten's charts mark this month as not over.
- The "By day" insight in Spending (`spending_by_day`, [domains/insights.md](domains/insights.md)).

## Device check

In light and dark, Russian and English: the charts on Analytics (the current period in the
middle, "so far", the forecast and a year ago, the options menu and a ruler the chart scrolls
under), a category's 12 months with its budget line, and "By day" (the feed card's bars, the
calendar, the weekday chart opening on the busiest day and its categories, what stands out).

## What's New (draft, 13 storefront locales)

No em dashes. en-GB takes ru's text, as in [release-notes.md](release-notes.md).

### en-US

```
What's new in Tenra <version>:
• Charts open on the current period in the middle of the screen and show where it is heading, next to the same period a year ago. A new menu next to the zoom adds the average line and the highs and lows, or lets the chart scroll under a ruler; your choice applies to every chart.
• Each category now has a chart of its last 12 months, with its budget as a line: months over it turn orange.
• New insight, By day: on which days of the week you spend the most and on what, every day of the last 16 weeks on a calendar, and what stands out, like weekends or the start of the month.
```

### ru

```
Что нового в Tenra <version>:
• Графики открываются на текущем периоде посередине экрана и показывают, куда он идёт, рядом с тем же периодом год назад. Новое меню рядом с лупами добавляет линию среднего, максимум и минимум или прокрутку под линейкой, и выбор действует на всех графиках.
• У каждой категории появился график за последние 12 месяцев с бюджетом в виде линии: месяцы выше него окрашиваются оранжевым.
• Новый инсайт «По дням»: в какие дни недели вы тратите больше всего и на что, каждый день последних 16 недель в календаре и закономерности, например выходные или начало месяца.
```

### de-DE

```
Neu in Tenra <version>:
• Diagramme öffnen sich mit dem aktuellen Zeitraum in der Bildschirmmitte und zeigen, wohin er sich entwickelt, neben demselben Zeitraum vor einem Jahr. Ein neues Menü neben dem Zoom fügt die Durchschnittslinie sowie Höchst- und Tiefstwerte hinzu oder lässt das Diagramm unter einem Lineal scrollen; Ihre Wahl gilt für alle Diagramme.
• Jede Kategorie hat jetzt ein Diagramm der letzten 12 Monate mit ihrem Budget als Linie: Monate darüber werden orange.
• Neuer Insight „Nach Tagen“: an welchen Wochentagen Sie am meisten ausgeben und wofür, jeder Tag der letzten 16 Wochen in einem Kalender und was auffällt, etwa Wochenenden oder der Monatsanfang.
```

### es-ES

```
Novedades de Tenra <version>:
• Los gráficos se abren en el periodo actual, en el centro de la pantalla, y muestran hacia dónde va junto al mismo periodo de hace un año. Un nuevo menú junto al zoom añade la línea de promedio y los máximos y mínimos, o hace que el gráfico se desplace bajo una regla; tu elección se aplica a todos los gráficos.
• Cada categoría tiene ahora un gráfico de sus últimos 12 meses con su presupuesto como línea: los meses que lo superan se ven en naranja.
• Nuevo análisis, Por días: qué días de la semana gastas más y en qué, cada día de las últimas 16 semanas en un calendario y lo que destaca, como los fines de semana o el inicio de mes.
```

### es-MX

```
Novedades de Tenra <version>:
• Las gráficas se abren en el periodo actual, en el centro de la pantalla, y muestran hacia dónde va junto al mismo periodo de hace un año. Un nuevo menú junto al zoom agrega la línea de promedio y los máximos y mínimos, o hace que la gráfica se desplace bajo una regla; tu elección se aplica a todas las gráficas.
• Cada categoría tiene ahora una gráfica de sus últimos 12 meses con su presupuesto como línea: los meses que lo superan se ven en naranja.
• Nuevo análisis, Por días: qué días de la semana gastas más y en qué, cada día de las últimas 16 semanas en un calendario y lo que destaca, como los fines de semana o el inicio de mes.
```

### fr-FR

```
Nouveautés de Tenra <version> :
• Les graphiques s'ouvrent sur la période en cours, au milieu de l'écran, et montrent où elle va, à côté de la même période il y a un an. Un nouveau menu à côté du zoom ajoute la ligne de moyenne et les plus hauts et plus bas, ou fait défiler le graphique sous une règle ; votre choix s'applique à tous les graphiques.
• Chaque catégorie a désormais un graphique de ses 12 derniers mois, avec son budget en ligne : les mois au-dessus passent en orange.
• Nouvel aperçu, Par jour : les jours de la semaine où vous dépensez le plus et pour quoi, chaque jour des 16 dernières semaines dans un calendrier, et ce qui ressort, comme les week-ends ou le début du mois.
```

### fr-CA

```
Nouveautés de Tenra <version> :
• Les graphiques s'ouvrent sur la période en cours, au milieu de l'écran, et montrent où elle va, à côté de la même période il y a un an. Un nouveau menu à côté du zoom ajoute la ligne de moyenne et les plus hauts et plus bas, ou fait défiler le graphique sous une règle ; votre choix s'applique à tous les graphiques.
• Chaque catégorie a maintenant un graphique de ses 12 derniers mois, avec son budget en ligne : les mois au-dessus passent en orange.
• Nouvel aperçu, Par jour : les jours de la semaine où vous dépensez le plus et pour quoi, chaque jour des 16 dernières semaines dans un calendrier, et ce qui ressort, comme les fins de semaine ou le début du mois.
```

### tr

```
Tenra <version>'deki yenilikler:
• Grafikler mevcut dönemi ekranın ortasında açıyor ve bir yıl önceki aynı dönemin yanında nereye gittiğini gösteriyor. Yakınlaştırmanın yanındaki yeni menü ortalama çizgisini, en yüksek ve en düşük değerleri ekliyor ya da grafiğin bir cetvelin altında kaymasını sağlıyor; seçiminiz tüm grafiklere uygulanır.
• Her kategorinin artık son 12 ayının grafiği var, bütçesi bir çizgi olarak gösteriliyor: bütçeyi aşan aylar turuncu olur.
• Yeni içgörü, Günlere göre: haftanın hangi günlerinde neye en çok harcadığınız, son 16 haftanın her günü bir takvimde ve öne çıkanlar, örneğin hafta sonları ya da ay başı.
```

### pt-BR

```
Novidades do Tenra <version>:
• Os gráficos abrem no período atual, no meio da tela, e mostram para onde ele vai, ao lado do mesmo período há um ano. Um novo menu ao lado do zoom adiciona a linha da média e os máximos e mínimos, ou faz o gráfico rolar sob uma régua; sua escolha vale para todos os gráficos.
• Cada categoria agora tem um gráfico dos últimos 12 meses com o orçamento como linha: os meses acima dele ficam laranja.
• Novo insight, Por dia: em quais dias da semana você gasta mais e com o quê, cada dia das últimas 16 semanas em um calendário e o que se destaca, como os fins de semana ou o início do mês.
```

### it

```
Novità di Tenra <version>:
• I grafici si aprono sul periodo in corso, al centro dello schermo, e mostrano dove sta andando, accanto allo stesso periodo di un anno fa. Un nuovo menu accanto allo zoom aggiunge la linea della media e i massimi e minimi, oppure fa scorrere il grafico sotto un righello; la scelta vale per tutti i grafici.
• Ogni categoria ha ora un grafico degli ultimi 12 mesi con il suo budget come linea: i mesi oltre il budget diventano arancioni.
• Nuovo insight, Per giorno: in quali giorni della settimana spendi di più e per cosa, ogni giorno delle ultime 16 settimane in un calendario e cosa spicca, come i fine settimana o l'inizio del mese.
```

### uk

```
Що нового в Tenra <version>:
• Графіки відкриваються на поточному періоді посередині екрана й показують, куди він іде, поруч із тим самим періодом рік тому. Нове меню поруч із лупами додає лінію середнього, максимум і мінімум або прокручування під лінійкою, і вибір діє на всіх графіках.
• Кожна категорія має графік за останні 12 місяців із бюджетом у вигляді лінії: місяці понад нього стають помаранчевими.
• Новий інсайт «За днями»: у які дні тижня ви витрачаєте найбільше і на що, кожен день останніх 16 тижнів у календарі та закономірності, наприклад вихідні чи початок місяця.
```

### ja

```
Tenra <version>の新機能：
• グラフは現在の期間を画面中央にして開き、1年前の同じ期間と並べて今後の見込みを示します。ズームの横の新しいメニューで平均線や最高・最低を追加したり、ルーラーの下でスクロールしたりできます。選択はすべてのグラフに適用されます。
• 各カテゴリに直近12か月のグラフが加わり、予算が線で表示されます。予算を超えた月はオレンジになります。
• 新しいインサイト「曜日別」：どの曜日に何に最も多く使っているか、直近16週間の毎日をカレンダーで、週末や月初など目立つ傾向も表示します。
```

### ko

```
Tenra <version>의 새로운 기능:
• 차트가 현재 기간을 화면 가운데에 두고 열리며, 1년 전 같은 기간과 함께 앞으로의 예상을 보여줍니다. 확대 옆의 새 메뉴에서 평균선과 최고·최저를 추가하거나 눈금자 아래로 차트를 스크롤할 수 있으며, 선택은 모든 차트에 적용됩니다.
• 각 카테고리에 예산을 선으로 표시한 최근 12개월 차트가 생겼습니다. 예산을 넘은 달은 주황색으로 표시됩니다.
• 새 인사이트 '요일별': 어느 요일에 무엇에 가장 많이 쓰는지, 최근 16주의 매일을 달력으로, 주말이나 월초처럼 눈에 띄는 패턴을 보여줍니다.
```
