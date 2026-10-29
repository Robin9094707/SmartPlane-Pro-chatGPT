import Foundation
import Combine
@preconcurrency import CoreBluetooth
import UIKit
import PlaneProtocol

struct NearbyPlane: Identifiable {
    let id: UUID
    var name: String
    var rssi: Int
    var lastSeen: Date
    var advertisement: [String: String]
    var probablePlane: Bool
}
struct GATTEntry: Identifiable, Codable {
    var id: String
    var service: String
    var uuid: String
    var properties: [String]
    var valueHex: String = ""
    var valueText: String = ""
    var notifying: Bool = false
    var descriptors: [String: String] = [:]
    var updatedAt: Date?
}
struct BLEEvent: Identifiable, Codable {
    var id = UUID()
    var time = Date()
    var kind: String
    var message: String
}

@MainActor final class BluetoothController: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var bluetoothStatus = "Bluetooth wird vorbereitet …"
    @Published var scanning = false
    @Published var devices: [NearbyPlane] = []
    @Published var entries: [GATTEntry] = []
    @Published var events: [BLEEvent] = []
    @Published var connectedName: String?
    @Published var connectingID: UUID?
    @Published var connectedID: UUID?
    @Published var rssi: Int?
    @Published var battery: Int?
    @Published var profile: ControlProfile?
    @Published var customProfiles: [ControlProfile] = []
    @Published var armed = false
    @Published var throttle: Double = 0
    @Published var rudder: Double = 0
    @Published var throttleLimit: Double = 0.5
    @Published var problem: String?
    @Published var flightSeconds = 0
    @Published var totalTX = 0
    @Published var totalRX = 0
    @Published var discoveryComplete = false
    var connected: Bool { connectedID != nil }
    var canArm: Bool { connected && discoveryComplete && profile != nil && !armed && pendingResponse == nil }
    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var peripheral: CBPeripheral?
    private var characteristics: [String: CBCharacteristic] = [:]
    private var gate = FlightGate()
    private var timer: Timer?
    private var scanTimer: Timer?
    private var connectTimeout: Timer?
    private var waitingServices: Set<String> = []
    private var pendingResponse: (key: String, at: Date)?
    private var pendingFrame: [(CBCharacteristic, Data)] = []
    private var lastFrame: [String: Data] = [:]
    private var lastRSSI = Date.distantPast
    private var flightStarted: Date?
    private var stopGeneration = UUID()
    private var probing = false
    private var pollCount = 0
    private var backgroundToken: UIBackgroundTaskIdentifier = .invalid
    private var profilesURL: URL { URL.documentsDirectory.appending(path: "control-profiles.json") }
    override init() {
        super.init()
        if let data = try? Data(contentsOf: profilesURL), let saved = try? JSONDecoder().decode([ControlProfile].self, from: data) {
            customProfiles = saved.filter { (try? $0.validate()) != nil }
        }
        central = CBCentralManager(delegate: self, queue: .main)
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }
    func log(_ kind: String, _ message: String) {
        events.append(.init(kind: kind, message: message))
        if events.count > 2000 { events.removeFirst(events.count - 2000) }
    }
    func scan() {
        guard central.state == .poweredOn, !connected, connectingID == nil else { problem = "Bluetooth aktivieren und bestehende Verbindung zuerst trennen."; return }
        devices.removeAll(); peripherals.removeAll(); scanning = true
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in Task { @MainActor in self?.stopScan() } }
        log("scan", "Ungefilterter BLE-Scan gestartet (20 Sekunden).")
    }
    func stopScan() { central.stopScan(); scanning = false; scanTimer?.invalidate() }
    func connect(_ id: UUID) {
        guard !connected, connectingID == nil, let p = peripherals[id], central.state == .poweredOn else { return }
        stopScan(); resetConnection(); peripheral = p; p.delegate = self; connectingID = id
        log("connect", "Verbinde mit \(p.name ?? id.uuidString)")
        central.connect(p, options: nil)
        connectTimeout?.invalidate()
        connectTimeout = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.connectingID != nil, let p = self.peripheral else { return }
                self.problem = "Verbindungsaufbau nach 15 Sekunden abgebrochen."
                self.central.cancelPeripheralConnection(p); self.resetConnection()
            }
        }
    }
    func disconnect() {
        stop(reason: "Verbindung wird getrennt")
        let generation = stopGeneration
        guard let p = peripheral else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.stopGeneration == generation else { return }
            self.central.cancelPeripheralConnection(p)
        }
    }
    func suspend() {
        stopScan()
        if connected || connectingID != nil {
            backgroundToken = UIApplication.shared.beginBackgroundTask(withName: "MotorStop")
            disconnect()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, self.backgroundToken != .invalid else { return }
                UIApplication.shared.endBackgroundTask(self.backgroundToken); self.backgroundToken = .invalid
            }
        }
    }
    func arm(acknowledged: Bool) {
        guard gate.arm(connected: connected, profileReady: canArm, acknowledged: acknowledged, throttle: throttle) else {
            problem = "Freigabe nicht möglich: Verbindung, Profil und Nullstellung prüfen."; return
        }
        armed = true; flightStarted = Date(); flightSeconds = 0
        lastFrame.removeAll(); sendFrame(force: true)
        log("arm", "Manuell freigegeben: \(profile?.name ?? "")")
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    func stop(reason: String = "STOP gedrückt") {
        gate.stop(); armed = false; throttle = 0; rudder = 0; flightStarted = nil
        stopGeneration = UUID(); pendingFrame.removeAll(); lastFrame.removeAll()
        // Best effort only: BLE writes cannot guarantee that the aircraft actually stopped.
        if connected && profile != nil { sendFrame(force: true) }
        log("stop", reason + ". Nullwerte angefordert; Zustellung ist nicht garantiert.")
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
    func setThrottle(_ value: Double) { throttle = armed ? min(1, max(0, value)) : 0 }
    func setRudder(_ value: Double) { rudder = armed ? min(1, max(-1, value)) : 0 }
    private func tick() {
        guard connected else { return }
        if Date().timeIntervalSince(lastRSSI) >= 2 { peripheral?.readRSSI(); lastRSSI = Date() }
        if let start = flightStarted { flightSeconds = Int(Date().timeIntervalSince(start)) }
        if let pending = pendingResponse, Date().timeIntervalSince(pending.at) > 1 {
            problem = "Bluetooth-Schreibvorgang antwortet nicht. Verbindung wird beendet."
            pendingResponse = nil; stop(reason: "Schreib-Timeout")
            if let p = peripheral { central.cancelPeripheralConnection(p) }
            return
        }
        if armed { sendFrame(force: false) }
        else { pump() }
        pollCount += 1
        if pollCount % 200 == 0, let c = characteristics.values.first(where: { $0.uuid == CBUUID(string: "2A19") && $0.properties.contains(.read) }) { peripheral?.readValue(for: c) }
    }
    private func key(_ c: CBCharacteristic) -> String { "\(c.service?.uuid.uuidString ?? "?")/\(c.uuid.uuidString)" }
    private func profileKey(_ uuid: String, service: String) -> String { "\(CBUUID(string: service).uuidString)/\(CBUUID(string: uuid).uuidString)" }
    private func sendFrame(force: Bool) {
        guard let profile, connected else { return }
        let output = gate.output(throttle: throttle, rudder: rudder)
        let (t, r) = profile.values(throttle: output.0, rudder: output.1, limit: throttleLimit)
        // Replace unsent frames instead of building a control backlog.
        var frame: [(CBCharacteristic, Data)] = []
        for command in profile.commands {
            let k = profileKey(command.characteristicUUID, service: profile.serviceUUID)
            guard let c = characteristics[k], let data = try? command.payload(throttle: t, rudder: r) else { continue }
            if force || lastFrame[k] != data { frame.append((c, data)) }
        }
        if !frame.isEmpty { pendingFrame = frame }
        pump()
    }
    private func pump() {
        guard let p = peripheral, connected, pendingResponse == nil else { return }
        while !pendingFrame.isEmpty {
            let (c, data) = pendingFrame[0]
            let type: CBCharacteristicWriteType = c.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
            if type == .withoutResponse && !p.canSendWriteWithoutResponse { return }
            pendingFrame.removeFirst()
            if type == .withResponse { pendingResponse = (key(c), Date()) }
            p.writeValue(data, for: c, type: type)
            lastFrame[key(c)] = data; totalTX += 1
            log("tx", "\(key(c)) ← \(data.hex) [\(type == .withoutResponse ? "no response" : "response")]")
            if type == .withResponse { return }
        }
    }
    func selectProfile(_ selected: ControlProfile) {
        guard !armed, (try? selected.validate()) != nil, matches(selected) else { problem = "Dieses Profil passt nicht zu den erkannten schreibbaren Eigenschaften."; return }
        profile = selected; lastFrame.removeAll(); log("profile", "Ausgewählt: \(selected.name)")
    }
    private func matches(_ p: ControlProfile) -> Bool {
        p.commands.allSatisfy { command in
            guard let c = characteristics[profileKey(command.characteristicUUID, service: p.serviceUUID)] else { return false }
            return c.properties.contains(.write) || c.properties.contains(.writeWithoutResponse)
        }
    }
    var matchingProfiles: [ControlProfile] { (ControlProfile.builtins + customProfiles).filter { matches($0) } }
    func importProfile(from url: URL) throws {
        guard !armed else { throw ProtocolError.invalid("Vor dem Import STOP drücken.") }
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard data.count < 65536 else { throw ProtocolError.invalid("Profil ist zu groß.") }
        let p = try JSONDecoder().decode(ControlProfile.self, from: data); try p.validate()
        guard !ControlProfile.builtins.contains(where: { $0.id == p.id }) else { throw ProtocolError.invalid("Für eigene Profile eine neue ID verwenden.") }
        var next = customProfiles.filter { $0.id != p.id }; next.append(p)
        try JSONEncoder().encode(next).write(to: profilesURL, options: .atomic)
        customProfiles = next
        if matches(p) { profile = p }
        log("profile", "Importiert: \(p.name)")
    }
    func removeProfile(_ p: ControlProfile) {
        guard !armed else { return }
        let next = customProfiles.filter { $0.id != p.id }
        do { try JSONEncoder().encode(next).write(to: profilesURL, options: .atomic); customProfiles = next
            if profile?.id == p.id { profile = nil }
        } catch { problem = error.localizedDescription }
    }
    func read(_ id: String) {
        guard !armed, let c = characteristics[id], c.properties.contains(.read) else { return }
        peripheral?.readValue(for: c)
    }
    func readAll() {
        guard !armed else { return }
        probing = true
        for c in characteristics.values where c.properties.contains(.read) { peripheral?.readValue(for: c) }
        log("probe", "Alle lesbaren GATT-Werte angefordert. Keine Schreibbefehle.")
    }
    func inspectDescriptors(_ id: String) {
        guard !armed, let c = characteristics[id] else { return }; peripheral?.discoverDescriptors(for: c)
    }
    func notify(_ id: String, enabled: Bool) {
        guard !armed, let c = characteristics[id], c.properties.contains(.notify) || c.properties.contains(.indicate) else { return }
        peripheral?.setNotifyValue(enabled, for: c)
    }
    func rawWrite(id: String, hex: String, withResponse: Bool) throws {
        guard !armed, pendingResponse == nil, pendingFrame.isEmpty, let p = peripheral, connected, let c = characteristics[id] else { throw ProtocolError.invalid("Nur bei ruhender, verbundener Steuerung verfügbar.") }
        let data = try Data(strictHex: hex)
        let type: CBCharacteristicWriteType = withResponse ? .withResponse : .withoutResponse
        guard c.properties.contains(withResponse ? .write : .writeWithoutResponse) else { throw ProtocolError.invalid("Dieser Schreibtyp wird nicht unterstützt.") }
        guard data.count <= p.maximumWriteValueLength(for: type) else { throw ProtocolError.invalid("Paket überschreitet die ausgehandelte BLE-Paketgröße.") }
        if !withResponse && !p.canSendWriteWithoutResponse { throw ProtocolError.invalid("Bluetooth-Puffer belegt. Erneut versuchen.") }
        if withResponse { pendingResponse = (id, Date()) }
        p.writeValue(data, for: c, type: type); totalTX += 1
        log("raw-tx", "\(id) ← \(data.hex)")
    }
    func exportReport() throws -> URL {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        struct Report: Encodable {
            let schemaVersion: Int; let date: Date; let appVersion: String; let iosVersion: String
            let deviceID: UUID?; let deviceName: String?; let rssi: Int?; let batteryPercent: Int?
            let advertisement: [String: String]; let gatt: [GATTEntry]; let events: [BLEEvent]
            let selectedProfile: ControlProfile?; let limitations: [String]
        }
        let ad = devices.first(where: { $0.id == connectedID })?.advertisement ?? [:]
        let report = Report(schemaVersion: 1, date: Date(), appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0", iosVersion: UIDevice.current.systemVersion, deviceID: connectedID, deviceName: connectedName, rssi: rssi, batteryPercent: battery, advertisement: ad, gatt: entries, events: events, selectedProfile: profile, limitations: ["iOS exposes a peripheral UUID, not its Bluetooth MAC address.", "Readable GATT and advertised data only; not a full firmware dump.", "Legacy SmartLink protocol is not confirmed for SmartPlane Pro.", "A successful write is not proof of physical motor state."])
        let directory = URL.documentsDirectory.appending(path: "Reports"); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "SmartPlane-\(Int(Date().timeIntervalSince1970)).json")
        try encoder.encode(report).write(to: url, options: .atomic); return url
    }
    func clearEvents() { guard !armed else { return }; events.removeAll() }
    private func resetConnection() {
        gate.stop(); armed = false; throttle = 0; rudder = 0; flightStarted = nil
        connectedID = nil; connectingID = nil; connectedName = nil; profile = nil
        entries.removeAll(); characteristics.removeAll(); waitingServices.removeAll()
        pendingResponse = nil; pendingFrame.removeAll(); lastFrame.removeAll()
        battery = nil; rssi = nil; discoveryComplete = false; probing = false
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: bluetoothStatus = "Bluetooth bereit"
        case .poweredOff: bluetoothStatus = "Bluetooth ausgeschaltet"
        case .unauthorized: bluetoothStatus = "Bluetooth-Zugriff nicht erlaubt – in Einstellungen freigeben"
        case .unsupported: bluetoothStatus = "Bluetooth LE nicht verfügbar"
        case .resetting: bluetoothStatus = "Bluetooth startet neu"
        default: bluetoothStatus = "Bluetooth-Status unbekannt"
        }
        log("state", bluetoothStatus)
        if central.state != .poweredOn { stopScan(); resetConnection() }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "Unbenanntes BLE-Gerät"
        var ad: [String: String] = [:]
        for (k, v) in advertisementData {
            if let d = v as? Data { ad[k] = d.hex }
            else if let uuids = v as? [CBUUID] { ad[k] = uuids.map(\.uuidString).joined(separator: ", ") }
            else if let dict = v as? [CBUUID: Data] { ad[k] = dict.map { "\($0.key.uuidString): \($0.value.hex)" }.sorted().joined(separator: "; ") }
            else { ad[k] = String(describing: v) }
        }
        let likely = ["smartplane", "tobyrich", "moskito", "vegas"].contains(where: { name.lowercased().contains($0) }) || ad.values.contains(where: { $0.lowercased().contains("75b64e51") })
        peripherals[peripheral.identifier] = peripheral
        let item = NearbyPlane(id: peripheral.identifier, name: name, rssi: RSSI.intValue, lastSeen: Date(), advertisement: ad, probablePlane: likely)
        if let i = devices.firstIndex(where: { $0.id == item.id }) { devices[i] = item }
        else if devices.count < 300 { devices.append(item); log("found", "\(name) · \(peripheral.identifier) · \(RSSI) dBm") }
        devices.sort { $0.probablePlane != $1.probablePlane ? $0.probablePlane : $0.rssi > $1.rssi }
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral.identifier == connectingID else { central.cancelPeripheralConnection(peripheral); return }
        connectTimeout?.invalidate(); connectingID = nil; connectedID = peripheral.identifier
        connectedName = peripheral.name ?? "BLE-Gerät"; log("connected", connectedName!)
        peripheral.discoverServices(nil)
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectTimeout?.invalidate(); problem = error?.localizedDescription ?? "Verbindung fehlgeschlagen"
        log("error", problem!); resetConnection()
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        log("disconnected", error?.localizedDescription ?? "Verbindung beendet")
        if armed { problem = "Verbindung verloren. Motorstopp kann nicht bestätigt werden." }
        resetConnection(); self.peripheral = nil
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error { problem = error.localizedDescription; log("error", error.localizedDescription); return }
        let services = peripheral.services ?? []; waitingServices = Set(services.map { $0.uuid.uuidString })
        for service in services { log("service", service.uuid.uuidString); peripheral.discoverCharacteristics(nil, for: service) }
        if services.isEmpty { discoveryComplete = true }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        waitingServices.remove(service.uuid.uuidString)
        if let error { log("error", error.localizedDescription) }
        for c in service.characteristics ?? [] {
            let k = key(c); characteristics[k] = c
            var props: [String] = []
            for (flag, label) in [(CBCharacteristicProperties.read, "read"), (.write, "write"), (.writeWithoutResponse, "writeWithoutResponse"), (.notify, "notify"), (.indicate, "indicate")] where c.properties.contains(flag) { props.append(label) }
            entries.append(.init(id: k, service: service.uuid.uuidString, uuid: c.uuid.uuidString, properties: props))
            log("characteristic", "\(k) [\(props.joined(separator: ", "))]")
            if ["180A", "180F"].contains(service.uuid.uuidString), c.properties.contains(.read) { peripheral.readValue(for: c) }
        }
        entries.sort { $0.id < $1.id }
        if waitingServices.isEmpty {
            discoveryComplete = true; profile = matchingProfiles.first
            log("profile", profile?.name ?? "Unbekanntes Protokoll – Diagnosemodus aktiv. Keine automatischen Schreibzugriffe.")
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let k = key(characteristic)
        if let error { log("read-error", "\(k): \(error.localizedDescription)"); return }
        guard let data = characteristic.value else { return }
        totalRX += 1; log("rx", "\(k) → \(data.hex)")
        if let i = entries.firstIndex(where: { $0.id == k }) {
            entries[i].valueHex = data.hex; entries[i].valueText = String(data: data, encoding: .utf8) ?? ""; entries[i].updatedAt = Date()
        }
        if characteristic.uuid == CBUUID(string: "2A19"), let level = data.first, level <= 100 { battery = Int(level) }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let i = entries.firstIndex(where: { $0.id == key(characteristic) }) { entries[i].notifying = characteristic.isNotifying }
        log("notify", "\(key(characteristic)) \(characteristic.isNotifying ? "an" : "aus") \(error?.localizedDescription ?? "")")
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
        if let error { log("descriptor-error", error.localizedDescription); return }
        for descriptor in characteristic.descriptors ?? [] { peripheral.readValue(for: descriptor) }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) {
        let text = (descriptor.value as? Data)?.hex ?? String(describing: descriptor.value ?? "")
        if let c = descriptor.characteristic, let i = entries.firstIndex(where: { $0.id == key(c) }) { entries[i].descriptors[descriptor.uuid.uuidString] = error?.localizedDescription ?? text }
        log("descriptor", "\(descriptor.uuid.uuidString): \(text)")
    }
    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) { if error == nil, RSSI.intValue != 127 { rssi = RSSI.intValue } }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        pendingResponse = nil
        if let error { problem = error.localizedDescription; stop(reason: "Schreibfehler"); central.cancelPeripheralConnection(peripheral) }
        else { log("ack", key(characteristic)); pump() }
    }
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) { pump() }
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        stop(reason: "GATT-Dienste geändert"); disconnect()
        problem = "Das Gerät hat seine Dienste geändert. Bitte neu verbinden."
    }
}
