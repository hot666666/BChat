import Foundation
import Compression

// MARK: - Compression Utility
/// - https://github.com/permissionlesstech/bitchat/blob/main/bitchat/Utils/CompressionUtil.swift

struct CompressionUtil {
    static let compressionThreshold = TransportConfig.compressionThresholdBytes

    static func compress(_ data: Data) -> Data? {
        // Skip compression for small data
        guard data.count >= compressionThreshold else {
            return nil
        }

        // zlib's worst-case scenario requires a slightly larger buffer than the original.
        let maxCompressedSize = data.count + (data.count / 255) + 16
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: maxCompressedSize)
        defer { destinationBuffer.deallocate() }

        let compressedSize = data.withUnsafeBytes { sourceBuffer -> Int in
            guard let sourcePtr = sourceBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return 0
            }
            return compression_encode_buffer(
                destinationBuffer,
                maxCompressedSize,
                sourcePtr,
                data.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        // Only consider it a success if compression actually happened and reduced the size.
        guard compressedSize > 0 && compressedSize < data.count else {
            return nil
        }

        return Data(bytes: destinationBuffer, count: compressedSize)
    }

    static func decompress(_ data: Data) -> Data? {
        // Must contain 4-byte size header
        guard data.count >= 4 else { return nil }

        // Extract original size from the first 4 bytes
        let originalSizeData = data.prefix(4)
        let originalSize = Int(UInt32(bigEndian: originalSizeData.withUnsafeBytes { $0.load(as: UInt32.self) }))

        // The rest is the actual compressed data
        let compressedData = data.suffix(from: 4)

        // Allocate buffer with the exact original size
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: originalSize)
        defer { buffer.deallocate() }

        let decompressedSize = compressedData.withUnsafeBytes { bytes in
            compression_decode_buffer(
                buffer, originalSize,
                bytes.bindMemory(to: UInt8.self).baseAddress!, compressedData.count,
                nil, COMPRESSION_ZLIB
            )
        }

        // If decompressed size does not match the original size, fail
        guard decompressedSize == originalSize else {
            return nil
        }
        
        return Data(bytes: buffer, count: decompressedSize)
    }
}
