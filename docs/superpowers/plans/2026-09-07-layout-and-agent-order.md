# Layout and Agent Order Implementation Plan

> **For agentic workers:** Execute inline in this session, verifying core behavior before packaging and visually reviewing the app.

**Goal:** Use a small logo without the provider name in the menu bar, refresh the panel and dashboard design, and persist drag-reordered sidebar agents.

**Architecture:** DashboardPreferences owns a normalized complete provider order and migrates the existing first-provider preference. UsageStore publishes that order for every surface. SwiftUI uses a local DragGesture with transient drag state and commits order on a valid release; presentation shares card styling.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Swift Testing, macOS 14+.

**Spec:** docs/spec.md and the user's September 7 request for smaller logos, no menu bar name, a styled layout, and sidebar drag ordering.

## Global Constraints

- macOS 14 이상. 외부 패키지 의존성 없음.
- Korean UI, system light/dark appearance, existing stale/missing quota information retained.
- Preserve saved first-agent choices; save all three positions and keep menu bar, dashboard, and summary in sync.
- No Git repository is present; do not create commits.

### Task 1: Persist full order and compact menu text

**Files:** Sources/AgentMeterCore/DashboardPreferences.swift; Sources/AgentMeterCore/MenuBarUsage.swift; Tests/AgentMeterCoreTests/DashboardPreferencesTests.swift; Tests/AgentMeterCoreTests/MenuBarUsageTests.swift.

**Interfaces:** `providers: [Provider]` becomes writable; `moveProvider(_:to:)` accepts a final zero-based index; `firstProvider` promotes without resetting remaining positions. MenuBarUsage.title omits provider names.

- [x] Add tests for every move direction, second/third-only changes, invalid indices, normalization, persistence and migration. Example: `[.claude, .codex, .gemini]` moved from Gemini to index 1 must restore as `[.claude, .gemini, .codex]`.
- [x] Update menu expectations to `42% ↻2h 15m`, retaining missing/stale/reset boundary cases; run `swift test` and confirm missing behavior fails.
- [x] Implement normalized storage using `dashboardProviderOrder`; fall back to `dashboardFirstProvider` only when no order exists. Remove the provider-name prefix from menu text. Run `swift test`.

### Task 2: Wire drag ordering and refresh presentation

**Files:** Sources/AgentMeter/UsageStore.swift; Sources/AgentMeter/AgentMeterApp.swift; Sources/AgentMeter/ProviderLogo.swift; Sources/AgentMeter/AgentSidebarRow.swift; Sources/AgentMeter/DesignSystem.swift; Sources/AgentMeter/DashboardView.swift; Sources/AgentMeter/MenuSummary.swift; Sources/AgentMeter/SettingsView.swift.

**Interfaces:** UsageStore publishes `orderedProviders`, computes `firstProvider`, and exposes `moveProvider(_:to:)`; AgentSidebarList computes a bounded destination from the pointer location; AgentSidebarRow provides selection and accessible move actions.

- [x] Publish full order after each persisted move; selection stays separate. Use a local DragGesture with a moving row and destination highlight and accessible move-up/down actions; commit order only on drop.
- [x] Resize the menu NSImage itself to 15pt, use it with the compact title, and preserve the provider name in tooltip/accessibility text.
- [x] Apply a shared 16pt card radius, subtle borders, teal accents, clear section hierarchy and compact logo sizing to dashboard and panel; remove the panel's app-name heading.
- [x] Run `swift build`; inspect actual native renders in light/dark appearance and the live dashboard, then correct layout issues.

### Task 3: Verify and deliver

**Files:** README.md; dist/Agent Meter.app; dist visual QA images.

- [x] Update README to explain drag ordering and the new menu bar appearance.
- [x] Run `swift test` and `./scripts/build-app.sh`; check signing and launch the resulting app.
- [x] Verify moves to first/last and between lower rows, cancellation, selection and persistence; record any live-UI verification limitation explicitly.


## Verification results

- Swift Testing: 34 tests passed, including all nine source/destination combinations, invalid positions, saved full order, duplicate/unknown identifiers, and legacy migration.
- Release build and deep/strict signature verification passed. Packaging now signs in a temporary directory outside iCloud and retries clearing FinderInfo after copying; this resolved a reproduced File Provider signing failure.
- Live UI: dragged Gemini from third to second and then first. Sidebar and dashboard ordering updated, the first-agent indicator changed, and Gemini selection remained selected across reordering. Quit/relaunch restored the complete Gemini/Claude/Codex order.
- Accessible move-down actions verified and used to restore the original Claude/Codex/Gemini order after testing.
- Actual SwiftUI/AppKit renders reviewed in light/dark at 360×690 for the panel, 1200×1000 for the dashboard, and the 1040×730 minimum window size. Provider card heights align; compact quota rows retain last-observed timestamps and stale indicators. Images are in dist/.
- Live external-drop cancellation and status-item popup clicks remain unverified: the computer-control capture returned noWindowsAvailable/SCStreamError during later drag attempts and exposes the dashboard rather than status items. The local gesture checks all four list bounds before committing and automatically clears its transient state on completion/cancellation.
