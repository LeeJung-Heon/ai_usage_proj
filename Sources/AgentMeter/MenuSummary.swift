import SwiftUI
import AgentMeterCore

struct MenuSummary: View {
    @EnvironmentObject private var store: UsageStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let today = UsageAggregation.filtered(store.result.events, provider: nil, days: 1, now: context.date)
            let total = today.reduce(0) { $0 + $1.total }
            let counts = Dictionary(grouping: today, by: \.provider).mapValues { $0.reduce(0) { $0 + $1.total } }

            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        overview(total: total, counts: counts, sessions: Set(today.map { $0.provider.rawValue + ":" + $0.session }).count)
                        HStack {
                            Text("에이전트").font(.system(size: 11, weight: .semibold))
                            Spacer()
                            Text("오늘의 토큰 · 최근 한도").font(.system(size: 10)).foregroundStyle(.secondary)
                        }.padding(.horizontal, 2).padding(.top, 4)
                        VStack(spacing: 12) {
                            ForEach(store.orderedProviders) { provider in
                                MenuProviderCard(provider: provider, count: counts[provider, default: 0])
                            }
                        }
                    }.padding(.horizontal, 18).padding(.bottom, 16)
                }
                .scrollBounceBehavior(.basedOnSize)
                footer
            }
            .frame(width: 360)
            .frame(height: min(690, (NSScreen.main?.visibleFrame.height ?? 800) - 40))
            .background(MeterStyle.canvas)
            .tint(MeterStyle.accent)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            MeterMark(size: 22)
            Text("사용량 요약").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            Spacer()
            Button { Task { await store.refresh(allowClaudeInteraction: true) } } label: {
                ZStack {
                    if store.isRefreshing { ProgressView().controlSize(.small) }
                    else { Image(systemName: "arrow.clockwise") }
                }.frame(width: 28, height: 28)
            }
            .disabled(store.isRefreshing)
            .keyboardShortcut("r", modifiers: .command)
            .help("사용 기록 새로고침 (⌘R)")
            .accessibilityLabel("사용 기록 새로고침")
            SettingsLink {
                Image(systemName: "slider.horizontal.3").frame(width: 28, height: 28)
            }.help("연결 및 설정").accessibilityLabel("연결 및 설정")
        }
        .buttonStyle(MenuControlStyle())
        .padding(.horizontal, 18).padding(.vertical, 10)
    }

    private func overview(total: Int, counts: [Provider: Int], sessions: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("오늘의 사용량").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Text(Date(), format: .dateTime.month().day())
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(compact(total))
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .tracking(-1.5).monospacedDigit()
                    .contentTransition(.numericText())
                    .help("\(total.formatted()) 토큰")
                Text("토큰").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(sessions.formatted()).font(.system(size: 17, weight: .medium, design: .rounded)).monospacedDigit()
                    Text("활성 세션").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            VStack(spacing: 10) {
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        ForEach(store.orderedProviders.filter { $0 != .antigravity }) { provider in
                            Rectangle().fill(provider.tint)
                                .frame(width: total > 0 ? geometry.size.width * Double(counts[provider, default: 0]) / Double(total) : 0)
                        }
                    }
                }
                .frame(height: 5)
                .background(.primary.opacity(0.07), in: Capsule())
                .clipShape(Capsule())
                .accessibilityLabel("오늘의 에이전트별 토큰 비중")
                HStack {
                    ForEach(store.orderedProviders.filter { $0 != .antigravity }) { provider in
                        HStack(spacing: 4) {
                            Circle().fill(provider.tint).frame(width: 5, height: 5)
                            Text(provider.name)
                            Text(total > 0 ? "\(Int((Double(counts[provider, default: 0]) / Double(total) * 100).rounded()))%" : "—")
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                        if provider != store.orderedProviders.last(where: { $0 != .antigravity }) { Spacer(minLength: 4) }
                    }
                }.font(.system(size: 10))
            }
            Text("토큰 합계에 Antigravity는 포함되지 않습니다.").font(.system(size: 9)).foregroundStyle(.secondary)
            if total == 0 {
                Text(store.isRefreshing ? "사용 기록을 읽고 있습니다…" : "오늘 사용 기록이 생기면 여기에 표시됩니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(LinearGradient(colors: [MeterStyle.accent.opacity(0.12), MeterStyle.accent.opacity(0.025)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(MeterStyle.accent.opacity(0.16)))
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button {
                openWindow(id: "dashboard")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                HStack {
                    Image(systemName: "square.grid.2x2")
                    Text("대시보드 열기")
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold))
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 13).padding(.vertical, 11)
                .foregroundStyle(.white)
                .background(MeterStyle.accent.gradient, in: RoundedRectangle(cornerRadius: 10))
            }.buttonStyle(MenuControlStyle())
            HStack(spacing: 5) {
                Image(systemName: "internaldrive").font(.system(size: 9))
                Text("로컬 기록")
                if let date = store.lastRefresh {
                    Text("·")
                    Text(date, format: .dateTime.hour().minute())
                    Text("갱신")
                }
                Spacer()
                Button("종료") { NSApp.terminate(nil) }
                    .buttonStyle(.plain).help("Agent Meter 종료")
            }.font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(14).padding(.top, -2)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

private struct MenuProviderCard: View {
    @EnvironmentObject private var store: UsageStore
    let provider: Provider
    let count: Int

    var body: some View {
        let quotas = store.result.quotas.filter { $0.provider == provider }
        let source = store.result.sources.first { $0.provider == provider }
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ProviderLogo(provider: provider, size: 22)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(provider.name).font(.system(size: 12, weight: .semibold))
                        if provider == store.firstProvider {
                            Image(systemName: "menubar.rectangle").font(.system(size: 9)).foregroundStyle(.secondary)
                                .help("메뉴 막대에 표시 중")
                        }
                    }
                    Text(provider == .antigravity ? (store.antigravityRefreshError == nil && !quotas.isEmpty ? "한도 연결됨" : "한도 연결 대기") : source == nil ? "확인 중" : source?.exists != true ? "기록 폴더 없음" : (source?.eventCount ?? 0) > 0 ? "기록 연결됨" : "토큰 기록 없음")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(provider == .antigravity ? "—" : compact(count)).font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text(provider == .antigravity ? "토큰 미지원" : "토큰").font(.system(size: 9)).foregroundStyle(.secondary)
                }.help(provider == .antigravity ? "토큰 집계 미지원" : "오늘 \(count.formatted()) 토큰")
                if !(source?.warnings.isEmpty ?? true) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange).help("연결 설정에서 수집 오류를 확인하세요.")
                }
            }
            if quotas.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "gauge.with.dots.needle.0percent")
                    Text(provider == .gemini ? "구독 한도 미지원" : "한도 정보 대기")
                    Spacer()
                    if provider == .claude || provider == .antigravity {
                        SettingsLink { Text("연결 설정").foregroundStyle(provider.tint) }
                            .buttonStyle(.plain)
                    }
                }.font(.system(size: 10)).foregroundStyle(.secondary)
            } else {
                Divider().overlay(provider.tint.opacity(0.05))
                ForEach(quotas) { quota in QuotaRow(quota: quota, compact: true) }
            }
            if let error = provider == .antigravity ? store.antigravityRefreshError : provider == .claude ? store.claudeRefreshError : provider == .codex ? store.codexRefreshError : nil {
                Text(error).font(.system(size: 10)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .meterCard()
    }
}

private struct MenuControlStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MenuControl(configuration: configuration)
    }

    private struct MenuControl: View {
        let configuration: ButtonStyleConfiguration
        @State private var isHovered = false
        var body: some View {
            configuration.label
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .background(.primary.opacity(configuration.isPressed ? 0.1 : isHovered ? 0.05 : 0), in: RoundedRectangle(cornerRadius: 8))
                .onHover { isHovered = $0 }
        }
    }
}
