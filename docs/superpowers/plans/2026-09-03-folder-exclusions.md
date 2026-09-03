# Folder Exclusions (#141) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Settings list of folders that scans hide and SafetyGuard refuses to delete.

**Architecture:** Pure `PathExclusion` + `FolderExclusionPreferences` in Kit; `CleanFilter` + `SafetyGuard` honor the list; Settings UI + coordinator/duplicates wiring in MacClean.

**Tech Stack:** Swift 6, SwiftUI, XCTest, UserDefaults, NSOpenPanel

## Global Constraints

- One feature per PR (CONTRIBUTING).
- Business logic in MacCleanKit; I/O (panel) stays in MacClean.
- Deletion only via SafetyGuard + CleaningEngine.
- No `password` / `secret` / `api_key` / `token` in `Sources/`.
- New strings via `L10n.tr(zh, en, ru)`.
- Do not modify `MCConstants.protectedPaths` system list.

## Files

| File | Role |
|---|---|
| `Sources/MacCleanKit/PathExclusion.swift` | Prefix match + candidate policy |
| `Sources/MacCleanKit/FolderExclusionPreferences.swift` | Persist / normalize list |
| `Sources/MacCleanKit/CleanFilter.swift` | Drop excluded from scan results |
| `Sources/MacCleanKit/SafetyGuard.swift` | Refuse delete of excluded |
| `Sources/MacClean/Views/Settings/SettingsPageView.swift` | UI section |
| `Sources/MacClean/Core/Scanner/ScanCoordinator.swift` | Same filter as modules |
| `Sources/MacClean/Modules/Duplicates/DuplicatesModule.swift` | Display groups honor exclusions |
| `Tests/MacCleanKitTests/PathExclusionTests.swift` | Policy + prefs |
| `Tests/MacCleanKitTests/CleanFilterTests.swift` | Exclusion drop |
| `Tests/MacCleanKitTests/SafetyGuardTests.swift` | userExcluded |
| `Tests/MacCleanTests/FolderExclusionSettingsTests.swift` | Source guards |

## Tasks

- [x] RED/GREEN: PathExclusion + FolderExclusionPreferences
- [x] RED/GREEN: CleanFilter + SafetyGuard
- [x] Wire Settings, ScanCoordinator, Duplicates
- [x] Source guards + full `swift test` + secrets grep (830 passed, 3 skipped, 0 failures)
- [ ] PR Fixes #141
