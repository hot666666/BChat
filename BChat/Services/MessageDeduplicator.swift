//
//  MessageDeduplicator.swift
//  BChat
//
//  Created by hs on 9/3/25.
//

import Foundation

// MARK: - Message Deduplicator

/// Simple message deduplication system
class MessageDeduplicator {
    private var processedMessages = Set<String>()
    private let maxMessages = 1000
    
    func isDuplicate(_ messageID: String) -> Bool {
        return processedMessages.contains(messageID)
    }
    
    func markProcessed(_ messageID: String) {
        processedMessages.insert(messageID)
        
        // Cleanup old messages
        if processedMessages.count > maxMessages {
            let toRemove = processedMessages.prefix(200)
            processedMessages.subtract(toRemove)
        }
    }
    
    func contains(_ messageID: String) -> Bool {
        return processedMessages.contains(messageID)
    }
    
    func reset() {
        processedMessages.removeAll()
    }
}
