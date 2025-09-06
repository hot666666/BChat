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
	@State private var showSidebar: Bool = false
	
	
	var body: some View {
		GeometryReader { geometry in
			HStack(spacing: 0) {
				// Main content
				VStack(spacing: 0) {
					// Header
					HeaderView(nickname: $nickname, chatViewModel: chatViewModel, showSidebar: $showSidebar)
						.frame(height: 30)
					
					Divider()
					
					// Messages area
					MessagesView(chatViewModel: chatViewModel)
					
					// Input area
					InputView(messageText: $messageText, chatViewModel: chatViewModel)
				}
				
				// Sidebar
				if showSidebar {
					SidebarView(chatViewModel: chatViewModel, showSidebar: $showSidebar)
						.frame(width: min(250, geometry.size.width * 0.3))
						.transition(.move(edge: .trailing))
				}
			}
		}
		.background(Color.black)
		.animation(.easeInOut(duration: 0.3), value: showSidebar)
	}
}

// MARK: - Header View
struct HeaderView: View {
	@Binding var nickname: String
	@ObservedObject var chatViewModel: ChatViewModel
	@Binding var showSidebar: Bool
	
	var body: some View {
		HStack {
			// Left side - App name and channel
			VStack(alignment: .leading, spacing: 0) {
				HStack {
					Text("Bchat/")
						.font(.system(size: 18, weight: .medium))
						.foregroundColor(.green)
					
					TextField("anon", text: $nickname)
						.font(.system(size: 18, weight: .medium))
						.foregroundColor(.primary)
						.textFieldStyle(.plain)
						.onSubmit {
							chatViewModel.setNickname(nickname)
						}
				}
			}
			
			Spacer()
			
			// Right side - People count and menu
			HStack(spacing: 12) {
				Button(action: {
					showSidebar.toggle()
				}) {
					HStack(spacing: 10) {
						Text("#mesh")
							.font(.system(size: 14))
							.foregroundColor(.blue)
						HStack(spacing: 4) {
							Image(systemName: "person.2.fill")
								.font(.system(size: 12))
							Text("\(chatViewModel.connectedPeers.count)")
								.font(.system(size: 14, weight: .medium))
						}
					}
					.foregroundColor(.primary)
				}
				.buttonStyle(.plain)
			}
			.contentShape(.rect)
		}
		.padding(.horizontal, 16)
		.padding(.vertical, 12)
		.background(Color.clear)
	}
}

// MARK: - Messages View
struct MessagesView: View {
	@ObservedObject var chatViewModel: ChatViewModel
	
	var body: some View {
		ScrollViewReader { proxy in
			ScrollView {
				LazyVStack(alignment: .leading, spacing: 16) {
					if chatViewModel.receivedMessages.isEmpty {
						VStack(spacing: 8) {
							Text("nobody around...")
								.foregroundColor(.secondary)
								.font(.system(size: 16))
						}
						.frame(maxWidth: .infinity, maxHeight: .infinity)
						.padding(.top, 100)
					} else {
						ForEach(chatViewModel.receivedMessages) { message in
							MessageBubble(message: message)
								.id(message.id)
						}
					}
				}
				.padding(.horizontal, 16)
				.padding(.top, 8)
			}
			.onChange(of: chatViewModel.receivedMessages.count) { _ in
				if let lastMessage = chatViewModel.receivedMessages.last {
					withAnimation(.easeInOut(duration: 0.3)) {
						proxy.scrollTo(lastMessage.id, anchor: .bottom)
					}
				}
			}
		}
	}
}

// MARK: - Input View
struct InputView: View {
	@Binding var messageText: String
	@ObservedObject var chatViewModel: ChatViewModel
	
	var body: some View {
		VStack(spacing: 0) {
			Divider()
			
			HStack(spacing: 12) {
				TextField("type a message...", text: $messageText)
					.textFieldStyle(.plain)
					.padding(.vertical, 12)
					.onSubmit {
						sendMessage()
					}
				
				Button(action: sendMessage) {
					Image(systemName: "arrow.up.circle.fill")
						.font(.system(size: 24))
						.foregroundColor(.blue)
				}
				.buttonStyle(.plain)
				.disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 8)
		}
		.background(Color.clear)
	}
	
	private func sendMessage() {
		guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
		chatViewModel.sendMessage(messageText)
		messageText = ""
	}
}

// MARK: - Sidebar View
struct SidebarView: View {
	@ObservedObject var chatViewModel: ChatViewModel
	@Binding var showSidebar: Bool
	
	var body: some View {
		VStack(spacing: 0) {
			// Header
			HStack {
				Text("PEOPLE")
					.font(.system(size: 14, weight: .semibold))
					.foregroundColor(.secondary)
				
				Spacer()
				
				Button(action: {
					showSidebar = false
				}) {
					Image(systemName: "xmark")
						.font(.system(size: 12, weight: .medium))
						.foregroundColor(.secondary)
				}
				.buttonStyle(.plain)
			}
			.padding(.horizontal, 16)
			.frame(height: 30)
			
			Divider()
			
			// People list
			ScrollView {
				LazyVStack(alignment: .leading, spacing: 12) {
					ForEach(chatViewModel.connectedPeers, id: \.self) { peerID in
						PeerRow(peerID: peerID, nickname: chatViewModel.peerNicknames[peerID] ?? "anon")
					}
					
					if chatViewModel.connectedPeers.isEmpty {
						Text("No peers connected")
							.font(.system(size: 14))
							.foregroundColor(.secondary)
							.padding(.top, 20)
					}
				}
				.padding(.horizontal, 16)
				.padding(.top, 8)
			}
			
			Spacer()
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.background(Color.clear)
		.overlay(
			Rectangle()
				.frame(width: 1)
				.foregroundColor(Color.separator)
				.offset(x: -0.5),
			alignment: .leading
		)
	}
}

// MARK: - Peer Row
struct PeerRow: View {
	let peerID: String
	let nickname: String
	
	var body: some View {
		HStack(spacing: 12) {
			Circle()
				.frame(width: 8, height: 8)
				.foregroundColor(.green)
			
			Text(nickname)
				.font(.system(size: 14))
				.foregroundColor(.primary)
			
			Spacer()
		}
		.padding(.vertical, 6)
		.contentShape(Rectangle())
	}
}


struct MessageBubble: View {
	let message: ChatMessage
	
	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			if !message.isFromSelf && !message.content.isEmpty {
				HStack(spacing: 6) {
					Text(message.senderNickname)
						.font(.system(size: 14, weight: .medium))
						.foregroundColor(.primary)
					
					Spacer()
				}
				.padding(.leading, 4)
			}
			
			if !message.content.isEmpty {
				Text(message.content)
					.font(.system(size: 16))
					.foregroundColor(.primary)
					.padding(.horizontal, 12)
					.padding(.vertical, 8)
					.background(
						message.isFromSelf ?
						Color.blue.opacity(0.15) :
						Color.secondarySystemBackground
					)
					.cornerRadius(12)
			}
		}
		.frame(maxWidth: .infinity, alignment: message.isFromSelf ? .trailing : .leading)
	}
}
