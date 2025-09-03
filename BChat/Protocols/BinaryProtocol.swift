//
//  BinaryProtocol.swift
//  BChat
//
//  Created by hs on 9/1/25.
//

import Foundation

/// Binary protocol for efficient packet encoding/decoding
/// Uses a fixed 13-byte header + variable payload
struct BinaryProtocol {
    
    // MARK: - Constants
    
    private static let headerSize = 13
    
    // MARK: - Flag Bits
    
    private struct Flags {
        static let recipientPresent: UInt8 = 1 << 0  // Bit 0: Recipient ID present
        static let compressed: UInt8 = 1 << 1        // Bit 1: Payload compressed
        // Bits 2-7: Reserved for future use
				// static let signaturePresent: UInt8 = 1 << 2  // Bit 2: Signature present
    }
    
    // MARK: - Encoding
    
    /// Encode a BitchatPacket to binary data
    /// - Parameters:
    ///   - packet: The packet to encode
    ///   - padding: Whether to apply privacy padding
    /// - Returns: Encoded binary data
    static func encode(_ packet: BitchatPacket, padding: Bool = false) -> Data? {
        var data = Data()
        
        // Prepare payload
        var finalPayload = packet.payload
        var flags: UInt8 = 0
        
        // Apply padding if requested
        if padding {
            finalPayload = MessagePadding.pad(finalPayload)
        }
        
        // Apply compression for large payloads
        if finalPayload.count > CompressionUtil.compressionThreshold {
            // 1. Get original size as 4-byte Big Endian
            let originalSize = UInt32(finalPayload.count).bigEndian

            if let compressedPayload = CompressionUtil.compress(finalPayload) {
                // 2. Create new payload: [original_size_info] + [compressed_data]
                var payloadWithHeader = Data()
                payloadWithHeader.append(contentsOf: withUnsafeBytes(of: originalSize) { Data($0) })
                payloadWithHeader.append(compressedPayload)

                // 3. Replace the final payload
                finalPayload = payloadWithHeader
                flags |= Flags.compressed
            }
        }
        
        // Set flags
        if packet.recipientID != nil {
            flags |= Flags.recipientPresent
        }
        
        // Build header (13 bytes)
        data.append(packet.version)                                    // 1 byte
        data.append(packet.type)                                       // 1 byte
        data.append(packet.ttl)                                        // 1 byte
        data.append(contentsOf: withUnsafeBytes(of: packet.timestamp.bigEndian) { Data($0) }) // 8 bytes
        data.append(flags)                                             // 1 byte
        data.append(contentsOf: withUnsafeBytes(of: UInt16(finalPayload.count).bigEndian) { Data($0) }) // 2 bytes
        
        // Add sender ID (always present, 8 bytes)
        guard packet.senderID.count == 8 else { return nil }
        data.append(packet.senderID)
        
        // Add recipient ID if present
        if let recipientID = packet.recipientID {
            guard recipientID.count == 8 else { return nil }
            data.append(recipientID)
        }
        
        // Add payload
        data.append(finalPayload)
        
        return data
    }
    
    // MARK: - Decoding
    
    /// Decode binary data to a BitchatPacket
    /// - Parameter data: Binary data to decode
    /// - Returns: Decoded packet or nil if invalid
    static func decode(_ data: Data) -> BitchatPacket? {
        guard data.count >= headerSize + 8 else { return nil } // Header + sender ID
        
        var offset = 0
        
        // Parse header (13 bytes)
        let _ = data[offset]; offset += 1  // version
        let type = data[offset]; offset += 1
        let ttl = data[offset]; offset += 1
        
        // Parse timestamp (8 bytes, big-endian)
        let timestampData = data.subdata(in: offset..<offset+8)
        let timestamp = UInt64(bigEndian: timestampData.withUnsafeBytes { $0.load(as: UInt64.self) })
        offset += 8
        
        let flags = data[offset]; offset += 1
        
        // Parse payload length (2 bytes, big-endian)
        let payloadLengthData = data.subdata(in: offset..<offset+2)
        let payloadLength = UInt16(bigEndian: payloadLengthData.withUnsafeBytes { $0.load(as: UInt16.self) })
        offset += 2
        
        // Parse sender ID (8 bytes)
        guard offset + 8 <= data.count else { return nil }
        let senderID = data.subdata(in: offset..<offset+8)
        offset += 8
        
        // Parse recipient ID if present
        var recipientID: Data? = nil
        if flags & Flags.recipientPresent != 0 {
            guard offset + 8 <= data.count else { return nil }
            recipientID = data.subdata(in: offset..<offset+8)
            offset += 8
        }
        
        // Parse payload
        guard offset + Int(payloadLength) <= data.count else { return nil }
        var payload = data.subdata(in: offset..<offset+Int(payloadLength))
        offset += Int(payloadLength)
        
        // Decompress payload if compressed
        if flags & Flags.compressed != 0 {
            guard let decompressed = CompressionUtil.decompress(payload) else { return nil }
            payload = decompressed
        }

        return BitchatPacket(
            type: type,
            senderID: senderID,
            recipientID: recipientID,
            timestamp: timestamp,
            payload: payload,
            ttl: ttl
        )
    }
}
