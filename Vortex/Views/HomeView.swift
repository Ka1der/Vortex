import SwiftUI

/// Main Shadowrocket-style dashboard
public struct HomeView: View {
    @Bindable var tunnelManager: TunnelManager

    // UI state
    @State private var isLocalServersExpanded: Bool = true
    @State private var expandedSubscriptionIds: Set<UUID> = []
    @State private var showingAddSheet: Bool = false
    @State private var showingQRScanner: Bool = false
    @State private var editingNode: ServerNode? = nil
    @State private var refreshingSubId: UUID? = nil
    @State private var toastMessage: String? = nil

    public init(tunnelManager: TunnelManager) {
        self.tunnelManager = tunnelManager
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // 1. Top Control Card (Master Toggle & Ping Test)
                        topControlCard

                        // 2. Local Servers Section
                        localServersSection

                        // 3. Subscriptions Section (if any subscriptions exist)
                        if !tunnelManager.subscriptions.isEmpty {
                            subscriptionsSection
                        }

                        Spacer(minLength: 30)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
            }
            .navigationTitle("Vortex")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .navigationBarLeadingOrLeading) {
                    Menu {
                        Button {
                            showingQRScanner = true
                        } label: {
                            Label("Сканировать QR-код", systemImage: "qrcode.viewfinder")
                        }

                        Button {
                            importFromClipboard()
                        } label: {
                            Label("Импорт из буфера", systemImage: "doc.on.clipboard")
                        }
                    } label: {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Theme.orange)
                    } primaryAction: {
                        showingQRScanner = true
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.orange)
                    }
                }
            }
            .sheet(isPresented: $showingQRScanner) {
                QRCodeScannerView { code in
                    importScannedCode(code)
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                NodeEditorView(tunnelManager: tunnelManager)
            }
            .sheet(item: $editingNode) { node in
                NodeEditorView(tunnelManager: tunnelManager, editingNode: node)
            }
            .overlay(alignment: .bottom) {
                if let toast = toastMessage {
                    Text(toast)
                        .font(.footnote)
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Theme.secondaryCard)
                        .clipShape(Capsule())
                        .shadow(radius: 8)
                        .padding(.bottom, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: toastMessage)
            .onAppear {
                for sub in tunnelManager.subscriptions {
                    expandedSubscriptionIds.insert(sub.id)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Top Control Card

    private var topControlCard: some View {
        VStack(spacing: 0) {
            // Row 1: Master VPN Toggle
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(tunnelManager.isConnected ? Theme.green.opacity(0.2) : Theme.secondaryCard)
                        .frame(width: 40, height: 40)

                    Image(systemName: tunnelManager.isConnected ? "shield.fill" : "shield")
                        .font(.system(size: 19))
                        .foregroundStyle(tunnelManager.isConnected ? Theme.green : Theme.secondaryText)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(tunnelManager.activeNode?.name ?? "Сервер не выбран")
                        .font(.headline)
                        .foregroundStyle(Color.white)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusDotColor)
                            .frame(width: 7, height: 7)

                        Text(tunnelManager.status.displayName)
                            .font(.caption)
                            .foregroundStyle(statusTextColor)
                    }
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { tunnelManager.isConnected || tunnelManager.status == .connecting },
                    set: { _ in
                        Task {
                            await tunnelManager.toggleTunnel()
                        }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Theme.green)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()
                .background(Theme.divider)

            // Row 2: Connectivity Test Button
            Button {
                Task {
                    await tunnelManager.testAllNodesLatency()
                }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "gauge.with.needle")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 28)

                    Text("Тест подключения")
                        .font(.body)
                        .foregroundStyle(Color.white)

                    Spacer()

                    if tunnelManager.isTestingPing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Theme.orange))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .disabled(tunnelManager.isTestingPing || tunnelManager.allNodes.isEmpty)
        }
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.secondaryCard, lineWidth: 1)
        )
    }

    private var statusDotColor: Color {
        switch tunnelManager.status {
        case .connected:
            return Theme.green
        case .connecting, .reasserting:
            return Theme.orange
        default:
            return Theme.secondaryText
        }
    }

    private var statusTextColor: Color {
        switch tunnelManager.status {
        case .connected:
            return Theme.green
        case .connecting, .reasserting:
            return Theme.orange
        default:
            return Theme.secondaryText
        }
    }

    // MARK: - Local Servers Section

    private var localServersSection: some View {
        VStack(spacing: 0) {
            // Header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isLocalServersExpanded.toggle()
                }
            } label: {
                HStack {
                    Text("Локальные серверы")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.secondaryText)

                    Text("(\(tunnelManager.localNodes.count))")
                        .font(.caption)
                        .foregroundStyle(Theme.tertiaryText)

                    Spacer()

                    Image(systemName: isLocalServersExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            if isLocalServersExpanded {
                VStack(spacing: 0) {
                    if tunnelManager.localNodes.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "server.rack")
                                .font(.system(size: 26))
                                .foregroundStyle(Theme.tertiaryText)
                            Text("Нет добавленных серверов")
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondaryText)
                            Text("Нажмите «+» в правом верхнем углу для добавления узла или импортируйте из буфера")
                                .font(.caption)
                                .foregroundStyle(Theme.tertiaryText)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                        .padding(.vertical, 24)
                        .frame(maxWidth: .infinity)
                    } else {
                        ForEach(Array(tunnelManager.localNodes.enumerated()), id: \.element.id) { index, node in
                            if index > 0 {
                                Divider()
                                    .background(Theme.divider)
                                    .padding(.leading, 54)
                            }

                            serverNodeRow(node: node, canDelete: true)
                        }
                    }
                }
            }
        }
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.secondaryCard, lineWidth: 1)
        )
    }

    // MARK: - Subscriptions Section

    private var subscriptionsSection: some View {
        VStack(spacing: 12) {
            ForEach(tunnelManager.subscriptions) { sub in
                let isExpanded = expandedSubscriptionIds.contains(sub.id)
                let isRefreshing = refreshingSubId == sub.id

                VStack(spacing: 0) {
                    // Subscription Card Header
                    HStack(alignment: .center, spacing: 12) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if isExpanded {
                                    expandedSubscriptionIds.remove(sub.id)
                                } else {
                                    expandedSubscriptionIds.insert(sub.id)
                                }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(sub.title)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Color.white)
                                        .lineLimit(1)

                                    Text("(\(sub.nodes.count))")
                                        .font(.caption)
                                        .foregroundStyle(Theme.tertiaryText)

                                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(Theme.secondaryText)
                                }

                                // Traffic string matching Shadowrocket format
                                Text(sub.trafficSummary)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Theme.secondaryText)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button {
                            refreshSubscription(sub)
                        } label: {
                            if isRefreshing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: Theme.orange))
                                    .scaleEffect(0.7)
                                    .frame(width: 28, height: 28)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Theme.secondaryText)
                                    .frame(width: 28, height: 28)
                            }
                        }
                        .disabled(isRefreshing)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    // Node list under subscription
                    if isExpanded {
                        Divider()
                            .background(Theme.divider)

                        if sub.nodes.isEmpty {
                            Text("В подписке нет доступных серверов")
                                .font(.footnote)
                                .foregroundStyle(Theme.tertiaryText)
                                .padding(.vertical, 12)
                        } else {
                            ForEach(Array(sub.nodes.enumerated()), id: \.element.id) { index, node in
                                if index > 0 {
                                    Divider()
                                        .background(Theme.divider)
                                        .padding(.leading, 54)
                                }

                                serverNodeRow(node: node, canDelete: false)
                            }
                        }
                    }
                }
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Theme.secondaryCard, lineWidth: 1)
                )
                .contextMenu {
                    Button(role: .destructive) {
                        tunnelManager.deleteSubscription(withId: sub.id)
                    } label: {
                        Label("Удалить подписку", systemImage: "trash")
                    }
                }
            }
        }
    }

    // MARK: - Server Node Row

    private func serverNodeRow(node: ServerNode, canDelete: Bool) -> some View {
        let isSelected = tunnelManager.activeNode?.id == node.id

        return HStack(spacing: 12) {
            // 1. Selection orange indicator dot
            ZStack {
                if isSelected {
                    Circle()
                        .fill(Theme.orange)
                        .frame(width: 8, height: 8)
                }
            }
            .frame(width: 12)

            // 2. Country Flag Emoji
            Text(node.flag)
                .font(.system(size: 24))

            // 3. Node Name and Shadowrocket Subtitle
            VStack(alignment: .leading, spacing: 3) {
                Text(node.name)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(Color.white)
                    .lineLimit(1)

                Text(node.subtitle)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            // 4. Latency badge
            if let latency = node.latencyMs {
                Text("\(latency) ms")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(latencyColor(latency))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(latencyColor(latency).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // 5. Actions: Delete button and Info (i)
            HStack(spacing: 12) {
                if canDelete {
                    Button(role: .destructive) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            tunnelManager.deleteLocalNode(withId: node.id)
                        }
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.secondaryText.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help("Удалить сервер")
                }

                Button {
                    editingNode = node
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.secondaryText)
                }
                .buttonStyle(.plain)
                .help("Настройки сервера")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            tunnelManager.selectNode(node)
        }
        .contextMenu {
            if canDelete {
                Button(role: .destructive) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        tunnelManager.deleteLocalNode(withId: node.id)
                    }
                } label: {
                    Label("Удалить сервер", systemImage: "trash")
                }
            }

            Button {
                editingNode = node
            } label: {
                Label("Настройки", systemImage: "info.circle")
            }
        }
        #if os(iOS)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if canDelete {
                Button(role: .destructive) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        tunnelManager.deleteLocalNode(withId: node.id)
                    }
                } label: {
                    Label("Удалить", systemImage: "trash")
                }
            }
        }
        #endif
    }

    private func latencyColor(_ ms: Int) -> Color {
        if ms <= 0 { return Theme.secondaryText }
        if ms < 80 { return Theme.green }
        if ms < 200 { return Theme.orange }
        return Theme.red
    }

    // MARK: - Actions

    private func importFromClipboard() {
        guard let text = ClipboardHelper.getString()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            showToast("Буфер обмена пуст")
            return
        }
        importScannedCode(text)
    }

    private func importScannedCode(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if text.hasPrefix("http://") || text.hasPrefix("https://") {
            guard let url = URL(string: text) else {
                showToast("Некорректная ссылка на подписку")
                return
            }
            Task {
                do {
                    try await tunnelManager.addSubscription(title: url.host ?? "Подписка", url: url)
                    showToast("Подписка успешно добавлена")
                } catch {
                    showToast("Ошибка: \(error.localizedDescription)")
                }
            }
        } else {
            do {
                let node = try SubscriptionParser.parseNode(from: text)
                tunnelManager.addLocalNode(node)
                showToast("Узел «\(node.name)» добавлен")
            } catch {
                // If single node failed, check if it's a multi-node subscription text or base64 blob
                if let multiNodes = try? SubscriptionParser.parseSubscriptionContent(text), !multiNodes.isEmpty {
                    for n in multiNodes {
                        tunnelManager.addLocalNode(n)
                    }
                    showToast("Добавлено узлов: \(multiNodes.count)")
                } else {
                    showToast("Не удалось распознать: \(error.localizedDescription)")
                }
            }
        }
    }

    private func refreshSubscription(_ sub: SubscriptionGroup) {
        refreshingSubId = sub.id
        Task {
            do {
                try await tunnelManager.refreshSubscription(sub)
                showToast("Подписка обновлена")
            } catch {
                showToast("Ошибка: \(error.localizedDescription)")
            }
            refreshingSubId = nil
        }
    }

    private func showToast(_ message: String) {
        toastMessage = message
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if toastMessage == message {
                toastMessage = nil
            }
        }
    }
}

// MARK: - Toolbar Extension helper

private extension ToolbarItemPlacement {
    static var navigationBarLeadingOrLeading: ToolbarItemPlacement {
        #if os(iOS)
        return .navigationBarLeading
        #else
        return .automatic
        #endif
    }
}
