import SwiftUI
import UIKit

struct CockpitView: View {
    @EnvironmentObject var ble: BluetoothController
    @Environment(\.dismiss) private var dismiss
    @StateObject private var motion = MotionSteering()
    let demo: Bool
    @State private var tilt = false
    @State private var inverted = false
    @State private var acknowledged = false
    @State private var showArm = false
    @State private var demoArmed = false
    @State private var demoThrottle: Double = 0
    @State private var demoRudder: Double = 0
    private var isArmed: Bool { demo ? demoArmed : ble.armed }
    private var thrust: Double { demo ? demoThrottle : ble.throttle }
    private var turn: Double { demo ? demoRudder : ble.rudder }
    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            ZStack {
                SkyBackground()
                VStack(spacing: landscape ? 10 : 24) {
                    topBar
                    if landscape {
                        HStack(spacing: 24) { throttleControl.frame(width: 120); horizon(compact: true).frame(maxWidth: .infinity); steeringControl(compact: true).frame(width: 210) }.frame(maxHeight: .infinity)
                    } else {
                        horizon(compact: false).frame(height: geometry.size.height * 0.26)
                        HStack(alignment: .center, spacing: 30) { throttleControl.frame(width: 100); steeringControl(compact: false).frame(maxWidth: .infinity) }.frame(maxHeight: .infinity)
                    }
                    bottomBar
                }.padding(landscape ? 16 : 24)
            }
        }.onAppear { UIApplication.shared.isIdleTimerDisabled = true }
            .onDisappear { stop(); motion.stop(); UIApplication.shared.isIdleTimerDisabled = false }
            .onChange(of: tilt) { _, enabled in stop(); if enabled { motion.start() } else { motion.stop() } }
            .onChange(of: motion.value) { _, value in if tilt { setTurn(inverted ? -value : value) } }
            .onChange(of: ble.connected) { _, connected in if !demo && !connected { stop() } }
            .sheet(isPresented: $showArm) { armSheet.presentationDetents([.medium, .large]).presentationDragIndicator(.visible) }
    }
    private var topBar: some View {
        HStack {
            Button { stop(); dismiss() } label: { Image(systemName: "xmark").font(.headline).frame(width: 44, height: 44).planeGlass() }.accessibilityLabel("Cockpit schließen")
            Spacer()
            VStack(spacing: 3) { Text(demo ? "TRAINING" : "FLIGHT DECK").font(.caption.bold()).tracking(3); Text(demo ? "Keine Bluetooth-Ausgabe" : ble.connectedName ?? "Keine Verbindung").font(.caption2).foregroundStyle(.secondary) }
            Spacer()
            StatusPill(text: isArmed ? "FREI" : "GESPERRT", active: isArmed)
        }
    }
    private func horizon(compact: Bool) -> some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().stroke(.white.opacity(0.1), lineWidth: 1)
                Circle().trim(from: 0.55, to: 0.95).stroke(.mint.opacity(0.4), style: StrokeStyle(lineWidth: 2, lineCap: .round)).rotationEffect(.degrees(-90))
                VStack(spacing: 16) {
                    Rectangle().fill(.white.opacity(0.12)).frame(width: 50, height: 1)
                    HStack(spacing: 15) { Rectangle().frame(width: 35, height: 2); Circle().stroke(lineWidth: 2).frame(width: 8, height: 8); Rectangle().frame(width: 35, height: 2) }.foregroundStyle(.mint)
                    Rectangle().fill(.white.opacity(0.12)).frame(width: 50, height: 1)
                }.rotationEffect(.degrees(turn * -30))
                Text("L").font(.caption2).offset(x: -65)
                Text("R").font(.caption2).offset(x: 65)
            }.frame(maxWidth: compact ? 115 : 190, maxHeight: compact ? 115 : 190).aspectRatio(1, contentMode: .fit)
            HStack(spacing: 24) {
                Text(demo ? "SIMULATION" : ble.rssi.map { "\($0) dBm" } ?? "Signal —")
                Text(demo ? "Akku —" : ble.battery.map { "\($0) %" } ?? "Akku —")
            }.font(.caption.monospaced()).foregroundStyle(.secondary)
            Text("Steuereingabe · keine Fluglage-Telemetrie").font(.system(size: 9)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }
    private var throttleControl: some View {
        VStack(spacing: 10) {
            Text("SCHUB").font(.caption2.bold()).tracking(2).foregroundStyle(.secondary)
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 24).fill(.white.opacity(0.06))
                    RoundedRectangle(cornerRadius: 24).fill(LinearGradient(colors: [.mint.opacity(0.7), .cyan.opacity(0.1)], startPoint: .bottom, endPoint: .top)).frame(height: max(0, geo.size.height * thrust))
                    VStack { Image(systemName: "chevron.up.chevron.up").foregroundStyle(.mint.opacity(0.7)); Spacer(); Text("HALTEN").font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(.secondary) }.padding(.vertical, 16)
                    Capsule().fill(.white).frame(width: 38, height: 5).offset(y: -max(8, (geo.size.height - 18) * thrust))
                }.contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0).onChanged { gesture in setThrust(1 - gesture.location.y / max(1, geo.size.height)) }.onEnded { _ in setThrust(0) })
                    .accessibilityLabel("Schub, zum Steuern gedrückt halten").accessibilityValue("\(Int(thrust * 100)) Prozent")
            }.frame(maxHeight: 270)
            Text("\(Int(thrust * (demo ? 50 : ble.throttleLimit * 100))) %").font(.title3.bold().monospacedDigit())
        }.opacity(isArmed ? 1 : 0.5)
    }
    private func steeringControl(compact: Bool) -> some View {
        let diameter: CGFloat = compact ? 100 : 180
        let travel: CGFloat = compact ? 27 : 60
        return VStack(spacing: compact ? 8 : 14) {
            Picker("Steuerung", selection: $tilt) { Text("Joystick").tag(false); Text("Neigen").tag(true) }.pickerStyle(.segmented).disabled(isArmed)
            ZStack {
                Circle().fill(.white.opacity(0.04)).overlay { Circle().stroke(.white.opacity(0.15)) }
                Rectangle().fill(.white.opacity(0.08)).frame(height: 1).padding(20)
                Rectangle().fill(.white.opacity(0.08)).frame(width: 1).padding(20)
                Image(systemName: tilt ? "iphone.gen3.radiowaves.left.and.right" : "arrow.left.and.right").font(.title2).foregroundStyle(.mint.opacity(0.35))
                Circle().fill(.mint.opacity(0.85)).frame(width: 48, height: 48).shadow(color: .mint.opacity(0.3), radius: 15).offset(x: turn * travel).allowsHitTesting(false)
            }.frame(width: diameter, height: diameter).contentShape(Circle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in if !tilt { let input = (gesture.location.x - diameter / 2) / travel; setTurn(inverted ? -input : input) } }.onEnded { _ in if !tilt { setTurn(0) } })
                .accessibilityLabel("Ruder, links und rechts ziehen").accessibilityValue("\(Int(turn * 100))")
            if tilt { Button("Neutralpunkt setzen") { motion.calibrate() }.font(.caption).disabled(isArmed); if !motion.available { Text("Bewegungssensor nicht verfügbar").font(.caption2).foregroundStyle(.orange) } }
            else { Text("Loslassen zentriert das Ruder").font(.caption2).foregroundStyle(.secondary) }
            Toggle("Ruder umkehren", isOn: $inverted).font(.caption).disabled(isArmed)
        }.opacity(isArmed ? 1 : 0.75)
    }
    private var bottomBar: some View {
        HStack(spacing: 14) {
            Button { stop() } label: { Label("STOP", systemImage: "stop.fill").font(.title3.bold()).frame(maxWidth: .infinity).padding(.vertical, 17) }.buttonStyle(.borderedProminent).tint(.red).accessibilityHint("Fordert sofort Nullschub an")
            Button { showArm = true; acknowledged = false } label: { Label(isArmed ? "Freigegeben" : "Freigeben", systemImage: isArmed ? "lock.open" : "lock").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 17) }.buttonStyle(.bordered).tint(.mint).disabled(isArmed || (!demo && !ble.canArm))
        }
    }
    private var armSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Label(demo ? "Training freigeben" : "Steuerung freigeben", systemImage: "airplane").font(.title2.bold())
                    Text(demo ? "Du kannst die Bedienung ausprobieren. Es werden keine Befehle an ein Flugzeug gesendet." : "Profil: \(ble.profile?.name ?? "Kein Profil")\n\nSmartPlane-Pro-Kompatibilität ist unbestätigt. Zuerst am Boden mit entferntem Propeller die Ruder, Nullschub und STOP prüfen.")
                    Toggle(demo ? "Trainingsmodus verstanden" : "Profil und Bodentest geprüft", isOn: $acknowledged)
                    Button(demo ? "Training starten" : "Steuerung jetzt freigeben") {
                        if demo { demoArmed = true } else { ble.arm(acknowledged: acknowledged) }
                        showArm = false
                    }.disabled(!acknowledged)
                }
            }.navigationTitle("Vor dem Start").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { showArm = false } } }
        }
    }
    private func setThrust(_ value: Double) {
        if demo { demoThrottle = demoArmed ? min(1, max(0, value)) : 0 } else { ble.setThrottle(value) }
    }
    private func setTurn(_ value: Double) {
        if demo { demoRudder = demoArmed ? min(1, max(-1, value)) : 0 } else { ble.setRudder(value) }
    }
    private func stop() {
        if demo { demoArmed = false; demoThrottle = 0; demoRudder = 0 }
        else { ble.stop(reason: "Cockpit-Stopp") }
    }
}
