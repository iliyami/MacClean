# Forget saved Wi-Fi networks (#50)

Date: 2026-08-12
Status: Design (approved for implementation)

## Problem

Saved preferred Wi-Fi networks persist SSIDs the Mac has joined. That is a
tracking surface. Issue #50 asks to list them and remove selected ones via
`networksetup -removepreferredwirelessnetwork` (admin).

## Goal

A Protection sidebar module **Saved Wi-Fi**: enumerate preferred networks on
Wi-Fi hardware ports, multi-select, confirm, remove with the standard macOS
admin password prompt. Listing is unprivileged; removal is privileged.

## Non-goals

- No current-network / signal / password display.
- No forgetting of the network the user is on as a special case (same CLI).
- No Smart Scan inclusion.
- No `Localizable.strings` migration; `L10n.tr` only.
- Do not add a persistent privileged helper; reuse osascript `do shell script
  … with administrator privileges` like Maintenance.

## Approach

Pure Kit:

- Parse `networksetup -listallhardwareports` → Wi-Fi `Device` names (`en0`, …).
- Parse `networksetup -listpreferredwirelessnetworks <device>` → SSIDs.
- Build argv / quoted shell lines. Reject device names that are not
  `[A-Za-z][A-Za-z0-9]*` so a bad parse cannot reach the shell. SSIDs (any
  Unicode, quotes, metacharacters) are passed as argv and quoted with
  `MaintenanceShell.quote` for the admin script.

MacClean:

- `PreferredWiFiClient` injects `Process` (list) and osascript (remove batch).
- One admin prompt per Forget action: quoted commands joined with ` ; `.
- `WiFiNetworksView` under Protection; deep link `wifi-networks`.

⌘1–⌘9: new item sits after Privacy, so digits 7–9 shift by one. Documented.

## Testing

Parser fixtures (English `networksetup` output, empty list, non-Wi-Fi device
message). Command-builder adversarial SSIDs and illegal devices. Client tests
with injected runners (no live `networksetup` in CI).
