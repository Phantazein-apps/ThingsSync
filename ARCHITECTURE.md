# ARCHITECTURE.md — Technical Specification

> This file defines the *how* of the project.
> Read after VECTOR.md and CLAUDE.md.

## System Overview

ThingsSync is a native macOS menu bar application that provides bidirectional sync between Things 3's Today list and a Notion database. It polls Things 3 via AppleScript/JXA every 60 seconds, diffs against the last known state, and pushes changes to Notion via REST API (and vice versa).

## Stack

| Layer | Technology | Why |
|-------|-----------|-----|
| **Runtime** | Swift 5.9 | Native macOS performance, AppleScript bridge |
| **Framework** | SwiftUI + AppKit | Menu bar via MenuBarExtra, AppKit for OAuth window |
| **Data** | JSON file persistence | Simple state snapshots, no database needed |
| **Auth** | OAuth 2.0 + Keychain | Zero-config Notion auth, secure credential storage |
| **Build** | Swift Package Manager | No Xcode project dependency |
| **Deploy** | GitHub Releases (.zip) | curl-based install script |

## Layer Architecture

```
┌─────────────────────────────────────┐
│  Presentation                       │  ← MenuBarView, SettingsView, OnboardingView
├─────────────────────────────────────┤
│  Application                        │  ← SyncEngine (timer + orchestration)
├─────────────────────────────────────┤
│  Domain                             │  ← ThingsItem, NotionPage, SyncState, DiffResolver
├─────────────────────────────────────┤
│  Infrastructure                     │  ← ThingsReader, NotionClient, NotionOAuth, KeychainHelper
└─────────────────────────────────────┘
```

### Rules
- Dependencies point **downward only**
- Each layer imports only from the layer directly below
- No circular dependencies

## Directory Structure

```
ThingsSync/
├── Package.swift
├── VECTOR.md
├── CLAUDE.md
├── ARCHITECTURE.md
├── README.md
├── install.sh
├── vector/
│   ├── research/
│   ├── schemas/
│   └── decisions/
└── ThingsSync/
    ├── ThingsSyncApp.swift              # @main, MenuBarExtra
    ├── Info.plist                        # LSUIElement, AppleEvents
    ├── Assets.xcassets/                  # App icons
    ├── Models/
    │   ├── ThingsItem.swift             # Things 3 to-do model
    │   ├── NotionPage.swift             # Notion page model
    │   └── SyncState.swift              # Snapshot for diff detection
    ├── Services/
    │   ├── ThingsReader.swift           # JXA/AppleScript bridge
    │   ├── NotionClient.swift           # Notion REST API
    │   ├── NotionOAuth.swift            # OAuth flow + local HTTP server
    │   ├── SyncEngine.swift             # Orchestrator + timer
    │   ├── DiffResolver.swift           # Change detection + actions
    │   ├── NotionPropertyBuilder.swift  # Property mapping helpers
    │   ├── KeychainHelper.swift         # Credential storage
    │   └── Secrets.swift                # OAuth secret (gitignored)
    └── Views/
        ├── MenuBarView.swift            # Menu bar dropdown UI
        ├── SettingsView.swift           # Preferences window
        ├── OnboardingView.swift         # Setup wizard
        └── OnboardingWindowController.swift
```

## Data Models

### ThingsItem
```
{
  id: String              // Things 3 internal ID
  title: String           // Task name
  notes: String?          // Task notes
  project: String?        // Things 3 project name
  dueDate: Date?          // Due date
  activationDate: Date?   // When scheduled to Today
  status: .open | .done   // Completion status
}
```

### NotionPage
```
{
  id: String              // Notion page ID
  thingsId: String?       // Linked Things 3 ID
  title: String           // Task property (title)
  status: String          // Select: Open, Done, or custom
  notes: String?          // Rich text
  project: String?        // Select
  dueDate: Date?          // Date property
  activationDate: Date?   // Date property
}
```

### SyncState
```
{
  lastSync: Date
  thingsSnapshot: [ThingsItem]   // Last known Things state
  notionSnapshot: [NotionPage]   // Last known Notion state
}
```

See `vector/schemas/` for complete data models.

## Sync Algorithm

```
Every 60 seconds:
  1. Read current Things 3 Today list (AppleScript)
  2. Read current Notion database pages (REST API)
  3. Diff both against last SyncState snapshot
  4. Resolve conflicts (Things wins)
  5. Push changes:
     - New in Things → Create in Notion
     - Done in Things → Mark Done in Notion
     - Done in Notion → Mark Done in Things (AppleScript)
     - Removed from Today → Archive in Notion
  6. Save new SyncState snapshot
```

## Key Patterns

### Snapshot-based diffing
Instead of tracking individual events, we snapshot the full state on each cycle and diff against the previous snapshot. Simple, debuggable, and resilient to missed events.

### Things-wins conflict resolution
If both sides changed since last sync, the Things 3 state takes precedence. This is a deliberate UX choice — users expect their primary task manager to be authoritative.

### Custom status preservation
Notion statuses beyond "Open" and "Done" (e.g., "In Progress", "App Projects") are preserved — ThingsSync only writes status when it detects a completion state change.

### OAuth with local HTTP server
`NotionOAuth` spins up a temporary local HTTP server on a random port to receive the OAuth callback. No redirect URI configuration needed beyond localhost.

## Build & Run

```bash
# Development
swift build
.build/debug/ThingsSync

# Release build
swift build -c release

# Install (downloads latest release)
curl -fsSL https://raw.githubusercontent.com/Phantazein-apps/ThingsSync/main/install.sh | bash
```

## Quality Gates

### Pre-commit
- [ ] `swift build` succeeds
- [ ] No force-unwraps outside of tests
- [ ] Secrets.swift is gitignored

### Pre-release
- [ ] Build produces working .app bundle
- [ ] Version bumped in code
- [ ] GitHub Release created with .zip artifact
- [ ] install.sh points to correct release tag

## Known Constraints

- Things 3 has no official API — AppleScript/JXA is the only bridge, and it requires Accessibility permissions
- Notion API rate limit: 3 requests/second — sync must batch efficiently
- Menu bar apps can't easily show modal dialogs — onboarding uses a separate AppKit window
- OAuth callback requires localhost — won't work if port is blocked

## Future Considerations

- Sync tags/labels between Things 3 and Notion
- Support for recurring tasks
- Auto-create Notion database during onboarding
- Notion webhook support (when available) to replace polling
- Multiple database support

---

*Reading order: VECTOR.md → CLAUDE.md → ARCHITECTURE.md*
