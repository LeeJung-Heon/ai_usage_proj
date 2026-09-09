# Permission Persistence Implementation Plan

> Execute inline in this session. The workspace has no Git repository.

**Goal:** Preserve the app identity across local builds so existing macOS permission decisions can apply to updates.

**Architecture:** Use an existing Apple code-signing identity for both the app and its capture helper. Select the sole valid identity automatically; require an explicit choice when there are none or several. Ad-hoc signing remains an explicit temporary build option. Do not reset system permissions or alter Keychain access lists.

**Tech Stack:** Bash, codesign, macOS Security, Swift 6.

**Spec:** User reports repeated macOS access prompts and requests one-time permission. Exact popup category is pending clarification.

## Evidence

- Installed app has a designated requirement consisting only of its cdhash; rebuilding changes that identity.
- This Mac has one valid Apple Development signing identity.
- Notification code already requests authorization only for notDetermined status.
- Keychain lookup already uses LAContext.interactionNotAllowed.

## Task: Stable signing

**Files:** scripts/build-app.sh, README.md.

- [x] Add AGENTMETER_SIGNING_IDENTITY override and auto-selection of one valid Apple Development / Developer ID Application identity before building.
- [x] Fail clearly for missing/ambiguous identities instead of silently generating a new ad-hoc identity.
- [x] Sign app and helper with the selected identity and retain existing signature verification.
- [x] Document initial migration permission, stable install path, and explicit ad-hoc limitation.
- [x] Build and verify app/helper requirements use stable identifiers and a certificate authority/team instead of cdhash.
- [x] Verify a changed copy signed with the same identity satisfies the prior requirement.
- [x] Restart the running app after packaging.

## Remaining diagnosis

If the popup also occurs during normal refresh without rebuilding, use the user's popup text to locate the responsible access. Do not claim signing resolves an unobserved runtime permission request.

## Verification results

- bash -n scripts/build-app.sh passed; production build completed.
- App and helper now have certificate-based requirements without cdhash.
- A temporary copy with CFBundleVersion changed to 2 was re-signed and passed the original app requirement; deep signature verification passed.
- iCloud reattached FinderInfo after packaging; removed that metadata as the existing packaging script does and re-verified the output signature.
- Restart requested for the packaged app. Exact popup text remains pending; no runtime access behavior was changed without that diagnosis.

## Follow-up: legacy login Keychain prompt confirmed by screenshot

**Goal:** No authentication dialogs during refresh; authorize Claude Keychain access only from an explicit settings button.

**Files:** Sources/AgentMeterCore/KeychainInteraction.swift; Tests/AgentMeterCoreTests/KeychainInteractionTests.swift; Sources/AgentMeter/ClaudeCredentials.swift; Sources/AgentMeter/UsageStore.swift; Sources/AgentMeter/SettingsView.swift; Sources/AgentMeterCore/ClaudeQuotaClient.swift; README.md.

- [x] Test the actual process Keychain interaction flag inside a synchronous operation and after success/error, including an initially disabled flag.
- [x] Implement a main-actor synchronous scope that saves SecKeychainGetUserInteractionAllowed, sets the requested interaction mode, and restores it with defer. Fail before reading credentials if disabling interaction fails.
- [x] Wrap the existing SecItemCopyMatching lookup with that scope and retain LAContext.interactionNotAllowed for automatic refresh.
- [x] Default refresh to no interaction; permit interaction only when the user presses the new settings button. Explain Always Allow and show an actionable error if silent access is denied.
- [x] Run regression tests, build/sign, restart, and verify silent refresh without reading or displaying credentials.

Keep access tokens in memory only. Do not automate password entry, change ACLs, or grant access for the user.

## Keychain follow-up verification

- Regression tests first failed with legacy interaction enabled during silent operations (3 failures), then all 54 tests passed after the scoped switch was implemented.
- Production build and developer certificate signing passed. Legacy Security APIs intentionally produce deprecation warnings: they are required here to control the login Keychain ACL dialog shown in the screenshot.
- Restarted the packaged app and triggered a normal refresh through its UI; refresh completed without a Keychain dialog. Claude returned its separate rate-limit status, so fresh quota data was unavailable.
- Verified the new settings authorization button and Always Allow instructions are present. Did not activate the interactive authorization or enter any password.
