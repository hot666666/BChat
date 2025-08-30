//
//  ContentView.swift
//  BChat
//
//  Created by hs on 8/29/25.
//

import SwiftUI

struct ContentView: View {
	@EnvironmentObject var bluetoothManager: BluetoothManager
	
	@State private var messageText: String = ""
	
	var body: some View {
		VStack {
			// 연결 상태 및 정보
			ConnectionsView()
			
			// 연결된 피어 목록
			List(bluetoothManager.connectedPeers, id: \.self) { peerID in
				HStack {
					// peerID가 너무 길 수 있으므로 앞 8자리만 표시
					Text(peerID.prefix(8))
						.font(.caption)
						.foregroundColor(.gray)
					Spacer()
					Circle()
						.frame(width: 10, height: 10)
						.foregroundColor(.green)
				}
			}
			.frame(height: 100) // 목록의 높이 제한
			.listStyle(PlainListStyle()) // 기본 리스트 스타일
			
			Divider()
			
			// 수신된 메시지
			ScrollView {
				VStack(alignment: .leading) {
					Text(bluetoothManager.receivedMessage)
						.padding()
						.background(Color.gray.opacity(0.2))
						.cornerRadius(8)
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding()
			}
			
			Spacer()
			
			// 메시지 입력 및 전송
			HStack {
				TextField("메시지를 입력하세요...", text: $messageText)
					.textFieldStyle(RoundedBorderTextFieldStyle())
					.padding(.leading)
				
				Button(action: {
					sendMessage()
				}) {
					Text("전송")
						.padding(.horizontal)
				}
				.padding(.trailing)
			}
			.padding(.bottom)
		}
		.navigationTitle("Bluetooth Chat")
	}
	
	private func sendMessage() {
		bluetoothManager.sendMessage(message: messageText)
		messageText = ""
	}
}

struct ConnectionsView: View {
	@EnvironmentObject var bluetoothManager: BluetoothManager
	
	var body: some View {
		VStack {
			Text("연결된 기기: \(bluetoothManager.connectedPeers.count)대")
				.font(.headline)
				.foregroundColor(bluetoothManager.connectedPeers.isEmpty ? .red : .green)
				.padding(.top)
		}
	}
}
