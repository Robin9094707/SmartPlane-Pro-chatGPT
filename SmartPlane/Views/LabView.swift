import SwiftUI
import PlaneProtocol

struct LabView: View {
    @EnvironmentObject var ble: BluetoothController
    @State private var report: URL?
    @State private var showEvents = false
    @State private var filter = ""
    private var services: [String] { Array(Set(ble.entries.map(\.service))).sorted() }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(ble.connectedName ?? "Kein Gerät verbunden", systemImage: ble.connected ? "link" : "link.badge.plus").font(.headline)
                    HStack {
                        Text("RX \(ble.totalRX)  •  TX \(ble.totalTX)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Spacer()
                        if ble.connected && !ble.discoveryComplete { ProgressView() }
                    }
                    if ble.connected {
                        Text(ble.profile?.name ?? "Unbekanntes Protokoll · Diagnose verfügbar").font(.caption).foregroundStyle(ble.profile == nil ? .orange : .mint)
                        if !ble.matchingProfiles.isEmpty {
                            Menu("Passendes Steuerprofil auswählen") {
                                ForEach(ble.matchingProfiles) { p in Button(p.name) { ble.selectProfile(p) } }
                            }.disabled(ble.armed)
                        }
                        Button("Alle lesbaren Werte abfragen") { ble.readAll() }.disabled(ble.armed)
                    }
                    Button { do { report = try ble.exportReport() } catch { ble.problem = error.localizedDescription } } label: { Label("Aktuellen Diagnosebericht erstellen", systemImage: "doc.badge.gearshape") }
                    if let report { ShareLink(item: report) { Label("Diagnosebericht teilen", systemImage: "square.and.arrow.up") } }
                } footer: { Text("Der Bericht enthält BLE-Kennung, Werbedaten, Dienste, Firmware-Informationen soweit lesbar und bis zu 2.000 Protokollereignisse. Er enthält kein vollständiges Firmware-Abbild. Nach neuen Messungen den Bericht erneut erstellen.") }
                Section {
                    Toggle("Ereignisprotokoll anzeigen", isOn: $showEvents)
                }
                if showEvents {
                    Section("Letzte 200 Ereignisse") {
                        Button("Protokoll löschen", role: .destructive) { ble.clearEvents() }.disabled(ble.armed)
                        ForEach(Array(ble.events.suffix(200).reversed())) { event in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack { Text(event.time, style: .time); Text(event.kind.uppercased()).foregroundStyle(.mint) }.font(.caption2.monospaced())
                                Text(event.message).font(.caption.monospaced()).textSelection(.enabled)
                            }
                        }
                    }
                } else {
                    if services.isEmpty { ContentUnavailableView("Bluetooth untersuchen", systemImage: "waveform.path.ecg", description: Text("Verbinde dein Flugzeug. Auch bei unbekanntem Protokoll kannst du hier alle angebotenen Dienste untersuchen.")) }
                    ForEach(services, id: \.self) { service in
                        Section(serviceName(service)) {
                            Text(service).font(.caption2.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                            ForEach(ble.entries.filter { $0.service == service && (filter.isEmpty || $0.uuid.localizedCaseInsensitiveContains(filter) || characteristicName($0.uuid).localizedCaseInsensitiveContains(filter)) }) { entry in
                                NavigationLink { CharacteristicView(entryID: entry.id) } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(characteristicName(entry.uuid)).font(.subheadline.bold())
                                        Text(entry.uuid).font(.caption2.monospaced()).foregroundStyle(.secondary)
                                        Text(entry.properties.joined(separator: " · ")).font(.caption2).foregroundStyle(.mint)
                                        if !entry.valueHex.isEmpty { Text(entry.valueHex).font(.caption.monospaced()).lineLimit(2) }
                                    }.padding(.vertical, 4)
                                }
                            }
                        }
                    }
                }
            }.navigationTitle("Bluetooth-Labor").searchable(text: $filter, prompt: "UUID oder Eigenschaft")
        }
    }
}
func serviceName(_ uuid: String) -> String {
    switch uuid.uppercased() {
    case "180A": return "Geräteinformationen"
    case "180F": return "Batterie"
    case "1800": return "Generic Access"
    case "1801": return "Generic Attribute"
    default: return uuid.lowercased().hasPrefix("75b64e51") ? "TobyRich SmartLink" : "Herstellerspezifischer Dienst"
    }
}
func characteristicName(_ uuid: String) -> String {
    switch uuid.uppercased() {
    case "2A19": return "Akkustand"
    case "2A24": return "Modellnummer"
    case "2A25": return "Seriennummer"
    case "2A26": return "Firmware-Version"
    case "2A27": return "Hardware-Version"
    case "2A28": return "Software-Version"
    case "2A29": return "Hersteller"
    case "2A00": return "Gerätename"
    case "75B64E51-0010-4ED1-921A-476090D80BA7": return "SmartLink · Motor"
    case "75B64E51-0021-4ED1-921A-476090D80BA7": return "SmartLink · Ruder"
    case "75B64E51-0030-4ED1-921A-476090D80BA7": return "SmartLink · Temperatur"
    case "75B64E51-0040-4ED1-921A-476090D80BA7": return "SmartLink · Ladestatus"
    default: return "Characteristic"
    }
}
struct CharacteristicView: View {
    @EnvironmentObject var ble: BluetoothController
    let entryID: String
    @State private var hex = ""
    @State private var response = true
    @State private var confirmation = false
    private var entry: GATTEntry? { ble.entries.first { $0.id == entryID } }
    var body: some View {
        Form {
            if let entry {
                Section("Eigenschaft") {
                    Text(characteristicName(entry.uuid)).font(.headline)
                    Text(entry.uuid).font(.caption.monospaced()).textSelection(.enabled)
                    Text("Dienst: \(entry.service)").font(.caption.monospaced()).textSelection(.enabled)
                    Text(entry.properties.joined(separator: " · ")).font(.caption).foregroundStyle(.mint)
                }
                Section("Wert") {
                    LabeledContent("Hex") { Text(entry.valueHex.isEmpty ? "Noch kein Wert" : entry.valueHex).font(.caption.monospaced()).textSelection(.enabled) }
                    if !entry.valueText.isEmpty { LabeledContent("UTF-8") { Text(entry.valueText).font(.caption).textSelection(.enabled) } }
                    if let date = entry.updatedAt { LabeledContent("Empfangen") { Text(date, style: .time).font(.caption) } }
                    if entry.properties.contains("read") { Button("Wert lesen") { ble.read(entryID) }.disabled(ble.armed) }
                    if entry.properties.contains("notify") || entry.properties.contains("indicate") {
                        Toggle("Benachrichtigungen", isOn: Binding(get: { entry.notifying }, set: { ble.notify(entryID, enabled: $0) })).disabled(ble.armed)
                    }
                    Button("Deskriptoren untersuchen") { ble.inspectDescriptors(entryID) }.disabled(ble.armed)
                    ForEach(entry.descriptors.keys.sorted(), id: \.self) { key in LabeledContent(key, value: entry.descriptors[key] ?? "").font(.caption.monospaced()) }
                }
                if entry.properties.contains("write") || entry.properties.contains("writeWithoutResponse") {
                    Section {
                        TextField("Hex-Bytes, z. B. 00", text: $hex).font(.body.monospaced()).textInputAutocapitalization(.characters).autocorrectionDisabled()
                        Toggle("Mit Antwort schreiben", isOn: $response)
                        Button("Einzelnes Paket senden", role: .destructive) { confirmation = true }.disabled(ble.armed || hex.isEmpty)
                    } header: { Text("Expertenkonsole") } footer: {
                        Text("Nur bekannte Befehle senden. Ein Paket kann den Motor starten, Einstellungen verändern oder einen Bootloader auslösen. Unbekannte Firmware-Befehle nicht ausprobieren. Vor Motortests den Propeller entfernen.")
                    }
                }
            } else { ContentUnavailableView("Nicht mehr verfügbar", systemImage: "link.slash") }
        }.navigationTitle("GATT-Details").navigationBarTitleDisplayMode(.inline)
            .onAppear { if let entry { response = entry.properties.contains("write") } }
            .alert("Rohpaket senden?", isPresented: $confirmation) {
                Button("Abbrechen", role: .cancel) {}
                Button("Paket senden", role: .destructive) { do { try ble.rawWrite(id: entryID, hex: hex, withResponse: response) } catch { ble.problem = error.localizedDescription } }
            } message: { Text("\(hex)\n\nNur fortfahren, wenn du die Wirkung dieses Befehls kennst. Das Flugzeug kann sofort reagieren.") }
    }
}
