import Foundation
import Network
import Combine

/// Simple WebSocket server that listens for expression commands on LAN
class WebSocketServer: ObservableObject {
    @MainActor @Published var isListening = false
    @MainActor @Published var connectedClients = 0
    @MainActor @Published var lastCommand = ""

    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let queue = DispatchQueue(label: "websocket")
    private let lock = NSLock()

    /// Callback: (command: String) -> Void
    @MainActor var onCommand: ((String) -> Void)?

    func start(port: UInt16 = 8765) {
        let parameters = NWParameters(tls: nil)
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.maximumMessageSize = 10 * 1024 * 1024  // 10MB for base64 audio
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        do {
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            print("❄️ Failed to create listener: \(error)")
            return
        }

        listener?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.isListening = true
                    print("❄️ WebSocket server listening on port \(port)")
                case .failed(let error):
                    print("❄️ Listener failed: \(error)")
                    self?.isListening = false
                default:
                    break
                }
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener?.start(queue: queue)
    }

    @MainActor
    func stop() {
        listener?.cancel()
        lock.lock()
        connections.forEach { $0.cancel() }
        connections.removeAll()
        lock.unlock()
        isListening = false
        connectedClients = 0
    }

    /// Send a text message to all connected clients
    func broadcast(_ text: String) {
        let data = text.data(using: .utf8)!
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "ws-response", metadata: [metadata])
        lock.lock()
        let conns = connections
        lock.unlock()
        for conn in conns {
            conn.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { error in
                if let error = error {
                    print("❄️ WebSocket send error: \(error)")
                }
            })
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        lock.lock()
        connections.append(connection)
        lock.unlock()

        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                Task { @MainActor in
                    self.connectedClients = self.connections.count
                }
                print("❄️ Client connected (total: \(self.connections.count))")
                self.receive(on: connection)
            case .cancelled, .failed:
                self.lock.lock()
                self.connections.removeAll { $0 === connection }
                let count = self.connections.count
                self.lock.unlock()
                Task { @MainActor in
                    self.connectedClients = count
                }
                print("❄️ Client disconnected (total: \(count))")
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] content, context, _, error in
            guard let self = self else { return }
            
            if let error = error {
                print("❄️ WebSocket receive error: \(error)")
                return
            }
            
            if let data = content,
               let message = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata,
               message.opcode == .text,
               let text = String(data: data, encoding: .utf8) {
                // Truncate log for large messages (e.g. audio base64)
                let logText = text.count > 200 ? "\(text.prefix(100))...(\(text.count) chars)" : text
                Task { @MainActor in
                    self.lastCommand = logText
                    self.onCommand?(text)
                    print("❄️ Received: \(logText)")
                }
            }

            // Continue receiving
            self.receive(on: connection)
        }
    }
}
