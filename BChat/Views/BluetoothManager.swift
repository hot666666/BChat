//
//  BluetoothManager.swift
//  BChat
//
//  Created by hs on 8/29/25.
//

import CoreBluetooth
import SwiftUI


final class BluetoothManager: NSObject, ObservableObject {
	// 블루투스 통신용 UUID (서비스와 특성 모두 동일)
	private let serviceUUID = CBUUID(string: "BD609DB8-2406-4CAE-B1C8-A249B84019CC")
	private let characteristicUUID = CBUUID(string: "BD609DB8-2406-4CAE-B1C8-A249B84019CC")
	
	// 블루투스 매니저 (Central: 스캔/연결, Peripheral: 광고/서비스 제공)
	private var centralManager: CBCentralManager!
	private var peripheralManager: CBPeripheralManager!
		
	// 메시지 송수신용 특성
	private var transferCharacteristic: CBMutableCharacteristic?
	
	// 연결 관리 설정
	private let maxConnections = 5
	private let connectionRetryInterval: TimeInterval = 10.0
	
	// 적응형 스캔 설정
	private var scanInterval: TimeInterval = 15.0    // 15초마다 스캔
	private var scanDuration: TimeInterval = 5.0     // 5초간 스캔
	private var scanTimer: Timer?
	private var stopScanTimer: Timer?
	private var isCurrentlyScanning = false
	
	// 연결 타임아웃 타이머들
	private var connectionTimers: [UUID: Timer] = [:]

	// MARK: - 연결 상태 추적 및 관리
	
	// 다중 연결 관리 시스템
	private var connections: [UUID: PeerConnectionState] = [:]
	private var peerIDToConnectionID: [String: UUID] = [:]

	
	// MARK: - UI 표시용
	
	// 현재 연결된 기기 목록 (UUID 문자열)
	@Published var connectedPeers: [String] = []
	// 수신 메시지
	@Published var receivedMessage: String = ""
	
	override init() {
		super.init()
		
		// 시스템 알림 활성화 옵션
		let options = [CBCentralManagerOptionShowPowerAlertKey: true]
		// Central 및 Peripheral 매니저 초기화
		centralManager = CBCentralManager(delegate: self, queue: nil, options: options)
		peripheralManager = CBPeripheralManager(delegate: self, queue: nil, options: options)
	}
	
	deinit {
		stopPeriodicScanning()
		connectionTimers.values.forEach { $0.invalidate() }
		connectionTimers.removeAll()
	}
	
	// MARK: - 연결 관리 헬퍼 메서드
	
	private func generatePeerID(for peripheral: CBPeripheral) -> String {
		return peripheral.identifier.uuidString
	}
	
	private func generatePeerID(for central: CBCentral) -> String {
		return central.identifier.uuidString
	}
	
	private func isAlreadyConnectedOrConnecting(peerID: String) -> Bool {
		return peerIDToConnectionID[peerID] != nil
	}
	
	private func canAcceptNewConnection() -> Bool {
		let connectedCount = connections.values.filter { $0.isConnected }.count
		return connectedCount < maxConnections
	}
	
	private func updateConnectedPeersList() {
		DispatchQueue.main.async {
			self.connectedPeers = self.connections.values
				.filter { $0.isConnected }
				.map { $0.peerID }
		}
	}
	
	// MARK: - 적응형 스캔 전략 관리
	
	private func updateScanStrategy() {
		let connectedCount = connections.values.filter { $0.isConnected }.count
		
		if connectedCount == 0 {
			// Discovery Mode: 연결 없음 - 적극적 스캔
			scanDuration = 8.0      // 더 길게 스캔
			scanInterval = 10.0     // 더 자주 스캔
			print("📡 Discovery 모드: 적극적 스캔")
		} else {
			// Maintenance Mode: 연결 있음 - 보존적 스캔
			scanDuration = 3.0      // 짧게 스캔
			scanInterval = 20.0     // 덜 자주 스캔
			print("🔋 Maintenance 모드: 보존적 스캔")
		}
		
		// 현재 스캔 중이면 재시작해서 새 설정 적용
		if isCurrentlyScanning {
			stopCurrentScan()
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
				self.startScanCycle()
			}
		}
	}
	
	// MARK: - 주기적 스캔 관리
	
	private func startPeriodicScanning() {
		stopPeriodicScanning() // 기존 타이머 정리
		
		// 즉시 첫 번째 스캔 시작
		startScanCycle()
		
		// 주기적 스캔 타이머 시작
		scanTimer = Timer.scheduledTimer(withTimeInterval: scanInterval, repeats: true) { [weak self] _ in
			self?.startScanCycle()
		}
		
		print("🔄 주기적 스캔 시작 (간격: \(scanInterval)초, 지속: \(scanDuration)초)")
	}
	
	private func stopPeriodicScanning() {
		scanTimer?.invalidate()
		scanTimer = nil
		stopScanTimer?.invalidate()
		stopScanTimer = nil
		
		if isCurrentlyScanning {
			centralManager?.stopScan()
			isCurrentlyScanning = false
		}
		
		print("⏹️ 주기적 스캔 중지")
	}
	
	private func startScanCycle() {
		// 최대 연결 수에 도달했으면 스캔 중지
		guard canAcceptNewConnection() else {
			print("⚠️ 최대 연결 수 도달, 스캔 생략")
			return
		}
		
		// 이미 스캔 중이면 무시
		guard !isCurrentlyScanning else { return }
		
		print("🔍 스캔 사이클 시작")
		isCurrentlyScanning = true
		centralManager?.scanForPeripherals(withServices: [serviceUUID])
		
		// 지정된 시간 후 스캔 중지
		stopScanTimer = Timer.scheduledTimer(withTimeInterval: scanDuration, repeats: false) { [weak self] _ in
			self?.stopCurrentScan()
		}
	}
	
	private func stopCurrentScan() {
		guard isCurrentlyScanning else { return }
		
		centralManager?.stopScan()
		isCurrentlyScanning = false
		print("⏸️ 스캔 사이클 완료")
	}
}

// MARK: - Peripheral은 자신의 존재를 외부에 알리고(서비스 Advertising), 다른 기기(Central)의 연결을 수락
// 서버느낌으로, Central의 구독을 감지하고 이를 새로운 연결 채널의 개통으로 간주하여 connections에 등록
extension BluetoothManager: CBPeripheralManagerDelegate {
	
	// MARK: - 서비스 등록 및 광고 시작
	
	func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
		if peripheral.state == .poweredOn {
			print("Peripheral: 블루투스 켜짐, 광고 시작")
			
			// 메시지 송수신용 특성 생성
			transferCharacteristic = CBMutableCharacteristic(
				type: characteristicUUID,
				properties: [.notify, .writeWithoutResponse, .write],
				value: nil,
				permissions: [.readable, .writeable]
			)
			
			// 서비스 생성 후 광고 시작
			let service = CBMutableService(type: serviceUUID, primary: true)
			service.characteristics = [transferCharacteristic!]
			peripheralManager.add(service)
			peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [serviceUUID]])
			
		} else {
			print("Peripheral: 블루투스 꺼짐 또는 문제 발생")
		}
	}
	
	// MARK: - Central의 쓰기 요청 처리
	
	func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
		for request in requests {
			if let value = request.value, let message = String(data: value, encoding: .utf8) {
				DispatchQueue.main.async {
					self.receivedMessage = message
					print("💬 메시지 수신: \(message)")
				}
			}
			
			// 쓰기 요청에 대한 응답 (필요한 경우)
			if request.characteristic.uuid == characteristicUUID {
				peripheral.respond(to: request, withResult: .success)
			}
		}
	}
	
	// MARK: - Central의 구독을 새 연결로 등록(Peripheral)
	
	func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
		let peerID = generatePeerID(for: central)
		print("🔔 \(peerID) 기기가 알림 구독 시작 (Peripheral 역할)")
		
		// 새 연결 수용 가능한지 확인
		guard canAcceptNewConnection() else {
			print("❌ 최대 연결 수 초과, 구독 거부")
			return
		}
		
		// 이미 연결된 기기인지 확인
		if isAlreadyConnectedOrConnecting(peerID: peerID) {
			print("⚠️ 이미 연결된 기기의 구독 요청 - 연결 상태 업데이트")
			if let connectionID = peerIDToConnectionID[peerID] {
				connections[connectionID]?.isConnected = true
			}
		} else {
			// 새 연결 추가
			let connectionID = UUID()
			let connectionState = PeerConnectionState(central: central, peerID: peerID)
			
			connections[connectionID] = connectionState
			peerIDToConnectionID[peerID] = connectionID
			
			print("📝 새 구독자 추가. 총 연결: \(connections.count)개")
		}
		
		updateConnectedPeersList()
		updateScanStrategy() // Peripheral 연결 시 스캔 전략 업데이트
	}
	
	// MARK: - Central의 알림 구독 해제
	
	func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
		let peerID = generatePeerID(for: central)
		print("🔕 \(peerID) 기기가 알림 구독 해제")
		
		// 연결 제거
		if let connectionID = peerIDToConnectionID[peerID] {
			connections.removeValue(forKey: connectionID)
			peerIDToConnectionID.removeValue(forKey: peerID)
			print("📝 연결 제거 완료. 총 연결: \(connections.count)개")
		}
		
		updateConnectedPeersList()
		updateScanStrategy() // Peripheral 연결 해제 시 스캔 전략 업데이트
	}
}

// MARK: - Central은 주변의 다른 기기(Peripheral)를 탐색(Scanning)하고, 연결을 요청
// 클라이언트 느낌으로, Peripheral에 보낸 연결 요청이 성공했을 때, 이를 연결 채널의 확립으로 보고 connections에 등록 및 connect 수행
extension BluetoothManager: CBCentralManagerDelegate, CBPeripheralDelegate {
	// MARK: - 스캔 및 연결 관리
	func centralManagerDidUpdateState(_ central: CBCentralManager) {
		if central.state == .poweredOn {
			print("Central: 블루투스 켜짐, 주기적 스캔 시작")
			startPeriodicScanning()
		} else {
			print("Central: 블루투스 꺼짐 또는 문제 발생")
			stopPeriodicScanning()
		}
	}
	
	// MARK: - 주변 기기 발견 시 연결 시도 및 상태 기록(Central)
	
	func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
		let peerID = generatePeerID(for: peripheral)
		
		// 최대 연결 수 확인
		guard canAcceptNewConnection() else {
			print("⚠️ 최대 연결 수 초과, \(peerID) 연결 시도 무시")
			return
		}
		
		// 이미 연결 시도 중이거나 연결된 기기인지 확인
		if isAlreadyConnectedOrConnecting(peerID: peerID) {
			return // 조용히 무시
		}
		
		// 연결 재시도 간격 확인
		if let connectionID = peerIDToConnectionID[peerID],
			 let lastAttempt = connections[connectionID]?.lastConnectionAttempt,
			 Date().timeIntervalSince(lastAttempt) < connectionRetryInterval {
			print("⚠️ \(peerID) 연결 재시도 간격 미충족")
			return
		}
		
		print("기기 발견: \(peripheral.name ?? "Unknown")(\(peerID)), 연결 시도 중...")
		
		// 새 연결 상태 생성
		let connectionID = UUID()
		var connectionState = PeerConnectionState(peripheral: peripheral, peerID: peerID)
		connectionState.isConnecting = true
		
		connections[connectionID] = connectionState
		peerIDToConnectionID[peerID] = connectionID
		
		// 연결 시도
		centralManager.connect(peripheral, options: nil)
		
		// 15초 후 연결 타임아웃 처리
		let timer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: false) { [weak self] _ in
			self?.handleConnectionTimeout(connectionID: connectionID)
		}
		connectionTimers[connectionID] = timer
	}
	
	// MARK: - 연결 성공 시 서비스 탐색 시작
	
	func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
		let peerID = generatePeerID(for: peripheral)
		print("✅ 기기 연결 성공 (Central 역할): \(peripheral.name ?? "Unknown")(\(peerID))")
		
		// 연결 상태 업데이트
		if let connectionID = peerIDToConnectionID[peerID] {
			connectionTimers[connectionID]?.invalidate()
			connectionTimers.removeValue(forKey: connectionID)
			
			connections[connectionID]?.isConnecting = false
			connections[connectionID]?.isConnected = true
		}
		
		// Delegate 설정 = Peripheral에서 이벤트 발생 시, Self의 CBPeripheralDelegate에서 처리
		peripheral.delegate = self
		peripheral.discoverServices([serviceUUID])
		
		updateConnectedPeersList()
		updateScanStrategy() // 연결 성공 시 스캔 전략 업데이트
		print("✅ 연결 설정 완료, 서비스 탐색 시작")
	}
	
	// MARK: - 연결 실패 시 다시 스캔 시작
	
	func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
		let peerID = generatePeerID(for: peripheral)
		print("❌ 연결 실패: \(peripheral.name ?? "Unknown")(\(peerID)), 에러: \(error?.localizedDescription ?? "알 수 없음")")
		
		// 연결 상태 정리
		if let connectionID = peerIDToConnectionID[peerID] {
			connectionTimers[connectionID]?.invalidate()
			connectionTimers.removeValue(forKey: connectionID)
			connections.removeValue(forKey: connectionID)
			peerIDToConnectionID.removeValue(forKey: peerID)
		}
		
		updateConnectedPeersList()
		updateScanStrategy() // 연결 실패 시 스캔 전략 업데이트
	}
	
	// MARK: - 연결 해제 시 처리
	
	func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
		let peerID = generatePeerID(for: peripheral)
		print("🔌 연결 해제 (Central 역할): \(peripheral.name ?? "Unknown")(\(peerID))")
		
		// 연결 상태 정리
		if let connectionID = peerIDToConnectionID[peerID] {
			connectionTimers[connectionID]?.invalidate()
			connectionTimers.removeValue(forKey: connectionID)
			connections.removeValue(forKey: connectionID)
			peerIDToConnectionID.removeValue(forKey: peerID)
		}
		
		updateConnectedPeersList()
		updateScanStrategy() // 연결 해제 시 스캔 전략 업데이트
		
		// 의도치 않은 연결 해제인 경우에만 재연결 대기
		if let error = error {
			print("⚠️ 예상치 못한 연결 해제: \(error.localizedDescription)")
		} else {
			print("✅ 정상적인 연결 해제")
		}
		
		// 주기적 스캔이 자동으로 재연결 시도함
	}
	
	// 연결 타임아웃 처리 (새 버전)
	private func handleConnectionTimeout(connectionID: UUID) {
		guard let connection = connections[connectionID] else { return }
		
		print("⏰ 연결 타임아웃: \(connection.peerID)")
		
		if let peripheral = connection.peripheral {
			centralManager.cancelPeripheralConnection(peripheral)
		}
		
		// 연결 상태 정리
		connectionTimers.removeValue(forKey: connectionID)
		connections.removeValue(forKey: connectionID)
		peerIDToConnectionID.removeValue(forKey: connection.peerID)
		
		updateConnectedPeersList()
	}
	
	// MARK: - Peripheral Delegate
	
	// 서비스 발견 후 특성 탐색
	func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
		guard let services = peripheral.services else { return }
		for service in services {
			peripheral.discoverCharacteristics([characteristicUUID], for: service)
		}
	}
	
	// 특성 발견 완료 (메시지 송신 준비 완료)
	func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
		let peerID = generatePeerID(for: peripheral)
		guard let characteristics = service.characteristics,
					let connectionID = peerIDToConnectionID[peerID] else { return }
		
		for characteristic in characteristics {
			if characteristic.uuid == characteristicUUID {
				// 연결별로 쓰기용 특성 저장
				if characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse) {
					connections[connectionID]?.writeCharacteristic = characteristic
					print("📝 \(peerID) 쓰기 특성 발견 및 저장 완료")
				}
				
				// 읽기/알림용 특성이면 구독 설정
				if characteristic.properties.contains(.notify) {
					peripheral.setNotifyValue(true, for: characteristic)
					print("🔔 \(peerID) 알림 구독 설정 완료")
				}
			}
		}
		
		print("✅ \(peerID) 양방향 통신 준비 완료")
	}
	
	// 특성 값 변경 알림 수신 (실시간 메시지 수신)
	func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
		guard characteristic.uuid == characteristicUUID,
					let data = characteristic.value,
					let message = String(data: data, encoding: .utf8) else { return }
		
		DispatchQueue.main.async {
			self.receivedMessage = message
			print("💬 실시간 메시지 수신: \(message)")
		}
	}
	
	// 쓰기 완료 콜백 (전송 성공/실패 확인용)
	func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
		if let error = error {
			print("❌ 메시지 전송 실패: \(error.localizedDescription)")
		} else {
			print("✅ 메시지 전송 성공")
		}
	}
}

// MARK: - 메시지 송수신 메서드 (Central/Peripheral 역할 모두 지원)
extension BluetoothManager {
	// 통합 메시지 전송 (다중 연결 지원)
	func sendMessage(message: String) {
		let connectedConnections = connections.values.filter { $0.isConnected }
		
		guard !connectedConnections.isEmpty else {
			print("❌ 전송 실패: 연결된 기기가 없음")
			return
		}
		
		print("📡 \(connectedConnections.count)개 연결로 메시지 전송: \(message)")
		
		// Central 연결로 전송
		sendMessageToCentralConnections(message: message)
		// Peripheral 연결로 전송
		sendMessageToPeripheralConnections(message: message)
	}
	
	// Central 역할 연결들로 메시지 전송
	private func sendMessageToCentralConnections(message: String) {
		let centralConnections = connections.values.filter { 
			$0.isConnected && $0.peripheral != nil && $0.writeCharacteristic != nil 
		}
		
		guard let data = message.data(using: .utf8) else { return }
		
		for connection in centralConnections {
			guard let peripheral = connection.peripheral,
				  let characteristic = connection.writeCharacteristic,
				  peripheral.state == .connected else { continue }
			
			let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
			peripheral.writeValue(data, for: characteristic, type: writeType)
			
			print("📤 메시지 전송 (Central→\(connection.peerID)): \(message)")
		}
	}
	
	// Peripheral 역할 연결들로 메시지 전송
	private func sendMessageToPeripheralConnections(message: String) {
		let peripheralConnections = connections.values.filter { 
			$0.isConnected && $0.central != nil 
		}
		
		guard !peripheralConnections.isEmpty,
			  let characteristic = transferCharacteristic,
			  let data = message.data(using: .utf8) else { return }
		
		// 연결된 Central들 추출
		let subscribedCentrals = peripheralConnections.compactMap { $0.central }
		
		// 모든 구독자에게 notify 전송
		let success = peripheralManager.updateValue(data, for: characteristic, onSubscribedCentrals: subscribedCentrals)
		
		if success {
			print("📤 메시지 전송 (Peripheral→\(peripheralConnections.count)개 Central): \(message)")
		} else {
			print("❌ Notify 전송 실패: 큐가 가득참 또는 기타 오류")
		}
	}
}

// MARK: - 연결 상태 추적 구조체

struct PeerConnectionState {
	let peripheral: CBPeripheral?
	let central: CBCentral?
	var isConnecting: Bool
	var isConnected: Bool
	let peerID: String
	var writeCharacteristic: CBCharacteristic?
	var lastConnectionAttempt: Date?
	
	// Central 연결용 생성자
	init(peripheral: CBPeripheral, peerID: String) {
		self.peripheral = peripheral
		self.central = nil
		self.isConnecting = false
		self.isConnected = false
		self.peerID = peerID
		self.writeCharacteristic = nil
		self.lastConnectionAttempt = Date()
	}
	
	// Peripheral 연결용 생성자
	init(central: CBCentral, peerID: String) {
		self.peripheral = nil
		self.central = central
		self.isConnecting = false
		self.isConnected = true // Central이 구독했으면 이미 연결된 상태
		self.peerID = peerID
		self.writeCharacteristic = nil
		self.lastConnectionAttempt = nil
	}
}
