# Quota Notifications Implementation Plan

> Execute inline in this session with test-first implementation.

**Goal:** 사용률 90% 이상을 처음 확인하면 에이전트·한도별 macOS 알림을 보낸다.

**Architecture:** AgentMeterCore에서 최신 한도를 판정하고 전송 성공 이력을 UserDefaults에 보관한다. 앱의 UserNotifications 어댑터는 권한 요청, 전송, 전경 배너를 담당하며 UsageStore의 새로고침에 연결한다.

**Tech Stack:** Swift 6, Swift Testing, SwiftUI, UserNotifications, macOS 14 이상. 외부 의존성 없음.

**Spec:** 사용자 요청 및 `docs/spec.md`. Gemini 한도는 기존 수집에서 제공되지 않으므로 미지원 사실을 표시한다.

### Task 1: Threshold and delivery state

Files: `Sources/AgentMeterCore/QuotaAlerts.swift`, `Tests/AgentMeterCoreTests/QuotaAlertTests.swift`.

- [x] 임계값 89.9/90/95, 제공사·한도 독립성, 중복 새로고침, 재시작, 주기 리셋, 리셋 미상 시 90% 미만 재관측, 오래된 값·미래 기록 제외, 전송 실패 재시도를 테스트한다.
- [x] `swift test --filter quotaAlert`로 실패를 확인한다.
- [x] `QuotaAlertMonitor.check(_:now:send:)`에서 유효한 최신 윈도우를 선택하고 전송 성공 후 이력을 저장한다. 한도 리셋 전에는 사용률 변동으로 재알림하지 않는다.
- [x] 같은 명령으로 테스트 통과를 확인한다.

### Task 2: Native notifications and settings

Files: `Sources/AgentMeter/UsageNotifications.swift`, `UsageStore.swift`, `SettingsView.swift`, `README.md`.

- [x] UserNotifications 권한을 요청하고 승인된 경우에만 코어 모니터를 호출한다. 전송 실패와 권한 거부 상태를 설정에 표시한다.
- [x] 알림을 기본 활성화하고 켜기·끄기 설정을 저장한다. 앱 전경에서도 배너와 소리를 표시한다.
- [x] 자동/수동 새로고침을 알림 검사에 연결하고 설정에 지원 범위 및 새로고침 조건을 명시한다.
- [x] `swift test` 및 `./scripts/build-app.sh`를 실행하고 `.app` 서명을 확인한다.
- [x] README에 알림 권한, 중복 방지, 리셋 미상 시 재알림 조건, Gemini 제한을 기록한다.

이 디렉터리는 Git 저장소가 아니므로 커밋은 생성하지 않는다.

## Verification

- 전체 Swift Testing 22개 통과(알림 테스트 9개).
- release 빌드 완료. iCloud가 다시 붙인 Finder 메타데이터로 최초 서명이 실패하여 `xattr -cr` 후 재서명했고 `codesign --verify --deep --strict`가 통과했다.
- 업데이트한 앱 실행 및 설정 화면 확인: 알림 토글 켜짐, macOS 알림 권한 승인 상태. 실제 사용량은 임계값 미만이므로 실제 90% 배너 수신은 재현하지 않았다.
