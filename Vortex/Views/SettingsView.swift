import SwiftUI

/// Settings view: MTU, DNS split-routing, VK Call pre-auth helper, and diagnostic controls
public struct SettingsView: View {
    @Bindable var tunnelManager: TunnelManager
    @State private var ruleSetManager = RuleSetManager.shared

    @State private var mtuValue: Double = Double(AppGroup.getMTU())
    @State private var remoteDns: String = AppGroup.getRemoteDNS()
    @State private var directDns: String = AppGroup.getDirectDNS()
    @State private var showingVKAuthHelper: Bool = false
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
                        // 1. MTU Configuration Card
                        mtuSectionCard

                        // 2. DNS Split-Routing Card
                        dnsSectionCard

                        // 3. RuleSets (.srs) Binary Databases Card
                        ruleSetsSectionCard

                        // 4. VK Call Helper Card
                        vkCallSectionCard

                        // 5. Data & Diagnostics Card
                        diagnosticsSectionCard

                        // 6. About / Version Card
                        aboutSectionCard

                        Spacer(minLength: 30)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
            }
            .navigationTitle("Настройки")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .sheet(isPresented: $showingVKAuthHelper) {
                vkAuthHelperSheet
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
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - MTU Card

    private var mtuSectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(Theme.orange)
                Text("Размер пакета MTU")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.white)

                Spacer()

                Text("\(Int(mtuValue))")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.orange)
            }

            Slider(value: $mtuValue, in: 1280...1420, step: 10) {
                Text("MTU")
            } onEditingChanged: { isEditing in
                if !isEditing {
                    AppGroup.setMTU(Int(mtuValue))
                    showToast("MTU сохранен: \(Int(mtuValue))")
                }
            }
            .tint(Theme.orange)

            Text("Значение 1280 обязательно при использовании VK Call для предотвращения фрагментации UDP/TURN пакетов. Для чистого VLESS допустимо до 1400.")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(16)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.secondaryCard, lineWidth: 1)
        )
    }

    // MARK: - DNS Card

    private var dnsSectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "network")
                    .foregroundStyle(Theme.blue)
                Text("DNS Маршрутизация")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.white)
            }

            Divider()
                .background(Theme.divider)

            // Remote DNS
            VStack(alignment: .leading, spacing: 6) {
                Text("Удаленный DNS (DoH / Proxy)")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .textCase(.uppercase)

                TextField("https://1.1.1.1/dns-query", text: $remoteDns)
                    .font(.system(.subheadline, design: .monospaced))
                    .padding(10)
                    .background(Theme.secondaryCard)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onSubmit {
                        AppGroup.setRemoteDNS(remoteDns)
                        showToast("Remote DNS сохранен")
                    }

                HStack(spacing: 6) {
                    dnsPresetButton(title: "Cloudflare DoH", address: "https://1.1.1.1/dns-query", target: $remoteDns)
                    dnsPresetButton(title: "Google DoH", address: "https://dns.google/dns-query", target: $remoteDns)
                }
            }

            // Direct DNS
            VStack(alignment: .leading, spacing: 6) {
                Text("Прямой DNS (.ru / хосты серверов)")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .textCase(.uppercase)

                TextField("77.88.8.8", text: $directDns)
                    .font(.system(.subheadline, design: .monospaced))
                    .padding(10)
                    .background(Theme.secondaryCard)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onSubmit {
                        AppGroup.setDirectDNS(directDns)
                        showToast("Direct DNS сохранен")
                    }

                HStack(spacing: 6) {
                    dnsPresetButton(title: "Яндекс (77.88.8.8)", address: "77.88.8.8", target: $directDns)
                    dnsPresetButton(title: "Cloudflare (1.1.1.1)", address: "1.1.1.1", target: $directDns)
                }
            }
        }
        .padding(16)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.secondaryCard, lineWidth: 1)
        )
    }

    private func dnsPresetButton(title: String, address: String, target: Binding<String>) -> some View {
        Button {
            target.wrappedValue = address
            if target.wrappedValue.contains("://") {
                AppGroup.setRemoteDNS(address)
            } else {
                AppGroup.setDirectDNS(address)
            }
            showToast("Применен DNS: \(title)")
        } label: {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.secondaryCard)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Rule-Sets Card

    private var ruleSetsSectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(Theme.orange)
                Text("Базы маршрутизации (.srs)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.white)

                Spacer()

                if ruleSetManager.isUpdating {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Button("Обновить") {
                        Task {
                            let ok = await ruleSetManager.updateAllRuleSets(force: true)
                            if ok {
                                showToast("Базы правил успешно обновлены")
                            } else if let err = ruleSetManager.lastErrorMessage {
                                showToast(err)
                            }
                        }
                    }
                    .font(.footnote)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.orange)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(RuleSetManager.standardRuleSets, id: \.tag) { item in
                    HStack {
                        Text(item.filename)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Theme.secondaryText)
                        Spacer()
                        if let size = ruleSetManager.fileSizes[item.tag] {
                            Text(formatBytes(size))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Theme.green)
                        } else {
                            Text("Отсутствует")
                                .font(.caption2)
                                .foregroundStyle(Theme.red)
                        }
                    }
                }
            }
            .padding(10)
            .background(Theme.secondaryCard.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Toggle("Автообновление (каждые 7 дней)", isOn: $ruleSetManager.autoUpdateRuleSets)
                    .font(.caption)
                    .foregroundStyle(Color.white)
                    .tint(Theme.orange)
            }

            if let last = ruleSetManager.lastUpdateDate {
                Text("Обновлено: \(last.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(16)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.secondaryCard, lineWidth: 1)
        )
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    // MARK: - VK Call Section

    private var vkCallSectionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "phone.bubble.left.fill")
                    .foregroundStyle(Theme.green)
                Text("VK Call Tunnel")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.white)

                Spacer()

                Button("Помощник") {
                    showingVKAuthHelper = true
                }
                .font(.footnote)
                .foregroundStyle(Theme.orange)
            }

            Text("Туннелирование через медиа-серверы звонков ВКонтакте. Обходит жесткие протокольные блокировки через TURN/WebRTC медиа-релеи.")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(16)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.secondaryCard, lineWidth: 1)
        )
    }

    // MARK: - Diagnostics Card

    private var diagnosticsSectionCard: some View {
        VStack(spacing: 12) {
            Button {
                AppGroup.setActiveNodeId(nil)
                tunnelManager.localNodes = []
                tunnelManager.subscriptions = []
                try? AppGroup.saveNodes([])
                try? AppGroup.saveSubscriptions([])
                showToast("Все серверы очищены")
            } label: {
                HStack {
                    Image(systemName: "trash")
                        .foregroundStyle(Theme.red)
                    Text("Очистить все серверы")
                        .font(.subheadline)
                        .foregroundStyle(Theme.red)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.secondaryCard, lineWidth: 1)
        )
    }

    // MARK: - About Card

    private var aboutSectionCard: some View {
        VStack(spacing: 8) {
            Text("Vortex VPN")
                .font(.headline)
                .foregroundStyle(Color.white)

            Text("Версия 1.0.0 (Build 1)")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)

            Text("Sing-box Engine • VLESS Reality • Vision • VK Call Tunnel")
                .font(.caption2)
                .foregroundStyle(Theme.tertiaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - VK Auth Helper Sheet

    private var vkAuthHelperSheet: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 16) {
                    Text("Как работает VK Call Tunnel:")
                        .font(.headline)
                        .foregroundStyle(Color.white)

                    Text("1. Создается комната звонка ВКонтакте на специальном сервере-мосте.\n2. Сетевые пакеты инкапсулируются в стандартный WebRTC/TURN трафик звонка.\n3. Для DPI провайдера трафик выглядит как легитимный аудио/видео звонок VK, не подлежащий замедлению или блокировке.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .lineSpacing(4)

                    Divider()
                        .background(Theme.divider)

                    Text("Сигнальные домены ВКонтакте (*.vk.com, *.mycdn.me, *.userapi.com) автоматически добавлены в правила исключения Anti-Loop.")
                        .font(.caption)
                        .foregroundStyle(Theme.tertiaryText)

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("VK Call Helper")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Понятно") {
                        showingVKAuthHelper = false
                    }
                    .foregroundStyle(Theme.orange)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func showToast(_ text: String) {
        toastMessage = text
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if toastMessage == text {
                toastMessage = nil
            }
        }
    }
}
