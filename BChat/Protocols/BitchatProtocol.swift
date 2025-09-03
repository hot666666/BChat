//
//  BitchatProtocol.swift
//  BChat
//
//  Created by hs on 9/4/25.
//

import Foundation

// MARK: - Message Padding

/// Privacy-preserving message padding using PKCS#7-style approach
struct MessagePadding {
	static let blockSizes = [256, 512, 1024, 2048]
	
	/// Add padding to data to obscure message length
	static func pad(_ data: Data) -> Data {
		guard !data.isEmpty else { return data }
		
		// Find the smallest block size that can contain the data
		let targetSize = blockSizes.first { $0 >= data.count } ?? blockSizes.last!
		let paddingLength = targetSize - data.count
		
		guard paddingLength > 0 else { return data }
		
		var paddedData = data
		let paddingByte = UInt8(paddingLength)
		paddedData.append(contentsOf: Array(repeating: paddingByte, count: paddingLength))
		
		return paddedData
	}
	
	/// Remove padding from data
	static func unpad(_ data: Data) -> Data? {
		guard !data.isEmpty else { return data }
		
		let paddingLength = Int(data.last!)
		guard paddingLength > 0 && paddingLength <= data.count else { return data }
		
		// Verify padding is valid (all padding bytes should be the same)
		let paddingStart = data.count - paddingLength
		for i in paddingStart..<data.count {
			guard data[i] == data.last! else { return data }
		}
		
		return data.dropLast(paddingLength)
	}
}

// MARK: - Message Types

/// Message types supported by the Bitchat protocol
enum MessageType: UInt8, CaseIterable {
	case announce = 1    // Peer presence announcement
	case message = 2     // Public broadcast message
	case leave = 3       // Peer leaving network
	case fragment = 4    // Message fragment
	
	var description: String {
		switch self {
		case .announce: return "Announce"
		case .message: return "Message"
		case .leave: return "Leave"
		case .fragment: return "Fragment"
		}
	}
}

// MARK: - Core Packet Structure

/// Core packet structure for the Bitchat protocol
struct BitchatPacket {
    let version: UInt8 = 1  // 1 byte
    let type: UInt8         // 1 byte
    var ttl: UInt8          // 1 byte
    let senderID: Data	 		// 8 bytes
    let recipientID: Data?  // 8 bytes, nil for broadcast
    let timestamp: UInt64		// 8 bytes
    let payload: Data
    
    init(type: UInt8, senderID: Data, recipientID: Data? = nil, 
         timestamp: UInt64, payload: Data, ttl: UInt8 = 8) {
        self.type = type
        self.ttl = ttl
        self.senderID = senderID
        self.recipientID = recipientID
        self.timestamp = timestamp
        self.payload = payload
    }
    
    /// Generate unique message ID for deduplication
    func messageID() -> String {
        let senderHex = senderID.hexEncodedString()
        return "\(senderHex)-\(timestamp)-\(type)"
    }
    
    /// Create complete binary representation
    func toBinaryData(padding: Bool = false) -> Data? {
        return BinaryProtocol.encode(self, padding: padding)
    }
}

// MARK: - Delegate Protocol

/// Delegate protocol for Bitchat events
@MainActor
protocol BitchatDelegate: AnyObject {
    // Message handling
    func didReceivePublicMessage(from peerID: String, nickname: String, content: String, timestamp: Date)
    
    // Peer management
    func didConnectToPeer(_ peerID: String)
    func didDisconnectFromPeer(_ peerID: String)
    func didUpdatePeerList(_ peerIDs: [String])
}
