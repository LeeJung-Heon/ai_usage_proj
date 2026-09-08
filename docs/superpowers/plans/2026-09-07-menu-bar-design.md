# Menu Bar Design Implementation Plan

> **For agentic workers:** Execute this focused visual change inline, checking the built macOS app after implementation.

**Goal:** Make Agent Meter a compact, readable menu bar usage panel.

**Architecture:** Keep the existing MenuBarExtra and UsageStore. Move its presentation into MenuSummary.swift, reuse QuotaRow, and use the current provider colors. The dashboard remains available from the panel.

**Tech Stack:** SwiftUI, macOS 14+, Swift Package Manager.

**Spec:** docs/spec.md and the user's request for a menu bar design.

## Global Constraints

- macOS 14 이상. 외부 패키지 의존성 없음.
- Korean labels; local records only; stale quota timestamps remain visible.
- Do not change usage parsing, stored settings, or provider connections.

### Task 1: Compact menu panel

**Files:** Sources/AgentMeter/AgentMeterApp.swift; Sources/AgentMeter/MenuSummary.swift.

- [x] Replace the existing inline MenuSummary with a 360pt panel in its own file.
- [x] Present today's total, provider distribution, and active sessions in a tinted summary card.
- [x] Present each provider's token count and existing QuotaRow in compact cards; explain unavailable quota data.
- [x] Add refresh, settings, dashboard, and quit actions with accessible labels and hover feedback.
- [x] Keep the menu bar label short and monochrome using `Label(compact(store.todayTotal), systemImage: "chart.bar.fill")`.

### Task 2: Verify and package

**Files:** README.md; dist/Agent Meter.app.

- [x] Run `swift test` and `./scripts/build-app.sh`.
- [x] Launch the packaged app and render the actual MenuSummary in an AppKit hosting view in both color schemes.
- [ ] Direct menu bar click and action smoke test: the computer-control surface only exposed the dashboard and reopened it when closed; popup interaction remains unverified.
- [x] Document the new menu presentation in README.md.

This is a reversible presentation change. Verify layout visually and run existing regression tests; no tests that mirror view construction. This workspace has no Git repository, so do not create commits.

## Verification

- Existing Swift Testing suite: 13 passed.
- Final release build and ad-hoc signature verification passed.
- Dark/light native renders saved as `dist/menu-bar-dark.png` and `dist/menu-bar-light.png`; reduced spacing after inspecting the first render so all three default provider cards fit. Additional quota rows remain scrollable.
