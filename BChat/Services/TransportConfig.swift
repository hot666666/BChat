//
//  TransportConfig.swift
//  BChat
//
//  Created by hs on 9/4/25.
//

import Foundation

// MARK: - Transport Configuration

/// Configuration constants for transport implementations
struct TransportConfig {
    
    static let compressionThresholdBytes = 256
    
    // MARK: - BLE Constants
    
    static let bleDefaultFragmentSize = 150
    static let messageTTLDefault: UInt8 = 8
    static let bleMaxInFlightAssemblies = 10
    static let bleHighDegreeThreshold = 5
    static let bleMaintenanceInterval: TimeInterval = 10.0
    static let bleMaintenanceLeewaySeconds = 2
    static let bleInitialAnnounceDelaySeconds: TimeInterval = 2.0
    static let blePostSubscribeAnnounceDelaySeconds: TimeInterval = 0.5
    static let blePostAnnounceDelaySeconds: TimeInterval = 0.1
    static let bleRestartScanDelaySeconds: TimeInterval = 1.0
    static let bleThreadSleepWriteShortDelaySeconds: TimeInterval = 0.1
    static let bleReconnectLogDebounceSeconds: TimeInterval = 5.0
    static let bleDisconnectNotifyDebounceSeconds: TimeInterval = 2.0
    
    // MARK: - Reachability
    
    static let bleReachabilityRetentionVerifiedSeconds: TimeInterval = 300.0 // 5 minutes
    static let bleReachabilityRetentionUnverifiedSeconds: TimeInterval = 60.0 // 1 minute
    static let blePeerInactivityTimeoutSeconds: TimeInterval = 30.0
    
    // MARK: - Fragment Lifetimes
    
    static let bleFragmentLifetimeSeconds: TimeInterval = 60.0
    static let bleIngressRecordLifetimeSeconds: TimeInterval = 30.0
    static let bleDirectedSpoolWindowSeconds: TimeInterval = 5.0
    
    // MARK: - Connection Management
    
    static let bleMaxCentralLinks = 10
    static let bleConnectRateLimitInterval: TimeInterval = 2.0
    static let bleConnectTimeoutSeconds: TimeInterval = 10.0
    static let bleConnectTimeoutBackoffWindowSeconds: TimeInterval = 30.0
    static let bleConnectionCandidatesMax = 50
    
    // MARK: - RSSI Thresholds
    
    static let bleDynamicRSSIThresholdDefault = -70
    static let bleRSSIIsolatedBase = -75
    static let bleRSSIIsolatedRelaxed = -85
    static let bleRSSIConnectedThreshold = -65
    static let bleRSSIHighTimeoutThreshold = -60
    static let bleWeakLinkRSSICutoff = -80
    static let bleWeakLinkCooldownSeconds: TimeInterval = 15.0
    static let bleRecentTimeoutWindowSeconds: TimeInterval = 30.0
    static let bleRecentTimeoutCountThreshold = 3
    static let bleIsolationRelaxThresholdSeconds: TimeInterval = 60.0
    
    // MARK: - Duty Cycle Scanning
    
    static let bleDutyOnDuration: TimeInterval = 10.0
    static let bleDutyOffDuration: TimeInterval = 5.0
    static let bleDutyOnDurationDense: TimeInterval = 5.0
    static let bleDutyOffDurationDense: TimeInterval = 10.0
    static let bleRecentTrafficForceScanSeconds: TimeInterval = 30.0
    
    // MARK: - Announce Intervals
    
    static let bleAnnounceMinInterval: TimeInterval = 3.0
    static let bleAnnounceIntervalSeconds: TimeInterval = 10.0
    static let bleConnectedAnnounceBaseSecondsSparse: TimeInterval = 30.0
    static let bleConnectedAnnounceJitterSparse: TimeInterval = 15.0
    static let bleConnectedAnnounceBaseSecondsDense: TimeInterval = 60.0
    static let bleConnectedAnnounceJitterDense: TimeInterval = 30.0
    static let bleForceAnnounceMinIntervalSeconds: TimeInterval = 1.0
    
    // MARK: - Packet Timing
    
    static let bleRecentPacketWindowSeconds: TimeInterval = 10.0
    static let bleRecentPacketWindowMaxCount = 100
    static let bleFragmentSpacingMs = 5
    static let bleFragmentSpacingDirectedMs = 2
    static let bleExpectedWritePerFragmentMs = 8
    static let bleExpectedWriteMaxMs = 500
    
    // MARK: - Queue Management
    
    static let blePendingNotificationsCapCount = 50
    static let blePendingWriteBufferCapBytes = 4096
}
