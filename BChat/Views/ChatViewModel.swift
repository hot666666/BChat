//
//  ChatViewModel.swift
//  BChat
//
//  Created by hs on 9/6/25.
//

import SwiftUI

// MARK: - ChatMessage Model

struct ChatMessage: Identifiable, Equatable {
	let id: String
	let content: String
	let senderID: String
	let senderNickname: String
	let timestamp: Date
	let isFromSelf: Bool
	let isPrivate: Bool
	
	init(id: String, content: String, senderID: String, senderNickname: String, timestamp: Date, isFromSelf: Bool, isPrivate: Bool = false) {
		self.id = id
		self.content = content
		self.senderID = senderID
		self.senderNickname = senderNickname
		self.timestamp = timestamp
		self.isFromSelf = isFromSelf
		self.isPrivate = isPrivate
	}
}

// MARK: - ChatViewModel

@MainActor
class ChatViewModel: ObservableObject, BitchatDelegate {
	@Published var connectedPeers: [String] = []
	@Published var peerNicknames: [String: String] = [:]
	@Published var receivedMessages: [ChatMessage] = []
	
	private let bleService = BLEService()
	
	init() {
		bleService.delegate = self
		bleService.startServices()
		
	}
	
	deinit {
		bleService.stopServices()
	}
	
	// MARK: - Public Methods
	
	func sendMessage(_ content: String) {
		print("🔵 UI SEND MESSAGE: content='\(content)', length=\(content.count) chars")
		let messageID = UUID().uuidString
		bleService.sendMessage(content)
		
		// Add to our messages as sent
		let message = ChatMessage(
			id: messageID,
			content: content,
			senderID: bleService.myPeerID,
			senderNickname: bleService.myNickname,
			timestamp: Date(),
			isFromSelf: true
		)
		receivedMessages.append(message)
	}
	
	func setNickname(_ nickname: String) {
		bleService.myNickname = nickname
		bleService.sendBroadcastAnnounce()
	}
	
	func logBLEDebugStatus() {
		bleService.logBLEDebugStatus()
	}
	
	// MARK: - BitchatDelegate
	
	func didReceivePublicMessage(from peerID: String, nickname: String, content: String, timestamp: Date) {
		let message = ChatMessage(
			id: UUID().uuidString,
			content: content,
			senderID: peerID,
			senderNickname: nickname,
			timestamp: timestamp,
			isFromSelf: false
		)
		
		receivedMessages.append(message)
	}
	
	func didConnectToPeer(_ peerID: String) {
		if !connectedPeers.contains(peerID) {
			connectedPeers.append(peerID)
		}
		updatePeerNicknames()
	}
	
	func didDisconnectFromPeer(_ peerID: String) {
		connectedPeers.removeAll { $0 == peerID }
		updatePeerNicknames()
	}
	
	func didUpdatePeerList(_ peerIDs: [String]) {
		connectedPeers = peerIDs
		updatePeerNicknames()
	}
	
	// MARK: - Private Methods
	
	private func updatePeerNicknames() {
		peerNicknames = bleService.getPeerNicknames()
	}
}
