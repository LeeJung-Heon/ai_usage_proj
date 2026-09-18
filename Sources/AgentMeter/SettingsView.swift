import SwiftUI
import AgentMeterCore

struct ConnectionSettings: View {
    @EnvironmentObject private var store: UsageStore
    var body: some View {
        Form {
            Section {
                Picker("대시보드 1번 에이전트", selection: $store.firstProvider) {
                    ForEach(Provider.allCases) { provider in
                        Text(provider.name).tag(provider)
                    }
                }
                Text("대시보드 왼쪽 에이전트를 드래그해 전체 순서를 바꿀 수 있습니다. 첫 번째 에이전트의 작은 로고, 사용률, 리셋까지 남은 시간을 메뉴 막대에 표시합니다.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("60초마다 사용 기록 새로고침", isOn: $store.autoRefresh)
                Text("메뉴 막대 앱이 실행 중일 때 자동으로 갱신합니다.").font(.caption).foregroundStyle(.secondary)
            } header: { Text("일반") }
            Section {
                Toggle("사용량 90% 도달 시 알림", isOn: $store.notificationsEnabled)
                Text("Claude·Codex·Antigravity의 각 한도가 90% 이상이면 한도 기간마다 한 번 알립니다. 앱 실행 중 사용량을 새로고침할 때 확인하며, 오래된 기록은 제외합니다. Gemini는 한도 정보가 없어 알림을 지원하지 않습니다.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text(store.notificationStatus).font(.caption).fixedSize(horizontal: false, vertical: true)
                Button("알림 권한 요청") { Task { await store.updateNotifications(requestPermission: true) } }
                    .disabled(!store.notificationsEnabled)
            } header: { Text("사용량 알림") }
            Section {
                ForEach(Provider.allCases.filter { $0 != .antigravity }) { provider in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label {
                                Text(provider.name)
                            } icon: {
                                ProviderLogo(provider: provider)
                            }.foregroundStyle(provider.tint).font(.headline)
                            Spacer()
                            if let source = store.result.sources.first(where: { $0.provider == provider }) {
                                Text("\(source.fileCount)개 파일 · \(source.eventCount)개 사용 기록").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        HStack {
                            TextField("기록 폴더", text: Binding(get: { store.roots[provider] ?? provider.defaultPath }, set: { store.roots[provider] = $0 }))
                                .textFieldStyle(.roundedBorder).onSubmit { store.savePaths() }
                            Button("선택…") { store.choosePath(for: provider) }
                        }
                        Text(provider == .codex ? "Codex 홈 (.codex): sessions와 archived_sessions를 읽습니다." : provider == .claude ? "Claude 설정 폴더 아래 projects를 선택하세요." : "Gemini tmp 아래 chats/session-*.json과 .jsonl을 읽습니다.")
                            .font(.caption).foregroundStyle(.secondary)
                        if let source = store.result.sources.first(where: { $0.provider == provider }) {
                            if !source.exists { Label("폴더를 찾을 수 없습니다.", systemImage: "folder.badge.questionmark").font(.caption).foregroundStyle(.orange) }
                            ForEach(Array(source.warnings.prefix(3).enumerated()), id: \.offset) { _, warning in Text(warning).font(.caption).foregroundStyle(.orange) }
                            if source.warnings.count > 3 { Text("외 \(source.warnings.count - 3)건").font(.caption).foregroundStyle(.orange) }
                        }
                    }.padding(.vertical, 6)
                }
                HStack {
                    Button("기본 경로 복원") { store.roots = Dictionary(uniqueKeysWithValues: Provider.allCases.map { ($0, $0.defaultPath) }); store.savePaths() }
                    Spacer()
                    Button("경로 저장 및 새로고침") { store.savePaths() }.buttonStyle(.borderedProminent)
                }
            } header: { Text("기록 연결") }
            Section {
                Button("Claude 로그인 접근 허용") {
                    Task { await store.refresh(allowClaudeInteraction: true) }
                }
                .disabled(store.isRefreshing)
                Text("최초 연결 시 이 버튼을 누르고, macOS 키체인 창에서 로그인 키체인 암호를 입력한 뒤 ‘항상 허용’을 선택하세요. ‘허용’은 해당 요청에만 적용됩니다. 자동 새로고침에서는 암호를 묻지 않으며, 접근할 수 없으면 마지막 한도와 안내를 표시합니다.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("새로고침하면 Claude Code의 기존 로그인으로 계정의 5시간·주간 한도와 모델별 주간 한도(예: Fable)를 조회합니다. 인증 정보는 저장하지 않으며 Claude 서버에만 전송합니다. 조회가 안 되면 마지막 수집 기록을 표시합니다.")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                Text("연결하면 Claude settings.json에 수집기를 등록하고 원본을 백업합니다. 기존 statusLine이 있으면 덮어쓰지 않습니다. 앱을 이동한 경우 수집기 경로도 변경해야 합니다.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let error = store.claudeRefreshError { Text(error).font(.caption).foregroundStyle(.orange) }
                Button("Claude 한도 연결") { store.installClaudeBridge() }
                if let message = store.bridgeMessage { Text(message).font(.caption).textSelection(.enabled) }
                if let error = store.bridgeReadError { Text(error).font(.caption).foregroundStyle(.orange) }
            } header: { Text("Claude 구독 한도") }
            Section {
                Label { Text("Antigravity") } icon: { ProviderLogo(provider: .antigravity) }
                    .font(.headline)
                Text("Antigravity를 실행하고 로그인하면 자동으로 연결됩니다. 모델 그룹별 사용률과 리셋 시각을 60초마다 확인하며, 메뉴 막대에는 가장 많이 사용한 그룹을 표시합니다.")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                Text("토큰·세션 집계는 미지원입니다. 조회 실패 시 마지막 한도와 실제 확인 시각을 유지합니다.")
                    .font(.caption).foregroundStyle(.secondary)
                if let error = store.antigravityRefreshError {
                    Text(error).font(.caption).foregroundStyle(.orange)
                } else if store.result.quotas.contains(where: { $0.provider == .antigravity }) {
                    Label("한도 연결됨", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                }
                Button("Antigravity 한도 새로고침") { Task { await store.refresh() } }
                    .disabled(store.isRefreshing)
            } header: { Text("Antigravity 구독 한도") }
            Section {
                Text("Codex 한도는 마지막 로컬 기록 기준이며 15분이 지나면 이전 기록으로 표시합니다. Gemini 구독 한도 연동은 이 버전에서 지원하지 않습니다. 로컬 토큰만으로 한도 사용률을 추정하지 않습니다.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } header: { Text("집계 범위") }
        }.formStyle(.grouped).padding(8).frame(width: 650, height: 770)
            .task { await store.updateNotifications() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                Task { await store.updateNotifications() }
            }
    }
}
