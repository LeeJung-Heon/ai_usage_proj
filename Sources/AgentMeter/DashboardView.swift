import SwiftUI
import Charts
import AgentMeterCore

struct DashboardView: View {
    @EnvironmentObject private var store: UsageStore
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    HStack(spacing: 14) {
                        metric("총 토큰", value: store.selection == .antigravity ? "—" : compact(store.total), footnote: store.selection == .antigravity ? "토큰 집계 미지원" : "캐시 · 추론 포함 · Antigravity 제외", symbol: "chart.bar.fill", accent: true)
                        metric("활성 세션", value: store.selection == .antigravity ? "—" : store.sessionCount.formatted(), footnote: "선택한 기간의 사용 세션", symbol: "square.stack.3d.up")
                        metric("캐시 적중 비율", value: store.selection == .antigravity ? "—" : String(format: "%.1f%%", store.cachePercent), footnote: "전체 입력 중 캐시 읽기", symbol: "arrow.triangle.2.circlepath")
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("에이전트 현황").font(.headline)
                            Spacer()
                            Text("토큰은 선택 기간 · 한도는 마지막 기록 기준").font(.caption).foregroundStyle(.secondary)
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .top), count: store.selection == nil ? 2 : 1), alignment: .leading, spacing: 14) {
                            ForEach(store.orderedProviders.filter { store.selection == nil || $0 == store.selection }) { provider in
                                ProviderCard(provider: provider).frame(maxWidth: .infinity, alignment: .topLeading)
                            }
                        }
                    }
                    if store.selection == .antigravity {
                        Label("Antigravity는 구독 한도를 표시합니다. 토큰·세션·캐시 통계는 아직 지원하지 않습니다.", systemImage: "info.circle")
                            .font(.callout).foregroundStyle(.secondary).padding(22).frame(maxWidth: .infinity, alignment: .leading).meterCard()
                    } else {
                        usageChart
                        modelBreakdown
                    }
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle")
                        Text("토큰은 이 Mac의 기록만 집계하고 Claude·Antigravity 한도는 로그인한 계정 기준입니다. 토큰 수를 구독 한도나 청구액으로 환산하지 않습니다.")
                    }.font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(28).frame(maxWidth: 1440).frame(maxWidth: .infinity)
            }.background(MeterStyle.canvas)
        }
        .tint(MeterStyle.accent)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { Task { await store.refresh(allowClaudeInteraction: true) } } label: {
                    HStack(spacing: 8) {
                        if let date = store.lastRefresh {
                            Text(date, format: .dateTime.hour().minute())
                                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                                .fixedSize()
                        }
                        if store.isRefreshing {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
                    .accessibilityLabel("새로고침")
                    .disabled(store.isRefreshing).help("사용 기록 새로고침 (⌘R)")
                SettingsLink { Label("연결 설정", systemImage: "slider.horizontal.3") }
            }
        }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                MeterMark(size: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Agent Meter").font(.system(size: 15, weight: .semibold))
                    Text("내 Mac의 AI 사용량").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 8).padding(.bottom, 32)
            Text("워크스페이스").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 12).padding(.bottom, 10)
            navigationRow("전체 개요", provider: nil)
            HStack {
                Text("에이전트").font(.system(size: 10, weight: .semibold))
                Spacer()
                Image(systemName: "arrow.up.arrow.down").font(.system(size: 9))
            }.foregroundStyle(.secondary).padding(.horizontal, 12).padding(.top, 28).padding(.bottom, 10)
            AgentSidebarList()
            Text("드래그로 정렬 · 맨 위는 메뉴 막대에 표시")
                .font(.system(size: 9)).foregroundStyle(.tertiary)
                .padding(.horizontal, 12).padding(.top, 10)
            Spacer(minLength: 30)
            VStack(alignment: .leading, spacing: 10) {
                Label("로컬에서 안전하게", systemImage: "lock.shield").font(.caption.weight(.medium))
                Text("대화 내용은 로컬에 보관합니다.\n한도는 기존 로그인으로 조회합니다.").font(.caption).foregroundStyle(.secondary).lineSpacing(3)
                HStack(spacing: 5) {
                    Circle().fill(store.autoRefresh ? MeterStyle.accent : Color.secondary).frame(width: 5, height: 5)
                    Text(store.autoRefresh ? "60초마다 자동 갱신" : "수동 갱신").font(.caption2).foregroundStyle(.secondary)
                }
            }.padding(13).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            SettingsLink { Label("연결 및 설정", systemImage: "gearshape") }.buttonStyle(.plain).font(.callout).padding(.top, 20).padding(.leading, 10)
            Text("VERSION 0.1.0").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(.tertiary).padding(.top, 24).padding(.leading, 10)
        }.padding(16).frame(width: 228).background(.thinMaterial)
    }
    private func navigationRow(_ name: String, provider: Provider?) -> some View {
        Button { store.selection = provider } label: {
            HStack(spacing: 11) {
                if let provider {
                    ProviderLogo(provider: provider, size: 18)
                } else {
                    Image(systemName: "square.grid.2x2").frame(width: 18).foregroundStyle(.teal)
                }
                Text(name).fontWeight(store.selection == provider ? .semibold : .regular)
                Spacer()
                if provider != nil { Circle().fill((store.result.sources.first { $0.provider == provider }?.eventCount ?? 0) > 0 ? MeterStyle.accent : Color.secondary.opacity(0.4)).frame(width: 5, height: 5) }
            }.padding(.horizontal, 12).padding(.vertical, 11).contentShape(Rectangle())
                .background(store.selection == provider ? MeterStyle.accent.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain).padding(.bottom, 4)
    }
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 7) {
                Text(Date(), format: .dateTime.year().month(.wide).day().weekday(.wide)).font(.caption).foregroundStyle(.secondary)
                Text(store.selection.map { "\($0.name) 사용량" } ?? "사용량 개요").font(.system(size: 29, weight: .bold))
                Text("에이전트별 토큰과 구독 한도를 한눈에 확인하세요.").font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("기간", selection: $store.days) {
                Text("오늘").tag(1); Text("7일").tag(7); Text("30일").tag(30)
            }.pickerStyle(.segmented).frame(width: 190)
        }
    }
    private func metric(_ title: String, value: String, footnote: String, symbol: String, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                    .foregroundStyle(accent ? MeterStyle.accent : Color.secondary)
                    .frame(width: 30, height: 30)
                    .background((accent ? MeterStyle.accent : Color.secondary).opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
            }
            Text(value).font(.system(size: 32, weight: .semibold, design: .rounded)).monospacedDigit().tracking(-0.8)
            Text(footnote).font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .meterCard(tint: accent ? MeterStyle.accent : nil)
            .overlay(alignment: .top) {
                if accent { Capsule().fill(MeterStyle.accent).frame(width: 34, height: 3).padding(.top, 1) }
            }
    }
    private var usageChart: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("사용 추이").font(.headline)
                    Text("일별 토큰 · 현재 Mac 시간대").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                ForEach(store.orderedProviders.filter { $0 != .antigravity && (store.selection == nil || $0 == store.selection) }) { provider in
                    HStack(spacing: 5) { Circle().fill(provider.tint).frame(width: 7, height: 7); Text(provider.name).font(.caption).foregroundStyle(.secondary) }
                }
            }
            if store.events.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "chart.xyaxis.line").font(.system(size: 28)).foregroundStyle(.tertiary)
                    Text(store.isRefreshing ? "사용 기록을 읽고 있습니다" : "이 기간에 기록된 사용량이 없습니다").font(.callout)
                    Text("기간을 바꾸거나 연결 설정에서 기록 폴더를 확인하세요.").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).frame(height: 165)
            } else {
                Chart(store.daily) { point in
                    BarMark(x: .value("날짜", point.date, unit: .day), y: .value("토큰", point.tokens))
                        .foregroundStyle(by: .value("에이전트", point.provider.name)).cornerRadius(3)
                }
                .chartForegroundStyleScale(domain: Provider.allCases.map(\.name), range: Provider.allCases.map(\.tint))
                .chartLegend(.hidden)
                .chartXAxis { AxisMarks(values: .stride(by: .day, count: store.days > 7 ? 5 : 1)) { _ in AxisValueLabel(format: .dateTime.month().day()); AxisTick() } }
                .chartYAxis { AxisMarks(position: .leading) { value in AxisGridLine().foregroundStyle(.primary.opacity(0.06)); AxisValueLabel { if let tokens = value.as(Int.self) { Text(compact(tokens)).font(.caption2) } } } }
                .frame(height: 170)
            }
        }.padding(22).meterCard()
    }
    private var modelBreakdown: some View {
        let groups = Dictionary(grouping: store.events) { $0.provider.rawValue + ":" + $0.model }
        let rows = groups.values.sorted { $0.reduce(0) { $0 + $1.total } > $1.reduce(0) { $0 + $1.total } }
        return VStack(alignment: .leading, spacing: 15) {
            Text("모델별 사용량").font(.headline)
            HStack {
                Text("모델").frame(maxWidth: .infinity, alignment: .leading)
                Text("입력").frame(width: 90, alignment: .trailing)
                Text("출력·추론").frame(width: 90, alignment: .trailing)
                Text("캐시 읽기·쓰기").frame(width: 100, alignment: .trailing)
                Text("합계").frame(width: 90, alignment: .trailing)
            }.font(.caption).foregroundStyle(.secondary)
            Divider()
            if rows.isEmpty { Text("사용 기록이 수집되면 모델별 토큰을 표시합니다.").font(.callout).foregroundStyle(.secondary).padding(.vertical, 10) }
            ForEach(rows, id: \.first!.id) { events in
                if let event = events.first {
                    HStack {
                        HStack(spacing: 9) {
                            ProviderLogo(provider: event.provider, size: 18)
                            Text(event.model).lineLimit(1).help(event.model)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Text(compact(events.reduce(0) { $0 + $1.input })).frame(width: 90, alignment: .trailing)
                        Text(compact(events.reduce(0) { $0 + $1.output })).frame(width: 90, alignment: .trailing)
                        Text(compact(events.reduce(0) { $0 + $1.cacheRead + $1.cacheWrite })).frame(width: 100, alignment: .trailing)
                        Text(compact(events.reduce(0) { $0 + $1.total })).fontWeight(.semibold).frame(width: 90, alignment: .trailing)
                    }.font(.system(size: 12)).monospacedDigit().padding(.vertical, 5)
                }
            }
        }.padding(22).meterCard()
    }
}

struct ProviderCard: View {
    @EnvironmentObject private var store: UsageStore
    let provider: Provider
    var body: some View {
        let events = store.events.filter { $0.provider == provider }
        let source = store.result.sources.first { $0.provider == provider }
        let quotas = store.result.quotas.filter { $0.provider == provider }
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 10) {
                ProviderLogo(provider: provider, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.name).font(.headline)
                    Text(provider.subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(provider == .antigravity ? "—" : compact(events.reduce(0) { $0 + $1.total })).font(.system(size: 25, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(provider == .antigravity ? "토큰 집계 미지원" : "토큰").font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            if quotas.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Label(provider == .gemini ? "구독 한도 미지원" : "한도 정보 대기", systemImage: "gauge.with.dots.needle.0percent").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Text(provider == .claude ? "Claude Code 로그인 후 새로고침하세요." : provider == .gemini ? "로컬 기록의 토큰 사용량을 집계합니다." : provider == .antigravity ? "Antigravity를 실행하고 로그인한 뒤 새로고침하세요." : "Codex CLI에서 ChatGPT 계정으로 로그인한 뒤 새로고침하세요.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.frame(minHeight: 57, alignment: .topLeading)
            } else {
                ForEach(quotas) { quota in QuotaRow(quota: quota) }
            }
            if let error = provider == .antigravity ? store.antigravityRefreshError : provider == .claude ? store.claudeRefreshError : provider == .codex ? store.codexRefreshError : nil {
                Text(error).font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                Circle().fill((provider == .antigravity ? store.antigravityRefreshError == nil && !quotas.isEmpty : (source?.eventCount ?? 0) > 0) ? provider.tint : Color.secondary.opacity(0.4)).frame(width: 5, height: 5)
                Text(provider == .antigravity ? (store.antigravityRefreshError == nil && !quotas.isEmpty ? "한도 연결됨" : "한도 연결 대기") : source == nil ? "확인 중" : source?.exists != true ? "기록 폴더 없음" : (source?.eventCount ?? 0) > 0 ? "기록 연결됨" : "토큰 기록 없음").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                if !(source?.warnings.isEmpty ?? true) { Image(systemName: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).help("연결 설정에서 수집 오류를 확인하세요.") }
            }
        }.padding(18).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .meterCard(tint: provider.tint)
            .overlay(alignment: .topLeading) {
                Capsule().fill(provider.tint.opacity(0.8)).frame(width: 24, height: 3).padding(.leading, 18).padding(.top, 1)
            }
    }
}

struct QuotaRow: View {
    let quota: QuotaWindow
    var compact = false
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let stale = quota.isStale(at: context.date)
            VStack(alignment: .leading, spacing: compact ? 5 : 7) {
                HStack {
                    Text(quota.label).font(.caption)
                    Spacer()
                    Text("\(Int(quota.usedPercent))% 사용").font(.caption.weight(.semibold)).monospacedDigit()
                }
                if compact {
                    GeometryReader { geometry in
                        Capsule().fill(.primary.opacity(0.08))
                            .overlay(alignment: .leading) {
                                Capsule().fill(stale ? Color.secondary : quota.usedPercent >= 90 ? .orange : quota.provider.tint)
                                    .frame(width: geometry.size.width * min(100, max(0, quota.usedPercent)) / 100)
                            }
                    }.frame(height: 4).accessibilityHidden(true)
                    HStack(spacing: 3) {
                        if let reset = quota.resetsAt {
                            if reset <= context.date { Text("리셋 경과 · 갱신 대기").foregroundStyle(.orange) }
                            else { Text(reset, style: .relative); Text("후 리셋") }
                        } else { Text("리셋 미정") }
                        Spacer(minLength: 4)
                        if stale { Image(systemName: "clock").foregroundStyle(.orange) }
                        Text(quota.observedAt, format: .dateTime.hour().minute())
                            .foregroundStyle(stale ? Color.orange : Color.secondary)
                        Text("확인").foregroundStyle(stale ? Color.orange : Color.secondary)
                    }.font(.system(size: 9)).foregroundStyle(.secondary)
                        .help("기록 확인: \(quota.observedAt.formatted(date: .abbreviated, time: .shortened))\(stale ? " · 이전 기록" : "")\n리셋: \(quota.resetsAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "미정")")
                } else {
                    ProgressView(value: min(100, max(0, quota.usedPercent)), total: 100)
                        .tint(stale ? .secondary : quota.usedPercent >= 90 ? .orange : quota.provider.tint)
                if let reset = quota.resetsAt {
                    if reset <= context.date { Text("리셋 시각 경과 · 새 기록 대기").font(.system(size: 10)).foregroundStyle(.orange) }
                    else {
                        HStack(spacing: 3) { Text(reset, style: .relative); Text("후 리셋") }.font(.system(size: 10)).foregroundStyle(.secondary)
                            .help(reset.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                HStack(spacing: 3) {
                    if stale { Image(systemName: "clock") }
                    Text(quota.observedAt, format: .dateTime.month().day().hour().minute())
                    Text("확인")
                }.font(.system(size: 9)).foregroundStyle(stale ? Color.orange : Color.secondary)
                }
            }
        }
    }
}
