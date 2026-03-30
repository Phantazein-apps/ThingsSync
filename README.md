# ThingsSync

Native macOS menu bar app for bidirectional **Things 3 ↔ Notion** sync.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/Phantazein-apps/ThingsSync/main/install.sh | bash
```

To install a specific version:

```bash
curl -fsSL https://raw.githubusercontent.com/Phantazein-apps/ThingsSync/main/install.sh | bash -s v0.2.0
```

## What it does

- Syncs your **Things 3 Today** list to a **Notion database** every 60 seconds
- **Bidirectional**: mark a task Done in either app and it syncs to the other
- **Custom Notion statuses preserved**: use "In Progress", "App Projects", or any status you want in Notion — ThingsSync won't overwrite them
- **Conflict resolution**: if both sides change, Things 3 wins
- Tasks removed from Things Today get archived in Notion

## Setup

On first launch, a setup wizard walks you through:

1. **Things 3** — tests the AppleScript connection (grant permission when prompted)
2. **Notion** — OAuth flow opens your browser, you pick a workspace and database
3. Done — syncing starts automatically

No API keys to paste. No database IDs to find.

## Requirements

- macOS 14.0 (Sonoma) or later
- [Things 3](https://culturedcode.com/things/)
- A Notion workspace

## Notion database setup

ThingsSync expects these properties in your Notion database:

| Property | Type | Purpose |
|---|---|---|
| Task | Title | Task name |
| Status | Select | `Open`, `Done`, or any custom status |
| Things ID | Rich text | Links the Notion page to the Things 3 task |
| Notes | Rich text | Task notes |
| Project | Select | Things 3 project name |
| Due Date | Date | Due date |
| Activation Date | Date | When the task was scheduled to Today |

## Architecture

```
┌─────────────────────────────────┐
│  SwiftUI Menu Bar App           │
│  ┌───────────────────────────┐  │
│  │ SyncEngine (Timer)        │  │
│  │  ├─ ThingsReader          │  │  ← AppleScript / JXA
│  │  ├─ NotionClient          │  │  ← URLSession + OAuth
│  │  ├─ DiffResolver          │  │  ← change detection
│  │  └─ StateStore            │  │  ← JSON persistence
│  └───────────────────────────┘  │
│  NotionOAuth                    │  ← OAuth flow
│  Onboarding + Settings UI       │  ← SwiftUI + AppKit
└─────────────────────────────────┘
```

## Building from source

```bash
git clone https://github.com/Phantazein-apps/ThingsSync.git
cd ThingsSync

# Create your Secrets.swift from the template
cp ThingsSync/Services/Secrets.swift.example ThingsSync/Services/Secrets.swift
# Edit Secrets.swift with your Notion OAuth client secret

swift build
.build/debug/ThingsSync
```

## Project structure

```
ThingsSync/
├── Package.swift
└── ThingsSync/
    ├── ThingsSyncApp.swift              # @main, MenuBarExtra
    ├── Info.plist                        # LSUIElement, AppleEvents
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
    │   ├── NotionPropertyBuilder.swift  # Property mapping
    │   ├── KeychainHelper.swift         # Credential storage
    │   └── Secrets.swift                # OAuth secret (gitignored)
    └── Views/
        ├── MenuBarView.swift            # Menu bar dropdown
        ├── SettingsView.swift           # Preferences window
        ├── OnboardingView.swift         # Setup wizard
        └── OnboardingWindowController.swift
```

## License

MIT
