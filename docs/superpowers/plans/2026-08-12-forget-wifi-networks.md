# Forget Saved Wi-Fi (#50) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Protection module to list preferred Wi-Fi networks and forget selected ones via `networksetup` + admin prompt.

**Architecture:** Pure parse/command builders in MacCleanKit; Process/osascript injected in MacClean; SwiftUI list + confirm.

**Tech Stack:** Swift 6, SwiftUI, XCTest, `networksetup`, `MaintenanceShell`

## Global Constraints

- One feature per PR (CONTRIBUTING).
- Business logic in MacCleanKit; I/O in MacClean with injected runners.
- SSIDs never concatenated unquoted into a shell string.
- No telemetry / network.
- `L10n.tr(zh, en, ru)` for new copy.

## Files

| File | Role |
|---|---|
| `Sources/MacCleanKit/PreferredWiFi.swift` | Model, parser, commands |
| `Tests/MacCleanKitTests/PreferredWiFiTests.swift` | Parser + quoting |
| `Sources/MacClean/Modules/WiFi/PreferredWiFiClient.swift` | Process + admin |
| `Sources/MacClean/Views/Protection/WiFiNetworksView.swift` | UI |
| `Sources/MacClean/Views/Sidebar/SidebarView.swift` | New item |
| `Sources/MacClean/App/ContentView.swift` | Route |
| `Tests/MacCleanTests/PreferredWiFiClientTests.swift` | Injected I/O |

## Tasks

- [x] RED/GREEN Kit parser + commands
- [x] RED/GREEN client
- [x] Sidebar + view
- [x] `swift test` (702 passed, 3 skipped, 0 failures)
- [ ] PR
