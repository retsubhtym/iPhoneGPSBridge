import SwiftUI

@main
struct iPhoneGPSBridgeApp: App {
    @StateObject private var bridge = GPSBridge()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bridge)
        }
    }
}
