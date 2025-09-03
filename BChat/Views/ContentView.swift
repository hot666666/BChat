//
//  ContentView.swift
//  BChat
//
//  Created by hs on 8/29/25.
//

import SwiftUI

struct ContentView: View {
	@StateObject private var chatViewModel = ChatViewModel()
	@State private var messageText: String = ""
	@State private var nickname: String = "anon"
	
	var body: some View {
		VStack {
			// Nickname setup
			HStack {
				TextField("Nickname", text: $nickname)
					.textFieldStyle(RoundedBorderTextFieldStyle())
				Button("Set") {
					chatViewModel.setNickname(nickname)
				}
				.buttonStyle(.bordered)
			}
			.padding()
			
			// Connection status and info
			ConnectionsView()
			
			// Connected peer list
			List(chatViewModel.connectedPeers, id: \.self) { peerID in
				HStack {
					// Display only the first 8 characters of peerID as it can be too long
					Text(chatViewModel.peerNicknames[peerID] ?? "anon")
						.font(.caption)
						.foregroundColor(.gray)
					Spacer()
					Circle()
						.frame(width: 10, height: 10)
						.foregroundColor(.green)
				}
			}
			.frame(height: 100)
			.listStyle(PlainListStyle())
			
			Divider()
			
			// Received messages
			ScrollViewReader { proxy in
				ScrollView {
					LazyVStack(alignment: .leading, spacing: 8) {
						ForEach(chatViewModel.receivedMessages) { message in
							MessageBubble(message: message)
								.id(message.id)
						}
					}
					.padding()
				}
				.onChange(of: chatViewModel.receivedMessages.count) { _ in
					// Scroll to the bottom when a new message is added
					if let lastMessage = chatViewModel.receivedMessages.last {
						withAnimation(.easeInOut(duration: 0.3)) {
							proxy.scrollTo(lastMessage.id, anchor: .bottom)
						}
					}
				}
			}
			
			Spacer()
			
			// Message input and sending
			HStack {
				TextField("Enter message...", text: $messageText)
					.textFieldStyle(RoundedBorderTextFieldStyle())
					.padding(.leading)
				
				Button(action: {
					sendMessage()
				}) {
					Text("Send")
						.padding(.horizontal)
				}
				.padding(.trailing)
			}
			.padding(.bottom)
		}
		.navigationTitle("BitChat")
		.environmentObject(chatViewModel)
	}
	
	private func sendMessage() {
		guard !messageText.isEmpty else { return }
		chatViewModel.sendMessage(messageText)
		messageText = ""
	}
}

struct ConnectionsView: View {
	@EnvironmentObject var chatViewModel: ChatViewModel
	
	var body: some View {
		VStack {
			Text("Connected Devices: \(chatViewModel.connectedPeers.count)")
				.font(.headline)
				.foregroundColor(chatViewModel.connectedPeers.isEmpty ? .red : .green)
				.padding(.top)
			
			// BLE debug button
			Button("🔍 Log BLE Status") {
				chatViewModel.logBLEDebugStatus()
			}
			.font(.caption)
			.padding(.horizontal, 8)
			.padding(.vertical, 4)
			.background(Color.blue.opacity(0.1))
			.foregroundColor(.blue)
			.cornerRadius(6)
		}
	}
}

struct MessageBubble: View {
	let message: ChatMessage
	
	var body: some View {
		HStack {
			if message.isFromSelf {
				Spacer()
			}
			
			VStack(alignment: message.isFromSelf ? .trailing : .leading) {
				if !message.isFromSelf {
					Text(message.senderNickname)
						.font(.caption)
						.foregroundColor(.secondary)
				}
				
				Text(message.content)
					.padding(.horizontal, 12)
					.padding(.vertical, 8)
					.background(message.isFromSelf ? Color.blue : Color.gray.opacity(0.3))
					.foregroundColor(message.isFromSelf ? .white : .primary)
					.cornerRadius(12)
				
				if message.isPrivate {
					Text("🔒 Private")
						.font(.caption2)
						.foregroundColor(.secondary)
				}
			}
			
			if !message.isFromSelf {
				Spacer()
			}
		}
	}
}
