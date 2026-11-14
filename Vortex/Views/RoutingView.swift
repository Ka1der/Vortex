import SwiftUI

/// Routing engine mode selector and domain/IP/Geo rule manager
public struct RoutingView: View {
    @Bindable var tunnelManager: TunnelManager

    @State private var searchText: String = ""
    @State private var selectedFilter: ActionFilter = .all
    @State private var showingAddRuleSheet: Bool = false
    @State private var editingRule: RoutingRule? = nil

    // New rule sheet state
    @State private var newRuleType: RuleType = .domainSuffix
    @State private var newRuleValue: String = ""
    @State private var newRuleAction: RuleAction = .direct

    public enum ActionFilter: String, CaseIterable, Identifiable {
        case all = "Все"
        case proxy = "PROXY"
        case direct = "DIRECT"
        case block = "BLOCK"

        public var id: String { rawValue }
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
                        // 1. Global Mode Segmented Control
                        modeSelectorCard

                        // 2. Action Filter Chips
                        filterChipsRow

                        // 3. Routing Rules List Card
                        rulesListCard

                        Spacer(minLength: 30)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
            }
            .searchable(text: $searchText, prompt: "Поиск по домену или правилу")
            .navigationTitle("Маршрутизация")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddRuleSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.orange)
                    }
                }
            }
            .sheet(isPresented: $showingAddRuleSheet) {
                addRuleSheet
            }
            .sheet(item: $editingRule) { rule in
                EditRuleSheet(rule: rule, tunnelManager: tunnelManager)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Global Mode Selector Card

    private var modeSelectorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Глобальный режим")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .textCase(.uppercase)

            Picker("Режим", selection: Binding(
                get: { tunnelManager.globalMode },
                set: { tunnelManager.setRoutingMode($0) }
            )) {
                ForEach(GlobalRoutingMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(modeExplanation(tunnelManager.globalMode))
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 2)
        }
        .padding(14)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.secondaryCard, lineWidth: 1)
        )
    }

    private func modeExplanation(_ mode: GlobalRoutingMode) -> String {
        switch mode {
        case .config:
            return "Трафик маршрутизируется по активным правилам доменов, IP и GeoIP. Все прочие запросы идут через PROXY."
        case .proxy:
            return "Весь трафик (за исключением защиты от петель VPN-сервера) направляется через активный узел."
        case .direct:
            return "Весь трафик направляется напрямую в обход туннеля через физический интерфейс."
        case .block:
            return "Все подключения блокируются (Kill-Switch режим)."
        }
    }

    // MARK: - Filter Chips Row

    private var filterChipsRow: some View {
        HStack(spacing: 8) {
            ForEach(ActionFilter.allCases) { filter in
                let isSelected = selectedFilter == filter

                Button {
                    selectedFilter = filter
                } label: {
                    Text(filter.rawValue)
                        .font(.caption)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundStyle(isSelected ? Color.white : Theme.secondaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(chipBackground(filter: filter, isSelected: isSelected))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
    }

    private func chipBackground(filter: ActionFilter, isSelected: Bool) -> Color {
        guard isSelected else { return Theme.cardBackground }
        switch filter {
        case .all:
            return Theme.orange
        case .proxy:
            return Theme.blue
        case .direct:
            return Theme.green
        case .block:
            return Theme.red
        }
    }

    // MARK: - Rules List Card

    private var filteredRules: [RoutingRule] {
        tunnelManager.rules.filter { rule in
            // Search text filter
            let matchesSearch = searchText.isEmpty ||
                rule.value.localizedCaseInsensitiveContains(searchText) ||
                rule.type.rawValue.localizedCaseInsensitiveContains(searchText)

            // Action filter
            let matchesAction: Bool
            switch selectedFilter {
            case .all:
                matchesAction = true
            case .proxy:
                matchesAction = rule.action == .proxy
            case .direct:
                matchesAction = rule.action == .direct
            case .block:
                matchesAction = rule.action == .block
            }

            return matchesSearch && matchesAction
        }
    }

    private var rulesListCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Список правил")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.secondaryText)

                Text("(\(filteredRules.count))")
                    .font(.caption)
                    .foregroundStyle(Theme.tertiaryText)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()
                .background(Theme.divider)

            if tunnelManager.rules.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.system(size: 32))
                        .foregroundStyle(Theme.tertiaryText)
                    Text("Список правил пуст")
                        .font(.headline)
                        .foregroundStyle(Theme.secondaryText)
                    Text("Нажмите «+» вверху, чтобы добавить первое правило маршрутизации")
                        .font(.caption)
                        .foregroundStyle(Theme.tertiaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 32)
                .padding(.horizontal, 24)
            } else if filteredRules.isEmpty {
                VStack(spacing: 6) {
                    Text("Ничего не найдено")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                    Text("Нет правил, соответствующих условиям фильтра")
                        .font(.caption)
                        .foregroundStyle(Theme.tertiaryText)
                }
                .padding(.vertical, 24)
            } else {
                ForEach(Array(filteredRules.enumerated()), id: \.element.id) { index, rule in
                    if index > 0 {
                        Divider()
                            .background(Theme.divider)
                            .padding(.leading, 16)
                    }

                    ruleRow(rule: rule)
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

    private func ruleRow(rule: RoutingRule) -> some View {
        HStack(spacing: 12) {
            // Tappable row body to open edit sheet
            Button {
                editingRule = rule
            } label: {
                HStack(spacing: 12) {
                    // Type badge
                    Text(rule.type.displayName)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Theme.secondaryCard)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    // Value
                    Text(rule.value)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(rule.isEnabled ? Color.white : Theme.tertiaryText)
                        .lineLimit(1)

                    Spacer()

                    // Action badge
                    Text(rule.action.displayName)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(actionColor(rule.action))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(actionColor(rule.action).opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    // Edit indicator chevron
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.tertiaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Toggle active state without opening sheet
            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { enabled in
                    tunnelManager.toggleRule(withId: rule.id, isEnabled: enabled)
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(Theme.orange)
            .scaleEffect(0.8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        #if os(iOS)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                tunnelManager.deleteRule(withId: rule.id)
            } label: {
                Label("Удалить", systemImage: "trash")
            }
        }
        #endif
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

    // MARK: - Add Rule Sheet

    private var addRuleSheet: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Тип сопоставления")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                            .textCase(.uppercase)

                        Picker("Тип правила", selection: $newRuleType) {
                            ForEach(RuleType.allCases, id: \.self) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                        .pickerStyle(.menu)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Значение (домен, маска или IP/CIDR)")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                            .textCase(.uppercase)

                        TextField(ruleValuePlaceholder(newRuleType), text: $newRuleValue)
                            .font(.system(.body, design: .monospaced))
                            .padding()
                            .background(Theme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Действие")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                            .textCase(.uppercase)

                        Picker("Действие", selection: $newRuleAction) {
                            ForEach(RuleAction.allCases, id: \.self) { act in
                                Text(act.displayName).tag(act)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Новое правило")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        showingAddRuleSheet = false
                    }
                    .foregroundStyle(Theme.secondaryText)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить") {
                        saveNewRule()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.orange)
                    .disabled(newRuleValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func ruleValuePlaceholder(_ type: RuleType) -> String {
        switch type {
        case .domain:
            return "example.com"
        case .domainSuffix:
            return "google.com или ru"
        case .domainKeyword:
            return "instagram"
        case .ipCidr:
            return "192.168.1.0/24"
        case .geoip:
            return "ru или private"
        case .geosite:
            return "category-ads-all"
        }
    }

    private func saveNewRule() {
        let trimmed = newRuleValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let rule = RoutingRule(
            type: newRuleType,
            value: trimmed,
            action: newRuleAction,
            isEnabled: true
        )
        tunnelManager.addRule(rule)

        newRuleValue = ""
        showingAddRuleSheet = false
    }
}

// MARK: - Edit Rule Sheet

public struct EditRuleSheet: View {
    @Environment(\.dismiss) private var dismiss
    let rule: RoutingRule
    let tunnelManager: TunnelManager

    @State private var ruleType: RuleType
    @State private var ruleValue: String
    @State private var ruleAction: RuleAction
    @State private var isEnabled: Bool

    public init(rule: RoutingRule, tunnelManager: TunnelManager) {
        self.rule = rule
        self.tunnelManager = tunnelManager
        _ruleType = State(initialValue: rule.type)
        _ruleValue = State(initialValue: rule.value)
        _ruleAction = State(initialValue: rule.action)
        _isEnabled = State(initialValue: rule.isEnabled)
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Type selector
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Тип сопоставления")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                                .textCase(.uppercase)

                            Picker("Тип правила", selection: $ruleType) {
                                ForEach(RuleType.allCases, id: \.self) { type in
                                    Text(type.displayName).tag(type)
                                }
                            }
                            .pickerStyle(.menu)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        // Value input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Значение (домен, маска или IP/CIDR)")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                                .textCase(.uppercase)

                            TextField(ruleValuePlaceholder(ruleType), text: $ruleValue)
                                .font(.system(.body, design: .monospaced))
                                .padding()
                                .background(Theme.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        // Action selector
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Действие")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                                .textCase(.uppercase)

                            Picker("Действие", selection: $ruleAction) {
                                ForEach(RuleAction.allCases, id: \.self) { act in
                                    Text(act.displayName).tag(act)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        // Rule active switch
                        VStack(spacing: 0) {
                            HStack {
                                Text("Правило активно")
                                    .font(.body)
                                    .foregroundStyle(Color.white)
                                Spacer()
                                Toggle("", isOn: $isEnabled)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                                    .tint(Theme.orange)
                            }
                            .padding()
                        }
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                        // Delete button
                        Button(role: .destructive) {
                            tunnelManager.deleteRule(withId: rule.id)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Удалить правило")
                            }
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.red)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Theme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Theme.red.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .padding(.top, 10)

                        Spacer()
                    }
                    .padding()
                }
            }
            .navigationTitle("Редактирование")
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
                    Button("Сохранить") {
                        saveChanges()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.orange)
                    .disabled(ruleValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func ruleValuePlaceholder(_ type: RuleType) -> String {
        switch type {
        case .domain:
            return "example.com"
        case .domainSuffix:
            return "google.com или ru"
        case .domainKeyword:
            return "instagram"
        case .ipCidr:
            return "192.168.1.0/24"
        case .geoip:
            return "ru или private"
        case .geosite:
            return "category-ads-all"
        }
    }

    private func saveChanges() {
        let trimmed = ruleValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let updated = RoutingRule(
            id: rule.id,
            type: ruleType,
            value: trimmed,
            action: ruleAction,
            isEnabled: isEnabled
        )
        tunnelManager.updateRule(updated)
        dismiss()
    }
}
