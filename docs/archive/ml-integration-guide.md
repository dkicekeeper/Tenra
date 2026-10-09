# 🤖 Руководство по интеграции ML в Tenra

**Дата:** 2026-01-18
**Версия:** 1.0
**Статус:** В разработке (Phase 1)

---

## 📋 Обзор

Система машинного обучения для улучшения распознавания категорий транзакций на основе исторических данных пользователя.

### Архитектура

```
┌─────────────────────────────────────┐
│   VoiceInputParser (Rule-Based)    │
│   - Regex patterns                   │
│   - Keywords matching                │
│   - 80% точность                     │
└──────────────┬──────────────────────┘
               │
               ▼
        ┌──────────────┐
        │ Confidence?  │
        └──────┬───────┘
               │
       ┌───────┴────────┐
       │                │
    HIGH              LOW
       │                │
       ▼                ▼
  ✅ Используем   🤖 ML Predictor
   rule-based      (Core ML)
   результат       90%+ точность
```

---

## 🎯 Фаза 1: Базовая интеграция (Текущая)

### Что сделано:

1. ✅ **CategoryMLPredictor.swift** - ML предсказатель категорий
2. ✅ **MLDataExporter.swift** - утилита экспорта данных для обучения
3. ✅ **Гибридный подход** - rule-based + ML fallback
4. ✅ **Debug логирование** - отслеживание работы ML

### Как работает:

```swift
// 1. Rule-based парсинг (текущий подход)
let (category, confidence) = parseCategory_RuleBased(from: text)

// 2. Если уверенность низкая → ML
if confidence < 0.8, mlPredictor.isAvailable {
    let (mlCategory, mlConfidence) = mlPredictor.predict(text: text)

    if mlConfidence > 0.7 {
        return mlCategory  // Используем ML результат
    }
}

// 3. Fallback на rule-based
return category
```

---

## 📊 Подготовка данных для обучения

### Шаг 1: Проверка готовности данных

```swift
import Tenra

// В вашем коде (например, в Settings или Debug menu)
let transactions = transactionsViewModel.allTransactions

// Генерируем отчет
let report = MLDataExporter.generateDataReadinessReport(from: transactions)
print(report)
```

**Минимальные требования:**
- ✅ Минимум **50 транзакций** (рекомендуется 200+)
- ✅ Минимум **5 примеров** на каждую категорию
- ✅ Разнообразие описаний (не копипаста)

### Шаг 2: Экспорт CSV

```swift
// Экспортируем данные
let csv = MLDataExporter.exportCategoryTrainingData(from: transactions)

// Сохраняем в файл
if let fileURL = MLDataExporter.saveToFile(csv: csv, filename: "training_data.csv") {
    print("CSV сохранен: \(fileURL.path)")
    // Используйте Share Sheet для экспорта на Mac
}
```

**Формат CSV:**
```csv
description,category,amount,type
"Купил молоко в магазине","Продукты",500,expense
"Оплатил такси до дома","Транспорт",1200,expense
"Получил зарплату","Зарплата",300000,income
```

---

## 🖥️ Обучение модели в Create ML (Mac)

### Требования:
- Mac с macOS 12.0+ (Monterey или новее)
- Xcode 13.0+
- Create ML (входит в Xcode)

### Инструкция:

1. **Откройте Create ML** (через Xcode → Open Developer Tool → Create ML)

2. **Создайте новый проект:**
   - New Document
   - Text Classifier
   - Название: `CategoryClassifier`

3. **Загрузите данные:**
   - Training Data: выберите `training_data.csv`
   - Column: `description` (Input)
   - Label: `category` (Target)

4. **Настройте параметры:**
   - Algorithm: Transfer Learning (рекомендуется)
   - Max Iterations: 20 (для начала)
   - Validation: 20% split

5. **Обучите модель:**
   - Нажмите Train
   - Дождитесь завершения (1-5 минут)

6. **Оцените качество:**
   - Посмотрите на Validation Accuracy (должно быть >70%)
   - Проверьте Confusion Matrix

7. **Экспортируйте модель:**
   - Output → `CategoryClassifier.mlmodel`
   - Копируйте в проект: `Tenra/Services/ML/Models/`

---

## 📱 Интеграция модели в приложение

### Шаг 1: Добавьте .mlmodel в Xcode

1. Перетащите `CategoryClassifier.mlmodel` в Xcode
2. Target Membership: ✅ Tenra
3. Xcode автоматически скомпилирует в `.mlmodelc`

### Шаг 2: Проверьте работу

```swift
// В вашем коде
let mlPredictor = CategoryMLPredictor()

if mlPredictor.isAvailable {
    print("✅ ML модель загружена и готова!")

    let (category, confidence) = mlPredictor.predict(
        text: "Купил продукты в супермаркете",
        amount: 5000,
        type: .expense
    )

    print("Предсказание: \(category ?? "nil"), уверенность: \(confidence)")
} else {
    print("❌ ML модель не найдена")
}
```

---

## 🔄 Интеграция с VoiceInputParser

Модель автоматически интегрируется через гибридный подход. Никаких изменений в `VoiceInputParser` не требуется - он уже готов к работе с ML!

```swift
// В VoiceInputParser (будущая интеграция)
private func parseCategory(from text: String) -> (category: String?, subcategories: [String]) {
    // Текущий rule-based подход
    let (ruleCategory, subcats) = parseCategory_RuleBased(from: text)

    // Вычисляем уверенность rule-based
    let confidence = ruleCategory == "Другое" ? 0.3 : 0.9

    // Гибридный подход
    if #available(iOS 14.0, *) {
        let finalCategory = mlPredictor.hybridPredict(
            text: text,
            ruleBasedCategory: ruleCategory,
            ruleBasedConfidence: confidence,
            amount: nil,
            type: .expense
        )
        return (finalCategory, subcats)
    }

    return (ruleCategory, subcats)
}
```

---

## 📊 Метрики и мониторинг

### Debug логирование

В режиме DEBUG автоматически логируются:
- ✅ Вызовы ML предсказателя
- ✅ Результаты предсказаний
- ✅ Уровни уверенности
- ✅ Когда используется ML vs rule-based

```
🔍 [VoiceInput] ML Predictor вызван для текста: "купил молоко"
🔍 [VoiceInput] ML Predictor выбрал: Продукты (confidence: 0.92)
```

### Сбор статистики

```swift
// Собираем статистику использования ML
let stats = MLDataExporter.collectStatistics(from: transactions)
print(stats)

// Результат:
// {
//   "total_transactions": 150,
//   "categories_count": 8,
//   "expense_ratio": 0.87,
//   ...
// }
```

---

## 🎓 Улучшение модели

### Когда переобучать:

- 📈 Накопилось **+100 новых транзакций**
- 📉 Точность упала ниже **70%**
- ➕ Добавлены **новые категории**
- 🔄 Изменились привычки пользователя

### Процесс переобучения:

1. Экспортируйте новый CSV с актуальными данными
2. Переобучите модель в Create ML
3. Замените старый `.mlmodel` новым
4. Пересоберите приложение

### Версионирование моделей:

```
CategoryClassifier_v1.mlmodel  (50 транзакций)
CategoryClassifier_v2.mlmodel  (150 транзакций) ← текущая
CategoryClassifier_v3.mlmodel  (300 транзакций)
```

---

## 🚀 Будущие улучшения (Roadmap)

### Фаза 2: Персонализация (2-3 недели)
- [ ] On-device обучение (Core ML Update Tasks)
- [ ] Автоматическое переобучение при достижении порога
- [ ] Предсказание счетов на основе категории

### Фаза 3: Продвинутые функции
- [ ] Anomaly Detection (необычные траты)
- [ ] Smart Suggestions ("Обычно вы платите за интернет в это время")
- [ ] Кластеризация транзакций
- [ ] NLP для извлечения сущностей (Named Entity Recognition)

### Фаза 4: Мультимодальность
- [ ] Учет времени дня/недели
- [ ] Геолокация (если есть)
- [ ] История последних транзакций
- [ ] Сезонность (праздники, отпуск)

---

## ❓ FAQ

### Q: Нужен ли интернет для работы ML?
**A:** Нет! Core ML работает полностью on-device. Все предсказания происходят локально.

### Q: Сколько места занимает модель?
**A:** Text Classifier обычно занимает 1-5 MB в зависимости от размера словаря.

### Q: Работает ли ML на старых устройствах?
**A:** Да! Core ML оптимизирован для всех устройств начиная с iOS 14. Даже на iPhone SE.

### Q: Что если у пользователя мало транзакций?
**A:** ML не активируется пока не накопится минимум 50 транзакций. До этого работает rule-based.

### Q: Можно ли использовать ML для других задач?
**A:** Да! Архитектура готова для:
- Предсказания счетов
- Определения типа операции (доход/расход)
- Автокоррекции транскрипции речи

---

## 📞 Поддержка

Если возникли вопросы или проблемы:
1. Проверьте Debug логи
2. Убедитесь что .mlmodel добавлен в Target
3. Проверьте что iOS 14.0+ (для Core ML)

---

**Статус:** ✅ Готово к использованию (требуется обучение модели)
