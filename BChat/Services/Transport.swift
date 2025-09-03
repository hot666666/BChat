//
//  Transport.swift
//  BChat
//
//  Created by hs on 9/1/25.
//

import Foundation

// MARK: - Transport Protocol

/// Abstract transport interface for Bitchat communication
protocol Transport: AnyObject {
    
    // MARK: - Identity
    
    /// My peer ID (8-byte identifier)
    var myPeerID: String { get }
    
    /// My nickname
    var myNickname: String { get set }
    
    // MARK: - Lifecycle
    
    /// Start transport services
    func startServices()
    
    /// Stop transport services
    func stopServices()
    
    // MARK: - Peer Management
    
    /// Get all connected peer nicknames
    func getPeerNicknames() -> [String: String]
    
    // MARK: - Messaging
    
    /// Send public broadcast message
    func sendMessage(_ content: String)
    
    /// Send broadcast announce
    func sendBroadcastAnnounce()

    
    // MARK: - Delegates
    
    /// Main delegate for UI events
    var delegate: BitchatDelegate? { get set }
    
}

// MARK: - Peer ID Utilities

/// Utilities for peer ID generation and validation
struct PeerIDUtils {
    
    /// Derive short peer ID from public key (first 16 hex chars)
    static func derivePeerID(fromPublicKey publicKey: Data) -> String {
        let fullHex = publicKey.hexEncodedString()
        return String(fullHex.prefix(16))
    }
    
    /// Validate peer ID format
    static func isValidPeerID(_ peerID: String) -> Bool {
        return peerID.count == 16 && peerID.allSatisfy { $0.isHexDigit }
    }
    
    /// Generate random peer ID (for testing)
    static func generateRandomPeerID() -> String {
        let bytes = (0..<8).map { _ in UInt8.random(in: 0...255) }
        return Data(bytes).hexEncodedString()
    }
}
