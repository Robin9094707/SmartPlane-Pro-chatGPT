import XCTest
@testable import PlaneProtocol
final class ProtocolTests: XCTestCase {
    func testPublishedEndpointsAndEncoding() throws {
        let p = ControlProfile.legacy
        try p.validate()
        XCTAssertEqual(p.serviceUUID, "75B64E51-F171-4ED1-921A-476090D80BA7")
        XCTAssertEqual(try p.commands[0].payload(throttle: 254, rudder: -126), Data([254]))
        XCTAssertEqual(try p.commands[1].payload(throttle: 254, rudder: -126), Data([130]))
        XCTAssertEqual(try p.commands[1].payload(throttle: 0, rudder: 126), Data([126]))
    }
    func testLimitsAndNonFiniteInput() {
        let p = ControlProfile.legacy
        let (t, r) = p.values(throttle: 10, rudder: -10, limit: 0.5)
        XCTAssertEqual(t, 127); XCTAssertEqual(r, -126)
        let (bad, _) = p.values(throttle: .nan, rudder: .infinity, limit: 1)
        XCTAssertEqual(bad, 0)
    }
    func testGateAndStop() {
        var g = FlightGate()
        XCTAssertFalse(g.arm(connected: false, profileReady: true, acknowledged: true, throttle: 0))
        XCTAssertFalse(g.arm(connected: true, profileReady: false, acknowledged: true, throttle: 0))
        XCTAssertFalse(g.arm(connected: true, profileReady: true, acknowledged: false, throttle: 0))
        XCTAssertFalse(g.arm(connected: true, profileReady: true, acknowledged: true, throttle: 0.01))
        XCTAssertTrue(g.arm(connected: true, profileReady: true, acknowledged: true, throttle: 0))
        g.stop(); XCTAssertEqual(g.output(throttle: 1, rudder: 1).0, 0)
    }
    func testCustomPacketAndRejection() throws {
        let c = ControlCommand(characteristicUUID: UUID().uuidString, template: "A5 {throttle} {rudder} 00")
        XCTAssertEqual(try c.payload(throttle: 100, rudder: -1), Data([165,100,255,0]))
        XCTAssertThrowsError(try ControlCommand(characteristicUUID: "bad", template: "{unknown}").payload(throttle: 0, rudder: 0))
        var profile = ControlProfile.legacy
        profile.throttleMax = 1000; XCTAssertThrowsError(try profile.validate())
        profile = .legacy; profile.commands = [.init(characteristicUUID: UUID().uuidString, template: "01")]
        XCTAssertThrowsError(try profile.validate())
        XCTAssertThrowsError(try Data(strictHex: "0")); XCTAssertThrowsError(try Data(strictHex: "GG"))
        XCTAssertEqual(try Data(strictHex: "aA 01\nFF").hex, "AA 01 FF")
    }
    func testProfilesRoundTrip() throws {
        for p in ControlProfile.builtins {
            try p.validate()
            XCTAssertEqual(try JSONDecoder().decode(ControlProfile.self, from: JSONEncoder().encode(p)), p)
        }
    }
}
