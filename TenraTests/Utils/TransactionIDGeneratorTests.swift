//
//  TransactionIDGeneratorTests.swift
//  AIFinanceManagerTests
//
//  Created on 2024
//

import Testing
@testable import AIFinanceManager

struct TransactionIDGeneratorTests {
    
    @Test("Generate ID for same transaction produces same ID")
    func testSameTransactionSameID() {
        let date = "2024-01-15"
        let description = "Test transaction"
        let amount = 100.0
        let type = TransactionType.expense
        let currency = "USD"
        
        let id1 = TransactionIDGenerator.generateID(
            date: date,
            description: description,
            amount: amount,
            type: type,
            currency: currency
        )
        
        let id2 = TransactionIDGenerator.generateID(
            date: date,
            description: description,
            amount: amount,
            type: type,
            currency: currency
        )
        
        #expect(id1 == id2)
    }
    
    @Test("Generate ID for different transactions produces different IDs")
    func testDifferentTransactionsDifferentIDs() {
        let date = "2024-01-15"
        let description = "Test transaction"
        let amount = 100.0
        let type = TransactionType.expense
        let currency = "USD"
        
        let id1 = TransactionIDGenerator.generateID(
            date: date,
            description: description,
            amount: amount,
            type: type,
            currency: currency
        )
        
        let id2 = TransactionIDGenerator.generateID(
            date: date,
            description: description,
            amount: amount + 1.0, // Different amount
            type: type,
            currency: currency
        )
        
        #expect(id1 != id2)
    }
    
    @Test("Generate ID for different types produces different IDs")
    func testDifferentTypesDifferentIDs() {
        let date = "2024-01-15"
        let description = "Test transaction"
        let amount = 100.0
        let currency = "USD"
        
        let id1 = TransactionIDGenerator.generateID(
            date: date,
            description: description,
            amount: amount,
            type: .expense,
            currency: currency
        )
        
        let id2 = TransactionIDGenerator.generateID(
            date: date,
            description: description,
            amount: amount,
            type: .income,
            currency: currency
        )
        
        #expect(id1 != id2)
    }
    
    @Test("Generate ID handles empty description")
    func testEmptyDescription() {
        let id = TransactionIDGenerator.generateID(
            date: "2024-01-15",
            description: "",
            amount: 100.0,
            type: .expense,
            currency: "USD"
        )
        
        #expect(!id.isEmpty)
    }
}
