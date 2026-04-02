//
//  CoreDataIndexes.swift
//  AIFinanceManager
//
//  Core Data Indexes configuration
//  Используется для программного добавления индексов, если GUI в Xcode недоступен

import Foundation
import CoreData

/// Утилита для создания индексов в Core Data
struct CoreDataIndexes {
    
    /// Добавить индексы к существующей модели (если не добавлены через GUI)
    /// Вызывать ТОЛЬКО если индексов нет в .xcdatamodeld файле
    static func addIndexesIfNeeded(to model: NSManagedObjectModel) {
        // На данный момент индексы добавляются через GUI в Xcode
        // Этот метод оставлен для будущего использования
        
        // Пример добавления индекса программно (не рекомендуется):
        /*
        if let transactionEntity = model.entitiesByName["TransactionEntity"] {
            // Создать индекс для date + type
            let dateTypeIndex = NSFetchIndexDescription(name: "dateTypeIndex", elements: [
                NSFetchIndexElementDescription(property: transactionEntity.propertiesByName["date"]!, collationType: .binary),
                NSFetchIndexElementDescription(property: transactionEntity.propertiesByName["type"]!, collationType: .binary)
            ])
            
            transactionEntity.indexes.append(dateTypeIndex)
        }
        */
        
    }
    
    /// Оптимизированные fetch requests с явным указанием, какие поля использовать для сортировки/фильтрации
    /// Эти запросы будут использовать индексы автоматически, если они созданы
    static func optimizedTransactionFetchRequest() -> NSFetchRequest<TransactionEntity> {
        let request = TransactionEntity.fetchRequest()
        
        // Core Data автоматически использует индексы для:
        // 1. Предикатов на индексированных полях
        // 2. Sort descriptors на индексированных полях
        
        // Сортировка по индексированному полю (date)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        
        // Batch size для pagination
        request.fetchBatchSize = 50
        
        return request
    }
    
    /// Fetch request для поиска по дате и типу (использует составной индекс)
    static func fetchTransactions(
        from startDate: Date,
        to endDate: Date,
        type: String? = nil
    ) -> NSFetchRequest<TransactionEntity> {
        let request = TransactionEntity.fetchRequest()
        
        var predicates: [NSPredicate] = []
        
        // Предикат по дате (использует индекс)
        predicates.append(NSPredicate(format: "date >= %@ AND date <= %@", startDate as NSDate, endDate as NSDate))
        
        // Предикат по типу (использует индекс)
        if let type = type {
            predicates.append(NSPredicate(format: "type == %@", type))
        }
        
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        request.fetchBatchSize = 50
        
        return request
    }
    
    /// Fetch request для поиска по счету (использует relationship)
    static func fetchTransactions(forAccountId accountId: String) -> NSFetchRequest<TransactionEntity> {
        let request = TransactionEntity.fetchRequest()
        
        request.predicate = NSPredicate(format: "account.id == %@", accountId)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        request.fetchBatchSize = 50
        
        return request
    }
    
    /// Fetch request для поиска по категории (использует индекс)
    static func fetchTransactions(forCategory category: String) -> NSFetchRequest<TransactionEntity> {
        let request = TransactionEntity.fetchRequest()
        
        request.predicate = NSPredicate(format: "category == %@", category)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        request.fetchBatchSize = 50
        
        return request
    }
    
    /// Статистика по использованию индексов (для debugging)
    static func printIndexStatistics(context: NSManagedObjectContext) {
        // Получить описание модели
        guard let model = context.persistentStoreCoordinator?.managedObjectModel else {
            return
        }
        
        
        for (_, entity) in model.entitiesByName {

            if !entity.indexes.isEmpty {
                for index in entity.indexes {
                    _ = index.elements.compactMap { $0.property?.name }.joined(separator: ", ")
                }
            }
        }
    }
}

// MARK: - Performance Tips

/*
 🎯 Советы по производительности без явных индексов:
 
 1. **Используйте NSFetchedResultsController**
    - Автоматический кэш запросов
    - Эффективное управление памятью
    - Автоматические обновления UI
 
 2. **Batch Size**
    - Всегда устанавливайте fetchBatchSize для больших запросов
    - Core Data будет загружать данные порциями
 
 3. **Фильтрация на уровне базы данных**
    - Используйте NSPredicate вместо filter() в Swift
    - Core Data оптимизирует запросы автоматически
 
 4. **Prefetching relationships**
    - Используйте relationshipKeyPathsForPrefetching
    - Избегайте N+1 проблемы
 
 5. **Фоновые контексты**
    - Тяжелые операции выполняйте в background context
    - Не блокируйте UI thread
 
 Пример оптимизированного запроса:
 
 ```swift
 let request = TransactionEntity.fetchRequest()
 request.predicate = NSPredicate(format: "date >= %@ AND type == %@", startDate, "expense")
 request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
 request.fetchBatchSize = 50
 request.relationshipKeyPathsForPrefetching = ["account", "recurringSeries"]
 
 let results = try context.fetch(request)
 ```
 
 Core Data автоматически оптимизирует этот запрос на уровне SQLite,
 даже без явных индексов!
 */
