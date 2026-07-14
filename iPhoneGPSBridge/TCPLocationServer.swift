import Foundation
import Network

final class TCPLocationServer: @unchecked Sendable {
    var onStateChange: (@Sendable (String) -> Void)?
    var onClientCountChange: (@Sendable (Int) -> Void)?

    private let queue = DispatchQueue(label: "GPSBridge.TCPServer")
    private var listener: NWListener?
    private var clients: [UUID: NWConnection] = [:]

    func start(port: UInt16) throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw ServerError.invalidPort
        }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        let listener = try NWListener(using: parameters, on: nwPort)

        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }

            switch state {
            case .setup:
                self.onStateChange?("Starting")
            case .waiting(let error):
                self.onStateChange?("Waiting: \(error.localizedDescription)")
            case .ready:
                self.onStateChange?("Listening")
            case .failed(let error):
                self.onStateChange?("Failed: \(error.localizedDescription)")
                self.stop()
            case .cancelled:
                self.onStateChange?("Stopped")
            @unknown default:
                self.onStateChange?("Unknown")
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }

        // Keep listener and client mutations on the server queue. Calling the
        // asynchronous stop() here could otherwise cancel this new listener.
        queue.sync {
            stopLocked()
            self.listener = listener
            listener.start(queue: queue)
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.stopLocked()
        }
    }

    func broadcast(_ data: Data) {
        queue.async { [weak self] in
            guard let self else { return }

            for (id, connection) in self.clients {
                connection.send(
                    content: data,
                    completion: .contentProcessed { [weak self] error in
                        if error != nil {
                            self?.removeClient(id)
                        }
                    }
                )
            }
        }
    }

    private func accept(_ connection: NWConnection) {
        let id = UUID()
        clients[id] = connection
        onClientCountChange?(clients.count)

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.removeClient(id)
            default:
                break
            }
        }

        connection.start(queue: queue)
        receiveUntilClosed(connection, id: id)
    }

    private func receiveUntilClosed(_ connection: NWConnection, id: UUID) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 4096
        ) { [weak self] _, _, isComplete, error in
            guard let self else { return }

            if isComplete || error != nil {
                self.removeClient(id)
                return
            }

            self.receiveUntilClosed(connection, id: id)
        }
    }

    private func removeClient(_ id: UUID) {
        queue.async { [weak self] in
            guard let self, let connection = self.clients.removeValue(forKey: id) else {
                return
            }

            connection.cancel()
            self.onClientCountChange?(self.clients.count)
        }
    }

    private func stopLocked() {
        listener?.cancel()
        listener = nil

        for connection in clients.values {
            connection.cancel()
        }

        clients.removeAll()
        onClientCountChange?(0)
    }

    enum ServerError: LocalizedError {
        case invalidPort

        var errorDescription: String? {
            "Invalid TCP port."
        }
    }
}
