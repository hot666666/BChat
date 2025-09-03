import Foundation
import CoreBluetooth

/// BLE Transport Implementation conforming to BitChat Transport protocol
final class BLEService: NSObject, Transport {

	// MARK: - Constants
	
#if DEBUG
	static let serviceUUID = CBUUID(string: "A47B5E2D-4A9E-4C5A-9B3F-8E1D2C3A4B5A") // testnet
#else
	static let serviceUUID = CBUUID(string: "A47B5E2D-4A9E-4C5A-9B3F-8E1D2C3A4B5C") // mainnet
#endif
	static let characteristicUUID = CBUUID(string: "F1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5D")
	
	// MARK: - Transport Protocol Implementation
	
	var myPeerID: String = ""
	var myNickname: String = "anon" {
		didSet {
			sendBroadcastAnnounce()
		}
	}
	
	weak var delegate: BitchatDelegate?
	
	// MARK: - Core State
	
	private let defaultFragmentSize = TransportConfig.bleDefaultFragmentSize
	private let messageTTL: UInt8 = TransportConfig.messageTTLDefault
	
	// MARK: - BLE Objects
	
	private var centralManager: CBCentralManager?
	private var peripheralManager: CBPeripheralManager?
	private var characteristic: CBMutableCharacteristic?
	
	// MARK: - Peer Management(peripherals)
	
	private struct PeripheralState {
		let peripheral: CBPeripheral
		var characteristic: CBCharacteristic?
		var peerID: String?
		var isConnecting: Bool = false
		var isConnected: Bool = false
		var lastConnectionAttempt: Date? = nil
	}
	private var peripherals: [String: PeripheralState] = [:]  // UUID -> PeripheralState
	private var peerToPeripheralUUID: [String: String] = [:]  // PeerID -> Peripheral UUID
	
	// BLE Centrals (when acting as peripheral)
	private var subscribedCentrals: [CBCentral] = []
	private var centralToPeerID: [String: String] = [:]  // Central UUID -> Peer ID mapping
	
	// Nickname Storage
	private var nicknames: [String: String] = [:]  // PeerID -> Nickname
	
	// Pending Notifications Queue (Bitchat-style)
	private var pendingNotifications: [(data: Data, centrals: [CBCentral])] = []
	private let maxPendingNotifications = 50
	
	// Message Processing
	private let messageDeduplicator = TimebasedDeduplicator(windowDuration: 30.0, maxEntries: 1000)
		
	// Fragment Deduplication (Time-based with memory limits)
	private let fragmentDeduplicator = TimebasedDeduplicator(windowDuration: 60.0, maxEntries: 2000)
	private var fragmentMetadata: [String: (type: UInt8, total: Int, timestamp: Date)] = [:]
	private var sentFragmentIDs: Set<String> = []
	private var incomingFragments: [String: [Int: Data]] = [:]
	
	// Queues
	private let bleQueue = DispatchQueue(label: "ble.service", qos: .userInitiated)
	private let collectionsQueue = DispatchQueue(label: "ble.collections", attributes: .concurrent)
	
	// Connection Budget Management
	private var lastGlobalConnectAttempt: Date = .distantPast
	
	// Announce Throttling
	private var lastAnnounceTime: Date = .distantPast
	private let announceMinInterval: TimeInterval = 2.0
	
	// Periodic Announce (Bitchat-style)
	private var announceTimer: DispatchSourceTimer?
	private let periodicAnnounceInterval: TimeInterval = 30.0 // Every 30 seconds
	
	// Maintenance Timer
	private var maintenanceTimer: Timer?
	
	// Adaptive Scanning
	private var scanningTimer: DispatchSourceTimer?
	private var isInAdaptiveScanning = false
	private var currentScanMode: ScanMode = .normal
	
	// Traffic Tracking for Adaptive Scanning
	private var recentPacketTimestamps: [Date] = []
	
	enum ScanMode {
		case normal     // 10 sec on / 5 sec off
		case dense      // 5sec on / 10sec off (trafic)
		case sparse     // 5sec on / 15sec off (idle)
		
		var durations: (on: TimeInterval, off: TimeInterval) {
			switch self {
			case .normal: return (10.0, 5.0)
			case .dense: return (5.0, 10.0)
			case .sparse: return (5.0, 15.0)
			}
		}
		
		var description: String {
			switch self {
			case .normal: return "Normal"
			case .dense: return "Dense"
			case .sparse: return "Sparse"
			}
		}
	}
	
	
	// MARK: - Initialization
	
	override init() {
		super.init()
		
		// TODO: - 영구 저장된 PeerID 사용 교체
		let deviceID = UUID().uuidString
		self.myPeerID = PeerIDUtils.derivePeerID(fromPublicKey: Data(deviceID.utf8))
		
		// Initialize BLE managers
		centralManager = CBCentralManager(delegate: self, queue: bleQueue)
		peripheralManager = CBPeripheralManager(delegate: self, queue: bleQueue)
		
		setupMaintenanceTimer()
	}
	
	deinit {
		stopServices()
		stopAdaptiveScanning()
		stopPeriodicAnnounce()
	}
	
	// MARK: - Transport Protocol Methods
	
	func startServices() {
		BLELogger.info("🚀 Starting BLE services...", category: BLELogger.general)
		
		bleQueue.async { [weak self] in
			guard let self = self else { return }
			
			// Services will auto-start when managers reach poweredOn state
			if self.centralManager?.state == .poweredOn {
				self.startScanning()
			}
			
			if self.peripheralManager?.state == .poweredOn {
				self.setupPeripheralService()
			}
			
			// Announce will be sent when both managers are ready
			if self.centralManager?.state == .poweredOn && self.peripheralManager?.state == .poweredOn {
				DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
					self?.sendBroadcastAnnounce()
					self?.startPeriodicAnnounce()
				}
			}
		}
	}
	
	func stopServices() {
		let dispatchGroup = DispatchGroup()
		
		// Stop timers first
		maintenanceTimer?.invalidate()
		maintenanceTimer = nil
		stopPeriodicAnnounce()
		stopAdaptiveScanning()
		
		// Send a leave message to all connected peers
		sendLeavePacket()
		
		// Clear delegate reference
		delegate = nil
		
		dispatchGroup.enter()
		bleQueue.async { [weak self] in
			defer { dispatchGroup.leave() }
			guard let self = self else { return }
			
			if self.centralManager?.isScanning == true {
				BLELogger.logScanningStopped()
			}
			if self.peripheralManager?.isAdvertising == true {
				BLELogger.logAdvertisingStopped()
			}
			
			self.centralManager?.stopScan()
			self.peripheralManager?.stopAdvertising()
			
			// Disconnect all peripherals
			for state in self.peripherals.values {
				self.centralManager?.cancelPeripheralConnection(state.peripheral)
			}
		}
		
		dispatchGroup.enter()
		collectionsQueue.async(flags: .barrier) { [weak self] in
			defer { dispatchGroup.leave() }
			guard let self = self else { return }
			
			// Complete resource cleanup
			self.messageDeduplicator.reset()
			self.fragmentDeduplicator.reset()
			self.fragmentMetadata.removeAll()
			self.sentFragmentIDs.removeAll()
			self.incomingFragments.removeAll()
			self.peripherals.removeAll()
			self.peerToPeripheralUUID.removeAll()
			self.centralToPeerID.removeAll()
			self.subscribedCentrals.removeAll()
			self.nicknames.removeAll()
			self.pendingNotifications.removeAll()
			self.recentPacketTimestamps.removeAll()
		}
		
		// Wait for all cleanup operations to complete
		dispatchGroup.wait()
	}
	
	func isPeerConnected(_ peerID: String) -> Bool {
		return getKnownPeerIDs().contains(peerID)
	}
	
	func getPeerNicknames() -> [String: String] {
		var result: [String: String] = [:]
		let knownPeers = getKnownPeerIDs()
		
		for peerID in knownPeers {
			let resolvedNickname = resolveNickname(for: peerID)
			result[peerID] = resolvedNickname
		}
		
		return result
	}
	
	func sendMessage(_ content: String) {
		BLELogger.debug("📤 SEND MESSAGE: content='\(content)', length=\(content.count) chars", category: BLELogger.general)
		
		let payload = Data(content.utf8)
		BLELogger.debug("📤 SEND MESSAGE: payload size=\(payload.count) bytes", category: BLELogger.general)
		
		let packet = BitchatPacket(
			type: MessageType.message.rawValue,
			senderID: Data(hexString: myPeerID) ?? Data(),
			timestamp: UInt64.currentTimestamp(),
			payload: payload,
			ttl: messageTTL
		)
		
		broadcastPacket(packet)
	}
	
	func sendBroadcastAnnounce() {
		// Throttling: minimum interval between announces
		let timeSinceLastAnnounce = Date().timeIntervalSince(lastAnnounceTime)
		guard timeSinceLastAnnounce >= announceMinInterval else {
			BLELogger.debug("🚫 Announce throttled: \(String(format: "%.2f", timeSinceLastAnnounce))s < \(announceMinInterval)s", category: BLELogger.peer)
			return
		}
		
		let announcement = AnnouncementPacket(
			nickname: myNickname,
			peerID: myPeerID
		)
		
		guard let payload = announcement.encode() else { return }
		
		let packet = BitchatPacket(
			type: MessageType.announce.rawValue,
			senderID: Data(hexString: myPeerID) ?? Data(),
			timestamp: UInt64.currentTimestamp(),
			payload: payload,
			ttl: messageTTL
		)
		
		lastAnnounceTime = Date()
		BLELogger.debug("📢 Broadcasting announce: nickname='\(myNickname)', peerID=\(myPeerID.prefix(8))", category: BLELogger.peer)
		broadcastPacket(packet)
	}

	func sendLeavePacket() {
		BLELogger.debug("➡️ Sending leave packet", category: BLELogger.peer)
		let packet = BitchatPacket(
			type: MessageType.leave.rawValue,
			senderID: Data(hexString: myPeerID) ?? Data(),
			timestamp: UInt64.currentTimestamp(),
			payload: Data(),
			ttl: 1 // No need to relay leave packets
		)
		broadcastPacket(packet)
	}

	
	// MARK: - Connection State Helpers
	
	/// Return all known peers (direct connections + announce received)
	private func getKnownPeerIDs() -> [String] {
		var knownIDs: Set<String> = []
		
		// Peers we connected to (Central role)
		for state in peripherals.values {
			if state.isConnected, let peerID = state.peerID {
				knownIDs.insert(peerID)
			}
		}
		
		// Peers connected to us (Peripheral role)
		for peerID in centralToPeerID.values {
			knownIDs.insert(peerID)
		}
		
		// All peers we've received announcements from (Mesh peers)
		for peerID in nicknames.keys {
			knownIDs.insert(peerID)
		}
		
		return Array(knownIDs)
	}
	
	/// Return only directly connected peers (for scanning logic)
	private func getDirectlyConnectedPeerIDs() -> [String] {
		var connectedIDs: Set<String> = []
		
		// Peers we connected to (Central role) - count BLE connections even without PeerID
		for (uuid, state) in peripherals {
			if state.isConnected {
				// Use real PeerID if available, otherwise use UUID as temporary ID
				let id = state.peerID ?? uuid
				connectedIDs.insert(id)
			}
		}
		
		// Peers connected to us (Peripheral role)
		for central in subscribedCentrals {
			let uuid = central.identifier.uuidString
			if let peerID = centralToPeerID[uuid] {
				connectedIDs.insert(peerID) // Use real ID if we have it
			} else {
				connectedIDs.insert(uuid) // Otherwise, use the temporary UUID
			}
		}
		
		return Array(connectedIDs)
	}
	
	/// Adaptively adjust scanning mode based on connection status
	private func updateScanningMode() {
		let connectedCount = getDirectlyConnectedPeerIDs().count
		
		if connectedCount == 0 {
			// Aggressive scanning when no connections
			startAggressiveScanning()
		} else {
			// Adaptive scanning when connected (battery saving for both Central and Peripheral)
			startAdaptiveScanning()
		}
	}
	
	/// Aggressive scanning - before connection
	private func startAggressiveScanning() {
		stopAdaptiveScanning()
		
		if centralManager?.state == .poweredOn && centralManager?.isScanning == false {
			BLELogger.logScanningStarted(allowDuplicates: true)
			centralManager?.scanForPeripherals(
				withServices: [BLEService.serviceUUID],
				options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
			)
		}
	}
	
	/// Adaptive scanning - battery saving after connection
	private func startAdaptiveScanning() {
		guard !isInAdaptiveScanning else { return }
		
		isInAdaptiveScanning = true
		let durations = currentScanMode.durations
		BLELogger.info("🔄 Starting adaptive scanning mode: \(currentScanMode.description) (\(durations.on)s on / \(durations.off)s off)", category: BLELogger.scanning)
		
		// Start first scan
		startScanCycle()
		
		// Setup periodic timer with current mode durations
		let timer = DispatchSource.makeTimerSource(queue: bleQueue)
		let totalCycle = Int(durations.on + durations.off)
		timer.schedule(deadline: .now() + .seconds(totalCycle),
									 repeating: .seconds(totalCycle))
		timer.setEventHandler { [weak self] in
			self?.startScanCycle()
		}
		timer.resume()
		scanningTimer = timer
	}
	
	/// Scan cycle (scan → rest → scan...)
	private func startScanCycle() {
		// Start scan
		if centralManager?.state == .poweredOn {
			let scanDuration = currentScanMode.durations.on
			BLELogger.logScanningStarted(allowDuplicates: false)
			centralManager?.scanForPeripherals(
				withServices: [BLEService.serviceUUID],
				options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
			)
			
			// Stop scan after duration based on current mode
			bleQueue.asyncAfter(deadline: .now() + .seconds(Int(scanDuration))) { [weak self] in
				if self?.centralManager?.isScanning == true {
					BLELogger.logScanningStopped()
					self?.centralManager?.stopScan()
				}
			}
		}
	}
	
	/// Stop adaptive scanning
	private func stopAdaptiveScanning() {
		if isInAdaptiveScanning {
			BLELogger.info("⏹️ Stopping adaptive scanning mode", category: BLELogger.scanning)
			isInAdaptiveScanning = false
			scanningTimer?.cancel()
			scanningTimer = nil
		}
	}
	
	/// Track incoming packet for traffic-based scanning adaptation
	private func trackIncomingPacket() {
		recentPacketTimestamps.append(Date())
		
		// Clean up old timestamps (older than configured window)
		let cutoff = Date().addingTimeInterval(-TransportConfig.bleRecentPacketWindowSeconds)
		recentPacketTimestamps = recentPacketTimestamps.filter { $0 > cutoff }
		
		updateScanningModeBasedOnTraffic()
	}
	
	/// Update scanning mode based on recent traffic and connected peers
	private func updateScanningModeBasedOnTraffic() {
		let recentTrafficCount = recentPacketTimestamps.count
		let connectedPeers = getDirectlyConnectedPeerIDs().count
		
		let newMode: ScanMode
		if recentTrafficCount > 10 || connectedPeers > 5 {
			newMode = .dense  // High traffic: scan more frequently but for shorter periods
		} else if recentTrafficCount < 2 && connectedPeers < 2 {
			newMode = .sparse  // Low traffic: scan less frequently to save battery
		} else {
			newMode = .normal  // Medium traffic: standard scanning
		}
		
		if newMode != currentScanMode {
			currentScanMode = newMode
			BLELogger.info("🔄 Scanning mode changed to \(newMode.description) (traffic: \(recentTrafficCount), peers: \(connectedPeers))", category: BLELogger.scanning)
			
			// Restart adaptive scanning with new mode
			if isInAdaptiveScanning {
				restartAdaptiveScanningWithNewMode()
			}
		}
	}
	
	/// Restart adaptive scanning with current mode settings
	private func restartAdaptiveScanningWithNewMode() {
		stopAdaptiveScanning()
		startAdaptiveScanning()
	}
	
	/// Start periodic announce mechanism (Bitchat-style)
	private func startPeriodicAnnounce() {
		stopPeriodicAnnounce()
		
		let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
		timer.schedule(deadline: .now() + periodicAnnounceInterval, repeating: periodicAnnounceInterval)
		timer.setEventHandler { [weak self] in
			guard let self = self else { return }
			
			// Only announce if we have subscribers or connections
			let hasConnections = !self.subscribedCentrals.isEmpty || !self.peripherals.values.filter { $0.isConnected }.isEmpty
			
			if hasConnections {
				BLELogger.debug("🔔 Periodic announce triggered", category: BLELogger.peer)
				self.sendBroadcastAnnounce()
			}
		}
		timer.resume()
		announceTimer = timer
		
		BLELogger.debug("⏰ Started periodic announce timer (interval: \(periodicAnnounceInterval)s)", category: BLELogger.peer)
	}
	
	/// Stop periodic announce mechanism
	private func stopPeriodicAnnounce() {
		announceTimer?.cancel()
		announceTimer = nil
		BLELogger.debug("⏹️ Stopped periodic announce timer", category: BLELogger.peer)
	}
	
	/// Force announce after new connection (Bitchat-style)
	private func scheduleConnectionBasedAnnounce() {
		DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
			guard let self = self else { return }
			
			let hasConnections = !self.subscribedCentrals.isEmpty || !self.peripherals.values.filter { $0.isConnected }.isEmpty
			
			if hasConnections {
				BLELogger.debug("🔗 Connection-based forced announce", category: BLELogger.peer)
				self.sendBroadcastAnnounce()
			}
		}
	}
	
	/// Clean up fragment data (memory management)
	private func cleanupFragmentData() {
		let now = Date()
		let timeoutInterval: TimeInterval = 30.0
		
		let expiredKeys = fragmentMetadata.compactMap { (key, metadata) -> String? in
			if now.timeIntervalSince(metadata.timestamp) > timeoutInterval {
				BLELogger.logFragmentTimeout(id: key.components(separatedBy: ":").last ?? "anon",
																		 received: incomingFragments[key]?.count ?? 0,
																		 total: metadata.total)
				return key
			}
			return nil
		}
		
		for key in expiredKeys {
			incomingFragments.removeValue(forKey: key)
			fragmentMetadata.removeValue(forKey: key)
		}
		
		if sentFragmentIDs.count > 1000 {
			sentFragmentIDs.removeAll()
		}
	}
	
	
	private func setupMaintenanceTimer() {
		maintenanceTimer = Timer.scheduledTimer(withTimeInterval: TransportConfig.bleMaintenanceInterval, repeats: true) { [weak self] _ in
			self?.performMaintenance()
		}
	}
	
	private func performMaintenance() {
		collectionsQueue.async(flags: .barrier) { [weak self] in
			guard let self = self else { return }
			
			self.cleanupFragmentData()
			
			let now = Date()
			let peerCutoff = now.addingTimeInterval(-TransportConfig.blePeerInactivityTimeoutSeconds)
			var disconnectedPeerIDs: [String] = []
			
			// Clean up peripherals we connected to
			for (uuid, state) in self.peripherals {
				if !state.isConnected && !state.isConnecting {
					// If we haven't seen this peripheral in a while, remove it
					if let lastSeen = state.lastConnectionAttempt, lastSeen < peerCutoff {
						self.peripherals.removeValue(forKey: uuid)
						if let peerID = state.peerID {
							self.peerToPeripheralUUID.removeValue(forKey: peerID)
							disconnectedPeerIDs.append(peerID)
						}
					}
				}
			}
			
			// Notify delegate of disconnected peers
			for peerID in disconnectedPeerIDs {
				DispatchQueue.main.async { [weak self] in
					self?.delegate?.didDisconnectFromPeer(peerID)
				}
			}
		}
	}
	
	private func startScanning() {
		updateScanningMode()
	}
	
	private func setupPeripheralService() {
		guard let peripheral = peripheralManager, peripheral.state == .poweredOn else { return }
		
		// Create characteristic
		characteristic = CBMutableCharacteristic(
			type: BLEService.characteristicUUID,
			properties: [.notify, .write, .writeWithoutResponse],
			value: nil,
			permissions: [.writeable]
		)
		
		// Create service
		let service = CBMutableService(type: BLEService.serviceUUID, primary: true)
		service.characteristics = [characteristic!]
		
		// Add service and start advertising
		peripheral.add(service)
		
		let advertisementData: [String: Any] = [
			CBAdvertisementDataServiceUUIDsKey: [BLEService.serviceUUID]
		]
		
		BLELogger.logAdvertisingStarted(withLocalName: false)
		
		peripheral.startAdvertising(advertisementData)
	}

	private func broadcastPacket(_ packet: BitchatPacket) {
		guard let data = packet.toBinaryData() else {
			BLELogger.error("❌ Failed to encode packet to binary", category: BLELogger.general)
			return
		}
		
		let typeString = MessageType(rawValue: packet.type)?.description ?? "anon(\(packet.type))"
		let recipientID = packet.recipientID?.hexEncodedString()
		
		// Fragment 타입 패킷인지 확인
		if packet.type == MessageType.fragment.rawValue {
			// Fragment 패킷은 항상 직접 전송 (재분할하지 않음)
			BLELogger.debug("📤 FRAGMENT BROADCAST: data=\(data.count) bytes", category: BLELogger.fragment)
			BLELogger.logPacketSent(type: typeString, size: data.count, to: recipientID)
			
			// 중복 방지를 위해 마킹
			let messageID = packet.messageID()
			messageDeduplicator.markProcessed(messageID)
			
			sendData(data)
		} else {
			BLELogger.debug("📤 BROADCAST PACKET: type=\(packet.type), data size=\(data.count) bytes, fragmentSize=\(defaultFragmentSize)", category: BLELogger.general)
			BLELogger.logPacketSent(type: typeString, size: data.count, to: recipientID)
			
			// Check if we need to fragment
			if data.count > defaultFragmentSize {
				BLELogger.debug("📦 FRAGMENTING: data=\(data.count) > threshold=\(defaultFragmentSize)", category: BLELogger.general)
				sendFragmentedPacket(packet)
			} else {
				BLELogger.debug("📤 DIRECT SEND: data=\(data.count) <= threshold=\(defaultFragmentSize)", category: BLELogger.general)
				
				// 중복 방지를 위해 마킹
				let messageID = packet.messageID()
				messageDeduplicator.markProcessed(messageID)
				
				sendData(data)
			}
		}
	}
	
	private func sendData(_ data: Data) {
		bleQueue.async { [weak self] in
			guard let self = self else { return }
			
			// Send to connected peripherals
			for state in self.peripherals.values where state.isConnected {
				if let characteristic = state.characteristic {
					state.peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
				}
			}
			
			// Send to subscribed centrals
			if let characteristic = self.characteristic, !self.subscribedCentrals.isEmpty {
				let success = self.peripheralManager?.updateValue(data, for: characteristic, onSubscribedCentrals: nil) ?? false
				
				if !success {
					// Failed to send - add to pending queue (Bitchat-style)
					BLELogger.debug("📋 UpdateValue failed, adding to pending queue", category: BLELogger.general)
					
					if self.pendingNotifications.count < self.maxPendingNotifications {
						self.pendingNotifications.append((data: data, centrals: self.subscribedCentrals))
					} else {
						BLELogger.debug("⚠️ Pending queue full, dropping oldest notification", category: BLELogger.general)
						self.pendingNotifications.removeFirst()
						self.pendingNotifications.append((data: data, centrals: self.subscribedCentrals))
					}
				}
			}
		}
	}
	
	private func sendFragmentedPacket(_ packet: BitchatPacket) {
		guard let data = packet.toBinaryData() else { return }
		
		let fragmentID = Data((0..<8).map { _ in UInt8.random(in: 0...255) })
		let fragmentIDString = fragmentID.hexEncodedString()
		
		let safeMTU = getEffectiveWriteLength()
		let fragmentHeaderSize = 13 // fragmentID(8) + index(2) + total(2) + type(1)
		let packetOverhead = 30 // BitchatPacket header overhead
		let safeChunkSize = max(32, safeMTU - fragmentHeaderSize - packetOverhead)
		
		let chunks = stride(from: 0, to: data.count, by: safeChunkSize).map { offset in
			Data(data[offset..<min(offset + safeChunkSize, data.count)])
		}
		
		sentFragmentIDs.insert(fragmentIDString)
		
		BLELogger.logFragmentSendStart(id: fragmentIDString, count: chunks.count, totalSize: data.count)
		
		for (index, chunk) in chunks.enumerated() {
			var fragmentPayload = Data()
			fragmentPayload.append(fragmentID)
			fragmentPayload.append(contentsOf: withUnsafeBytes(of: UInt16(index).bigEndian) { Data($0) })
			fragmentPayload.append(contentsOf: withUnsafeBytes(of: UInt16(chunks.count).bigEndian) { Data($0) })
			fragmentPayload.append(packet.type)
			fragmentPayload.append(chunk)
			
			BLELogger.debug("🔧 FRAGMENT CREATE: index=\(index), fragmentID=\(fragmentIDString.prefix(8)), chunkSize=\(chunk.count), payloadSize=\(fragmentPayload.count)", category: BLELogger.fragment)
			
			let fragmentPacket = BitchatPacket(
				type: MessageType.fragment.rawValue,
				senderID: packet.senderID,
				recipientID: packet.recipientID,
				timestamp: packet.timestamp,
				payload: fragmentPayload,
				ttl: packet.ttl
			)
			
			if let fragmentData = fragmentPacket.toBinaryData() {
				let actualMTU = getEffectiveWriteLength()
				BLELogger.debug("🔍 MTU CHECK: fragmentData=\(fragmentData.count) vs actualMTU=\(actualMTU)", category: BLELogger.fragment)
				
				if fragmentData.count > actualMTU {
					BLELogger.error("❌ Fragment \(index)/\(chunks.count) too large: \(fragmentData.count) > MTU \(actualMTU)", category: BLELogger.fragment)
					continue
				}
				
				let baseDelayMs = chunks.count > 10 ? 30 : 20
				let delayMs = index * baseDelayMs
				
				DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delayMs)) { [weak self] in
					guard let self = self else { return }
					
					if !self.peripherals.isEmpty || !self.subscribedCentrals.isEmpty {
						BLELogger.debug("🚀 FRAGMENT SEND: index=\(index), size=\(fragmentData.count) bytes, delay=\(delayMs)ms", category: BLELogger.fragment)
						self.sendData(fragmentData)
						BLELogger.logFragmentSend(id: fragmentIDString, index: index, total: chunks.count, size: fragmentData.count)
					} else {
						BLELogger.error("❌ No connected peers for fragment \(index)", category: BLELogger.fragment)
					}
				}
			}
		}
		
		BLELogger.logFragmentSendComplete(id: fragmentIDString, count: chunks.count, totalSize: data.count)
		
		DispatchQueue.main.asyncAfter(deadline: .now() + 60.0) { [weak self] in
			self?.sentFragmentIDs.remove(fragmentIDString)
		}
	}
	
	private func handleReceivedData(_ data: Data, from sourceID: String, peripheral: CBPeripheral? = nil, central: CBCentral? = nil) {
		
		collectionsQueue.async(flags: .barrier) { [weak self] in
			guard let self = self,
						let packet = BinaryProtocol.decode(data) else { return }
			
			// Track incoming packet for adaptive scanning
			self.trackIncomingPacket()
			
			let senderID = packet.senderID.hexEncodedString()
			let messageID = packet.messageID()
			
			let typeString = MessageType(rawValue: packet.type)?.description ?? "anon(\(packet.type))"
			BLELogger.logPacketReceived(type: typeString, size: data.count, from: senderID)
			
			if packet.type != MessageType.fragment.rawValue {
				if self.messageDeduplicator.isDuplicate(messageID) {
					return
				}
				self.messageDeduplicator.markProcessed(messageID)
			}
			
			// Process by type
			switch MessageType(rawValue: packet.type) {
				
			case .announce:
				self.handleAnnounce(packet, sourceID: sourceID, peripheral: peripheral, central: central)
				
			case .message:
				self.handleMessage(packet)
				
			case .fragment:
				self.handleFragment(packet)
				
			case .leave:
				self.handleLeave(packet)
				
			default:
				break
			}
			
			// Relay if needed (but not own messages and not fragments)
			if packet.ttl > 1 && packet.type != MessageType.fragment.rawValue {
				self.relayPacket(packet)
			}
		}
	}
	
	// Process already-decoded packet (used for fragment reassembly)
	private func handleDecodedPacket(_ packet: BitchatPacket, originalDataSize: Int, wasFragmented: Bool = false) {
		let senderID = packet.senderID.hexEncodedString()
		let messageID = packet.messageID()
		
		// 패킷 수신 로그
		let typeString = MessageType(rawValue: packet.type)?.description ?? "anon(\(packet.type))"
		BLELogger.logPacketReceived(type: typeString, size: originalDataSize, from: senderID)
		
		// Deduplication (Fragment는 자체적으로 관리하므로 제외)
		if packet.type != MessageType.fragment.rawValue {
			if messageDeduplicator.isDuplicate(messageID) {
				return
			}
			messageDeduplicator.markProcessed(messageID)
		}
		
		// Process by type
		switch MessageType(rawValue: packet.type) {
		case .announce:
			// Reassembled announce packets might lack source context, handle gracefully
			handleAnnounce(packet, sourceID: senderID)
			
		case .message:
			handleMessage(packet)
			
		case .fragment:
			handleFragment(packet)
			
		case .leave:
			handleLeave(packet)
			
		default:
			break
		}
		
		// Relay if needed (Fragment는 handleFragment에서 개별적으로 relay 결정)
		if packet.ttl > 1 && packet.type != MessageType.fragment.rawValue {
			relayPacket(packet, forceFragment: wasFragmented)
		}
	}
	
	private func handleAnnounce(_ packet: BitchatPacket, sourceID: String, peripheral: CBPeripheral? = nil, central: CBCentral? = nil) {
		guard let announcement = AnnouncementPacket.decode(from: packet.payload) else { return }
		
		let peerID = announcement.peerID
		let nickname = announcement.nickname
		
		BLELogger.logAnnouncePacket(from: peerID, nickname: nickname, isNew: false)
		
		nicknames[peerID] = nickname
		
		// Update mappings and notify delegate for both central and peripheral roles
		if let peripheral = peripheral {
			// Central role: we connected to this peripheral
			let peripheralUUID = peripheral.identifier.uuidString
			if var state = peripherals[peripheralUUID] {
				let wasNewPeer = state.peerID == nil
				state.peerID = peerID
				peripherals[peripheralUUID] = state
				peerToPeripheralUUID[peerID] = peripheralUUID
				
				// Now that we have real peer info, notify delegate
				if wasNewPeer && state.isConnected {
					DispatchQueue.main.async { [weak self] in
						self?.delegate?.didConnectToPeer(peerID)
					}
				}
			}
		} else if let central = central {
			// Peripheral role: this central connected to us
			let centralUUID = central.identifier.uuidString
			let wasNewConnection = centralToPeerID[centralUUID] == nil
			centralToPeerID[centralUUID] = peerID
			
			// Report connection for Peripheral role (Central connected to us)
			if wasNewConnection {
				DispatchQueue.main.async { [weak self] in
					self?.delegate?.didConnectToPeer(peerID)
				}
			}
		}
		
		// Send immediate announce response if we haven't sent one recently
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
			self.sendBroadcastAnnounce()
		}
		
		// Update peer list
		DispatchQueue.main.async { [weak self] in
			guard let self = self else { return }
			let knownPeerIDs = self.getKnownPeerIDs()
			self.delegate?.didUpdatePeerList(knownPeerIDs)
		}
	}
	
	private func handleMessage(_ packet: BitchatPacket) {
		guard let content = String(data: packet.payload, encoding: .utf8) else { return }
		
		let senderID = packet.senderID.hexEncodedString()
		
		guard senderID != myPeerID else { return }
		
		let resolvedNickname = resolveNickname(for: senderID)
		let timestamp = Date(timeIntervalSince1970: Double(packet.timestamp) / 1000)
		
		DispatchQueue.main.async { [weak self] in
			self?.delegate?.didReceivePublicMessage(from: senderID, nickname: resolvedNickname, content: content, timestamp: timestamp)
		}
	}
	
	private func handleFragment(_ packet: BitchatPacket) {
		guard packet.payload.count >= 13 else {
			BLELogger.error("❌ Fragment payload too short: \(packet.payload.count) bytes", category: BLELogger.fragment)
			return
		}
		
		let senderID = packet.senderID.hexEncodedString()
		let fragmentID = packet.payload[0..<8].hexEncodedString()
		let index = Int(UInt16(bigEndian: packet.payload[8..<10].withUnsafeBytes { $0.load(as: UInt16.self) }))
		let total = Int(UInt16(bigEndian: packet.payload[10..<12].withUnsafeBytes { $0.load(as: UInt16.self) }))
		let originalType = packet.payload[12]
		let fragmentData = packet.payload.suffix(from: 13)
		
		BLELogger.debug("🔍 Fragment parsed: ID=\(fragmentID.prefix(8)), index=\(index), total=\(total), type=\(originalType), dataSize=\(fragmentData.count)", category: BLELogger.fragment)
		
		if senderID == myPeerID {
			BLELogger.debug("🔄 Echo fragment ignored: senderID=\(senderID) == myPeerID", category: BLELogger.fragment)
			return
		}
		if sentFragmentIDs.contains(fragmentID) {
			BLELogger.debug("🔄 Sent fragment ignored: fragmentID=\(fragmentID.prefix(8))", category: BLELogger.fragment)
			return
		}
		
		let fragmentKey = "\(senderID):\(fragmentID):\(index)"
		BLELogger.debug("🔍 FRAGMENT DEDUP CHECK: key=\(fragmentKey)", category: BLELogger.fragment)
		
		if fragmentDeduplicator.isDuplicate(fragmentKey) {
			BLELogger.debug("🔄 Duplicate fragment ignored: \(fragmentKey)", category: BLELogger.fragment)
			return
		}
		BLELogger.debug("✅ FRAGMENT DEDUP PASS: key=\(fragmentKey)", category: BLELogger.fragment)
		fragmentDeduplicator.markProcessed(fragmentKey)
		
		// Fragment relay (중복이 아닌 경우에만)
		if packet.ttl > 1 {
			relayPacket(packet, forceFragment: true)
		}
		
		let key = "\(senderID):\(fragmentID)"
		
		if incomingFragments[key] == nil {
			incomingFragments[key] = [:]
			fragmentMetadata[key] = (originalType, total, Date())
			BLELogger.debug("📦 New fragment group: \(fragmentID.prefix(8)) (expecting \(total) fragments)", category: BLELogger.fragment)
		}
		
		incomingFragments[key]?[index] = Data(fragmentData)
		
		if let fragments = incomingFragments[key], fragments.count == total {
			let startTime = Date()
			
			var reassembled = Data()
			for i in 0..<total {
				if let fragment = fragments[i] {
					reassembled.append(fragment)
				} else {
					BLELogger.error("❌ Missing fragment \(i) during reassembly \(fragmentID)", category: BLELogger.fragment)
					return
				}
			}
			
			// Process reassembled packet
			if let originalPacket = BinaryProtocol.decode(reassembled) {
				let duration = Date().timeIntervalSince(startTime)
				BLELogger.logFragmentAssemblyComplete(id: fragmentID, size: reassembled.count, duration: duration)
				
				// Fragment로 재조립된 패킷임을 표시
				handleDecodedPacket(originalPacket, originalDataSize: reassembled.count, wasFragmented: true)
			} else {
				BLELogger.error("❌ Failed to decode reassembled fragment \(fragmentID) (\(reassembled.count) bytes)", category: BLELogger.fragment)
			}
		}
	}
	
	private func handleLeave(_ packet: BitchatPacket) {
		let senderID = packet.senderID.hexEncodedString()
		
		// Disconnect if we are central to this peer
		if let peripheralUUID = peerToPeripheralUUID[senderID], let state = peripherals[peripheralUUID] {
			centralManager?.cancelPeripheralConnection(state.peripheral)
		}
		
		// Clean up local state
		peerToPeripheralUUID.removeValue(forKey: senderID)
		if let centralUUID = centralToPeerID.first(where: { $0.value == senderID })?.key {
			centralToPeerID.removeValue(forKey: centralUUID)
		}
		
		DispatchQueue.main.async { [weak self] in
			self?.delegate?.didDisconnectFromPeer(senderID)
			self?.delegate?.didUpdatePeerList(self?.getKnownPeerIDs() ?? [])
		}
	}
	
	private func relayPacket(_ packet: BitchatPacket, forceFragment: Bool = false) {
		guard shouldRelay(packet) else {
			BLELogger.debug("🚫 Relay skipped for packet type=\(packet.type)", category: BLELogger.packet)
			return
		}
		
		var relayPacket = packet
		relayPacket.ttl = packet.ttl - 1
		
		BLELogger.debug("📡 Relaying packet: type=\(packet.type), ttl=\(relayPacket.ttl), forceFragment=\(forceFragment)", category: BLELogger.packet)
		
		DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 0.01...0.05)) { [weak self] in
			if forceFragment {
				BLELogger.debug("📦 FORCE FRAGMENT: Original was fragmented, relaying as fragments", category: BLELogger.fragment)
				self?.sendFragmentedPacket(relayPacket)
			} else {
				self?.broadcastPacket(relayPacket)
			}
		}
	}
	
	/// Determine if packet should be relayed based on network density
	private func shouldRelay(_ packet: BitchatPacket) -> Bool {
		let connectedCount = getDirectlyConnectedPeerIDs().count
		
		if connectedCount <= 2 { return true }
		if MessageType(rawValue: packet.type) == .announce && connectedCount > 5 { return Double.random(in: 0...1) < 0.3 }
		if connectedCount > 5 { return Double.random(in: 0...1) < 0.5 }
		
		return true
	}
	
	private func getEffectiveWriteLength() -> Int {
		let connectedPeripherals = peripherals.values.filter { $0.isConnected }
		guard !connectedPeripherals.isEmpty else { return defaultFragmentSize }
		
		let minWriteLength = connectedPeripherals.reduce(Int.max) { (minVal, state) -> Int in
			let writeLength = state.peripheral.maximumWriteValueLength(for: .withoutResponse)
			return min(minVal, writeLength > 0 ? writeLength : Int.max)
		}
		
		return min(defaultFragmentSize, minWriteLength == Int.max ? defaultFragmentSize : minWriteLength)
	}
	
	private func resolveNickname(for peerID: String) -> String {
		return nicknames[peerID] ?? "anon"
	}
	
	// MARK: - Debug Helpers
	
	/// Debug method to log complete BLE status
	func logBLEDebugStatus() {
		bleQueue.async { [weak self] in
			guard let self = self else { return }
			
			let centralState = self.centralManager?.state.description ?? "nil"
			let peripheralState = self.peripheralManager?.state.description ?? "nil"
			let isScanning = self.centralManager?.isScanning ?? false
			let isAdvertising = self.peripheralManager?.isAdvertising ?? false
			let connectedDevices = self.peripherals.values.filter { $0.isConnected }.count
			let discoveredPeers = self.peripherals.count
			
			BLELogger.logBLEDebugSnapshot(
				centralState: centralState,
				peripheralState: peripheralState,
				isScanning: isScanning,
				isAdvertising: isAdvertising,
				connectedDevices: connectedDevices,
				discoveredPeers: discoveredPeers
			)
			
			let peerList = self.getKnownPeerIDs().map {
				(id: $0, nickname: self.resolveNickname(for: $0))
			}
			BLELogger.logPeerList(peerList)
		}
	}
}

// MARK: - CBCentralManagerDelegate

extension BLEService: CBCentralManagerDelegate, CBPeripheralDelegate {
	func centralManagerDidUpdateState(_ central: CBCentralManager) {
		let stateString: String
		switch central.state {
		case .unknown: stateString = "Unknown"
		case .resetting: stateString = "Resetting"
		case .unsupported: stateString = "Unsupported"
		case .unauthorized: stateString = "Unauthorized"
		case .poweredOff: stateString = "PoweredOff"
		case .poweredOn: stateString = "PoweredOn"
		@unknown default: stateString = "Unknown(\(central.state.rawValue))"
		}
		
		BLELogger.logCentralStateChange(stateString)
		
		if central.state == .poweredOn {
			startScanning()
			
			// Send initial announce after both managers are ready
			if peripheralManager?.state == .poweredOn {
				DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
					self?.sendBroadcastAnnounce()
					self?.startPeriodicAnnounce()
				}
			}
		}
	}
	
	func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
		let peripheralUUID = peripheral.identifier.uuidString
		
		collectionsQueue.async(flags: .barrier) { [weak self] in
			guard let self = self else { return }
			
			// Connection Budget Check
			let connectedCount = self.peripherals.values.filter { $0.isConnected || $0.isConnecting }.count
			guard connectedCount < TransportConfig.bleMaxCentralLinks else {
				BLELogger.debug("Connection budget exceeded: \(connectedCount)/\(TransportConfig.bleMaxCentralLinks)", category: BLELogger.connection)
				return
			}
			
			// Rate Limiting Check
			let timeSinceLastAttempt = Date().timeIntervalSince(self.lastGlobalConnectAttempt)
			guard timeSinceLastAttempt >= TransportConfig.bleConnectRateLimitInterval else {
				BLELogger.debug("Rate limit exceeded: \(String(format: "%.2f", timeSinceLastAttempt))s < \(TransportConfig.bleConnectRateLimitInterval)s", category: BLELogger.connection)
				return
			}
			
			// Check if we should connect
			if self.peripherals[peripheralUUID] == nil {
				let isConnectable = (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue ?? true
				guard RSSI.intValue > -80, isConnectable else { return }
				
				// TODO: - 임시 PeerID 값 비교를 통해 서로 동시에 연결 방지(서로가 Central과 Peripheral로 각각 연결되는 케이스)
				let otherPeerID = PeerIDUtils.derivePeerID(fromPublicKey: Data(peripheralUUID.utf8))
				if self.myPeerID > otherPeerID {
					self.lastGlobalConnectAttempt = Date()
					
					var newState = PeripheralState(peripheral: peripheral)
					newState.isConnecting = true
					newState.lastConnectionAttempt = Date()
					self.peripherals[peripheralUUID] = newState
					
					BLELogger.logConnectionAttempt(peripheral.name ?? "anon", peripheralUUID)
					
					peripheral.delegate = self
					central.connect(peripheral, options: nil)
				} else {
					BLELogger.debug("Skipping connection - other device has priority: \(otherPeerID.prefix(8))", category: BLELogger.connection)
				}
			}
		}
	}
	
	func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
		let peripheralUUID = peripheral.identifier.uuidString
		BLELogger.logConnectionSuccess("Connected", peripheralUUID)
		
		collectionsQueue.async(flags: .barrier) { [weak self] in
			guard let self = self else { return }
			
			if var state = self.peripherals[peripheralUUID] {
				state.isConnecting = false
				state.isConnected = true
				self.peripherals[peripheralUUID] = state
				
				DispatchQueue.main.async {
					// Immediately notify UI of BLE connection (will be updated with real PeerID later)
					self.delegate?.didConnectToPeer(peripheralUUID)
					self.delegate?.didUpdatePeerList(self.getKnownPeerIDs())
					
					// Update scanning mode based on new connection count
					self.updateScanningMode()
					
					// Schedule connection-based announce
					self.scheduleConnectionBasedAnnounce()
				}
			}
		}
		
		peripheral.discoverServices([BLEService.serviceUUID])
	}
	
	func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
		let peripheralUUID = peripheral.identifier.uuidString
		BLELogger.logConnectionFailure(peripheral.name ?? "anon", peripheralUUID, error: error?.localizedDescription)
		
		collectionsQueue.async(flags: .barrier) { [weak self] in
			self?.peripherals.removeValue(forKey: peripheralUUID)
		}
	}
	
	func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
		let peripheralUUID = peripheral.identifier.uuidString
		BLELogger.logDisconnection(peripheral.name ?? "anon", peripheralUUID, reason: error?.localizedDescription)
		
		collectionsQueue.async(flags: .barrier) { [weak self] in
			guard let self = self else { return }
			
			let disconnectedPeerID = self.peripherals[peripheralUUID]?.peerID
			self.peripherals.removeValue(forKey: peripheralUUID)
			
			if let peerID = disconnectedPeerID {
				self.peerToPeripheralUUID.removeValue(forKey: peerID)
				// Remove from nicknames to prevent re-appearance
				self.nicknames.removeValue(forKey: peerID)
				
				DispatchQueue.main.async {
					// Update the UI with the cleaned list
					self.delegate?.didUpdatePeerList(self.getKnownPeerIDs())
					self.updateScanningMode()
				}
			}
		}
	}
	
	// MARK: - CBPeripheralDelegate
	
	func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
		guard let service = peripheral.services?.first(where: { $0.uuid == BLEService.serviceUUID }) else { return }
		peripheral.discoverCharacteristics([BLEService.characteristicUUID], for: service)
	}
	
	func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
		guard let characteristic = service.characteristics?.first(where: { $0.uuid == BLEService.characteristicUUID }) else { return }
		
		let peripheralUUID = peripheral.identifier.uuidString
		collectionsQueue.async(flags: .barrier) { [weak self] in
			if var state = self?.peripherals[peripheralUUID] {
				state.characteristic = characteristic
				self?.peripherals[peripheralUUID] = state
			}
		}
		
		if characteristic.properties.contains(.notify) {
			peripheral.setNotifyValue(true, for: characteristic)
		}
		
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
			BLELogger.debug("🔄 Central sending proactive announce to newly discovered peripheral", category: BLELogger.peer)
			self?.sendBroadcastAnnounce()
		}
	}
	
	func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
		guard let data = characteristic.value else { return }
		let peripheralUUID = peripheral.identifier.uuidString
		handleReceivedData(data, from: peripheralUUID, peripheral: peripheral)
	}
}

// MARK: - CBPeripheralManagerDelegate

extension BLEService: CBPeripheralManagerDelegate {
	func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
		if peripheral.state == .poweredOn {
			setupPeripheralService()
			
			// Send initial announce after both managers are ready
			if centralManager?.state == .poweredOn {
				DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
					self?.sendBroadcastAnnounce()
					self?.startPeriodicAnnounce()
				}
			}
		}
	}
	
	func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
		guard error == nil else { return }
		
		let advertisementData: [String: Any] = [
			CBAdvertisementDataServiceUUIDsKey: [BLEService.serviceUUID]
		]
		peripheral.startAdvertising(advertisementData)
	}
	
	func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
		let centralUUID = central.identifier.uuidString
		BLELogger.debug("📋 Central subscribed: \(centralUUID)", category: BLELogger.peer)
		
		collectionsQueue.async(flags: .barrier) { [weak self] in
			guard let self = self else { return }
			if !self.subscribedCentrals.contains(where: { $0.identifier == central.identifier }) {
				self.subscribedCentrals.append(central)
			}
			
			DispatchQueue.main.async { [weak self] in
				// Immediately notify UI of new connection (will be updated with real PeerID later)
				self?.delegate?.didConnectToPeer(centralUUID)
				self?.delegate?.didUpdatePeerList(self?.getKnownPeerIDs() ?? [])
				
				// Update scanning mode based on new connection count
				self?.updateScanningMode()
				
				self?.scheduleConnectionBasedAnnounce()
			}
		}
	}
	
	func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
		let centralUUID = central.identifier.uuidString
		BLELogger.debug("📋 Central unsubscribed: \(centralUUID)", category: BLELogger.peer)
		
		collectionsQueue.async(flags: .barrier) { [weak self] in
			guard let self = self else { return }
			self.subscribedCentrals.removeAll { $0.identifier == central.identifier }
			
			if let peerID = self.centralToPeerID[centralUUID] {
				self.centralToPeerID.removeValue(forKey: centralUUID)
				// Remove from nicknames to prevent re-appearance
				self.nicknames.removeValue(forKey: peerID)
				
				DispatchQueue.main.async {
					// Update the UI with the cleaned list
					self.delegate?.didUpdatePeerList(self.getKnownPeerIDs())
					self.updateScanningMode()
				}
			}
		}
	}
	
	func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
		for request in requests {
			peripheral.respond(to: request, withResult: .success)
			
			if let data = request.value {
				let centralUUID = request.central.identifier.uuidString
				handleReceivedData(data, from: centralUUID, central: request.central)
			}
		}
	}
	
	func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
		// Process pending notifications queue (Bitchat-style)
		bleQueue.async { [weak self] in
			guard let self = self,
						let characteristic = self.characteristic,
						!self.pendingNotifications.isEmpty else { return }
			
			BLELogger.debug("📋 Processing pending notifications: \(self.pendingNotifications.count) items", category: BLELogger.general)
			
			var processedCount = 0
			var failedNotifications: [(data: Data, centrals: [CBCentral])] = []
			
			for notification in self.pendingNotifications {
				let success = peripheral.updateValue(notification.data, for: characteristic, onSubscribedCentrals: notification.centrals)
				
				if success {
					processedCount += 1
				} else {
					failedNotifications.append(notification)
					break // Stop processing if we hit another failure
				}
			}
			
			self.pendingNotifications = failedNotifications
			
			if processedCount > 0 {
				BLELogger.debug("📋 Processed \(processedCount) pending notifications, \(failedNotifications.count) remain", category: BLELogger.general)
			}
		}
	}
}
