import Foundation
import NetworkExtension

/// Standardized VPN connection status
public enum TunnelStatus: String, Codable, Sendable {
    case invalid = "invalid"
    case disconnected = "disconnected"
    case connecting = "connecting"
    case connected = "connected"
    case reasserting = "reasserting"
    case disconnecting = "disconnecting"

    public var displayName: String {
        switch self {
        case .invalid:
            return "Недоступен"
        case .disconnected:
            return "Отключено"
        case .connecting:
            return "Подключение..."
        case .connected:
            return "Подключено"
        case .reasserting:
            return "Переподключение..."
        case .disconnecting:
            return "Отключение..."
        }
    }

    public var isConnected: Bool {
        return self == .connected
    }

    /// Converts Apple NEVPNStatus to Vortex TunnelStatus
    public static func from(neStatus: NEVPNStatus) -> TunnelStatus {
        switch neStatus {
        case .invalid:
            return .invalid
        case .disconnected:
            return .disconnected
        case .connecting:
            return .connecting
        case .connected:
            return .connected
        case .reasserting:
            return .reasserting
        case .disconnecting:
            return .disconnecting
        @unknown default:
            return .disconnected
        }
    }
}

/// Abstract contract for tunnel execution engines (Mock, Libbox/Go, NetworkExtension)
public protocol TunnelEngineProtocol: Sendable {
    func getStatus() async -> TunnelStatus
    func start(node: ServerNode, mode: GlobalRoutingMode, rules: [RoutingRule]) async throws
    func stop() async throws
    func ping(node: ServerNode) async -> Int?
    func getTrafficStats() async -> (txBytes: Int64, rxBytes: Int64, memoryBytes: Int64)
}

// MARK: - IPC Message Envelope

/// Structure of IPC messages exchanged via `NETunnelProviderSession.sendProviderMessage`
public struct TunnelIPCMessage: Codable, Sendable {
    public enum Command: String, Codable, Sendable {
        case getStatus = "getStatus"
        case getStats = "getStats"
        case reloadConfig = "reloadConfig"
        case reloadRules = "reloadRules"
        case pingNode = "pingNode"
    }

    public var command: Command
    public var payload: [String: String]?

    public init(command: Command, payload: [String: String]? = nil) {
        self.command = command
        self.payload = payload
    }

    public func encode() -> Data? {
        return try? JSONEncoder().encode(self)
    }

    public static func decode(from data: Data) -> TunnelIPCMessage? {
        return try? JSONDecoder().decode(TunnelIPCMessage.self, from: data)
    }
}

// MARK: - Mock Engine Implementation

/// High-fidelity actor simulator for Xcode Simulator, macOS preview and testing without Go binary
public actor MockTunnelEngine: TunnelEngineProtocol {
    private var _status: TunnelStatus = .disconnected
    private var _txBytes: Int64 = 0
    private var _rxBytes: Int64 = 0
    private var _memoryBytes: Int64 = 22 * 1024 * 1024 // Initial ~22 MB
    private var trafficTask: Task<Void, Never>?

    private var onStatusChange: (@Sendable (TunnelStatus) -> Void)?

    public init() {}

    public func setStatusChangeHandler(_ handler: (@Sendable (TunnelStatus) -> Void)?) {
        self.onStatusChange = handler
    }

    public func getStatus() async -> TunnelStatus {
        return _status
    }

    private func setStatus(_ newStatus: TunnelStatus) {
        _status = newStatus
        onStatusChange?(newStatus)
    }

    public func start(node: ServerNode, mode: GlobalRoutingMode, rules: [RoutingRule]) async throws {
        setStatus(.connecting)

        // Simulate network handshake delay
        try? await Task.sleep(nanoseconds: 350_000_000) // 350ms

        setStatus(.connected)
        startTrafficSimulation()
    }

    public func stop() async throws {
        setStatus(.disconnecting)
        stopTrafficSimulation()

        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
        setStatus(.disconnected)
    }

    public func ping(node: ServerNode) async -> Int? {
        let address = node.address

        // Simulate 20-85ms network round-trip delay
        let randomJitter = Int.random(in: 25...75)
        try? await Task.sleep(nanoseconds: UInt64(randomJitter) * 1_000_000)

        if address.contains("198.51.") || address.contains("vk.com") || !address.isEmpty {
            return randomJitter
        }

        return nil
    }

    public func getTrafficStats() async -> (txBytes: Int64, rxBytes: Int64, memoryBytes: Int64) {
        return (_txBytes, _rxBytes, _memoryBytes)
    }

    // MARK: - Simulation Loop

    private func startTrafficSimulation() {
        stopTrafficSimulation()

        trafficTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s
                guard let self = self else { break }
                await self.tickSimulation()
            }
        }
    }

    private func tickSimulation() {
        guard _status == .connected else { return }

        // Simulate realistic cellular/Wi-Fi traffic increments:
        // TX: 30 - 350 KB/s
        // RX: 120 KB/s - 2.5 MB/s
        let deltaTx = Int64.random(in: 30_000...350_000)
        let deltaRx = Int64.random(in: 120_000...2_500_000)

        _txBytes += deltaTx
        _rxBytes += deltaRx

        // Memory fluctuates slightly around 22-28 MB (under 40 MB Jetsam limit)
        let memoryJitter = Int64.random(in: -500_000...500_000)
        let newMem = _memoryBytes + memoryJitter
        _memoryBytes = max(18 * 1024 * 1024, min(newMem, 32 * 1024 * 1024))
    }

    private func stopTrafficSimulation() {
        trafficTask?.cancel()
        trafficTask = nil
    }
}
