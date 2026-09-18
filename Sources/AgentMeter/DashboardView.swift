import SwiftUI
import Charts
import AgentMeterCore

/// Two-column window: system sidebar for destinations, toolbar for actions on
/// the current content, scrolling detail for the content itself.
struct DashboardView: View {
    @EnvironmentObject private var store: UsageStore
    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            DashboardSidebar()
        } detail: {
            DashboardDetail()
        }
        .navigationTitle(store.selection?.name ?? "전체 개요")
        .navigationSubtitle(subtitle)
        .toolbar {
            // Period sits with the title; actions on the content stay at the trailing edge.
            ToolbarItem(placement: .automatic) {
                Picker("기간", selection: $store.days) {
                    Text("오늘").tag(1)
                    Text("7일").tag(7)
                    Text("30일").tag(30)
                }
                .pickerStyle(.segmented)
                .help("토큰 집계 기간")
            }
            ToolbarItem(placement: .automatic) { Spacer() }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { Task { await store.refresh(allowClaudeInteraction: true) } } label: {
                    if store.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("새로고침", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(store.isRefreshing)
                .help("사용 기록 새로고침 (⌘R)")
                SettingsLink { Label("연결 및 설정", systemImage: "gearshape") }
                    .help("연결 및 설정")
            }
        }
    }

    private var subtitle: String {
        let period = store.days == 1 ? "오늘" : "최근 \(store.days)일"
        guard let date = store.lastRefresh else { return period }
        return "\(period) · \(date.formatted(date: .omitted, time: .shortened)) 확인"
    }
}

private struct DashboardDetail: View {
    @EnvironmentObject private var store: UsageStore

    private var quotaProviders: [Provider] {
        store.orderedProviders.filter { store.selection == nil || $0 == store.selection }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                quotaSection
                if store.selection == .antigravity {
                    Label("Antigravity는 구독 한도만 표시합니다. 토큰·세션·캐시 통계는 아직 지원하지 않습니다.", systemImage: "info.circle")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    tokenSection
                    chartSection
                    modelSection
                }
                Text("토큰은 이 Mac의 기록만 집계하고 Claude·Antigravity 한도는 로그인한 계정 기준입니다. 토큰 수를 구독 한도나 청구액으로 환산하지 않습니다.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(MeterStyle.gutter)
            .frame(maxWidth: 1200, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(MeterStyle.canvas)
    }

    // MARK: 구독 한도

    private var quotaSection: some View {
        VStack(alignment: .leading, spacing: MeterStyle.gap) {
            SectionHeader("구독 한도", note: "마지막 확인 기준")
            if let selected = store.selection {
                ProviderQuotaCard(provider: selected).frame(maxWidth: 640, alignment: .leading)
            } else {
                // Two equal-height cards per row keep the four agents aligned.
                ForEach(Array(stride(from: 0, to: quotaProviders.count, by: 2)), id: \.self) { start in
                    HStack(alignment: .top, spacing: MeterStyle.gap) {
                        ForEach(quotaProviders[start..<min(start + 2, quotaProviders.count)]) { provider in
                            ProviderQuotaCard(provider: provider)
                        }
                        if start + 1 >= quotaProviders.count { Color.clear.frame(maxWidth: .infinity) }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: 토큰 사용량

    private var tokenSection: some View {
        VStack(alignment: .leading, spacing: MeterStyle.gap) {
            SectionHeader("토큰 사용량", note: store.days == 1 ? "오늘" : "최근 \(store.days)일")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: MeterStyle.gap)], spacing: MeterStyle.gap) {
                StatTile(title: "총 토큰", value: compact(store.total), detail: "캐시 · 추론 포함", symbol: "number")
                StatTile(title: "활성 세션", value: store.sessionCount.formatted(), detail: "기간 내 사용한 세션", symbol: "square.stack.3d.up")
                StatTile(title: "캐시 적중 비율", value: String(format: "%.1f%%", store.cachePercent), detail: "전체 입력 중 캐시 읽기", symbol: "arrow.triangle.2.circlepath")
            }
        }
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: MeterStyle.gap) {
            SectionHeader("사용 추이", note: "일별 토큰") {
                HStack(spacing: 10) {
                    ForEach(store.orderedProviders.filter { $0 != .antigravity && (store.selection == nil || $0 == store.selection) }) { provider in
                        HStack(spacing: 5) {
                            Circle().fill(provider.tint).frame(width: 8, height: 8)
                            Text(provider.name).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.accessibilityHidden(true)
            }
            Group {
                if store.events.isEmpty {
                    EmptyContent(symbol: "chart.xyaxis.line",
                                 title: store.isRefreshing ? "사용 기록을 읽고 있습니다" : "이 기간에 기록된 사용량이 없습니다",
                                 detail: "기간을 바꾸거나 연결 및 설정에서 기록 폴더를 확인하세요.")
                        .frame(height: 200)
                } else {
                    Chart(store.daily) { point in
                        BarMark(x: .value("날짜", point.date, unit: .day), y: .value("토큰", point.tokens))
                            .foregroundStyle(by: .value("에이전트", point.provider.name))
                            .cornerRadius(3)
                    }
                    .chartForegroundStyleScale(domain: Provider.allCases.map(\.name), range: Provider.allCases.map(\.tint))
                    .chartLegend(.hidden)
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: store.days > 7 ? 5 : 1)) { _ in
                            AxisValueLabel(format: .dateTime.month().day())
                            AxisTick()
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine().foregroundStyle(Color(nsColor: .separatorColor))
                            AxisValueLabel {
                                if let tokens = value.as(Int.self) { Text(compact(tokens)).font(.caption) }
                            }
                        }
                    }
                    .frame(height: 200)
                }
            }
            .padding(16)
            .meterCard()
        }
    }

    // MARK: 모델별 사용량

    private var modelSection: some View {
        let groups = Dictionary(grouping: store.events) { $0.provider.rawValue + ":" + $0.model }
        let rows = groups.values.sorted { $0.reduce(0) { $0 + $1.total } > $1.reduce(0) { $0 + $1.total } }
        return VStack(alignment: .leading, spacing: MeterStyle.gap) {
            SectionHeader("모델별 사용량")
            Group {
                if rows.isEmpty {
                    EmptyContent(symbol: "cpu", title: "모델별 사용량이 없습니다", detail: "사용 기록이 수집되면 모델별 토큰을 표시합니다.")
                        .frame(height: 120)
                } else {
                    Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 0) {
                        GridRow {
                            Text("모델").gridColumnAlignment(.leading)
                            Text("입력")
                            Text("출력·추론")
                            Text("캐시 읽기·쓰기")
                            Text("합계")
                        }
                        .font(.subheadline).foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                        Divider()
                        ForEach(Array(rows.enumerated()), id: \.element.first!.id) { offset, events in
                            if let event = events.first {
                                GridRow {
                                    HStack(spacing: 8) {
                                        ProviderLogo(provider: event.provider, size: 18)
                                        Text(event.model).lineLimit(1).truncationMode(.middle).help(event.model)
                                    }
                                    .gridColumnAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(compact(events.reduce(0) { $0 + $1.input }))
                                    Text(compact(events.reduce(0) { $0 + $1.output }))
                                    Text(compact(events.reduce(0) { $0 + $1.cacheRead + $1.cacheWrite }))
                                    Text(compact(events.reduce(0) { $0 + $1.total })).fontWeight(.semibold)
                                }
                                .monospacedDigit()
                                .padding(.vertical, 8)
                                if offset < rows.count - 1 { Divider() }
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 4)
                }
            }
            .meterCard()
        }
    }
}

// MARK: - Components

private struct StatTile: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.subheadline).foregroundStyle(.secondary)
            Text(value)
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(detail).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .meterCard()
        .accessibilityElement(children: .combine)
    }
}

private struct EmptyContent: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 28)).foregroundStyle(.tertiary)
            Text(title).font(.callout)
            Text(detail).font(.footnote).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}

/// One provider's quota windows, or the guidance needed to connect them.
struct ProviderQuotaCard: View {
    @EnvironmentObject private var store: UsageStore
    let provider: Provider

    private var quotas: [QuotaWindow] { store.result.quotas.filter { $0.provider == provider } }
    private var source: SourceStatus? { store.result.sources.first { $0.provider == provider } }
    private var error: String? {
        switch provider {
        case .antigravity: store.antigravityRefreshError
        case .claude: store.claudeRefreshError
        case .codex: store.codexRefreshError
        case .gemini: nil
        }
    }
    private var status: (text: String, connected: Bool) {
        if provider == .antigravity {
            let ok = store.antigravityRefreshError == nil && !quotas.isEmpty
            return (ok ? "한도 연결됨" : "한도 연결 대기", ok)
        }
        guard let source else { return ("확인 중", false) }
        if !source.exists { return ("기록 폴더 없음", false) }
        return source.eventCount > 0 ? ("기록 연결됨", true) : ("토큰 기록 없음", false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ProviderLogo(provider: provider, size: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.name).font(.headline)
                    Text(provider.subtitle).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                HStack(spacing: 5) {
                    Circle().fill(status.connected ? Color.green : Color.secondary.opacity(0.5)).frame(width: 6, height: 6)
                    Text(status.text).font(.footnote).foregroundStyle(.secondary)
                    if !(source?.warnings.isEmpty ?? true) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange)
                            .help("연결 및 설정에서 수집 오류를 확인하세요.")
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if quotas.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label(provider == .gemini ? "구독 한도 미지원" : "한도 정보 대기", systemImage: "gauge.with.dots.needle.0percent")
                        .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    Text(guidance).font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 6)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(quotas) { quota in QuotaRow(quota: quota) }
                }
            }
            if let error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.footnote).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .meterCard()
    }

    private var guidance: String {
        switch provider {
        case .claude: "Claude Code에 로그인한 뒤 새로고침하세요."
        case .codex: "Codex CLI에서 ChatGPT 계정으로 로그인한 뒤 새로고침하세요."
        case .gemini: "로컬 기록의 토큰 사용량만 집계합니다."
        case .antigravity: "Antigravity를 실행하고 로그인한 뒤 새로고침하세요."
        }
    }
}

/// A single quota window: label, usage bar, reset countdown and observation time.
struct QuotaRow: View {
    let quota: QuotaWindow
    var compact = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let stale = quota.isStale(at: context.date)
            let barColor: Color = stale ? .secondary : quota.usedPercent >= 90 ? .orange : quota.provider.tint
            VStack(alignment: .leading, spacing: compact ? 4 : 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(quota.label).font(compact ? .caption : .subheadline)
                    Spacer()
                    Text("\(Int(quota.usedPercent))%")
                        .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(quota.usedPercent >= 90 && !stale ? Color.orange : Color.primary)
                }
                ProgressView(value: min(100, max(0, quota.usedPercent)), total: 100)
                    .tint(barColor)
                    .controlSize(compact ? .small : .regular)
                HStack(spacing: 4) {
                    if let reset = quota.resetsAt {
                        if reset <= context.date {
                            Label("리셋 경과 · 새 기록 대기", systemImage: "clock.arrow.circlepath").foregroundStyle(.orange)
                        } else {
                            Text(reset, style: .relative)
                            Text("후 리셋")
                        }
                    } else {
                        Text("리셋 미정")
                    }
                    Spacer(minLength: 4)
                    if stale { Image(systemName: "clock").foregroundStyle(.orange) }
                    Text(quota.observedAt, format: compact ? .dateTime.hour().minute() : .dateTime.month().day().hour().minute())
                    Text("확인")
                }
                .font(compact ? .caption2 : .caption)
                .foregroundStyle(stale ? Color.orange : Color.secondary)
                .help("기록 확인: \(quota.observedAt.formatted(date: .abbreviated, time: .shortened))\(stale ? " · 이전 기록" : "")\n리셋: \(quota.resetsAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "미정")")
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(quota.provider.name) \(quota.label) 한도")
            .accessibilityValue("\(Int(quota.usedPercent))% 사용\(stale ? ", 이전 기록" : "")")
        }
    }
}
