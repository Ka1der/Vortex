import SwiftUI

/// Manual configuration sheet for adding or editing nodes and importing subscriptions
public struct NodeEditorView: View {
    @Environment(\.dismiss) private var dismiss
    var tunnelManager: TunnelManager

    public var editingNode: ServerNode?

    @State private var selectedTab: EditorTab = .quickLink

    // Quick Link state
    @State private var quickLinkText: String = ""
    @State private var subscriptionTitle: String = ""
    @State private var showingQRScanner: Bool = false

    // VLESS fields
    @State private var vlessName: String = ""
    @State private var vlessAddress: String = ""
    @State private var vlessPort: String = "443"
    @State private var vlessUUID: String = ""
    @State private var vlessFlow: String = "xtls-rprx-vision"
    @State private var vlessSecurity: String = "reality"
    @State private var vlessSNI: String = ""
    @State private var vlessPBK: String = ""
    @State private var vlessSID: String = ""
    @State private var vlessFP: String = "chrome"
    @State private var vlessNetwork: String = "tcp"
    @State private var vlessWSPath: String = "/"
    @State private var vlessWSHost: String = ""
    @State private var vlessGRPCService: String = ""

    // Proprietary fields
    @State private var propName: String = ""
    @State private var propAddress: String = ""
    @State private var propPort: String = "8443"
    @State private var propSecret: String = ""
    @State private var propMode: String = "udp-mask"

    // VK Call fields
    @State private var vkName: String = ""
    @State private var vkRelayAddress: String = ""
    @State private var vkRelayPort: String = "3478"
    @State private var vkCallLink: String = ""
    @State private var vkSecret: String = ""
    @State private var vkTurnUser: String = ""
    @State private var vkTurnPass: String = ""

    @State private var errorMessage: String? = nil
    @State private var isProcessing: Bool = false

    public enum EditorTab: String, CaseIterable, Identifiable {
        case quickLink = "Ссылка"
        case vless = "VLESS"
        case proprietary = "Vortex"
        case vkCall = "VK Call"

        public var id: String { rawValue }
    }

    public init(tunnelManager: TunnelManager, editingNode: ServerNode? = nil) {
        self.tunnelManager = tunnelManager
        self.editingNode = editingNode
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        if editingNode == nil {
                            // Tab Selector
                            Picker("Тип добавления", selection: $selectedTab) {
                                ForEach(EditorTab.allCases) { tab in
                                    Text(tab.rawValue).tag(tab)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal)
                        }

                        if let error = errorMessage {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Theme.red)
                                Text(error)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.red)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .padding(.horizontal)
                        }

                        // Tab Contents
                        switch selectedTab {
                        case .quickLink:
                            quickLinkSection
                        case .vless:
                            vlessSection
                        case .proprietary:
                            proprietarySection
                        case .vkCall:
                            vkCallSection
                        }

                        if let node = editingNode {
                            Button(role: .destructive) {
                                withAnimation {
                                    tunnelManager.deleteLocalNode(withId: node.id)
                                }
                                dismiss()
                            } label: {
                                HStack {
                                    Spacer()
                                    Image(systemName: "trash")
                                    Text("Удалить сервер")
                                        .fontWeight(.semibold)
                                    Spacer()
                                }
                                .padding()
                                .background(Theme.red.opacity(0.12))
                                .foregroundStyle(Theme.red)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Theme.red.opacity(0.3), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal)
                            .padding(.top, 10)
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle(editingNode == nil ? "Добавить узел" : "Редактировать узел")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.secondaryText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isProcessing ? "Сохранение..." : "Сохранить") {
                        saveAction()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.orange)
                    .disabled(isProcessing)
                }
            }
            .sheet(isPresented: $showingQRScanner) {
                QRCodeScannerView { code in
                    quickLinkText = code
                }
            }
            .onAppear {
                populateFromEditingNode()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Quick Link View

    private var quickLinkSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Вставьте ссылку или URL подписки")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .textCase(.uppercase)

                TextEditor(text: $quickLinkText)
                    .frame(height: 120)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Theme.secondaryCard, lineWidth: 1)
                    )

                HStack(spacing: 16) {
                    Button {
                        showingQRScanner = true
                    } label: {
                        Label("Сканировать QR", systemImage: "qrcode.viewfinder")
                            .font(.footnote)
                            .foregroundStyle(Theme.orange)
                    }

                    Button {
                        if let text = ClipboardHelper.getString() {
                            quickLinkText = text
                        }
                    } label: {
                        Label("Вставить из буфера", systemImage: "doc.on.clipboard")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }

                    Spacer()

                    if !quickLinkText.isEmpty {
                        Button("Очистить") {
                            quickLinkText = ""
                        }
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                    }
                }
            }

            if isSubscriptionUrl(quickLinkText) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Название подписки (опционально)")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .textCase(.uppercase)

                    TextField("Моя подписка", text: $subscriptionTitle)
                        .padding()
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Поддерживаемые форматы:")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                Text("• vless://... (Reality, Vision, TLS, WS, gRPC)\n• vortex://... (Proprietary protocol)\n• vkcall://... (VK TURN relay)\n• https://... (Base64 Remote Subscription)")
                    .font(.caption2)
                    .foregroundStyle(Theme.tertiaryText)
            }
            .padding(.top, 8)
        }
        .padding(.horizontal)
    }

    // MARK: - VLESS View

    private var vlessSection: some View {
        VStack(spacing: 16) {
            formGroup(title: "Основные параметры") {
                formRow(label: "Имя узла", placeholder: "Мой VLESS сервер", text: $vlessName)
                formRow(label: "Адрес сервера", placeholder: "example.com или IP", text: $vlessAddress)
                formRow(label: "Порт", placeholder: "443", text: $vlessPort)
                formRow(label: "UUID", placeholder: "UUID v4", text: $vlessUUID)
            }

            formGroup(title: "Безопасность и Reality") {
                Picker("Безопасность", selection: $vlessSecurity) {
                    Text("Reality").tag("reality")
                    Text("TLS").tag("tls")
                    Text("None").tag("none")
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 4)

                Picker("Flow", selection: $vlessFlow) {
                    Text("xtls-rprx-vision").tag("xtls-rprx-vision")
                    Text("None").tag("")
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 4)

                if vlessSecurity == "reality" || vlessSecurity == "tls" {
                    formRow(label: "SNI (Server Name)", placeholder: "speed.cloudflare.com", text: $vlessSNI)
                    Picker("Fingerprint", selection: $vlessFP) {
                        Text("chrome").tag("chrome")
                        Text("safari").tag("safari")
                        Text("firefox").tag("firefox")
                        Text("ios").tag("ios")
                    }
                    .padding(.vertical, 4)
                }

                if vlessSecurity == "reality" {
                    formRow(label: "Public Key (pbk)", placeholder: "Reality Public Key", text: $vlessPBK)
                    formRow(label: "Short ID (sid)", placeholder: "6ba85170", text: $vlessSID)
                }
            }

            formGroup(title: "Транспорт") {
                Picker("Сеть", selection: $vlessNetwork) {
                    Text("TCP").tag("tcp")
                    Text("WebSocket").tag("ws")
                    Text("gRPC").tag("grpc")
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 4)

                if vlessNetwork == "ws" {
                    formRow(label: "WS Path", placeholder: "/", text: $vlessWSPath)
                    formRow(label: "WS Host Header", placeholder: "domain.com", text: $vlessWSHost)
                } else if vlessNetwork == "grpc" {
                    formRow(label: "gRPC Service Name", placeholder: "vless-grpc", text: $vlessGRPCService)
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Proprietary View

    private var proprietarySection: some View {
        VStack(spacing: 16) {
            formGroup(title: "Параметры Vortex") {
                formRow(label: "Имя узла", placeholder: "Vortex Node", text: $propName)
                formRow(label: "Адрес сервера", placeholder: "192.0.2.1", text: $propAddress)
                formRow(label: "Порт", placeholder: "8443", text: $propPort)
                formRow(label: "Секретный ключ", placeholder: "Secret key", text: $propSecret)

                Picker("Режим обфускации", selection: $propMode) {
                    Text("UDP Mask").tag("udp-mask")
                    Text("TLS Mimic").tag("tls-mimic")
                    Text("Raw").tag("raw")
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 4)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - VK Call View

    private var vkCallSection: some View {
        VStack(spacing: 16) {
            formGroup(title: "Параметры VK Call Tunnel") {
                formRow(label: "Имя узла", placeholder: "VK Call Relay", text: $vkName)
                formRow(label: "Ссылка на звонок", placeholder: "https://vk.com/call/join/...", text: $vkCallLink)
                formRow(label: "TURN Relay Адрес", placeholder: "relay.example.com", text: $vkRelayAddress)
                formRow(label: "TURN Порт", placeholder: "3478", text: $vkRelayPort)
                formRow(label: "Секретный ключ", placeholder: "Ключ шифрования", text: $vkSecret)
            }

            formGroup(title: "TURN Реквизиты (Опционально)") {
                formRow(label: "Username", placeholder: "client_user", text: $vkTurnUser)
                formRow(label: "Password", placeholder: "client_password", text: $vkTurnPass)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Form Helper Builders

    private func formGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .textCase(.uppercase)

            VStack(spacing: 1) {
                content()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.secondaryCard, lineWidth: 1)
            )
        }
    }

    private func formRow(label: String, placeholder: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 130, alignment: .leading)

            TextField(placeholder, text: text)
                .font(.subheadline)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(Color.white)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Logic & Actions

    private func isSubscriptionUrl(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
    }

    private func populateFromEditingNode() {
        guard let node = editingNode else { return }

        switch node.configuration {
        case .vless(let cfg):
            selectedTab = .vless
            vlessName = node.name
            vlessAddress = cfg.address
            vlessPort = "\(cfg.port)"
            vlessUUID = cfg.uuid
            vlessFlow = cfg.flow ?? ""
            vlessSecurity = cfg.security
            vlessSNI = cfg.sni ?? ""
            vlessPBK = cfg.publicKey ?? ""
            vlessSID = cfg.shortId ?? ""
            vlessFP = cfg.fingerprint ?? "chrome"
            vlessNetwork = cfg.network
            vlessWSPath = cfg.wsPath ?? "/"
            vlessWSHost = cfg.wsHeaders?["Host"] ?? ""
            vlessGRPCService = cfg.grpcServiceName ?? ""

        case .proprietary(let cfg):
            selectedTab = .proprietary
            propName = node.name
            propAddress = cfg.address
            propPort = "\(cfg.port)"
            propSecret = cfg.secretKey
            propMode = cfg.obfuscationMode

        case .vkCall(let cfg):
            selectedTab = .vkCall
            vkName = node.name
            vkRelayAddress = cfg.relayAddress
            vkRelayPort = "\(cfg.relayPort)"
            vkCallLink = cfg.callJoinLink
            vkSecret = cfg.secretKey ?? ""
            vkTurnUser = cfg.turnCredentials?.username ?? ""
            vkTurnPass = cfg.turnCredentials?.password ?? ""
        }
    }

    private func saveAction() {
        errorMessage = nil

        switch selectedTab {
        case .quickLink:
            handleQuickLinkImport()
        case .vless:
            handleSaveVLESS()
        case .proprietary:
            handleSaveProprietary()
        case .vkCall:
            handleSaveVKCall()
        }
    }

    private func handleQuickLinkImport() {
        let trimmed = quickLinkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Введите ссылку или URL"
            return
        }

        if isSubscriptionUrl(trimmed) {
            guard let url = URL(string: trimmed) else {
                errorMessage = "Некорректный URL подписки"
                return
            }
            isProcessing = true
            Task {
                do {
                    try await tunnelManager.addSubscription(title: subscriptionTitle, url: url)
                    dismiss()
                } catch {
                    isProcessing = false
                    errorMessage = error.localizedDescription
                }
            }
        } else {
            do {
                let node = try SubscriptionParser.parseNode(from: trimmed)
                tunnelManager.addLocalNode(node)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func handleSaveVLESS() {
        let portInt = Int(vlessPort) ?? 443
        guard !vlessAddress.isEmpty else {
            errorMessage = "Укажите адрес сервера"
            return
        }
        guard !vlessUUID.isEmpty else {
            errorMessage = "Укажите UUID"
            return
        }

        var wsHeaders: [String: String]? = nil
        if !vlessWSHost.isEmpty {
            wsHeaders = ["Host": vlessWSHost]
        }

        let config = VLESSConfig(
            uuid: vlessUUID,
            address: vlessAddress,
            port: portInt,
            flow: vlessFlow.isEmpty ? nil : vlessFlow,
            security: vlessSecurity,
            sni: vlessSNI.isEmpty ? nil : vlessSNI,
            publicKey: vlessPBK.isEmpty ? nil : vlessPBK,
            shortId: vlessSID.isEmpty ? nil : vlessSID,
            fingerprint: vlessFP,
            network: vlessNetwork,
            wsPath: vlessNetwork == "ws" ? vlessWSPath : nil,
            wsHeaders: wsHeaders,
            grpcServiceName: vlessNetwork == "grpc" ? vlessGRPCService : nil
        )

        let name = vlessName.isEmpty ? "\(vlessAddress):\(portInt)" : vlessName
        let node = ServerNode(
            id: editingNode?.id ?? UUID(),
            name: name,
            configuration: .vless(config),
            latencyMs: editingNode?.latencyMs,
            subscriptionId: editingNode?.subscriptionId
        )

        tunnelManager.addLocalNode(node)
        dismiss()
    }

    private func handleSaveProprietary() {
        let portInt = Int(propPort) ?? 8443
        guard !propAddress.isEmpty else {
            errorMessage = "Укажите адрес сервера"
            return
        }
        guard !propSecret.isEmpty else {
            errorMessage = "Укажите секретный ключ"
            return
        }

        let config = ProprietaryConfig(
            address: propAddress,
            port: portInt,
            secretKey: propSecret,
            obfuscationMode: propMode
        )

        let name = propName.isEmpty ? "Vortex \(propAddress)" : propName
        let node = ServerNode(
            id: editingNode?.id ?? UUID(),
            name: name,
            configuration: .proprietary(config),
            latencyMs: editingNode?.latencyMs
        )

        tunnelManager.addLocalNode(node)
        dismiss()
    }

    private func handleSaveVKCall() {
        let portInt = Int(vkRelayPort) ?? 3478
        guard !vkRelayAddress.isEmpty else {
            errorMessage = "Укажите адрес TURN сервера"
            return
        }

        var turnCreds: TurnCredentials? = nil
        if !vkTurnUser.isEmpty && !vkTurnPass.isEmpty {
            turnCreds = TurnCredentials(username: vkTurnUser, password: vkTurnPass)
        }

        let config = VKCallConfig(
            callJoinLink: vkCallLink,
            relayAddress: vkRelayAddress,
            relayPort: portInt,
            turnCredentials: turnCreds,
            secretKey: vkSecret.isEmpty ? nil : vkSecret
        )

        let name = vkName.isEmpty ? "VK Call Relay" : vkName
        let node = ServerNode(
            id: editingNode?.id ?? UUID(),
            name: name,
            configuration: .vkCall(config),
            latencyMs: editingNode?.latencyMs
        )

        tunnelManager.addLocalNode(node)
        dismiss()
    }
}
