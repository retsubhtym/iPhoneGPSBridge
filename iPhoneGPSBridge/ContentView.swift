import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var bridge: GPSBridge

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    LabeledContent("Status", value: bridge.serverStatus)
                    LabeledContent("TCP port", value: "\(bridge.port)")
                    LabeledContent("Clients", value: "\(bridge.clientCount)")
                }

                Section("Location") {
                    LabeledContent("Permission", value: bridge.authorizationText)
                    LabeledContent("Latitude", value: coordinate(bridge.latitude))
                    LabeledContent("Longitude", value: coordinate(bridge.longitude))
                    LabeledContent("Accuracy", value: distance(bridge.horizontalAccuracy))
                    LabeledContent("Altitude", value: distance(bridge.altitude))
                    LabeledContent("Speed", value: speed(bridge.speed))
                }

                Section {
                    Button(bridge.isRunning ? "Stop GPS Bridge" : "Start GPS Bridge") {
                        bridge.isRunning ? bridge.stop() : bridge.start()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Request Always Location Access") {
                        bridge.requestAlwaysAuthorization()
                    }

                    Text("Always location access is recommended for reliable streaming when this app is in the background.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Laptop connection") {
                    Text("Connect the iPhone by USB, trust the laptop, then run in Terminal 1:")
                    Text("iproxy 10110 10110")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                    Text("Keep it running. In Terminal 2, read the GPS stream with:")
                    Text("nc 127.0.0.1 10110")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }

                if let error = bridge.lastError {
                    Section("Last error") {
                        Text(error)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("GPS Bridge")
        }
    }

    private func coordinate(_ value: Double?) -> String {
        guard let value else { return "-" }
        return String(format: "%.7f", value)
    }

    private func distance(_ value: Double?) -> String {
        guard let value, value >= 0 else { return "-" }
        return String(format: "%.1f m", value)
    }

    private func speed(_ value: Double?) -> String {
        guard let value, value >= 0 else { return "-" }
        return String(format: "%.2f m/s", value)
    }
}
