//
//  BChatApp.swift
//  BChat
//
//  Created by hs on 8/29/25.
//

import SwiftUI

@main
struct BChatApp: App {
	@StateObject private var bluetoothManager = BluetoothManager()
	
	var body: some Scene {
		WindowGroup {
			ContentView()
				.environmentObject(bluetoothManager)
		}
	}
}
