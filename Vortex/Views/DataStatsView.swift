import SwiftUI

/// Data metrics, live TX/RX bandwidth, Packet Tunnel RAM monitor, and connection log
public struct DataStatsView: View {
    @Bindable var tunnelManager: TunnelManager

    // Live connection events
    @State private var connectionLogs: [ConnectionLogEntry] = []

    public struct ConnectionLogEntry: Identifiable, Sendable {
        public let id = UUID()
        public let timestamp = Date()
        public let domain: String
        public let rule: String
        public let action: RuleAction
        public let protocolStr: String
    }

    public init(tunnelManager: TunnelManager) {
        self.tunnelManager = tunnelManager
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // 1. Live Speed Cards (Download & Upload)
                        liveSpeedGrid

                        // 2. Session Totals Card
                        sessionTotalsCard

                        // 3. Packet Tunnel RAM Monitor
                        ramMonitorCard

                        // 4. Live Connection Activity Log
                        activityLogCard

                        Spacer(minLength: 30)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
            }
            .navigationTitle("Данные")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        connectionLogs.removeAll()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Live Speed Grid

    private var liveSpeedGrid: some View {
        HStack(spacing: 12) {
            // Download Speed Card
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(Theme.green)
                    Text("Входящая")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }

                Text(formatSpeed(tunnelManager.rxRate))
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Theme.secondaryCard, lineWidth: 1)
            )

            // Upload Speed Card
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(Theme.orange)
                    Text("Исходящая")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }

                Text(formatSpeed(tunnelManager.txRate))
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Theme.secondaryCard, lineWidth: 1)
            )
        }
    }

    // MARK: - Session Totals Card

    private var sessionTotalsCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Трафик сессии")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.secondaryText)

                Spacer()

                HStack(spacing: 4) {
                    Circle()
                        .fill(tunnelManager.isConnected ? Theme.green : Theme.secondaryText)
                        .frame(width: 6, height: 6)
                    Text(tunnelManager.isConnected ? "Активна" : "Не активна")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            Divider()
                .background(Theme.divider)

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Получено")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    Text(SubscriptionGroup.formatBytes(tunnelManager.rxBytes))
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 3) {
                    Text("Отправлено")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    Text(SubscriptionGroup.formatBytes(tunnelManager.txBytes))
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 3) {
                    Text("Всего")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    Text(SubscriptionGroup.formatBytes(tunnelManager.txBytes + tunnelManager.rxBytes))
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.orange)
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

    // MARK: - RAM Monitor Card

    private var ramMonitorCard: some View {
        let memMB = Double(tunnelManager.memoryUsageBytes) / (1024 * 1024)
        let maxMB: Double = 50.0 // iOS hard Jetsam limit
        let progress = min(1.0, max(0.0, memMB / maxMB))

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "memorychip")
                    .foregroundStyle(Theme.orange)

                Text("Память Packet Tunnel")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.white)

                Spacer()

                Text(String(format: "%.1f MB / 50 MB", memMB))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(memMB < 40 ? Theme.green : Theme.red)
            }

            // Custom Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.secondaryCard)
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(memMB < 35 ? Theme.green : (memMB < 45 ? Theme.orange : Theme.red))
                        .frame(width: max(8, geo.size.width * CGFloat(progress)), height: 8)
                }
            }
            .frame(height: 8)

            HStack {
                Text(memMB < 40 ? "Безопасный уровень (целевой < 40 MB)" : "Внимание: приближение к лимиту 50 MB")
                    .font(.caption2)
                    .foregroundStyle(memMB < 40 ? Theme.secondaryText : Theme.red)

                Spacer()

                Text("Jetsam Limit: 50MB")
                    .font(.caption2)
                    .foregroundStyle(Theme.tertiaryText)
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

    // MARK: - Activity Log Card

    private var activityLogCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Журнал соединений")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.secondaryText)

                Text("(\(connectionLogs.count))")
                    .font(.caption)
                    .foregroundStyle(Theme.tertiaryText)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()
                .background(Theme.divider)

            if connectionLogs.isEmpty {
                Text("Журнал соединений пуст")
                    .font(.footnote)
                    .foregroundStyle(Theme.tertiaryText)
                    .padding(.vertical, 20)
            } else {
                ForEach(Array(connectionLogs.enumerated()), id: \.element.id) { index, log in
                    if index > 0 {
                        Divider()
                            .background(Theme.divider)
                            .padding(.leading, 16)
                    }

                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(log.domain)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.white)
                                .lineLimit(1)

                            HStack(spacing: 6) {
                                Text(log.protocolStr)
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Theme.secondaryText)

                                Text(log.rule)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(Theme.tertiaryText)
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        Text(log.action.displayName)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(actionColor(log.action))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(actionColor(log.action).opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
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

    private func formatSpeed(_ bytesPerSec: Int64) -> String {
        guard bytesPerSec > 0 else { return "0.0 KB/s" }
        let kb = Double(bytesPerSec) / 1024.0
        let mb = kb / 1024.0
        if mb >= 1.0 {
            return String(format: "%.1f MB/s", mb)
        } else {
            return String(format: "%.1f KB/s", kb)
        }
    }

    private func actionColor(_ action: RuleAction) -> Color {
        switch action {
        case .proxy:
            return Theme.blue
        case .direct:
            return Theme.green
        case .block:
            return Theme.red
        }
    }
}
