//
//  BLELogger.swift
//  BChat
//
//  Logger for debugging BLE connection status
//

import Foundation
import os.log
import CoreBluetooth

/// Structured logging system for BLE Transport
/// Can be filtered by subsystem and category in the Console.app
final class BLELogger {
    
    // MARK: - Time Formatting
    
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
    
    private static func timePrefix() -> String {
        return "[\(timeFormatter.string(from: Date()))]"
    }
    
    // MARK: - Log Categories
    
    /// Logs for BLE connection and discovery
    static let connection = OSLog(subsystem: "com.bchat.ble", category: "connection")
    
    /// Logs for BLE scanning and advertising
    static let scanning = OSLog(subsystem: "com.bchat.ble", category: "scanning")
    
    /// Logs for packet transmission and reception
    static let packet = OSLog(subsystem: "com.bchat.ble", category: "packet")
    
    /// Logs for fragment splitting/reassembly
    static let fragment = OSLog(subsystem: "com.bchat.ble", category: "fragment")
    
    /// Logs for peer management
    static let peer = OSLog(subsystem: "com.bchat.ble", category: "peer")
    
    /// Logs for performance and statistics
    static let performance = OSLog(subsystem: "com.bchat.ble", category: "performance")
    
    /// General BLE logs
    static let general = OSLog(subsystem: "com.bchat.ble", category: "general")
    
    // MARK: - State Tracking
    
    private static var connectionStats: [String: Date] = [:]
    private static var scanningStartTime: Date?
    private static var performanceTrackers: [String: Date] = [:]
    private static let trackerQueue = DispatchQueue(label: "ble.logger.tracker")
    
    // MARK: - Connection Status Logging
    
    /// Log BLE Central Manager state changes
    static func logCentralStateChange(_ state: String) {
        os_log("%@ 🔵 Central Manager State: %@", 
               log: BLELogger.connection, type: .info, timePrefix(), state)
    }
    
    /// Log BLE Peripheral Manager state changes
    static func logPeripheralStateChange(_ state: String) {
        os_log("🟣 Peripheral Manager State: %@", 
               log: BLELogger.connection, type: .info, state)
    }
    
    /// Log device discovery
    static func logDeviceDiscovered(_ name: String, rssi: Int, connectable: Bool) {
        let status = connectable ? "Connectable" : "Not Connectable"
        os_log("📱 Device Discovered: %@ [RSSI: %d, %@]", 
               log: BLELogger.scanning, type: .info, name, rssi, status)
    }
    
    /// Log connection attempts
    static func logConnectionAttempt(_ deviceName: String, _ deviceID: String) {
        os_log("%@ 🔄 Connection Attempt: %@ [%@]", 
               log: BLELogger.connection, type: .info, timePrefix(), deviceName, deviceID)
        connectionStats[deviceID] = Date()
    }
    
    /// Log connection success
    static func logConnectionSuccess(_ deviceName: String, _ deviceID: String) {
        let duration = connectionStats[deviceID]?.timeIntervalSinceNow ?? 0
        let durationMs = abs(duration * 1000)
        os_log("%@ ✅ Connection Success: %@ [%@] (%.0fms)", 
               log: BLELogger.connection, type: .info, timePrefix(), deviceName, deviceID, durationMs)
        connectionStats.removeValue(forKey: deviceID)
    }
    
    /// Log connection failure
    static func logConnectionFailure(_ deviceName: String, _ deviceID: String, error: String?) {
        let duration = connectionStats[deviceID]?.timeIntervalSinceNow ?? 0
        let durationMs = abs(duration * 1000)
        os_log("❌ Connection Failed: %@ [%@] after %.0fms - %@", 
               log: BLELogger.connection, type: .error, deviceName, deviceID, durationMs, error ?? "Unknown error")
        connectionStats.removeValue(forKey: deviceID)
    }
    
    /// Log disconnection
    static func logDisconnection(_ deviceName: String, _ deviceID: String, reason: String?) {
        if let reason = reason {
            os_log("🔌 Disconnected: %@ [%@] - %@", 
                   log: BLELogger.connection, type: .info, deviceName, deviceID, reason)
        } else {
            os_log("🔌 Disconnected: %@ [%@]", 
                   log: BLELogger.connection, type: .info, deviceName, deviceID)
        }
    }
    
    // MARK: - Scanning Status Logging
    
    /// Log scanning started
    static func logScanningStarted(allowDuplicates: Bool) {
        let mode = allowDuplicates ? "Aggressive Mode" : "Power-saving Mode"
        os_log("🔍 Scanning Started (%@)", 
               log: BLELogger.scanning, type: .info, mode)
        scanningStartTime = Date()
    }
    
    /// Log scanning stopped
    static func logScanningStopped() {
        let duration = scanningStartTime?.timeIntervalSinceNow ?? 0
        let durationSec = abs(duration)
        os_log("⏸️ Scanning Stopped (ran for %.1fs)", 
               log: BLELogger.scanning, type: .info, durationSec)
        scanningStartTime = nil
    }
    
    /// Log advertising started
    static func logAdvertisingStarted(withLocalName: Bool) {
        let privacy = withLocalName ? "Public Name" : "Anonymous Mode"
        os_log("📡 Advertising Started (%@)", 
               log: BLELogger.scanning, type: .info, privacy)
    }
    
    /// Log advertising stopped
    static func logAdvertisingStopped() {
        os_log("📡 Advertising Stopped", 
               log: BLELogger.scanning, type: .info)
    }
    
    // MARK: - Peer Management Logging
    
    /// Log new peer discovered
    static func logNewPeerDiscovered(_ peerID: String, nickname: String) {
        os_log("🆕 New Peer: %@ [%@]", 
               log: BLELogger.peer, type: .info, nickname, String(peerID.prefix(8)))
    }
    
    /// Log peer reconnected
    static func logPeerReconnected(_ peerID: String, nickname: String) {
        os_log("🔄 Peer Reconnected: %@ [%@]", 
               log: BLELogger.peer, type: .info, nickname, String(peerID.prefix(8)))
    }
    
    /// Log peer disconnected
    static func logPeerDisconnected(_ peerID: String, nickname: String) {
        os_log("📤 Peer Disconnected: %@ [%@]", 
               log: BLELogger.peer, type: .info, nickname, String(peerID.prefix(8)))
    }
    
    /// Log peer status update
    static func logPeerStats(connected: Int, total: Int) {
        os_log("📊 Peer Status: %d connected, %d total", 
               log: BLELogger.peer, type: .debug, connected, total)
    }
    
    // MARK: - Packet Logging
    
    /// Log packet sent
    static func logPacketSent(type: String, size: Int, to: String?) {
        if let destination = to {
            os_log("%@ 📤 Packet Sent: %@ (%d bytes) → %@", 
                   log: BLELogger.packet, type: .debug, timePrefix(), type, size, String(destination.prefix(8)))
        } else {
            os_log("%@ 📤 Packet Broadcast: %@ (%d bytes)", 
                   log: BLELogger.packet, type: .debug, timePrefix(), type, size)
        }
    }
    
    /// Log packet received
    static func logPacketReceived(type: String, size: Int, from: String) {
        os_log("%@ 📥 Packet Received: %@ (%d bytes) ← %@", 
               log: BLELogger.packet, type: .debug, timePrefix(), type, size, String(from.prefix(8)))
    }
    
    /// Special log for Announce packets (due to high frequency)
    static func logAnnouncePacket(from: String, nickname: String, isNew: Bool) {
        let status = isNew ? "NEW" : "UPDATE"
        os_log("📢 Announce [%@]: %@ [%@]", 
               log: BLELogger.packet, type: .debug, status, nickname, String(from.prefix(8)))
    }
    
    // MARK: - Fragment Logging
    
    /// Log fragment send start
    static func logFragmentSendStart(id: String, count: Int, totalSize: Int) {
        os_log("📦 Fragment Send Start: %@ (%d fragments, %d bytes)", 
               log: BLELogger.fragment, type: .info, String(id.prefix(8)), count, totalSize)
    }
    
    /// Log individual fragment sent
    static func logFragmentSend(id: String, index: Int, total: Int, size: Int) {
        os_log("📤 Sending fragment %d/%d - ID: %@ (%d bytes)",
               log: BLELogger.fragment, type: .info,
               index + 1, total, String(id.prefix(8)), size)
    }
    
    /// Log fragment send complete
    static func logFragmentSendComplete(id: String, count: Int, totalSize: Int) {
        os_log("✅ Fragment Send Complete: %@ (%d fragments, %d bytes)", 
               log: BLELogger.fragment, type: .info, String(id.prefix(8)), count, totalSize)
    }
    
    /// Log fragment receive progress
    static func logFragmentReceiveProgress(id: String, received: Int, total: Int) {
        let progress = (received * 100) / total
        os_log("📦 Fragment Progress: %@ (%d%% - %d/%d)", 
               log: BLELogger.fragment, type: .debug, String(id.prefix(8)), progress, received, total)
    }
    
    /// Log fragment assembly complete
    static func logFragmentAssemblyComplete(id: String, size: Int, duration: TimeInterval) {
        os_log("✅ Fragment Complete: %@ (%d bytes in %.0fms)", 
               log: BLELogger.fragment, type: .info, String(id.prefix(8)), size, duration * 1000)
    }
    
    /// Log fragment timeout
    static func logFragmentTimeout(id: String, received: Int, total: Int) {
        os_log("⏰ Fragment Timeout: %@ (%d/%d received)", 
               log: BLELogger.fragment, type: .error, String(id.prefix(8)), received, total)
    }
    
    // MARK: - Performance Measurement
    
    /// Start performance tracking
    static func startPerformanceTracking(_ identifier: String) {
        trackerQueue.async {
            performanceTrackers[identifier] = Date()
        }
    }
    
    /// End performance tracking and log
    static func endPerformanceTracking(_ identifier: String, operation: String) {
        trackerQueue.async {
            guard let startTime = performanceTrackers.removeValue(forKey: identifier) else {
                os_log("⚠️ Performance tracker not found: %@", 
                       log: BLELogger.performance, type: .error, identifier)
                return
            }
            
            let duration = Date().timeIntervalSince(startTime)
            let durationMs = duration * 1000
            
            os_log("⏱️ %@ completed in %.2fms", 
                   log: BLELogger.performance, type: .info, operation, durationMs)
        }
    }
    
    /// Log throughput statistics
    static func logThroughput(operation: String, bytesPerSecond: Double) {
        os_log("📈 Throughput - %@: %.2f bytes/sec", 
               log: BLELogger.performance, type: .info, operation, bytesPerSecond)
    }
    
    // MARK: - System Status Logging
    
    /// Log system status summary
    static func logSystemStatus(connections: Int, fragments: Int, processedMessages: Int, uptime: TimeInterval) {
        let uptimeMin = uptime / 60
        os_log("📊 System Status - Connections: %d, Fragments: %d, Messages: %d (Uptime: %.1fm)", 
               log: BLELogger.performance, type: .info, connections, fragments, processedMessages, uptimeMin)
    }
    
    /// Log memory usage
    static func logMemoryUsage(peers: Int, fragments: Int, messages: Int) {
        os_log("🧠 Memory Usage - Peers: %d, Active Fragments: %d, Cached Messages: %d", 
               log: BLELogger.performance, type: .debug, peers, fragments, messages)
    }
}

// MARK: - Convenience Extensions

extension BLELogger {
    /// General info log
    static func info(_ message: String, category: OSLog = BLELogger.general) {
        os_log("%@ ℹ️ %@", log: category, type: .info, timePrefix(), message)
    }
    
    /// Debug log
    static func debug(_ message: String, category: OSLog = BLELogger.general) {
        os_log("%@ 🐛 %@", log: category, type: .debug, timePrefix(), message)
    }
    
    /// Error log
    static func error(_ message: String, category: OSLog = BLELogger.general) {
        os_log("%@ ❌ %@", log: category, type: .error, timePrefix(), message)
    }
    
    /// Fault log
    static func fault(_ message: String, category: OSLog = BLELogger.general) {
        os_log("%@ 💥 %@", log: category, type: .fault, timePrefix(), message)
    }
}

// MARK: - Debugging Helpers

extension BLELogger {
    /// Debug helper to log BLE state snapshot
    static func logBLEDebugSnapshot(
        centralState: String,
        peripheralState: String,
        isScanning: Bool,
        isAdvertising: Bool,
        connectedDevices: Int,
        discoveredPeers: Int
    ) {
        os_log("🔍 BLE DEBUG SNAPSHOT:", log: BLELogger.general, type: .info)
        os_log("  Central: %@", log: BLELogger.general, type: .info, centralState)
        os_log("  Peripheral: %@", log: BLELogger.general, type: .info, peripheralState)
        os_log("  Scanning: %@", log: BLELogger.general, type: .info, isScanning ? "YES" : "NO")
        os_log("  Advertising: %@", log: BLELogger.general, type: .info, isAdvertising ? "YES" : "NO")
        os_log("  Connected: %d devices", log: BLELogger.general, type: .info, connectedDevices)
        os_log("  Discovered: %d peers", log: BLELogger.general, type: .info, discoveredPeers)
    }
    
    /// Log peer list for debugging
    static func logPeerList(_ peers: [(id: String, nickname: String)]) {
        os_log("👥 PEER LIST (%d total):", log: BLELogger.peer, type: .info, peers.count)
        for peer in peers {
            os_log("  🟢 %@ [%@]", log: BLELogger.peer, type: .info, 
                   peer.nickname, String(peer.id.prefix(8)))
        }
    }
}

// MARK: - Extensions for String Descriptions

extension CBManagerState {
    var description: String {
        switch self {
        case .unknown: return "Unknown"
        case .resetting: return "Resetting"
        case .unsupported: return "Unsupported"
        case .unauthorized: return "Unauthorized"
        case .poweredOff: return "PoweredOff"
        case .poweredOn: return "PoweredOn"
        @unknown default: return "Unknown(\(rawValue))"
        }
    }
}
