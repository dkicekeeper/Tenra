#!/usr/bin/env python3
"""Generates Tenra/Utils/IconCatalog+Data.swift, the icon picker's catalog.

    python3 scripts/generate_icon_catalog.py

Reads the SF Symbols metadata that ships with macOS (CoreGlyphs.bundle):
  - name_availability.plist: only symbols available on the deployment target
    (iOS 26.0) are emitted, so no icon renders blank on an older iPhone;
  - symbol_search.plist: Apple's English search keywords for each symbol.

GROUPS lists base names; the ".fill" variant is used when it exists. A symbol
lands in the first group that lists it (the "frequently used" row may repeat
symbols). CONCEPTS are search synonyms in the app's 11 languages, each pointing
at catalog symbols; the runtime search matches a query against every language,
so "кофе", "kahve" and "コーヒー" all find the cups. Unknown names fail loudly.
"""

import os
import plistlib
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Tenra", "Utils", "IconCatalog+Data.swift")
GLYPHS = "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/"
DEPLOYMENT_TARGET = (26, 0)
LANGS = ["en", "ru", "uk", "de", "es", "fr", "it", "pt", "tr", "ja", "ko"]

FREQUENT = ["banknote.fill", "cart.fill", "car.fill", "bag.fill", "fork.knife", "house.fill",
            "briefcase.fill", "heart.fill", "airplane", "gift.fill", "creditcard.fill", "tv.fill",
            "book.fill", "star.fill", "bolt.fill", "flame.fill"]

GROUPS = [
    ("iconPicker.foodAndDrinks", """
        fork.knife takeoutbag.and.cup.and.straw cup.and.saucer cup.and.heat.waves mug wineglass
        waterbottle birthday.cake carrot fish frying.pan popcorn laurel.leading
            spoon.serving menucard
    """),
    ("iconPicker.transport", """
        car car.2 car.side car.rear suv.side convertible.side bus bus.doubledecker tram
        tram.fill.tunnel lightrail train.side.front.car cablecar airplane airplane.departure
        airplane.arrival ferry sailboat bicycle scooter moped motorcycle fuelpump ev.charger
        bolt.car parkingsign steeringwheel road.lanes tire box.truck truck.box location map
        signpost.right figure.walk
            airplane.ticket airplaneseat car.ferry tram.card licenseplate key.car.radiowaves.forward helmet oilcan gearshift.layout.sixspeed
    """),
    ("iconPicker.shopping", """
        bag cart basket handbag storefront tshirt hanger shoe shoe.2 sunglasses crown tag
        giftcard purchased barcode qrcode backpack
            receipt hat.cap hat.widebrim jacket coat
    """),
    ("iconPicker.homeAndUtilities", """
        house house.lodge building building.2 key door.left.hand.open sofa chair chair.lounge
        bed.double lamp.desk lamp.floor lamp.table lamp.ceiling lightbulb lightbulb.led fan
        air.conditioner.horizontal heater.vertical fireplace bolt powerplug powercord drop flame
        spigot shower bathtub toilet sink washer dryer dishwasher refrigerator oven stove
        microwave cooktop trash window.vertical.closed blinds.vertical.closed curtains.closed
        wifi.router sprinkler.and.droplets
            chandelier table.furniture cabinet stairs robotic.vacuum humidifier air.purifier fan.ceiling fan.desk lightswitch.on poweroutlet.type.f video.doorbell window.casement shower.handheld air.conditioner.vertical dehumidifier sprinkler fire.extinguisher
    """),
    ("iconPicker.health", """
        cross.case cross pills syringe bandage stethoscope waveform.path.ecg heart.text.clipboard
        cross.vial medical.thermometer ivfluid.bag lungs brain brain.head.profile ear eye
        eyeglasses mouth allergens facemask microbe staroflife testtube.2 flask
        figure.mind.and.body
            pill blood.pressure.cuff inhaler apple.meditate bolt.heart staroflife.shield thermometer.medium
    """),
    ("iconPicker.group.beauty", """
        comb scissors sparkles hands.and.sparkles face.smiling mustache eyebrow wand.and.stars
            eyedropper.halffull
    """),
    ("iconPicker.group.family", """
        figure.2.and.child.holdinghands figure.and.child.holdinghands figure.child stroller
        teddybear person person.2 person.3 figure.2.arms.open hands.clap hand.thumbsup heart
        suit.heart
            figure.2
    """),
    ("iconPicker.group.pets", """
        pawprint dog cat bird hare tortoise lizard ant ladybug
            pet.carrier service.dog
    """),
    ("iconPicker.group.educationWork", """
        graduationcap book book.closed books.vertical text.book.closed pencil
        pencil.and.ruler ruler highlighter studentdesk magazine newspaper briefcase doc doc.text
        folder tray archivebox paperclip list.clipboard pencil.and.list.clipboard note.text
        signature compass.drawing globe.desk atom function
            eraser scroll clipboard text.document megaphone lanyardcard pencil.tip
    """),
    ("iconPicker.moneyAndFinance", """
        banknote dollarsign eurosign rublesign tengesign sterlingsign yensign
        chineseyuanrenminbisign turkishlirasign wonsign indianrupeesign bitcoinsign creditcard
        wallet.pass wallet.bifold building.columns chart.bar chart.line.uptrend.xyaxis chart.pie
        percent shield checkmark.shield lock.shield umbrella lock
            hryvniasign brazilianrealsign polishzlotysign larisign manatsign dongsign bahtsign pesosign francsign australiandollarsign swedishkronasign norwegiankronesign danishkronesign shekelsign singaporedollarsign malaysianringgitsign nairasign centsign creditcard.rewards chart.xyaxis.line arrow.left.arrow.right arrow.triangle.2.circlepath
    """),
    ("iconPicker.entertainment", """
        film film.stack movieclapper tv gamecontroller puzzlepiece dice die.face.5
        music.note music.note.list music.mic guitars pianokeys theatermasks ticket party.popper
        paintpalette paintbrush camera photo figure.dance figure.socialdance
            play.tv microphone photo.artframe arcade.stick metronome
    """),
    ("iconPicker.group.travel", """
        suitcase suitcase.rolling suitcase.cart beach.umbrella tent tent.2 mountain.2 binoculars
        globe globe.europe.africa globe.americas globe.asia.australia mappin flag.checkered
        figure.hiking
            figure.walk.suitcase.rolling globe.central.south.asia lifepreserver sun.horizon
    """),
    ("iconPicker.group.sports", """
        dumbbell sportscourt stopwatch trophy medal soccerball basketball football tennis.racket
        tennisball baseball volleyball hockey.puck skateboard skis snowboard surfboard
        oar.2.crossed figure.run figure.run.treadmill figure.strengthtraining.traditional
        figure.strengthtraining.functional figure.cross.training figure.core.training
        figure.highintensity.intervaltraining figure.mixed.cardio figure.elliptical
        figure.stair.stepper figure.jumprope figure.yoga figure.pilates figure.flexibility
        figure.cooldown figure.pool.swim figure.open.water.swim figure.water.fitness
        figure.outdoor.cycle figure.indoor.cycle figure.soccer figure.basketball figure.volleyball
        figure.tennis figure.table.tennis figure.badminton figure.hockey figure.ice.hockey
        figure.ice.skating figure.skating figure.skiing.downhill figure.skiing.crosscountry
        figure.snowboarding figure.skateboarding figure.surfing figure.sailing figure.rower
        figure.climbing figure.boxing figure.kickboxing figure.martial.arts figure.wrestling
        figure.fencing figure.gymnastics figure.golf figure.bowling figure.archery
        figure.equestrian.sports figure.track.and.field figure.fishing figure.hunting
        figure.american.football figure.baseball figure.handball figure.rugby figure.taichi
            rugbyball cricket.ball duffle.bag flag.pattern.checkered figure.squash figure.indoor.rowing figure.barre figure.step.training figure.walk.treadmill figure.curling
    """),
    ("iconPicker.group.tech", """
        iphone ipad laptopcomputer desktopcomputer display applewatch airpods airpodspro
        airpodsmax earbuds headphones homepod appletv visionpro macmini keyboard computermouse
        printer scanner externaldrive cpu memorychip flipphone candybarphone phone message
        bubble.left envelope antenna.radiowaves.left.and.right wifi network icloud simcard
        battery.100 cable.connector hifispeaker radio
            macbook pc airtag applepencil headset server.rack sdcard internaldrive personalhotspot esim faxmachine 4k.tv video envelope.open translate waveform
    """),
    ("iconPicker.group.services", """
        wrench.adjustable wrench.and.screwdriver hammer screwdriver paintbrush.pointed level
        shippingbox paperplane scalemass gearshape gearshape.2 bell checkmark.seal
        exclamationmark.triangle hand.raised
            magnifyingglass flashlight.on key.card
    """),
    ("iconPicker.group.celebrations", """
        gift balloon balloon.2 fireworks star rosette
            greetingcard medal.star
    """),
    ("iconPicker.group.nature", """
        leaf tree camera.macro sun.max moon cloud cloud.rain cloud.snow cloud.bolt snowflake wind
        rainbow sunrise sunset thermometer.sun humidity tornado water.waves
            cloud.sun cloud.moon moon.stars cloud.drizzle cloud.fog cloud.heavyrain sun.haze hurricane tropicalstorm smoke
    """),
    ("iconPicker.group.symbols", """
        bookmark flag pin infinity hourglass timer alarm clock calendar seal diamond hexagon
        octagon triangle rhombus capsule suit.spade suit.club suit.diamond link at number
        questionmark exclamationmark
    """),
]

# Search synonyms: symbols (base names) | terms per language ("lang: a, b; lang: c").
CONCEPTS = [
    ("fork.knife takeoutbag.and.cup.and.straw carrot fish frying.pan birthday.cake",
     "en: food, meal, eat, dinner, lunch, breakfast; ru: еда, питание, обед, ужин, завтрак; uk: їжа, харчування, обід, вечеря, сніданок; de: essen, mahlzeit, mittagessen, abendessen, frühstück; es: comida, almuerzo, cena, desayuno; fr: nourriture, repas, déjeuner, dîner, petit-déjeuner; it: cibo, pasto, pranzo, cena, colazione; pt: comida, refeição, almoço, jantar, café da manhã; tr: yemek, gıda, öğle yemeği, akşam yemeği, kahvaltı; ja: 食べ物, 食事, 昼食, 夕食, 朝食, ごはん; ko: 음식, 식사, 점심, 저녁, 아침"),
    ("fork.knife",
     "en: restaurant, restaurants, dining; ru: ресторан, рестораны; uk: ресторан, ресторани; de: restaurant; es: restaurante; fr: restaurant; it: ristorante; pt: restaurante; tr: restoran, lokanta; ja: レストラン, 外食; ko: 레스토랑, 식당, 외식"),
    ("cup.and.saucer mug cup.and.heat.waves",
     "en: coffee, cafe, coffee shop; ru: кофе, кафе, кофейня; uk: кава, кафе, кав'ярня; de: kaffee, café; es: café, cafetería; fr: café; it: caffè, bar; pt: café, cafeteria; tr: kahve, kafe; ja: コーヒー, カフェ, 喫茶; ko: 커피, 카페"),
    ("cup.and.saucer mug",
     "en: tea; ru: чай; uk: чай; de: tee; es: té; fr: thé; it: tè; pt: chá; tr: çay; ja: お茶, 紅茶; ko: 차"),
    ("takeoutbag.and.cup.and.straw shippingbox",
     "en: fast food, takeaway, takeout, food delivery; ru: фастфуд, еда на вынос, доставка еды; uk: фастфуд, їжа на винос, доставка їжі; de: fastfood, imbiss, essen zum mitnehmen, lieferdienst; es: comida rápida, para llevar, comida a domicilio; fr: fast-food, à emporter, livraison de repas; it: fast food, da asporto, cibo a domicilio; pt: fast food, para viagem, delivery; tr: fast food, paket servis, yemek siparişi; ja: ファストフード, テイクアウト, 出前; ko: 패스트푸드, 포장, 배달음식"),
    ("cart basket carrot bag storefront",
     "en: groceries, grocery, supermarket; ru: продукты, супермаркет, магазин; uk: продукти, супермаркет, магазин; de: lebensmittel, supermarkt, einkauf; es: supermercado, comestibles, alimentos; fr: courses, supermarché, épicerie; it: spesa, supermercato, alimentari; pt: mercado, supermercado, mantimentos; tr: market, süpermarket, bakkal; ja: 食料品, スーパー; ko: 식료품, 마트, 장보기"),
    ("carrot leaf",
     "en: vegetables, fruit, healthy food; ru: овощи, фрукты; uk: овочі, фрукти; de: gemüse, obst; es: verduras, frutas; fr: légumes, fruits; it: verdura, frutta; pt: legumes, frutas, verduras; tr: sebze, meyve; ja: 野菜, 果物; ko: 채소, 과일"),
    ("fish",
     "en: fish, seafood, sushi; ru: рыба, морепродукты, суши; uk: риба, морепродукти, суші; de: fisch, meeresfrüchte, sushi; es: pescado, marisco, sushi; fr: poisson, fruits de mer, sushi; it: pesce, frutti di mare, sushi; pt: peixe, frutos do mar, sushi; tr: balık, deniz ürünleri, suşi; ja: 魚, 寿司, 海鮮; ko: 생선, 해산물, 초밥"),
    ("birthday.cake",
     "en: dessert, sweets, cake, bakery, pastry; ru: сладости, десерт, торт, выпечка, пекарня; uk: солодощі, десерт, торт, випічка, пекарня; de: süßigkeiten, dessert, kuchen, bäckerei; es: dulces, postre, pastel, panadería; fr: desserts, sucreries, gâteau, boulangerie, pâtisserie; it: dolci, dessert, torta, panetteria, pasticceria; pt: doces, sobremesa, bolo, padaria; tr: tatlı, pasta, fırın; ja: スイーツ, デザート, ケーキ, パン屋; ko: 디저트, 과자, 케이크, 빵집"),
    ("wineglass mug",
     "en: alcohol, wine, beer, bar, drinks, pub; ru: алкоголь, вино, пиво, бар, напитки; uk: алкоголь, вино, пиво, бар, напої; de: alkohol, wein, bier, bar, getränke, kneipe; es: alcohol, vino, cerveza, bar, bebidas; fr: alcool, vin, bière, bar, boissons; it: alcol, vino, birra, bar, bevande; pt: álcool, vinho, cerveja, bar, bebidas; tr: alkol, şarap, bira, bar, içecek; ja: お酒, ワイン, ビール, バー, 飲み物; ko: 술, 와인, 맥주, 바, 음료"),
    ("waterbottle drop",
     "en: water; ru: вода; uk: вода; de: wasser; es: agua; fr: eau; it: acqua; pt: água; tr: su; ja: 水; ko: 물"),
    ("car car.2 car.side car.rear suv.side convertible.side steeringwheel licenseplate key.car.radiowaves.forward",
     "en: car, auto, vehicle, driving; ru: машина, авто, автомобиль; uk: машина, авто, автомобіль; de: auto, wagen, fahrzeug; es: coche, auto, carro, vehículo; fr: voiture, auto, véhicule; it: auto, macchina, veicolo; pt: carro, automóvel, veículo; tr: araba, otomobil, araç; ja: 車, 自動車; ko: 자동차, 차"),
    ("car car.side",
     "en: taxi, cab, uber, ride; ru: такси; uk: таксі; de: taxi; es: taxi; fr: taxi; it: taxi; pt: táxi; tr: taksi; ja: タクシー; ko: 택시"),
    ("fuelpump ev.charger bolt.car",
     "en: fuel, gas, petrol, gas station, charging; ru: бензин, топливо, заправка, азс, зарядка; uk: бензин, пальне, заправка, азс, зарядка; de: benzin, tanken, tankstelle, kraftstoff, laden; es: gasolina, combustible, gasolinera, carga; fr: essence, carburant, station-service, recharge; it: benzina, carburante, distributore, ricarica; pt: gasolina, combustível, posto, recarga; tr: benzin, yakıt, akaryakıt, şarj; ja: ガソリン, 燃料, 給油, 充電; ko: 주유, 휘발유, 연료, 충전"),
    ("parkingsign car",
     "en: parking; ru: парковка, стоянка; uk: паркування, стоянка; de: parken, parkplatz; es: aparcamiento, estacionamiento, parking; fr: parking, stationnement; it: parcheggio; pt: estacionamento; tr: otopark, park; ja: 駐車場, パーキング; ko: 주차"),
    ("bus bus.doubledecker tram tram.fill.tunnel lightrail train.side.front.car cablecar tram.card",
     "en: public transport, transit, bus, metro, subway, tram, train; ru: транспорт, общественный транспорт, автобус, метро, трамвай, поезд, электричка; uk: транспорт, громадський транспорт, автобус, метро, трамвай, потяг; de: nahverkehr, bus, u-bahn, straßenbahn, zug, bahn; es: transporte público, autobús, metro, tranvía, tren; fr: transports en commun, bus, métro, tram, train; it: trasporto pubblico, autobus, metro, tram, treno; pt: transporte público, ônibus, metrô, trem, bonde; tr: toplu taşıma, otobüs, metro, tramvay, tren; ja: 交通, 公共交通, バス, 地下鉄, 電車, 路面電車; ko: 대중교통, 버스, 지하철, 트램, 기차"),
    ("airplane airplane.departure airplane.arrival airplane.ticket airplaneseat",
     "en: flight, plane, airplane, airline, airport; ru: самолёт, авиабилеты, перелёт, авиа, аэропорт; uk: літак, авіаквитки, переліт, аеропорт; de: flug, flugzeug, flughafen; es: vuelo, avión, aeropuerto; fr: vol, avion, aéroport; it: volo, aereo, aeroporto; pt: voo, avião, aeroporto; tr: uçak, uçuş, havalimanı; ja: 飛行機, 航空券, 空港; ko: 비행기, 항공권, 공항"),
    ("bicycle scooter moped motorcycle figure.outdoor.cycle",
     "en: bike, bicycle, scooter, motorcycle; ru: велосипед, самокат, мотоцикл, скутер; uk: велосипед, самокат, мотоцикл; de: fahrrad, roller, motorrad; es: bicicleta, patinete, moto; fr: vélo, trottinette, moto; it: bici, bicicletta, monopattino, moto; pt: bicicleta, patinete, moto; tr: bisiklet, scooter, motosiklet; ja: 自転車, スクーター, バイク; ko: 자전거, 킥보드, 오토바이"),
    ("ferry sailboat",
     "en: boat, ferry, ship; ru: лодка, паром, корабль; uk: човен, пором, корабель; de: boot, fähre, schiff; es: barco, ferry; fr: bateau, ferry; it: barca, traghetto, nave; pt: barco, balsa, navio; tr: tekne, feribot, gemi; ja: 船, フェリー; ko: 배, 페리"),
    ("wrench.adjustable wrench.and.screwdriver tire oilcan",
     "en: car service, car repair, tires, maintenance; ru: автосервис, ремонт авто, шины, техобслуживание; uk: автосервіс, ремонт авто, шини; de: werkstatt, autoreparatur, reifen, wartung; es: taller, reparación, neumáticos, mantenimiento; fr: garage, réparation, pneus, entretien; it: officina, riparazione, gomme, manutenzione; pt: oficina, conserto, pneus, manutenção; tr: servis, tamir, lastik, bakım; ja: 整備, 修理, タイヤ; ko: 정비, 수리, 타이어"),
    ("bag cart handbag storefront basket receipt",
     "en: shopping, store, shop, mall, purchase; ru: покупки, шопинг, магазин, торговый центр; uk: покупки, шопінг, магазин; de: einkaufen, shopping, laden, geschäft; es: compras, tienda, centro comercial; fr: achats, shopping, magasin, boutique; it: acquisti, shopping, negozio; pt: compras, loja, shopping; tr: alışveriş, mağaza, avm; ja: 買い物, ショッピング, 店; ko: 쇼핑, 구매, 매장"),
    ("tshirt hanger shoe shoe.2 handbag sunglasses hat.cap hat.widebrim jacket coat",
     "en: clothes, clothing, fashion, shoes, apparel; ru: одежда, обувь, мода; uk: одяг, взуття, мода; de: kleidung, schuhe, mode; es: ropa, zapatos, moda, calzado; fr: vêtements, chaussures, mode; it: vestiti, abbigliamento, scarpe, moda; pt: roupas, sapatos, moda, calçados; tr: giyim, kıyafet, ayakkabı, moda; ja: 服, 衣類, 靴, ファッション; ko: 옷, 의류, 신발, 패션"),
    ("shippingbox box.truck truck.box",
     "en: delivery, parcel, package, online shopping, marketplace; ru: доставка, посылка, маркетплейс, интернет-магазин; uk: доставка, посилка, маркетплейс; de: lieferung, paket, versand, onlineshop; es: envío, paquete, entrega, tienda online; fr: livraison, colis, achats en ligne; it: consegna, pacco, spedizione, acquisti online; pt: entrega, pacote, encomenda, compras online; tr: kargo, paket, teslimat, online alışveriş; ja: 配送, 荷物, 宅配, 通販; ko: 배송, 택배, 소포, 온라인 쇼핑"),
    ("house house.lodge building building.2 key door.left.hand.open",
     "en: home, house, rent, apartment, mortgage; ru: дом, квартира, аренда, жильё, ипотека; uk: дім, квартира, оренда, житло, іпотека; de: zuhause, haus, miete, wohnung, hypothek; es: casa, hogar, alquiler, piso, hipoteca; fr: maison, logement, loyer, appartement, hypothèque; it: casa, affitto, appartamento, mutuo; pt: casa, aluguel, apartamento, moradia, hipoteca; tr: ev, kira, daire, konut, ipotek; ja: 家, 住まい, 家賃, マンション, 住宅ローン; ko: 집, 주거, 월세, 아파트, 대출"),
    ("sofa chair chair.lounge bed.double lamp.desk lamp.floor lamp.table lamp.ceiling table.furniture cabinet chandelier",
     "en: furniture, interior, bed, sofa; ru: мебель, интерьер, кровать, диван; uk: меблі, інтер'єр, ліжко, диван; de: möbel, einrichtung, bett, sofa; es: muebles, cama, sofá; fr: meubles, mobilier, lit, canapé; it: mobili, arredamento, letto, divano; pt: móveis, cama, sofá; tr: mobilya, yatak, koltuk; ja: 家具, インテリア, ベッド, ソファ; ko: 가구, 인테리어, 침대, 소파"),
    ("bolt lightbulb drop flame powerplug spigot fan heater.vertical air.conditioner.horizontal lightswitch.on poweroutlet.type.f",
     "en: utilities, bills, electricity, water, gas, heating; ru: коммунальные, коммуналка, счета, электричество, свет, газ, отопление, жкх; uk: комунальні, комуналка, рахунки, електрика, світло, газ, опалення; de: nebenkosten, rechnungen, strom, gas, heizung; es: servicios, facturas, luz, electricidad, gas, calefacción; fr: charges, factures, électricité, gaz, chauffage; it: utenze, bollette, luce, elettricità, gas, riscaldamento; pt: contas, luz, energia, gás, aquecimento; tr: fatura, faturalar, elektrik, doğalgaz, ısınma; ja: 光熱費, 公共料金, 電気, ガス, 暖房; ko: 공과금, 관리비, 전기, 가스, 난방"),
    ("wifi wifi.router network globe phone iphone antenna.radiowaves.left.and.right simcard personalhotspot esim",
     "en: internet, phone, mobile, cellular, wifi, communication; ru: интернет, связь, телефон, мобильная связь, сотовая; uk: інтернет, зв'язок, телефон, мобільний; de: internet, telefon, handy, mobilfunk; es: internet, teléfono, móvil, celular; fr: internet, téléphone, mobile, forfait; it: internet, telefono, cellulare; pt: internet, telefone, celular; tr: internet, telefon, cep, mobil; ja: インターネット, 電話, 携帯, 通信; ko: 인터넷, 전화, 휴대폰, 통신"),
    ("refrigerator oven stove microwave cooktop dishwasher washer dryer frying.pan",
     "en: appliances, kitchen, fridge, washing machine; ru: бытовая техника, кухня, холодильник, стиральная машина; uk: побутова техніка, кухня, холодильник, пральна машина; de: haushaltsgeräte, küche, kühlschrank, waschmaschine; es: electrodomésticos, cocina, nevera, lavadora; fr: électroménager, cuisine, frigo, lave-linge; it: elettrodomestici, cucina, frigo, lavatrice; pt: eletrodomésticos, cozinha, geladeira, máquina de lavar; tr: beyaz eşya, mutfak, buzdolabı, çamaşır makinesi; ja: 家電, キッチン, 冷蔵庫, 洗濯機; ko: 가전, 주방, 냉장고, 세탁기"),
    ("washer sparkles trash shower robotic.vacuum",
     "en: cleaning, laundry, household; ru: уборка, стирка, химчистка, бытовая химия, хозяйство; uk: прибирання, прання, хімчистка, побутова хімія; de: putzen, reinigung, wäsche, haushalt; es: limpieza, lavandería, hogar; fr: ménage, nettoyage, lessive, pressing; it: pulizie, lavanderia, casa; pt: limpeza, lavanderia; tr: temizlik, çamaşır, kuru temizleme; ja: 掃除, 洗濯, クリーニング, 日用品; ko: 청소, 세탁, 세탁소, 생활용품"),
    ("hammer wrench.and.screwdriver screwdriver paintbrush paintbrush.pointed ruler level wrench.adjustable",
     "en: repair, renovation, tools, construction; ru: ремонт, стройка, инструменты, стройматериалы; uk: ремонт, будівництво, інструменти; de: reparatur, renovierung, werkzeug, baumarkt; es: reparación, reforma, herramientas, obra; fr: réparation, travaux, rénovation, outils; it: riparazione, ristrutturazione, attrezzi; pt: reparo, reforma, ferramentas, obra; tr: tamir, tadilat, alet, inşaat; ja: 修理, リフォーム, 工具; ko: 수리, 리모델링, 공구, 공사"),
    ("cross.case cross pills syringe bandage stethoscope waveform.path.ecg heart.text.clipboard cross.vial medical.thermometer pill blood.pressure.cuff inhaler",
     "en: health, medicine, doctor, hospital, clinic, medical; ru: здоровье, медицина, врач, больница, клиника, поликлиника; uk: здоров'я, медицина, лікар, лікарня, клініка; de: gesundheit, medizin, arzt, krankenhaus, klinik; es: salud, medicina, médico, hospital, clínica; fr: santé, médecine, médecin, hôpital, clinique; it: salute, medicina, medico, ospedale, clinica; pt: saúde, medicina, médico, hospital, clínica; tr: sağlık, tıp, doktor, hastane, klinik; ja: 健康, 医療, 病院, 医者, クリニック; ko: 건강, 의료, 병원, 의사, 클리닉"),
    ("pills cross.case syringe cross.vial pill",
     "en: pharmacy, drugstore, pills, drugs; ru: аптека, лекарства, таблетки; uk: аптека, ліки, таблетки; de: apotheke, medikamente, tabletten; es: farmacia, medicamentos, pastillas; fr: pharmacie, médicaments; it: farmacia, farmaci, medicine; pt: farmácia, remédios, medicamentos; tr: eczane, ilaç; ja: 薬局, 薬; ko: 약국, 약"),
    ("mouth",
     "en: dentist, teeth, dental; ru: стоматолог, зубы, дантист; uk: стоматолог, зуби; de: zahnarzt, zähne; es: dentista, dientes; fr: dentiste, dents; it: dentista, denti; pt: dentista, dentes; tr: diş, dişçi, diş hekimi; ja: 歯医者, 歯科; ko: 치과, 치아"),
    ("eye eyeglasses",
     "en: glasses, optics, eyes, vision; ru: очки, оптика, зрение, глаза; uk: окуляри, оптика, зір; de: brille, optiker, augen; es: gafas, óptica, ojos; fr: lunettes, opticien, yeux; it: occhiali, ottica, occhi; pt: óculos, ótica, olhos; tr: gözlük, optik, göz; ja: 眼鏡, メガネ, 目; ko: 안경, 안과, 눈"),
    ("shield checkmark.shield umbrella lock.shield",
     "en: insurance, protection; ru: страховка, страхование, защита; uk: страховка, страхування, захист; de: versicherung, schutz; es: seguro, protección; fr: assurance, protection; it: assicurazione, protezione; pt: seguro, proteção; tr: sigorta, koruma; ja: 保険, 保障; ko: 보험, 보장"),
    ("dumbbell figure.strengthtraining.traditional figure.run figure.yoga figure.pool.swim sportscourt",
     "en: gym, fitness, sport, sports, workout, training; ru: спорт, фитнес, спортзал, тренировки, зал; uk: спорт, фітнес, спортзал, тренування; de: sport, fitness, fitnessstudio, training; es: gimnasio, deporte, fitness, entrenamiento; fr: sport, salle de sport, fitness, entraînement; it: palestra, sport, fitness, allenamento; pt: academia, esporte, fitness, treino; tr: spor, spor salonu, fitness, antrenman; ja: ジム, スポーツ, フィットネス, トレーニング; ko: 헬스, 운동, 피트니스, 스포츠"),
    ("figure.yoga figure.mind.and.body figure.pilates figure.taichi leaf",
     "en: yoga, meditation, wellness, spa; ru: йога, медитация, спа, релакс; uk: йога, медитація, спа; de: yoga, meditation, wellness, spa; es: yoga, meditación, bienestar, spa; fr: yoga, méditation, bien-être, spa; it: yoga, meditazione, benessere, spa; pt: yoga, ioga, meditação, bem-estar, spa; tr: yoga, meditasyon, spa; ja: ヨガ, 瞑想, スパ; ko: 요가, 명상, 스파"),
    ("figure.pool.swim figure.open.water.swim figure.water.fitness water.waves",
     "en: swimming, pool; ru: плавание, бассейн; uk: плавання, басейн; de: schwimmen, schwimmbad; es: natación, piscina; fr: natation, piscine; it: nuoto, piscina; pt: natação, piscina; tr: yüzme, havuz; ja: 水泳, プール; ko: 수영, 수영장"),
    ("figure.run figure.run.treadmill figure.track.and.field stopwatch",
     "en: running, jogging, marathon; ru: бег, пробежка, марафон; uk: біг, пробіжка, марафон; de: laufen, joggen, marathon; es: correr, running, maratón; fr: course, jogging, marathon; it: corsa, maratona; pt: corrida, maratona; tr: koşu, maraton; ja: ランニング, マラソン; ko: 달리기, 러닝, 마라톤"),
    ("soccerball figure.soccer",
     "en: football, soccer; ru: футбол; uk: футбол; de: fußball; es: fútbol; fr: football, foot; it: calcio; pt: futebol; tr: futbol; ja: サッカー; ko: 축구"),
    ("basketball figure.basketball",
     "en: basketball; ru: баскетбол; uk: баскетбол; de: basketball; es: baloncesto; fr: basket; it: pallacanestro, basket; pt: basquete; tr: basketbol; ja: バスケ, バスケットボール; ko: 농구"),
    ("tennis.racket tennisball figure.tennis figure.table.tennis figure.badminton",
     "en: tennis, ping pong, badminton; ru: теннис, настольный теннис, бадминтон; uk: теніс, бадмінтон; de: tennis, tischtennis, badminton; es: tenis, pádel, bádminton; fr: tennis, ping-pong, badminton; it: tennis, ping pong, badminton; pt: tênis, pingue-pongue, badminton; tr: tenis, masa tenisi, badminton; ja: テニス, 卓球, バドミントン; ko: 테니스, 탁구, 배드민턴"),
    ("volleyball figure.volleyball",
     "en: volleyball; ru: волейбол; uk: волейбол; de: volleyball; es: voleibol; fr: volley; it: pallavolo; pt: vôlei; tr: voleybol; ja: バレーボール; ko: 배구"),
    ("hockey.puck figure.hockey figure.ice.hockey figure.ice.skating figure.skating",
     "en: hockey, skating, ice rink; ru: хоккей, коньки, каток; uk: хокей, ковзани, ковзанка; de: eishockey, schlittschuh, eisbahn; es: hockey, patinaje; fr: hockey, patinoire, patin; it: hockey, pattinaggio; pt: hóquei, patinação; tr: hokey, paten, buz pateni; ja: ホッケー, スケート; ko: 하키, 스케이트"),
    ("figure.skiing.downhill figure.skiing.crosscountry figure.snowboarding skis snowboard snowflake mountain.2",
     "en: skiing, ski, snowboard, winter sports; ru: лыжи, горные лыжи, сноуборд; uk: лижі, сноуборд; de: ski, skifahren, snowboard; es: esquí, snowboard; fr: ski, snowboard; it: sci, snowboard; pt: esqui, snowboard; tr: kayak, snowboard; ja: スキー, スノーボード; ko: 스키, 스노보드"),
    ("figure.boxing figure.martial.arts figure.kickboxing figure.wrestling",
     "en: boxing, martial arts, karate, wrestling; ru: бокс, единоборства, карате, борьба; uk: бокс, єдиноборства, карате, боротьба; de: boxen, kampfsport, karate, ringen; es: boxeo, artes marciales, kárate, lucha; fr: boxe, arts martiaux, karaté, lutte; it: boxe, arti marziali, karate, lotta; pt: boxe, artes marciais, caratê, luta; tr: boks, dövüş sanatları, karate, güreş; ja: ボクシング, 格闘技, 空手; ko: 복싱, 무술, 태권도, 레슬링"),
    ("figure.golf",
     "en: golf; ru: гольф; uk: гольф; de: golf; es: golf; fr: golf; it: golf; pt: golfe; tr: golf; ja: ゴルフ; ko: 골프"),
    ("figure.dance figure.socialdance",
     "en: dance, dancing; ru: танцы; uk: танці; de: tanzen, tanz; es: baile; fr: danse; it: danza, ballo; pt: dança; tr: dans; ja: ダンス; ko: 춤, 댄스"),
    ("figure.hiking mountain.2 tent binoculars",
     "en: hiking, camping, outdoors, mountains; ru: поход, походы, кемпинг, горы, туризм; uk: похід, кемпінг, гори, туризм; de: wandern, camping, berge; es: senderismo, camping, montaña; fr: randonnée, camping, montagne; it: escursionismo, campeggio, montagna; pt: trilha, acampamento, montanha; tr: yürüyüş, kamp, dağ; ja: ハイキング, キャンプ, 山; ko: 등산, 캠핑, 산"),
    ("figure.fishing fish figure.hunting",
     "en: fishing, hunting; ru: рыбалка, охота; uk: риболовля, полювання; de: angeln, jagd; es: pesca, caza; fr: pêche, chasse; it: pesca, caccia; pt: pesca, caça; tr: balık tutma, avcılık; ja: 釣り, 狩猟; ko: 낚시, 사냥"),
    ("comb scissors sparkles hands.and.sparkles face.smiling mustache eyebrow wand.and.stars",
     "en: beauty, salon, haircut, barber, hairdresser, cosmetics, makeup, manicure; ru: красота, салон, стрижка, парикмахерская, барбершоп, косметика, макияж, маникюр; uk: краса, салон, стрижка, перукарня, барбершоп, косметика, манікюр; de: schönheit, friseur, haarschnitt, kosmetik, makeup, maniküre; es: belleza, peluquería, barbería, cosmética, maquillaje, manicura; fr: beauté, coiffeur, coupe, barbier, cosmétiques, maquillage, manucure; it: bellezza, parrucchiere, barbiere, cosmetici, trucco, manicure; pt: beleza, salão, cabeleireiro, barbearia, cosméticos, maquiagem, manicure; tr: güzellik, kuaför, berber, kozmetik, makyaj, manikür; ja: 美容, 美容院, 床屋, 化粧品, ネイル; ko: 뷰티, 미용실, 이발소, 화장품, 네일"),
    ("shower bathtub drop comb",
     "en: hygiene, personal care, bath; ru: гигиена, уход, ванна, душ; uk: гігієна, догляд, ванна, душ; de: hygiene, körperpflege, bad; es: higiene, cuidado personal, baño; fr: hygiène, soins, bain; it: igiene, cura personale, bagno; pt: higiene, cuidados pessoais, banho; tr: hijyen, kişisel bakım, banyo; ja: 衛生, お風呂, ケア; ko: 위생, 목욕, 개인 관리"),
    ("figure.2.and.child.holdinghands figure.and.child.holdinghands person.2 person.3 house heart",
     "en: family, parents, relatives; ru: семья, родители, родственники, мама, папа; uk: сім'я, родина, батьки, родичі, мама, тато; de: familie, eltern, verwandte; es: familia, padres, parientes; fr: famille, parents, proches; it: famiglia, genitori, parenti; pt: família, pais, parentes; tr: aile, ebeveyn, akraba, anne, baba; ja: 家族, 両親, 親戚; ko: 가족, 부모, 친척"),
    ("figure.child stroller teddybear figure.and.child.holdinghands balloon",
     "en: kids, children, child, baby, toys; ru: дети, ребёнок, малыш, игрушки, детский сад; uk: діти, дитина, малюк, іграшки, садок; de: kinder, kind, baby, spielzeug, kita; es: niños, hijos, bebé, juguetes, guardería; fr: enfants, enfant, bébé, jouets, crèche; it: bambini, figli, neonato, giocattoli, asilo; pt: crianças, filhos, bebê, brinquedos, creche; tr: çocuk, bebek, oyuncak, kreş; ja: 子供, 赤ちゃん, おもちゃ, 保育園; ko: 아이, 아기, 장난감, 어린이집"),
    ("heart suit.heart gift",
     "en: love, partner, relationship, date, wife, husband, girlfriend, boyfriend; ru: любовь, любимая, любимый, отношения, свидание, жена, муж, девушка, парень; uk: кохання, кохана, коханий, стосунки, побачення, дружина, чоловік; de: liebe, partner, beziehung, date, frau, mann, freundin, freund; es: amor, pareja, cita, esposa, esposo, novia, novio; fr: amour, couple, rendez-vous, femme, mari, copine, copain; it: amore, coppia, appuntamento, moglie, marito, fidanzata, fidanzato; pt: amor, namorada, namorado, casal, encontro, esposa, marido; tr: aşk, sevgili, ilişki, randevu, eş, karı, koca; ja: 恋人, 愛, デート, 妻, 夫, 彼女, 彼氏; ko: 사랑, 연인, 데이트, 아내, 남편, 여자친구, 남자친구"),
    ("person.2 person.3 person hands.clap",
     "en: friends, people, social; ru: друзья, люди, общение; uk: друзі, люди, спілкування; de: freunde, leute, soziales; es: amigos, gente, social; fr: amis, gens, social; it: amici, persone, sociale; pt: amigos, pessoas, social; tr: arkadaşlar, insanlar, sosyal; ja: 友達, 人, 交流; ko: 친구, 사람, 모임"),
    ("pawprint dog cat bird fish hare tortoise lizard pet.carrier service.dog",
     "en: pets, pet, dog, cat, vet, animals; ru: питомцы, животные, собака, кошка, кот, ветеринар, зоомагазин; uk: тварини, улюбленці, собака, кіт, кішка, ветеринар; de: haustier, tiere, hund, katze, tierarzt; es: mascotas, animales, perro, gato, veterinario; fr: animaux, animal, chien, chat, vétérinaire; it: animali, cane, gatto, veterinario; pt: pets, animais, cachorro, cão, gato, veterinário; tr: evcil hayvan, hayvan, köpek, kedi, veteriner; ja: ペット, 動物, 犬, 猫, 獣医; ko: 반려동물, 동물, 강아지, 고양이, 동물병원"),
    ("graduationcap book books.vertical backpack pencil studentdesk text.book.closed pencil.and.ruler eraser scroll",
     "en: education, school, university, study, courses, tuition; ru: образование, учёба, школа, университет, курсы, обучение; uk: освіта, навчання, школа, університет, курси; de: bildung, schule, universität, studium, kurse; es: educación, escuela, universidad, estudios, cursos; fr: éducation, école, université, études, cours; it: istruzione, scuola, università, studio, corsi; pt: educação, escola, faculdade, universidade, cursos; tr: eğitim, okul, üniversite, kurs; ja: 教育, 学校, 大学, 勉強, 講座; ko: 교육, 학교, 대학, 공부, 학원"),
    ("book book.closed books.vertical text.book.closed magazine newspaper",
     "en: books, reading, library, magazine; ru: книги, чтение, библиотека, журнал; uk: книги, читання, бібліотека, журнал; de: bücher, lesen, bibliothek, zeitschrift; es: libros, lectura, biblioteca, revista; fr: livres, lecture, bibliothèque, magazine; it: libri, lettura, biblioteca, rivista; pt: livros, leitura, biblioteca, revista; tr: kitap, okuma, kütüphane, dergi; ja: 本, 読書, 図書館, 雑誌; ko: 책, 독서, 도서관, 잡지"),
    ("briefcase building.2 desktopcomputer laptopcomputer printer lanyardcard megaphone",
     "en: work, job, office, business; ru: работа, офис, бизнес; uk: робота, офіс, бізнес; de: arbeit, job, büro, geschäft; es: trabajo, oficina, negocio; fr: travail, emploi, bureau, entreprise; it: lavoro, ufficio, azienda; pt: trabalho, emprego, escritório, negócio; tr: iş, ofis, şirket; ja: 仕事, 職場, オフィス, ビジネス; ko: 일, 직장, 사무실, 사업"),
    ("banknote dollarsign briefcase chart.line.uptrend.xyaxis",
     "en: salary, income, wage, paycheck, bonus, earnings; ru: зарплата, доход, заработок, премия, аванс; uk: зарплата, дохід, заробіток, премія; de: gehalt, lohn, einkommen, bonus; es: salario, sueldo, ingresos, nómina; fr: salaire, revenu, paie, prime; it: stipendio, reddito, salario, bonus; pt: salário, renda, bônus; tr: maaş, gelir, prim; ja: 給料, 収入, 給与, ボーナス; ko: 월급, 급여, 수입, 보너스"),
    ("banknote dollarsign eurosign rublesign tengesign sterlingsign yensign wonsign turkishlirasign hryvniasign brazilianrealsign polishzlotysign larisign manatsign dongsign bahtsign pesosign francsign australiandollarsign swedishkronasign norwegiankronesign danishkronesign shekelsign singaporedollarsign malaysianringgitsign nairasign centsign chineseyuanrenminbisign indianrupeesign",
     "en: money, cash, currency; ru: деньги, наличные, валюта; uk: гроші, готівка, валюта; de: geld, bargeld, währung; es: dinero, efectivo, moneda; fr: argent, espèces, liquide, devise; it: soldi, denaro, contanti, valuta; pt: dinheiro, espécie, moeda; tr: para, nakit, döviz; ja: お金, 現金, 通貨; ko: 돈, 현금, 통화"),
    ("creditcard building.columns wallet.pass wallet.bifold creditcard.rewards",
     "en: bank, card, credit card, account, payment, wallet; ru: банк, карта, карточка, счёт, оплата, платёж, кошелёк; uk: банк, картка, рахунок, оплата, платіж, гаманець; de: bank, karte, kreditkarte, konto, zahlung, geldbörse; es: banco, tarjeta, cuenta, pago, cartera; fr: banque, carte, compte, paiement, portefeuille; it: banca, carta, conto, pagamento, portafoglio; pt: banco, cartão, conta, pagamento, carteira; tr: banka, kart, kredi kartı, hesap, ödeme, cüzdan; ja: 銀行, カード, 口座, 支払い, 財布; ko: 은행, 카드, 계좌, 결제, 지갑"),
    ("chart.line.uptrend.xyaxis chart.bar chart.pie banknote lock",
     "en: savings, investment, deposit, stocks, piggy bank; ru: накопления, копилка, сбережения, инвестиции, вклад, депозит, акции; uk: заощадження, скарбничка, інвестиції, вклад, депозит, акції; de: sparen, ersparnisse, investition, einlage, aktien; es: ahorro, inversión, depósito, acciones, hucha; fr: épargne, investissement, dépôt, actions, tirelire; it: risparmi, investimenti, deposito, azioni, salvadanaio; pt: poupança, investimento, depósito, ações, cofrinho; tr: birikim, yatırım, mevduat, hisse, kumbara; ja: 貯金, 投資, 預金, 株; ko: 저축, 투자, 예금, 주식"),
    ("creditcard building.columns percent doc.text",
     "en: loan, credit, debt, installment, interest; ru: кредит, долг, долги, займ, рассрочка, проценты; uk: кредит, борг, позика, розстрочка, відсотки; de: kredit, schulden, darlehen, raten, zinsen; es: préstamo, crédito, deuda, cuotas, intereses; fr: prêt, crédit, dette, mensualités, intérêts; it: prestito, credito, debito, rate, interessi; pt: empréstimo, crédito, dívida, parcelas, juros; tr: kredi, borç, taksit, faiz; ja: ローン, 借金, 分割, 利息; ko: 대출, 빚, 할부, 이자"),
    ("doc.text building.columns percent list.clipboard",
     "en: taxes, tax, fees, fines; ru: налоги, налог, пошлины, штрафы; uk: податки, податок, мито, штрафи; de: steuern, steuer, gebühren, bußgeld; es: impuestos, tasas, multas; fr: impôts, taxes, frais, amendes; it: tasse, imposte, multe; pt: impostos, taxas, multas; tr: vergi, harç, ceza; ja: 税金, 手数料, 罰金; ko: 세금, 수수료, 벌금"),
    ("bitcoinsign",
     "en: crypto, bitcoin; ru: крипта, криптовалюта, биткоин; uk: крипта, криптовалюта, біткоїн; de: krypto, bitcoin; es: cripto, bitcoin; fr: crypto, bitcoin; it: cripto, bitcoin; pt: cripto, bitcoin; tr: kripto, bitcoin; ja: 暗号資産, ビットコイン; ko: 암호화폐, 비트코인"),
    ("percent tag creditcard.rewards",
     "en: discount, sale, cashback, promo; ru: скидка, распродажа, кэшбэк, акция; uk: знижка, розпродаж, кешбек, акція; de: rabatt, sale, cashback, angebot; es: descuento, rebajas, cashback, oferta; fr: réduction, soldes, cashback, promo; it: sconto, saldi, cashback, offerta; pt: desconto, promoção, cashback; tr: indirim, kampanya, nakit iade; ja: 割引, セール, キャッシュバック; ko: 할인, 세일, 캐시백"),
    ("film film.stack popcorn movieclapper tv ticket play.tv",
     "en: movies, cinema, film, tv, streaming; ru: кино, кинотеатр, фильмы, сериалы, тв, стриминг; uk: кіно, кінотеатр, фільми, серіали; de: kino, film, filme, fernsehen, streaming; es: cine, películas, series, tele, streaming; fr: cinéma, films, séries, télé, streaming; it: cinema, film, serie, tv, streaming; pt: cinema, filmes, séries, tv, streaming; tr: sinema, film, dizi, televizyon; ja: 映画, 映画館, ドラマ, テレビ, 配信; ko: 영화, 영화관, 드라마, 스트리밍"),
    ("music.note music.note.list headphones guitars pianokeys music.mic hifispeaker radio microphone metronome",
     "en: music, concert, songs, karaoke; ru: музыка, концерт, песни, караоке; uk: музика, концерт, пісні, караоке; de: musik, konzert, lieder, karaoke; es: música, concierto, canciones, karaoke; fr: musique, concert, chansons, karaoké; it: musica, concerto, canzoni, karaoke; pt: música, show, canções, karaokê; tr: müzik, konser, şarkı, karaoke; ja: 音楽, コンサート, カラオケ; ko: 음악, 콘서트, 노래방"),
    ("gamecontroller puzzlepiece dice die.face.5 arcade.stick",
     "en: games, gaming, video games; ru: игры, видеоигры, гейминг; uk: ігри, відеоігри; de: spiele, gaming, videospiele; es: juegos, videojuegos; fr: jeux, jeux vidéo; it: giochi, videogiochi; pt: jogos, videogames, games; tr: oyun, oyunlar, video oyunu; ja: ゲーム; ko: 게임"),
    ("theatermasks party.popper ticket balloon star paintpalette",
     "en: entertainment, leisure, fun, theater, events, tickets; ru: развлечения, досуг, театр, мероприятия, билеты; uk: розваги, дозвілля, театр, заходи, квитки; de: unterhaltung, freizeit, theater, events, tickets; es: entretenimiento, ocio, teatro, eventos, entradas; fr: loisirs, divertissement, théâtre, sorties, billets; it: divertimento, svago, teatro, eventi, biglietti; pt: entretenimento, lazer, teatro, eventos, ingressos; tr: eğlence, tiyatro, etkinlik, bilet; ja: 娯楽, 劇場, イベント, チケット; ko: 여가, 오락, 공연, 행사, 티켓"),
    ("paintpalette paintbrush camera photo scissors",
     "en: hobby, art, crafts, photography; ru: хобби, творчество, рисование, фото; uk: хобі, творчість, малювання, фото; de: hobby, kunst, basteln, fotografie; es: hobby, pasatiempo, arte, manualidades, fotografía; fr: loisirs créatifs, art, dessin, photo; it: hobby, arte, fai da te, fotografia; pt: hobby, arte, artesanato, fotografia; tr: hobi, sanat, el işi, fotoğraf; ja: 趣味, アート, 写真; ko: 취미, 미술, 사진"),
    ("tv music.note.list newspaper icloud calendar play.tv arrow.triangle.2.circlepath",
     "en: subscriptions, subscription, streaming; ru: подписки, подписка; uk: підписки, підписка; de: abos, abonnement; es: suscripciones, suscripción; fr: abonnements, abonnement; it: abbonamenti, abbonamento; pt: assinaturas, assinatura; tr: abonelik, üyelik; ja: サブスク, 定額; ko: 구독"),
    ("airplane suitcase suitcase.rolling beach.umbrella globe map tent binoculars mountain.2",
     "en: travel, trip, vacation, holiday, tourism; ru: путешествия, поездка, отпуск, туризм, отдых; uk: подорожі, поїздка, відпустка, туризм, відпочинок; de: reisen, reise, urlaub, tourismus; es: viajes, viaje, vacaciones, turismo; fr: voyage, voyages, vacances, tourisme; it: viaggi, viaggio, vacanze, turismo; pt: viagem, viagens, férias, turismo; tr: seyahat, gezi, tatil, turizm; ja: 旅行, 旅, 休暇, 観光; ko: 여행, 휴가, 관광"),
    ("bed.double building house.lodge key",
     "en: hotel, accommodation, hostel, airbnb; ru: отель, гостиница, жильё, хостел; uk: готель, житло, хостел; de: hotel, unterkunft, hostel; es: hotel, alojamiento, hostal; fr: hôtel, hébergement, auberge; it: hotel, alloggio, ostello; pt: hotel, hospedagem, hostel; tr: otel, konaklama, hostel; ja: ホテル, 宿泊; ko: 호텔, 숙박"),
    ("beach.umbrella sun.max water.waves sailboat",
     "en: beach, summer, sea, sun; ru: пляж, лето, море, солнце; uk: пляж, літо, море, сонце; de: strand, sommer, meer, sonne; es: playa, verano, mar, sol; fr: plage, été, mer, soleil; it: spiaggia, estate, mare, sole; pt: praia, verão, mar, sol; tr: plaj, yaz, deniz, güneş; ja: ビーチ, 夏, 海, 太陽; ko: 해변, 여름, 바다, 햇빛"),
    ("iphone ipad laptopcomputer desktopcomputer applewatch headphones airpods tv display keyboard computermouse macbook pc airtag headset",
     "en: electronics, gadgets, tech, computer, laptop, smartphone; ru: электроника, гаджеты, техника, компьютер, ноутбук, смартфон; uk: електроніка, гаджети, техніка, комп'ютер, ноутбук, смартфон; de: elektronik, gadgets, technik, computer, laptop, smartphone; es: electrónica, gadgets, tecnología, ordenador, portátil, móvil; fr: électronique, high-tech, ordinateur, portable, smartphone; it: elettronica, gadget, tecnologia, computer, portatile, smartphone; pt: eletrônicos, tecnologia, computador, notebook, celular; tr: elektronik, teknoloji, bilgisayar, laptop, akıllı telefon; ja: 家電, ガジェット, パソコン, スマホ; ko: 전자기기, 가젯, 컴퓨터, 노트북, 스마트폰"),
    ("icloud desktopcomputer laptopcomputer",
     "en: software, apps, cloud, storage; ru: программы, приложения, облако, софт; uk: програми, застосунки, хмара; de: software, apps, cloud, speicher; es: software, apps, aplicaciones, nube; fr: logiciels, applis, cloud; it: software, app, cloud; pt: software, apps, aplicativos, nuvem; tr: yazılım, uygulama, bulut; ja: ソフト, アプリ, クラウド; ko: 소프트웨어, 앱, 클라우드"),
    ("envelope paperplane shippingbox",
     "en: mail, post, letter; ru: почта, письмо, посылка; uk: пошта, лист, посилка; de: post, brief, paket; es: correo, carta, paquete; fr: courrier, poste, lettre, colis; it: posta, lettera, pacco; pt: correio, carta, encomenda; tr: posta, mektup, kargo; ja: 郵便, 手紙; ko: 우편, 편지, 우체국"),
    ("gift giftcard party.popper greetingcard",
     "en: gift, gifts, present; ru: подарок, подарки, сувенир; uk: подарунок, подарунки, сувенір; de: geschenk, geschenke; es: regalo, regalos; fr: cadeau, cadeaux; it: regalo, regali; pt: presente, presentes; tr: hediye; ja: プレゼント, ギフト, 贈り物; ko: 선물"),
    ("party.popper balloon balloon.2 birthday.cake fireworks sparkles wineglass",
     "en: holiday, party, celebration, birthday, new year, christmas, wedding; ru: праздник, праздники, вечеринка, день рождения, новый год, свадьба; uk: свято, свята, вечірка, день народження, новий рік, весілля; de: feier, party, geburtstag, silvester, weihnachten, hochzeit; es: fiesta, celebración, cumpleaños, año nuevo, navidad, boda; fr: fête, anniversaire, nouvel an, noël, mariage; it: festa, compleanno, capodanno, natale, matrimonio; pt: festa, comemoração, aniversário, ano novo, natal, casamento; tr: bayram, parti, kutlama, doğum günü, yılbaşı, düğün; ja: お祝い, パーティー, 誕生日, 正月, クリスマス, 結婚式; ko: 축하, 파티, 생일, 새해, 크리스마스, 결혼식"),
    ("camera.macro leaf tree sprinkler.and.droplets",
     "en: flowers, garden, plants; ru: цветы, сад, растения, дача; uk: квіти, сад, рослини, дача; de: blumen, garten, pflanzen; es: flores, jardín, plantas; fr: fleurs, jardin, plantes; it: fiori, giardino, piante; pt: flores, jardim, plantas; tr: çiçek, bahçe, bitki; ja: 花, 庭, 植物; ko: 꽃, 정원, 식물"),
    ("heart hands.and.sparkles gift hand.raised",
     "en: charity, donation, donate; ru: благотворительность, пожертвование, донат; uk: благодійність, пожертва, донат; de: spende, spenden, wohltätigkeit; es: donación, caridad, donativo; fr: don, dons, charité; it: donazione, beneficenza; pt: doação, caridade; tr: bağış, hayır; ja: 寄付, 募金; ko: 기부, 후원"),
    ("sun.max cloud cloud.rain cloud.snow snowflake wind umbrella thermometer.sun cloud.sun cloud.drizzle cloud.heavyrain cloud.fog moon.stars",
     "en: weather, rain, snow, sun, winter; ru: погода, дождь, снег, солнце, зима; uk: погода, дощ, сніг, сонце, зима; de: wetter, regen, schnee, sonne, winter; es: tiempo, lluvia, nieve, sol, invierno; fr: météo, pluie, neige, soleil, hiver; it: meteo, pioggia, neve, sole, inverno; pt: clima, chuva, neve, sol, inverno; tr: hava, yağmur, kar, güneş, kış; ja: 天気, 雨, 雪, 晴れ, 冬; ko: 날씨, 비, 눈, 해, 겨울"),
    ("leaf tree mountain.2 flame drop globe.europe.africa",
     "en: nature, eco, green, environment; ru: природа, экология; uk: природа, екологія; de: natur, umwelt, öko; es: naturaleza, ecología, medio ambiente; fr: nature, écologie, environnement; it: natura, ecologia, ambiente; pt: natureza, ecologia, meio ambiente; tr: doğa, ekoloji, çevre; ja: 自然, エコ, 環境; ko: 자연, 환경, 친환경"),
    ("calendar clock alarm hourglass timer",
     "en: time, calendar, schedule, deadline; ru: время, календарь, расписание, срок; uk: час, календар, розклад, термін; de: zeit, kalender, termin, frist; es: tiempo, calendario, horario, plazo; fr: temps, calendrier, agenda, échéance; it: tempo, calendario, orario, scadenza; pt: tempo, calendário, agenda, prazo; tr: zaman, takvim, program, süre; ja: 時間, カレンダー, 予定, 期限; ko: 시간, 달력, 일정, 기한"),
    ("doc.text folder paperclip signature list.clipboard archivebox tray clipboard text.document scroll",
     "en: documents, papers, contract, notary; ru: документы, бумаги, договор, нотариус; uk: документи, папери, договір, нотаріус; de: dokumente, unterlagen, vertrag, notar; es: documentos, papeles, contrato, notario; fr: documents, papiers, contrat, notaire; it: documenti, carte, contratto, notaio; pt: documentos, papéis, contrato, cartório; tr: belge, evrak, sözleşme, noter; ja: 書類, 契約, 公証; ko: 서류, 문서, 계약, 공증"),
    ("building.columns doc.text checkmark.seal",
     "en: government, legal, lawyer, court; ru: госуслуги, юрист, адвокат, суд, государство; uk: держпослуги, юрист, адвокат, суд; de: behörde, anwalt, gericht, recht; es: gobierno, abogado, tribunal, trámites; fr: administration, avocat, tribunal, justice; it: pubblica amministrazione, avvocato, tribunale; pt: governo, advogado, tribunal; tr: devlet, avukat, mahkeme, hukuk; ja: 行政, 弁護士, 裁判所; ko: 관공서, 변호사, 법원"),
    ("lock key lock.shield",
     "en: security, lock, keys, password; ru: безопасность, замок, ключи, пароль; uk: безпека, замок, ключі, пароль; de: sicherheit, schloss, schlüssel, passwort; es: seguridad, candado, llaves, contraseña; fr: sécurité, serrure, clés, mot de passe; it: sicurezza, lucchetto, chiavi, password; pt: segurança, cadeado, chaves, senha; tr: güvenlik, kilit, anahtar, şifre; ja: セキュリティ, 鍵, パスワード; ko: 보안, 자물쇠, 열쇠, 비밀번호"),
    ("arrow.left.arrow.right banknote creditcard paperplane building.columns",
     "en: transfer, transfers, send money, money transfer; ru: перевод, переводы, перевод денег; uk: переказ, перекази, переказ грошей; de: überweisung, überweisungen, geld senden; es: transferencia, transferencias, envío de dinero; fr: virement, virements, envoi d'argent; it: bonifico, bonifici, trasferimento; pt: transferência, transferências, pix; tr: havale, eft, para transferi; ja: 振込, 送金; ko: 이체, 송금"),
    ("arrow.triangle.2.circlepath calendar",
     "en: recurring, regular payment, monthly; ru: регулярные, регулярный платёж, ежемесячно; uk: регулярні, регулярний платіж, щомісяця; de: wiederkehrend, dauerauftrag, monatlich; es: recurrente, pago periódico, mensual; fr: récurrent, prélèvement, mensuel; it: ricorrente, pagamento periodico, mensile; pt: recorrente, pagamento recorrente, mensal; tr: düzenli, düzenli ödeme, aylık; ja: 定期, 毎月; ko: 정기, 매월, 자동이체"),
    ("translate",
     "en: translation, translator, languages; ru: переводчик, языки, иностранный язык; uk: перекладач, мови, іноземна мова; de: übersetzung, übersetzer, sprachen; es: traducción, traductor, idiomas; fr: traduction, traducteur, langues; it: traduzione, traduttore, lingue; pt: tradução, tradutor, idiomas; tr: çeviri, tercüman, dil; ja: 翻訳, 語学; ko: 번역, 통역, 어학"),
    ("rugbyball cricket.ball figure.rugby figure.american.football",
     "en: rugby, american football, cricket; ru: регби, американский футбол, крикет; uk: регбі, американський футбол, крикет; de: rugby, american football, cricket; es: rugby, fútbol americano, críquet; fr: rugby, football américain, cricket; it: rugby, football americano, cricket; pt: rúgbi, futebol americano, críquete; tr: ragbi, amerikan futbolu, kriket; ja: ラグビー, アメフト, クリケット; ko: 럭비, 미식축구, 크리켓"),
    ("star heart sparkles bookmark flag tag",
     "en: other, misc, general, favorite; ru: другое, прочее, разное, избранное; uk: інше, різне, обране; de: sonstiges, andere, allgemein, favorit; es: otros, varios, general, favorito; fr: autre, divers, général, favori; it: altro, varie, generale, preferito; pt: outros, diversos, geral, favorito; tr: diğer, çeşitli, genel, favori; ja: その他, 雑費, お気に入り; ko: 기타, 잡비, 즐겨찾기"),
]


# Currency names -> their sign, in the 11 languages (en ru uk de es fr it pt tr ja ko).
CURRENCIES = [
    ("dollarsign australiandollarsign singaporedollarsign", "dollar|доллар|долар|dollar|dólar|dollar|dollaro|dólar|dolar|ドル|달러"),
    ("eurosign", "euro|евро|євро|euro|euro|euro|euro|euro|euro|ユーロ|유로"),
    ("rublesign", "ruble, rouble|рубль|рубль|rubel|rublo|rouble|rublo|rublo|ruble|ルーブル|루블"),
    ("tengesign", "tenge|тенге|теньге|tenge|tenge|tenge|tenge|tenge|tenge|テンゲ|텡게"),
    ("hryvniasign", "hryvnia|гривна|гривня|hrywnja|grivna|hryvnia|grivnia|grívnia|grivna|フリヴニャ|흐리우냐"),
    ("turkishlirasign", "lira, turkish lira|лира|ліра|lira|lira|livre turque|lira turca|lira|lira, türk lirası|リラ|리라"),
    ("sterlingsign", "pound, sterling|фунт|фунт|pfund|libra|livre sterling|sterlina|libra|sterlin|ポンド|파운드"),
    ("yensign", "yen|иена, йена|єна|yen|yen|yen|yen|iene|yen|円|엔"),
    ("wonsign", "won|вона|вона|won|won|won|won|won|won|ウォン|원"),
    ("indianrupeesign", "rupee|рупия|рупія|rupie|rupia|roupie|rupia|rupia|rupi|ルピー|루피"),
    ("chineseyuanrenminbisign", "yuan, renminbi|юань|юань|yuan|yuan|yuan|yuan|yuan|yuan|人民元, 元|위안"),
    ("brazilianrealsign", "real|реал|реал|real|real|réal|real|real|real|レアル|헤알"),
    ("polishzlotysign", "zloty|злотый|злотий|zloty|esloti|zloty|zloty|zlóti|zloti|ズウォティ|즐로티"),
    ("larisign", "lari|лари|ларі|lari|lari|lari|lari|lari|lari|ラリ|라리"),
    ("manatsign", "manat|манат|манат|manat|manat|manat|manat|manat|manat|マナト|마나트"),
    ("francsign", "franc|франк|франк|franken|franco|franc|franco|franco|frank|フラン|프랑"),
    ("shekelsign", "shekel|шекель|шекель|schekel|séquel|shekel|shekel|shekel|şekel|シェケル|셰켈"),
    ("dongsign", "dong|донг|донг|dong|dong|dong|dong|dong|dong|ドン|동"),
    ("bahtsign", "baht|бат|бат|baht|baht|baht|baht|baht|baht|バーツ|바트"),
    ("pesosign", "peso|песо|песо|peso|peso|peso|peso|peso|peso|ペソ|페소"),
    ("swedishkronasign norwegiankronesign danishkronesign", "krona, krone|крона|крона|krone|corona|couronne|corona|coroa|kron|クローナ, クローネ|크로나, 크로네"),
]
CONCEPTS += [
    (symbols, "; ".join(f"{lang}: {names}" for lang, names in zip(LANGS, row.split("|"))))
    for symbols, row in CURRENCIES
]


def load_symbols():
    availability = plistlib.load(open(GLYPHS + "name_availability.plist", "rb"))
    releases = availability["year_to_release"]

    def ios(year):
        return tuple(int(part) for part in releases[year]["iOS"].split("."))

    available = {name for name, year in availability["symbols"].items() if ios(year) <= DEPLOYMENT_TARGET}
    keywords = plistlib.load(open(GLYPHS + "symbol_search.plist", "rb"))
    return available, keywords


def resolve(base, available):
    for candidate in (base + ".fill", base):
        if candidate in available:
            return candidate
    return None


def swift_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    available, apple_keywords = load_symbols()
    errors = []
    seen = set()
    groups = []
    base_to_symbol = {}

    for name in FREQUENT:
        if name not in available:
            errors.append(f"frequently used: {name} is not available on iOS 26.0")

    for key, names in GROUPS:
        symbols = []
        for base in names.split():
            symbol = resolve(base, available)
            if symbol is None:
                errors.append(f"{key}: {base} is not available on iOS 26.0")
                continue
            base_to_symbol[base] = symbol
            if symbol in seen:
                continue
            seen.add(symbol)
            symbols.append(symbol)
        groups.append((key, symbols))

    concepts = []
    for symbol_list, terms_text in CONCEPTS:
        symbols = []
        for base in symbol_list.split():
            symbol = base_to_symbol.get(base) or resolve(base, available)
            if symbol is None or symbol not in seen:
                errors.append(f"concept {terms_text[:30]}: {base} is not in the catalog")
                continue
            if symbol not in symbols:
                symbols.append(symbol)
        terms = []
        languages = set()
        for part in terms_text.split(";"):
            lang, _, words = part.strip().partition(":")
            languages.add(lang.strip())
            for word in words.split(","):
                word = word.strip().lower()
                if word and word not in terms:
                    terms.append(word)
        missing = set(LANGS) - languages
        if missing:
            errors.append(f"concept {terms_text[:30]}: missing languages {sorted(missing)}")
        concepts.append((terms, symbols))

    if errors:
        print("\n".join(errors), file=sys.stderr)
        sys.exit(1)

    lines = [
        "//",
        "//  IconCatalog+Data.swift",
        "//  Tenra",
        "//",
        "//  GENERATED by scripts/generate_icon_catalog.py. Do not edit by hand: change the",
        "//  script and run it again. Every symbol is available on iOS 26.0.",
        "//",
        "",
        "import Foundation",
        "",
        "nonisolated extension IconCatalog {",
        "",
        "    static let frequentlyUsed: [String] = [",
        "        " + ", ".join(swift_string(name) for name in FREQUENT),
        "    ]",
        "",
        "    static let groups: [IconCatalogGroup] = [",
    ]
    for key, symbols in groups:
        lines.append(f"        IconCatalogGroup(titleKey: {swift_string(key)}, symbols: [")
        for start in range(0, len(symbols), 6):
            lines.append("            " + ", ".join(swift_string(s) for s in symbols[start:start + 6]) + ",")
        lines.append("        ]),")
    lines += ["    ]", "", "    static let concepts: [IconCatalogConcept] = ["]
    for terms, symbols in concepts:
        lines.append("        IconCatalogConcept(")
        lines.append("            terms: [" + ", ".join(swift_string(t) for t in terms) + "],")
        lines.append("            symbols: [" + ", ".join(swift_string(s) for s in symbols) + "]")
        lines.append("        ),")
    lines += ["    ]", "", "    /// Apple's English search keywords (SF Symbols metadata), per catalog symbol.",
              "    static let appleKeywords: [IconCatalogKeywords] = ["]
    for key, symbols in groups:
        for symbol in symbols:
            words = apple_keywords.get(symbol) or apple_keywords.get(symbol.removesuffix(".fill")) or []
            if words:
                lines.append(f"        IconCatalogKeywords(symbol: {swift_string(symbol)}, words: ["
                             + ", ".join(swift_string(w.lower()) for w in words) + "]),")
    lines += ["    ]", "}", ""]

    with open(OUT, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines))
    total = sum(len(symbols) for _, symbols in groups)
    print(f"wrote {OUT}: {total} icons in {len(groups)} groups, {len(concepts)} concepts")


if __name__ == "__main__":
    main()
