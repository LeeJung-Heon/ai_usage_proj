import SwiftUI
import OSLog
import AgentMeterCore

private let claudeLog = Logger(subsystem: "local.agentmeter.mac", category: "claude-quota")

@MainActor
final class UsageStore: ObservableObject {
    @Published var result = ScanResult()
    @Published var selection: Provider?
    @Published private(set) var orderedProviders: [Provider]
    @Published var days = 7
    @Published var isRefreshing = false
    @Published var lastRefresh: Date?
    @Published private(set) var menuBarNow = Date()
    @Published var roots: [Provider: String]
    @Published var bridgeMessage: String?
    @Published var bridgeReadError: String?
    @Published private(set) var claudeRefreshError: String?
    @Published private(set) var antigravityRefreshError: String?
    @Published var notificationStatus = "알림 권한을 확인하고 있습니다."
    @Published var notificationsEnabled = UserDefaults.standard.object(forKey: "quotaNotificationsEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(notificationsEnabled, forKey: "quotaNotificationsEnabled")
            notifications.enabled = notificationsEnabled
            Task { await updateNotifications(requestPermission: notificationsEnabled) }
        }
    }
    @Published var autoRefresh = UserDefaults.standard.object(forKey: "autoRefresh") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoRefresh, forKey: "autoRefresh") }
    }
    private let scanner = UsageScanner()
    private let antigravityMonitor = AntigravityQuotaMonitor()
    private let dashboardPreferences = DashboardPreferences()
    private let notifications = UsageNotifications()

    init() {
        orderedProviders = dashboardPreferences.providers
        roots = Dictionary(uniqueKeysWithValues: Provider.allCases.map { ($0, UserDefaults.standard.string(forKey: "path.\($0.rawValue)") ?? $0.defaultPath) })
        notifications.enabled = notificationsEnabled
        Task { [weak self] in
            await self?.refresh()
            await self?.updateNotifications(requestPermission: true)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self else { return }
                self.menuBarNow = Date()
                if self.autoRefresh { await self.refresh() }
            }
        }
    }
    var firstProvider: Provider {
        get { orderedProviders[0] }
        set {
            dashboardPreferences.firstProvider = newValue
            orderedProviders = dashboardPreferences.providers
        }
    }
    func moveProvider(_ provider: Provider, to index: Int) {
        dashboardPreferences.moveProvider(provider, to: index)
        orderedProviders = dashboardPreferences.providers
    }
    var menuBarUsage: MenuBarUsage { MenuBarUsage(provider: firstProvider, quotas: result.quotas, now: menuBarNow) }
    var events: [UsageEvent] { UsageAggregation.filtered(result.events, provider: selection, days: days, now: Date()) }
    var total: Int { events.reduce(0) { $0 + $1.total } }
    var todayTotal: Int { UsageAggregation.filtered(result.events, provider: nil, days: 1, now: Date()).reduce(0) { $0 + $1.total } }
    var daily: [DailyUsage] { UsageAggregation.daily(events, days: days, now: Date()) .filter { selection == nil || $0.provider == selection } }
    var sessionCount: Int { Set(events.map { $0.provider.rawValue + ":" + $0.session }).count }
    var cachePercent: Double {
        let input = events.reduce(0) { $0 + $1.input + $1.cacheRead + $1.cacheWrite }
        return input > 0 ? Double(events.reduce(0) { $0 + $1.cacheRead }) / Double(input) * 100 : 0
    }
    func refresh(allowClaudeInteraction: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        async let antigravityRefresh = antigravityMonitor.refresh()
        var scanned = await scanner.scan(roots: roots)
        bridgeReadError = nil
        let destination = ClaudeBridge.defaultDestination
        if FileManager.default.fileExists(atPath: destination.path) {
            do { scanned.quotas += try JSONDecoder().decode([QuotaWindow].self, from: Data(contentsOf: destination)) }
            catch { bridgeReadError = "Claude 한도 파일을 읽지 못했습니다. Claude Code에서 다음 응답 후 다시 확인하세요." }
        }
        do {
            let token = try ClaudeCredentials.accessToken(allowInteraction: allowClaudeInteraction)
            let quotas = try await ClaudeQuotaClient.fetch(accessToken: token)
            scanned.quotas.removeAll { $0.provider == .claude }
            scanned.quotas += quotas
            claudeRefreshError = nil
            claudeLog.info("Claude 한도 조회 성공: \(quotas.count, privacy: .public)개 창")
        } catch {
            claudeLog.error("Claude 한도 조회 실패: \(String(describing: error), privacy: .public)")
            // Keep the newest known observation, never relabel cached data as fresh.
            let previous = result.quotas.filter { $0.provider == .claude }
            let candidates = scanned.quotas.filter { $0.provider == .claude } + previous
            let latest = Dictionary(grouping: candidates, by: \.id)
                .compactMap { $0.value.max { $0.observedAt < $1.observedAt } }
            scanned.quotas.removeAll { $0.provider == .claude }
            scanned.quotas += latest.sorted { $0.id < $1.id }
            claudeRefreshError = error.localizedDescription
        }
        let antigravity = await antigravityRefresh
        scanned.quotas += antigravity.quotas
        antigravityRefreshError = antigravity.error
        result = scanned
        lastRefresh = Date()
        menuBarNow = lastRefresh ?? Date()
        await updateNotifications()
        isRefreshing = false
    }
    func updateNotifications(requestPermission: Bool = false) async {
        notificationStatus = await notifications.check(result.quotas, requestPermission: requestPermission)
    }
    func savePaths() {
        for provider in Provider.allCases { UserDefaults.standard.set(roots[provider], forKey: "path.\(provider.rawValue)") }
        Task { await refresh() }
    }
    func installClaudeBridge() {
        guard let resources = Bundle.main.resourceURL else { bridgeMessage = "빌드된 .app에서 연결하세요."; return }
        let helper = resources.appendingPathComponent("AgentMeterCapture")
        guard FileManager.default.isExecutableFile(atPath: helper.path) else { bridgeMessage = "수집기를 찾을 수 없습니다. scripts/build-app.sh로 앱을 빌드하세요."; return }
        let projectRoot = URL(fileURLWithPath: ((roots[.claude] ?? Provider.claude.defaultPath) as NSString).expandingTildeInPath)
        do {
            try ClaudeBridge.install(settings: projectRoot.deletingLastPathComponent().appendingPathComponent("settings.json"), executable: helper, destination: ClaudeBridge.defaultDestination)
            bridgeMessage = "연결했습니다. Claude Code를 다시 시작하고 응답을 한 번 받으면 한도가 표시됩니다."
        } catch { bridgeMessage = error.localizedDescription }
    }
    func choosePath(for provider: Provider) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.message = provider == .codex ? "sessions 폴더가 들어 있는 Codex 홈을 선택하세요." : "\(provider.name) 사용 기록 폴더를 선택하세요."
        panel.directoryURL = URL(fileURLWithPath: roots[provider] ?? provider.defaultPath)
        if panel.runModal() == .OK, let url = panel.url { roots[provider] = url.path; savePaths() }
    }
}

extension Provider {
    var tint: Color {
        switch self { case .claude: Color(red: 0.76, green: 0.39, blue: 0.26); case .codex: Color(red: 0.12, green: 0.52, blue: 0.43); case .gemini: Color(red: 0.34, green: 0.44, blue: 0.80); case .antigravity: Color(red: 0.30, green: 0.48, blue: 0.90) }
    }
}
func compact(_ value: Int) -> String {
    if value >= 1_000_000 { return String(format: "%.2fM", Double(value) / 1_000_000) }
    if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
    return value.formatted()
}
