import SwiftUI
import UIKit

@main struct SmartPlaneApp: App {
    @StateObject private var bluetooth = BluetoothController()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(bluetooth)
                .tint(.mint)
                .onChange(of: scenePhase) { _, phase in if phase != .active { bluetooth.suspend() } }
                .alert("SmartPlane", isPresented: Binding(get: { bluetooth.problem != nil }, set: { if !$0 { bluetooth.problem = nil } })) {
                    Button("OK") { bluetooth.problem = nil }
                } message: { Text(bluetooth.problem ?? "") }
        }
    }
}
