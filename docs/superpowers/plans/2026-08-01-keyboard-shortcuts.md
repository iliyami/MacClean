# Keyboard Shortcuts (#9) Implementation Plan

> **For agentic workers:** Use TDD. One feature per PR.

**Goal:** ⌘R scan, ⌘K clean (when results), ⌘1–9 sidebar jump.

**Architecture:** Pure `SidebarItem` digit mapping + `AppState` shortcut nonces. `moduleIsSelected` environment + shared view modifier. Commands in `MacCleanApp`.

**Tech Stack:** Swift 6, SwiftUI, XCTest
