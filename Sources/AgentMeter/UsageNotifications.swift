import Foundation
import UserNotifications
import AgentMeterCore

@MainActor
final class UsageNotifications: NSObject, UNUserNotificationCenterDelegate {
    var enabled = true
    private let monitor = QuotaAlertMonitor()
    private let center: UNUserNotificationCenter?
    private var isChecking = false
    private var status = "알림 권한을 확인하고 있습니다."

    override init() {
        // The notification center requires an application bundle, not a swift run executable.
        center = Bundle.main.bundleURL.pathExtension == "app" ? .current() : nil
        super.init()
        center?.delegate = self
    }

    func check(_ quotas: [QuotaWindow], requestPermission: Bool = false) async -> String {
        guard enabled else { return "사용량 알림이 꺼져 있습니다." }
        guard !isChecking else { return status }
        guard let center else { return "알림은 빌드된 Agent Meter.app에서 사용할 수 있습니다." }
        isChecking = true
        defer { isChecking = false }

        var settings = await center.notificationSettings()
        if requestPermission, settings.authorizationStatus == .notDetermined {
            do {
                _ = try await center.requestAuthorization(options: [.alert, .sound])
                settings = await center.notificationSettings()
            } catch {
                status = "알림 권한 요청에 실패했습니다. 알림 켜기를 다시 시도하세요."
                return status
            }
        }
        guard enabled else { return "사용량 알림이 꺼져 있습니다." }
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            let succeeded = await monitor.check(quotas) { [self] quota in
                guard enabled else { throw CancellationError() }
                let content = UNMutableNotificationContent()
                content.title = "\(quota.provider.name) 사용량 90% 도달"
                content.body = "\(quota.label) 한도의 \(quota.usedPercent.formatted(.number.precision(.fractionLength(0...1))))%를 사용했습니다."
                if let reset = quota.resetsAt {
                    content.body += " 리셋: \(reset.formatted(date: .abbreviated, time: .shortened))"
                }
                content.sound = .default
                let request = UNNotificationRequest(identifier: "quota.\(quota.provider.rawValue).\(quota.id)", content: content, trigger: nil)
                try await center.add(request)
            }
            status = enabled
                ? (succeeded ? "알림이 켜져 있습니다. 사용량 새로고침 시 90% 도달 여부를 확인합니다."
                             : "일부 알림을 보내지 못했습니다. 다음 새로고침 때 다시 시도합니다.")
                : "사용량 알림이 꺼져 있습니다."
        case .denied:
            status = "알림 권한이 꺼져 있습니다. 시스템 설정 → 알림 → Agent Meter에서 허용하세요."
        case .notDetermined:
            status = "알림 권한이 필요합니다. ‘알림 권한 요청’을 눌러 허용하세요."
        @unknown default:
            status = "시스템 설정 → 알림에서 Agent Meter의 권한을 확인하세요."
        }
        return status
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
