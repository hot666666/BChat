//
//  TimebasedDeduplicator.swift
//  BChat
//
//  Created by Claude Code on 9/4/25.
//

import Foundation

/// Time-based message deduplicator with automatic cleanup
/// Inspired by BitChat's efficient deduplication approach
final class TimebasedDeduplicator {
    
    // MARK: - Configuration
    
    private let windowDuration: TimeInterval
    private let maxEntries: Int
    
    // MARK: - Storage
    
    private var entries: [String: Date] = [:]
    private var lastCleanupTime: Date = Date()
    private let cleanupInterval: TimeInterval = 10.0 // Clean up every 10 seconds
    
    // MARK: - Initialization
    
    init(windowDuration: TimeInterval = 30.0, maxEntries: Int = 1000) {
        self.windowDuration = windowDuration
        self.maxEntries = maxEntries
    }
    
    // MARK: - Public Methods
    
    /// Check if message ID is duplicate
    /// - Parameter messageID: Unique message identifier
    /// - Returns: true if duplicate, false if new
    func isDuplicate(_ messageID: String) -> Bool {
        performPeriodicCleanup()
        return entries.keys.contains(messageID)
    }
    
    /// Mark message as processed
    /// - Parameter messageID: Unique message identifier
    func markProcessed(_ messageID: String) {
        entries[messageID] = Date()
        
        // Emergency cleanup if too many entries
        if entries.count > maxEntries {
            performEmergencyCleanup()
        }
    }
    
    /// Check if contains message (alias for isDuplicate)
    /// - Parameter messageID: Unique message identifier
    /// - Returns: true if contains, false otherwise
    func contains(_ messageID: String) -> Bool {
        return isDuplicate(messageID)
    }
    
    /// Reset all entries (for emergency situations)
    func reset() {
        entries.removeAll()
        lastCleanupTime = Date()
    }
    
    /// Get current statistics
    /// - Returns: (entryCount, oldestEntry age in seconds)
    func getStats() -> (entryCount: Int, oldestEntryAge: TimeInterval?) {
        let count = entries.count
        let oldestAge = entries.values.min()?.timeIntervalSinceNow.magnitude
        return (count, oldestAge)
    }
    
    // MARK: - Private Methods
    
    /// Perform periodic cleanup based on time window
    private func performPeriodicCleanup() {
        let now = Date()
        
        // Only clean up periodically to avoid performance impact
        guard now.timeIntervalSince(lastCleanupTime) >= cleanupInterval else {
            return
        }
        
        let cutoffTime = now.addingTimeInterval(-windowDuration)
        let initialCount = entries.count
        
        entries = entries.filter { $0.value > cutoffTime }
        
        lastCleanupTime = now
        
        let removedCount = initialCount - entries.count
        if removedCount > 0 {
            BLELogger.debug("🧹 Deduplicator cleanup: removed \(removedCount) old entries, \(entries.count) remaining", category: BLELogger.performance)
        }
    }
    
    /// Emergency cleanup when entries exceed maximum
    private func performEmergencyCleanup() {
        let targetSize = maxEntries / 2
        let sortedEntries = entries.sorted { $0.value < $1.value }
        let entriesToKeep = Array(sortedEntries.suffix(targetSize))
        
        entries = Dictionary(uniqueKeysWithValues: entriesToKeep)
        lastCleanupTime = Date()
        
        BLELogger.debug("⚡ Emergency deduplicator cleanup: kept newest \(targetSize) entries", category: BLELogger.performance)
    }
}
