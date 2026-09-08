# Claude Refresh and Menu Bar Implementation Plan

> **For agentic workers:** Execute inline in this session, task by task.

**Goal:** Fetch current Claude quota on refresh and present a more spacious menu bar with circular icons and no reset glyph.

**Architecture:** Add a quota client to AgentMeterCore with injectable credentials and HTTP transport. The app reads existing Claude credentials from Keychain without opening authorization prompts and sends them only to Claude's usage endpoint. Keep the statusLine file as a fallback; never change its observation time during a reread.

**Tech Stack:** Swift 6, Foundation URLSession, Security, SwiftUI/AppKit; macOS 14.

**Spec:** User request in this session; docs/spec.md for the existing app.

## Global Constraints

- No model requests, token estimates, credential storage, or conversation transmission.
- Preserve truthful timestamps and expose fetch failures.
- Existing local token scanning remains unchanged.

### Task 1: Live Claude quota

Files: create Sources/AgentMeterCore/ClaudeQuotaClient.swift and Tests/AgentMeterCoreTests/ClaudeQuotaClientTests.swift; modify Sources/AgentMeter/UsageStore.swift; create Sources/AgentMeter/ClaudeCredentials.swift.

- [x] Test a new HTTP response replacing 17:11 values, percent/reset parsing, empty quota, malformed responses and HTTP errors.
- [x] Run `swift test --filter ClaudeQuota` and observe failure before implementation.
- [x] Implement `ClaudeQuotaClient.fetch(accessToken:now:transport:) async throws -> [QuotaWindow]` with a 15-second timeout, fixed endpoint and sanitized errors.
- [x] Refresh with existing Claude Keychain credentials; retain local observations if unavailable and report the reason.
- [x] Run focused tests and check a live quota response without printing credentials.

### Task 2: Menu appearance and verification

Files: Sources/AgentMeterCore/MenuBarUsage.swift, Sources/AgentMeter/ProviderLogo.swift, Sources/AgentMeter/AgentMeterApp.swift, Sources/AgentMeter/MenuSummary.swift, Sources/AgentMeter/SettingsView.swift, README.md.

- [x] Update existing title expectations from `42% ↻2h 15m` to `42%  2h 15m`; run focused tests.
- [x] Remove reset glyph, add image/text spacing in the native status item image, draw circular menu bar logos, clip provider logos to circles and increase panel padding/gaps.
- [x] Document live fetch, fallback, and timestamps in UI and README.
- [x] Run `swift test`, `./scripts/build-app.sh`, restart the existing app and inspect the actual menu and current quota.

## Verification result

- 38 tests passed; release app built and code signature verified after removing iCloud FinderInfo metadata.
- A live authenticated usage request returned HTTP 200 with updated 5-hour and weekly percentages; no credentials were printed or persisted.
- Restarted the packaged app and confirmed its process is running.
- Rendered the actual menu icon and title components to `dist/menu-bar-updated.png` and inspected the result.
- Full on-screen UI verification remains unavailable: computer-use returned `cgWindowNotFound` for multiple apps and then timed out. The preview is a component rendering with sample values, not a desktop screenshot.
