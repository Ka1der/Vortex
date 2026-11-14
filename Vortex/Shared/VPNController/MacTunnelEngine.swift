import Foundation
#if canImport(Libbox)
import Libbox
#endif

/// Direct in-process sing-box engine for native macOS execution
@MainActor
public final class MacTunnelEngine: @unchecked Sendable {
    public static let shared = MacTunnelEngine()

    #if canImport(Libbox)
    private var service: LibboxBoxService?
    private var platform: MacPlatformAdapter?
    #endif

    public private(set) var isRunning: Bool = false

    private init() {}

    /// Starts sing-box service in-process on macOS and enables system SOCKS/HTTP proxy
    public func start(configJSON: String) throws {
        #if canImport(Libbox)
        stop()

        let baseDir = AppGroup.containerURL.path
        let setupOptions = LibboxSetupOptions()
        setupOptions.basePath = baseDir
        setupOptions.workingPath = baseDir
        setupOptions.tempPath = baseDir
        setupOptions.username = ""
        var setupError: NSError?
        LibboxSetup(setupOptions, &setupError)

        let adapter = MacPlatformAdapter()
        self.platform = adapter

        var serviceError: NSError?
        guard let newService = LibboxNewService(configJSON, adapter, &serviceError) else {
            throw serviceError ?? NSError(
                domain: "MacTunnelEngine",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Не удалось создать сервис sing-box"]
            )
        }

        try newService.start()
        self.service = newService
        self.isRunning = true

        // Configure system proxy for macOS so Safari/Chrome/Telegram use the tunnel
        setSystemProxy(enabled: true)
        #else
        throw NSError(
            domain: "MacTunnelEngine",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Модуль Libbox недоступен на данной платформе"]
        )
        #endif
    }

    /// Stops sing-box service and disables system proxy
    public func stop() {
        #if canImport(Libbox)
        if isRunning {
            setSystemProxy(enabled: false)
            try? service?.close()
            service = nil
            platform = nil
            isRunning = false
        }
        #endif
    }

    /// Automatically sets or clears macOS system proxy for active network interfaces
    public func setSystemProxy(enabled: Bool, port: Int = 10808) {
        #if os(macOS)
        let networkServices = getNetworkServices()
        for svc in networkServices {
            if enabled {
                runNetworkSetup(["-setsocksfirewallproxy", svc, "127.0.0.1", String(port)])
                runNetworkSetup(["-setsocksfirewallproxystate", svc, "on"])
                runNetworkSetup(["-setwebproxy", svc, "127.0.0.1", String(port)])
                runNetworkSetup(["-setwebproxystate", svc, "on"])
                runNetworkSetup(["-setsecurewebproxy", svc, "127.0.0.1", String(port)])
                runNetworkSetup(["-setsecurewebproxystate", svc, "on"])
            } else {
                runNetworkSetup(["-setsocksfirewallproxystate", svc, "off"])
                runNetworkSetup(["-setwebproxystate", svc, "off"])
                runNetworkSetup(["-setsecurewebproxystate", svc, "off"])
            }
        }
        #endif
    }

    #if os(macOS)
    private func getNetworkServices() -> [String] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        task.arguments = ["-listallnetworkservices"]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return ["Wi-Fi"] }

        var list: [String] = []
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !trimmed.contains("*") && !trimmed.contains("An asterisk") {
                list.append(trimmed)
            }
        }
        return list.isEmpty ? ["Wi-Fi"] : list
    }

    private func runNetworkSetup(_ arguments: [String]) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        task.arguments = arguments
        try? task.run()
        task.waitUntilExit()
    }
    #endif
}

// MARK: - Mac Platform Adapter

#if canImport(Libbox)
final class MacPlatformAdapter: NSObject, LibboxPlatformInterfaceProtocol, @unchecked Sendable {
    func autoDetectControl(_ fd: Int32) throws {}
    func clearDNSCache() {}
    func closeDefaultInterfaceMonitor(_ listener: (any LibboxInterfaceUpdateListenerProtocol)?) throws {}
    func findConnectionOwner(
        _ ipProtocol: Int32,
        sourceAddress: String?,
        sourcePort: Int32,
        destinationAddress: String?,
        destinationPort: Int32,
        ret0_: UnsafeMutablePointer<Int32>?
    ) throws {}

    func getInterfaces() throws -> any LibboxNetworkInterfaceIteratorProtocol {
        return MacEmptyInterfaceIterator()
    }

    func includeAllNetworks() -> Bool { false }
    func openTun(_ options: (any LibboxTunOptionsProtocol)?, ret0_: UnsafeMutablePointer<Int32>?) throws {}
    func packageName(byUid uid: Int32, error: NSErrorPointer) -> String { "" }
    func readWIFIState() -> LibboxWIFIState? { nil }
    func send(_ notification: LibboxNotification?) throws {}
    func startDefaultInterfaceMonitor(_ listener: (any LibboxInterfaceUpdateListenerProtocol)?) throws {}
    func uid(byPackageName packageName: String?, ret0_: UnsafeMutablePointer<Int32>?) throws {}
    func underNetworkExtension() -> Bool { false }
    func usePlatformAutoDetectControl() -> Bool { false }
    func useProcFS() -> Bool { false }

    func writeLog(_ message: String?) {
        if let msg = message {
            NSLog("[VortexMac:sing-box] %@", msg)
        }
    }
}

final class MacEmptyInterfaceIterator: NSObject, LibboxNetworkInterfaceIteratorProtocol {
    func hasNext() -> Bool { false }
    func next() -> LibboxNetworkInterface? { nil }
}
#endif
