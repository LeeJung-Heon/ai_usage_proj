# Agent Meter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Build a runnable native macOS usage monitor for Claude, Codex, and Gemini.

**Architecture:** A pure Swift core parses local provider records into deduplicated usage events and quota snapshots. A SwiftUI desktop/menu bar app shares a background-loaded store; a small capture executable accepts Claude statusLine input and persists only quota metadata.

**Tech Stack:** Swift 6, SwiftUI, Charts, Foundation, Swift Testing; macOS 14+.

**Spec:** `docs/spec.md`

## Global Constraints

- macOS 14 이상, 외부 패키지 의존성 없음.
- Claude Code, Codex, Gemini CLI만 지원.
- 대화 내용/인증 토큰은 저장하거나 전송하지 않는다.
- 실제 사용량과 확인할 수 없는 한도를 구분한다.

---

### Task 1: Normalize usage and quota records

**Files:** `Package.swift`, `Sources/AgentMeterCore/Models.swift`, `Sources/AgentMeterCore/Parsers.swift`, `Tests/AgentMeterCoreTests/ParserTests.swift`.

**Interfaces:** `UsageParser.parse(data:provider:source:) -> ParsedUsage`; `UsageEvent` contains provider, session, model, date, input, output, cacheRead, cacheWrite. Input excludes cacheRead; total is input + output + cacheRead + cacheWrite. `QuotaWindow` exposes observation and reset timestamps.

- [x] Write tests with synthetic provider records: Claude repeated message IDs yield one event; Codex cumulative 120 → 180 → 180 yields 180 total; Gemini cached input is not double counted; malformed trailing JSONL does not discard valid earlier records.
- [x] Run `swift test`, confirm missing parsing behavior fails.
- [x] Parse only usage metadata, normalize provider-specific token semantics, retain latest duplicate response, and calculate Codex cumulative deltas.
- [x] Run `swift test`, confirm hand-calculated totals and quota freshness pass.

### Task 2: Collect files and capture Claude quota

**Files:** `Sources/AgentMeterCore/UsageScanner.swift`, `Sources/AgentMeterCore/ClaudeBridge.swift`, `Sources/AgentMeterCapture/main.swift`, `Tests/AgentMeterCoreTests/ScannerTests.swift`.

**Interfaces:** `UsageScanner.scan(roots:) -> ScanResult`; `ClaudeBridge.capture(data:destination:) throws`; scanner caches parsed usage by file size and modification time.

- [x] Write temporary-directory tests for recursive discovery, missing directories, updated/deleted files, duplicate sessions, and sanitized quota capture.
- [x] Run `swift test` to observe missing behavior.
- [x] Implement allowed file discovery and error reporting; keep all parsing off main actor. Implement atomic sanitized capture and conflict-safe statusLine setup with backup.
- [x] Run `swift test` and feed synthetic stdin to `AgentMeterCapture`; verify only quota metadata is saved.

### Task 3: Native dashboard and distributable app

**Files:** `Sources/AgentMeter/AgentMeterApp.swift`, `Sources/AgentMeter/UsageStore.swift`, `Sources/AgentMeter/DashboardView.swift`, `Sources/AgentMeter/SettingsView.swift`, `scripts/build-app.sh`, `README.md`.

**Interfaces:** `UsageStore` owns selected provider/range and published scan results. Views consume filtered events; menu bar and dashboard share the store.

- [x] Add aggregation tests: local-day date boundary, range/provider filtering, zero-filled daily buckets.
- [x] Run tests, implement aggregation, then verify.
- [x] Build SwiftUI sidebar, cards, chart, model table, quota states, menu bar summary, connection settings and auto refresh.
- [x] Package with `swift build -c release`, generate bundle Info.plist, ad-hoc sign both executables and app.
- [x] Open actual app, inspect window and interactions, fix observed layout issues, run final tests, document supported data sources and limitations.

Execution: continue inline under the already-authorized implementation request. No repository exists yet; do not create commits without a user request.
