//
//  Data+Extension.swift
//  BChat
//
//  Created by hs on 9/3/25.
//

import Foundation

extension Data {
	/// Create data from hex string
	init?(hexString: String) {
		let cleanHex = hexString.replacingOccurrences(of: " ", with: "")
		guard cleanHex.count % 2 == 0 else { return nil }
		
		var data = Data()
		var index = cleanHex.startIndex
		
		while index < cleanHex.endIndex {
			let nextIndex = cleanHex.index(index, offsetBy: 2)
			let byteString = String(cleanHex[index..<nextIndex])
			guard let byte = UInt8(byteString, radix: 16) else { return nil }
			data.append(byte)
			index = nextIndex
		}
		
		self = data
	}
	
	/// Convert data to hex string representation
	func hexEncodedString() -> String {
		return map { String(format: "%02x", $0) }.joined()
	}
}
