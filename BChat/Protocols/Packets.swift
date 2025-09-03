//
//  Packets.swift
//  BChat
//
//  Created by hs on 9/1/25.
//

import Foundation

// MARK: - Announcement Packet

/// Announcement packet for peer discovery and identity
struct AnnouncementPacket {
	let nickname: String
	let peerID: String
	
	private enum TLVType: UInt8 {
		case nickname = 0x01
		// TODO: - 일단 암호화 프로토콜없이 PeerID 전송
		case peerID = 0x02
	}
	
	init(nickname: String, peerID: String) {
		self.nickname = nickname
		self.peerID = peerID
	}
	
	/// Encode announcement to TLV binary data
	func encode() -> Data? {
		guard let nicknameData = nickname.data(using: .utf8),
					nicknameData.count <= 255,
					let peerIDData = peerID.data(using: .utf8),
					peerIDData.count <= 255 else { return nil }
		
		var data = Data()
		
		// Nickname TLV
		data.append(TLVType.nickname.rawValue)
		data.append(UInt8(nicknameData.count))
		data.append(nicknameData)
		
		// PeerID TLV
		data.append(TLVType.peerID.rawValue)
		data.append(UInt8(peerIDData.count))
		data.append(peerIDData)
		
		return data
	}
	
	/// Decode announcement from TLV binary data
	static func decode(from data: Data) -> AnnouncementPacket? {
		var offset = 0
		var nickname: String?
		var peerID: String?
		
		while offset + 2 <= data.count {
			let type = data[offset]
			let length = Int(data[offset + 1])
			offset += 2
			
			guard offset + length <= data.count else { break }
			
			let value = data.subdata(in: offset..<offset+length)
			
			if let tlvType = TLVType(rawValue: type) {
				switch tlvType {
				case .nickname:
					nickname = String(data: value, encoding: .utf8)
				case .peerID:
					peerID = String(data: value, encoding: .utf8)
				}
			}
			
			offset += length
		}
		
		guard let nick = nickname, let pid = peerID else { return nil }
		
		return AnnouncementPacket(nickname: nick, peerID: pid)
	}
}
