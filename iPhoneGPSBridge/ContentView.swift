import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var bridge: GPSBridge

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    LabeledContent("Status", value: bridge.serverStatus)
                    LabeledContent("TCP port") {
                        PortWheelPicker(port: $bridge.port)
                            .frame(width: 110, height: 100)
                            .clipped()
                    }
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
                    Text(bridge.iproxyCommand)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                    Text("Keep it running. In Terminal 2, read the GPS stream with:")
                    Text(bridge.netcatCommand)
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

private struct PortWheelPicker: UIViewRepresentable {
    @Binding var port: UInt16

    func makeCoordinator() -> Coordinator {
        Coordinator(port: $port)
    }

    func makeUIView(context: Context) -> UIPickerView {
        let picker = UIPickerView()
        picker.dataSource = context.coordinator
        picker.delegate = context.coordinator
        picker.selectRow(Int(port) - 1, inComponent: 0, animated: false)
        picker.accessibilityLabel = "TCP port"
        return picker
    }

    func updateUIView(_ picker: UIPickerView, context: Context) {
        let selectedRow = Int(port) - 1
        if picker.selectedRow(inComponent: 0) != selectedRow {
            picker.selectRow(selectedRow, inComponent: 0, animated: true)
        }
    }

    final class Coordinator: NSObject, UIPickerViewDataSource, UIPickerViewDelegate {
        private var port: Binding<UInt16>

        init(port: Binding<UInt16>) {
            self.port = port
        }

        func numberOfComponents(in pickerView: UIPickerView) -> Int {
            1
        }

        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
            Int(UInt16.max)
        }

        func pickerView(
            _ pickerView: UIPickerView,
            titleForRow row: Int,
            forComponent component: Int
        ) -> String? {
            String(row + 1)
        }

        func pickerView(
            _ pickerView: UIPickerView,
            didSelectRow row: Int,
            inComponent component: Int
        ) {
            port.wrappedValue = UInt16(row + 1)
        }
    }
}
