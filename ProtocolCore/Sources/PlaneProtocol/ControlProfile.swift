import Foundation

public enum ProtocolError: Error, LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let reason) = self { return reason }; return nil }
}

/// Only these templates produce flight writes. Unknown GATT services never enable control.
public struct ControlCommand: Codable, Hashable, Sendable {
    public var characteristicUUID: String
    /// Space-separated hex bytes plus {throttle} and/or {rudder} (signed int8, two's complement).
    public var template: String
    public init(characteristicUUID: String, template: String) {
        self.characteristicUUID = characteristicUUID; self.template = template
    }
    public func payload(throttle: UInt8, rudder: Int8) throws -> Data {
        let parts = template.split(whereSeparator: { $0.isWhitespace })
        guard !parts.isEmpty, parts.count <= 64 else { throw ProtocolError.invalid("Paket muss 1–64 Bytes enthalten.") }
        return try Data(parts.map { token in
            switch token.lowercased() {
            case "{throttle}": return throttle
            case "{rudder}": return UInt8(bitPattern: rudder)
            default:
                guard token.count == 2, let byte = UInt8(token, radix: 16) else { throw ProtocolError.invalid("Ungültiges Byte: \(token)") }
                return byte
            }
        })
    }
}

public struct ControlProfile: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var serviceUUID: String
    public var throttleMax: Int
    public var rudderMax: Int
    public var commands: [ControlCommand]
    public var evidence: String
    public init(id: String, name: String, serviceUUID: String, throttleMax: Int = 254, rudderMax: Int = 126, commands: [ControlCommand], evidence: String) {
        self.id = id; self.name = name; self.serviceUUID = serviceUUID
        self.throttleMax = throttleMax; self.rudderMax = rudderMax; self.commands = commands; self.evidence = evidence
    }
    public func validate() throws {
        guard !id.isEmpty, !name.isEmpty, UUID(uuidString: serviceUUID) != nil,
              (1...254).contains(throttleMax), (1...126).contains(rudderMax), (1...4).contains(commands.count) else {
            throw ProtocolError.invalid("Ungültiges Steuerprofil: UUID, Grenzen oder Befehle prüfen.")
        }
        guard commands.contains(where: { $0.template.lowercased().contains("{throttle}") }),
              commands.contains(where: { $0.template.lowercased().contains("{rudder}") }) else {
            throw ProtocolError.invalid("Profil benötigt Schub- und Ruderkanal.")
        }
        for command in commands {
            guard UUID(uuidString: command.characteristicUUID) != nil else { throw ProtocolError.invalid("Ungültige Characteristic-UUID.") }
            _ = try command.payload(throttle: 0, rudder: 0)
        }
    }
    public func values(throttle: Double, rudder: Double, limit: Double) -> (UInt8, Int8) {
        let t = throttle.isFinite ? min(1, max(0, throttle)) : 0
        let r = rudder.isFinite ? min(1, max(-1, rudder)) : 0
        let l = limit.isFinite ? min(1, max(0, limit)) : 0
        return (UInt8((t * l * Double(throttleMax)).rounded()), Int8((r * Double(rudderMax)).rounded()))
    }
    public static let legacy = ControlProfile(id: "tobyrich-smartlink", name: "SmartLink · SmartPlane / Moskito", serviceUUID: "75B64E51-F171-4ED1-921A-476090D80BA7", commands: [
        .init(characteristicUUID: "75B64E51-0010-4ED1-921A-476090D80BA7", template: "{throttle}"),
        .init(characteristicUUID: "75B64E51-0021-4ED1-921A-476090D80BA7", template: "{rudder}")
    ], evidence: "TobyRich Android SmartLink (2015); Pro-Kompatibilität nicht bestätigt.")
    public static let legacyTest = ControlProfile(id: "tobyrich-smartlink-test", name: "SmartLink · ältere Testvariante", serviceUUID: "75B64E51-F181-4ED1-921A-476090D80BA7", commands: [
        .init(characteristicUUID: "75B64E51-F184-4ED1-921A-476090D80BA7", template: "{throttle}"),
        .init(characteristicUUID: "75B64E51-F185-4ED1-921A-476090D80BA7", template: "{rudder}")
    ], evidence: "TobyRich services.plist sml1test; Pro-Kompatibilität nicht bestätigt.")
    public static let builtins = [legacy, legacyTest]
}

public extension Data {
    var hex: String { map { String(format: "%02X", $0) }.joined(separator: " ") }
    init(strictHex: String) throws {
        let compact = strictHex.filter { !$0.isWhitespace }
        guard !compact.isEmpty, compact.count.isMultiple(of: 2), compact.count <= 1024 else { throw ProtocolError.invalid("1–512 vollständige Hex-Bytes eingeben.") }
        var bytes: [UInt8] = []; var index = compact.startIndex
        while index < compact.endIndex {
            let end = compact.index(index, offsetBy: 2)
            guard let byte = UInt8(compact[index..<end], radix: 16) else { throw ProtocolError.invalid("Nur Hex-Zeichen 0–9 und A–F verwenden.") }
            bytes.append(byte); index = end
        }
        self.init(bytes)
    }
}

public struct FlightGate: Sendable {
    public private(set) var armed = false
    public init() {}
    public mutating func arm(connected: Bool, profileReady: Bool, acknowledged: Bool, throttle: Double) -> Bool {
        armed = connected && profileReady && acknowledged && throttle.isFinite && throttle <= 0 && throttle >= 0
        return armed
    }
    public mutating func stop() { armed = false }
    public func output(throttle: Double, rudder: Double) -> (Double, Double) {
        armed ? (throttle, rudder) : (0, 0)
    }
}
