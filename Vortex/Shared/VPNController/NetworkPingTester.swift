import Foundation
import Network
import os

/// Performs real low-level TCP handshakes to remote server nodes to measure real round-trip latency
public actor NetworkPingTester {
    public static let shared = NetworkPingTester()

    public init() {}

    /// Measures real TCP round-trip latency to a host:port in milliseconds
    public func ping(host: String, port: Int, timeoutSeconds: Double = 3.0) async -> Int? {
        guard !host.isEmpty, port > 0, port <= 65535 else { return nil }
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else { return nil }

        let start = ContinuousClock.now
        let endpoint = NWEndpoint.Host(host)

        return await withCheckedContinuation { continuation in
            let connection = NWConnection(host: endpoint, port: nwPort, using: .tcp)
            let isResumed = OSAllocatedUnfairLock(initialState: false)

            let queue = DispatchQueue(label: "com.vortex.ping.\(host).\(port)")
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + timeoutSeconds)
            timer.setEventHandler {
                let alreadyResumed = isResumed.withLock { resumed -> Bool in
                    if resumed { return true }
                    resumed = true
                    return false
                }
                if !alreadyResumed {
                    connection.cancel()
                    continuation.resume(returning: nil)
                }
            }
            timer.resume()

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let alreadyResumed = isResumed.withLock { resumed -> Bool in
                        if resumed { return true }
                        resumed = true
                        return false
                    }
                    if !alreadyResumed {
                        timer.cancel()
                        let elapsed = ContinuousClock.now - start
                        let ms = Int(elapsed.components.seconds * 1000) + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
                        connection.cancel()
                        continuation.resume(returning: max(1, ms))
                    }
                case .failed, .cancelled:
                    let alreadyResumed = isResumed.withLock { resumed -> Bool in
                        if resumed { return true }
                        resumed = true
                        return false
                    }
                    if !alreadyResumed {
                        timer.cancel()
                        continuation.resume(returning: nil)
                    }
                default:
                    break
                }
            }

            connection.start(queue: queue)
        }
    }
}
