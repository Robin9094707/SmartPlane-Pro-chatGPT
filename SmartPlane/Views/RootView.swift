import SwiftUI
import UniformTypeIdentifiers
import PlaneProtocol

struct RootView: View {
    @EnvironmentObject var ble: BluetoothController
    @State private var selection = 0
    var body: some View {
        TabView(selection: $selection) {
            HomeView(selection: $selection).tabItem { Label("Hangar", systemImage: "airplane") }.tag(0)
            ScannerView().tabItem { Label("Verbinden", systemImage: "antenna.radiowaves.left.and.right") }.tag(1)
            LabView().tabItem { Label("Bluetooth-Labor", systemImage: "waveform.path.ecg") }.tag(2)
            SettingsView().tabItem { Label("Einstellungen", systemImage: "slider.horizontal.3") }.tag(3)
        }.preferredColorScheme(.dark)
            .onChange(of: selection) { _, _ in if ble.armed { ble.stop(reason: "Ansicht gewechselt") } }
    }
}
private enum CockpitRoute: String, Identifiable {
    case live, training
    var id: String { rawValue }
    var isTraining: Bool { self == .training }
}
struct HomeView: View {
    @EnvironmentObject var ble: BluetoothController
    @Binding var selection: Int
    @State private var cockpit: CockpitRoute?
    var body: some View {
        NavigationStack {
            ZStack {
                SkyBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack { Text("SMARTPLANE").font(.caption.bold()).tracking(4).foregroundStyle(.mint); Spacer(); Text("PRO / REVIVAL").font(.caption2.monospaced()).foregroundStyle(.secondary) }
                        Text("Zurück in\ndie Luft.").font(.system(size: 48, weight: .bold, design: .rounded)).tracking(-2)
                        Text("Dein Flugzeug. Ein neues Cockpit.").font(.subheadline).foregroundStyle(.secondary)
                        ZStack {
                            ForEach(0..<3) { i in Circle().stroke(.mint.opacity(0.05 + Double(i)*0.025), lineWidth: 1).frame(width: CGFloat(150+i*65), height: CGFloat(150+i*65)).scaleEffect(y: 0.65) }
                            PlaneSilhouette().fill(LinearGradient(colors: [.mint, .cyan.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 225, height: 240).rotationEffect(.degrees(-30)).shadow(color: .mint.opacity(0.25), radius: 30, y: 20)
                            VStack { Spacer(); StatusPill(text: ble.connectedName ?? "Bereit für die Verbindung", active: ble.connected) }.padding(.bottom, 3)
                        }.frame(height: 280).frame(maxWidth: .infinity)
                        HStack(spacing: 12) {
                            Metric(title: "Signal", value: ble.rssi.map { "\($0) dBm" } ?? "—", symbol: "antenna.radiowaves.left.and.right")
                            Metric(title: "Akku", value: ble.battery.map { "\($0) %" } ?? "—", symbol: "battery.75percent")
                            Metric(title: "Verbindung", value: ble.connected ? "BLE" : "Offline", symbol: "link")
                        }.panel()
                        VStack(alignment: .leading, spacing: 12) {
                            Label(ble.profile == nil ? "Protokoll prüfen" : "Steuerprofil erkannt", systemImage: ble.profile == nil ? "magnifyingglass" : "checkmark.circle").font(.headline)
                            Text(ble.profile?.evidence ?? "Die App erkennt bekannte SmartLink-Dienste. Für SmartPlane Pro ist die Steuerung noch nicht bestätigt. Bei abweichendem Protokoll hilft das Bluetooth-Labor.").font(.subheadline).foregroundStyle(.secondary)
                        }.panel()
                        Button { if ble.connected { cockpit = .live } else { selection = 1 } } label: {
                            Label(ble.connected ? "Cockpit öffnen" : "Flugzeug verbinden", systemImage: ble.connected ? "airplane.departure" : "antenna.radiowaves.left.and.right").font(.headline).frame(maxWidth: .infinity).padding(18)
                        }.buttonStyle(.borderedProminent).tint(.mint).foregroundStyle(.black)
                        Button { cockpit = .training } label: { Label("Cockpit im Trainingsmodus ansehen", systemImage: "play.circle").frame(maxWidth: .infinity) }.buttonStyle(.plain).foregroundStyle(.mint)
                        Text("Training sendet keine Bluetooth-Befehle.").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }.padding(24).padding(.bottom, 20)
                }
            }.toolbar(.hidden, for: .navigationBar)
                .fullScreenCover(item: $cockpit) { route in CockpitView(demo: route.isTraining).environmentObject(ble).preferredColorScheme(.dark) }
        }
    }
}
struct ScannerView: View {
    @EnvironmentObject var ble: BluetoothController
    @State private var showAll = false
    @State private var search = ""
    private var filtered: [NearbyPlane] { ble.devices.filter { (showAll || $0.probablePlane) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.id.uuidString.localizedCaseInsensitiveContains(search)) } }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(ble.bluetoothStatus, systemImage: "antenna.radiowaves.left.and.right").font(.subheadline)
                    if ble.connected {
                        LabeledContent("Verbunden", value: ble.connectedName ?? "Gerät")
                        Button("Verbindung trennen", role: .destructive) { ble.disconnect() }
                    } else if ble.connectingID != nil {
                        HStack { ProgressView(); Text("Verbindung wird aufgebaut …") }
                        Button("Abbrechen", role: .cancel) { ble.disconnect() }
                    } else {
                        Button { ble.scanning ? ble.stopScan() : ble.scan() } label: { Label(ble.scanning ? "Suche beenden" : "20 Sekunden suchen", systemImage: ble.scanning ? "stop.circle" : "magnifyingglass") }
                    }
                } footer: { Text("Akku einsetzen, Flugzeug nah ans iPhone halten. Verbinden erfolgt hier in der App. Ein Gerätename allein bestätigt kein passendes Protokoll.") }
                Section {
                    Toggle("Alle BLE-Geräte anzeigen", isOn: $showAll)
                } footer: { Text("Wenn dein Flugzeug nicht erkannt wird, aktiviere diese Option. Auch unbenannte Geräte sind dann sichtbar.") }
                Section("In der Nähe · \(filtered.count)") {
                    if filtered.isEmpty {
                        ContentUnavailableView(ble.scanning ? "Suche läuft …" : "Noch kein Flugzeug", systemImage: "airplane", description: Text("Suche starten oder alle BLE-Geräte einblenden."))
                    }
                    ForEach(filtered) { device in
                        NavigationLink {
                            DeviceDetailView(device: device)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: device.probablePlane ? "airplane" : "wave.3.right").font(.title2).foregroundStyle(device.probablePlane ? .mint : .secondary)
                                VStack(alignment: .leading, spacing: 5) { Text(device.name).font(.headline); Text(device.id.uuidString).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1) }
                                Spacer(); Text("\(device.rssi)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }.padding(.vertical, 6)
                        }
                    }
                }
            }.searchable(text: $search, prompt: "Gerätename oder Kennung").navigationTitle("Verbinden")
        }
    }
}
struct DeviceDetailView: View {
    @EnvironmentObject var ble: BluetoothController
    let device: NearbyPlane
    var body: some View {
        List {
            Section {
                Text(device.name).font(.title2.bold())
                LabeledContent("Signal", value: "\(device.rssi) dBm")
                Text(device.id.uuidString).font(.caption.monospaced()).textSelection(.enabled)
                if ble.connectedID == device.id { Label("Verbunden – Labor öffnen für GATT", systemImage: "checkmark.circle").foregroundStyle(.mint) }
                else { Button("Mit diesem Gerät verbinden") { ble.connect(device.id) }.disabled(ble.connected || ble.connectingID != nil) }
            }
            Section("Werbedaten / Advertisement") {
                ForEach(device.advertisement.keys.sorted(), id: \.self) { key in VStack(alignment: .leading, spacing: 6) { Text(key).font(.caption).foregroundStyle(.secondary); Text(device.advertisement[key] ?? "").font(.caption.monospaced()).textSelection(.enabled) } }
            }
        }.navigationTitle("BLE-Gerät").navigationBarTitleDisplayMode(.inline)
    }
}
struct SettingsView: View {
    @EnvironmentObject var ble: BluetoothController
    @State private var importing = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Steuerung") {
                    LabeledContent("Maximaler Schub", value: "\(Int(ble.throttleLimit*100)) %")
                    Slider(value: $ble.throttleLimit, in: 0.1...1, step: 0.05).disabled(ble.armed)
                    Text("Nach dem Verbinden ist der Motor gesperrt. Freigabe erfolgt im Cockpit. Beim Verlassen oder Sperren der App wird ein Stopp angefordert und die Verbindung getrennt.").font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    ForEach(ControlProfile.builtins) { p in VStack(alignment: .leading, spacing: 4) { Text(p.name); Text(p.evidence).font(.caption).foregroundStyle(.secondary) } }
                    ForEach(ble.customProfiles) { p in HStack { Text(p.name); Spacer(); Button(role: .destructive) { ble.removeProfile(p) } label: { Image(systemName: "trash") }.disabled(ble.armed) } }
                    Button("JSON-Steuerprofil importieren") { importing = true }.disabled(ble.armed)
                } header: { Text("Steuerprofile") } footer: { Text("Eigene Profile nur mit belegten UUIDs und Befehlen verwenden. Keine automatischen Pro-Stunts ohne rekonstruiertes Protokoll.") }
                Section("Firmware & Datenschutz") {
                    Text("Das Labor liest die angebotenen Bluetooth-Dienste, Firmware-Versionsnummern und Rohwerte. Ein vollständiges Firmware-Abbild lässt sich über normales BLE nicht allgemein auslesen.")
                    Text("Alle Daten bleiben auf deinem iPhone. Berichte werden nur über die Teilen-Funktion weitergegeben. Keine Analyse- oder Cloud-Dienste.")
                }
                Section("Installation") { Text("Die GitHub-Aktion erstellt eine unsignierte IPA. Diese vor der Installation mit deinem Signierdienst oder einem eigenen Apple-Profil signieren. Bluetooth benötigt keine speziellen Entitlements.") }
                Section("Projekt") {
                    Link("Quellcode & IPA-Builds", destination: URL(string: "https://github.com/Robin9094707/SmartPlane-Pro-chatGPT")!)
                    LabeledContent("Version", value: "1.0.0 · Research Preview")
                }
            }.navigationTitle("Einstellungen")
                .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                    do { try ble.importProfile(from: result.get()) } catch { ble.problem = error.localizedDescription }
                }
        }
    }
}
