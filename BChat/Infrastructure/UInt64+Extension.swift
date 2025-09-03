//
//  UInt64+Extension.swift
//  BChat
//
//  Created by hs on 9/3/25.
//

import Foundation

extension UInt64 {
	/// Current timestamp in milliseconds
	static func currentTimestamp() -> UInt64 {
		return UInt64(Date().timeIntervalSince1970 * 1000)
	}
}
