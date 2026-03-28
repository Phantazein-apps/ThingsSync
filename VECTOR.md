# VECTOR.md — Project Doctrine

> This file defines the *why* and *what* of this project.
> Claude reads this first at every session start.

## Project

- **Name:** ThingsSync
- **Stage:** development
- **Owner:** Phantazein
- **Repository:** github.com/Phantazein-apps/ThingsSync

## Problem Statement

Things 3 is the best personal task manager on macOS, but it has no native integration with Notion — where many users manage projects, notes, and team context. Users who live in both apps must manually copy tasks between them, leading to stale data and missed deadlines.

## Audience

- **Primary:** macOS power users who use both Things 3 and Notion daily
- **Secondary:** Small teams where one member manages personal tasks in Things 3 but shares status via Notion

## Value Proposition

Bidirectional, zero-config sync between Things 3 Today and a Notion database — install it and forget it.

## Non-Goals

- [ ] Syncing all Things 3 areas/projects (only Today list)
- [ ] Supporting other task managers (Todoist, OmniFocus, etc.)
- [ ] iOS/iPadOS companion app
- [ ] Replacing Notion as a project management tool

## Success Metrics

| Metric | Target | How Measured |
|--------|--------|--------------|
| Sync latency | < 60s end-to-end | Timer interval + API round-trip |
| Conflict resolution accuracy | 100% (Things wins) | Integration tests |
| Setup completion rate | > 90% | Onboarding funnel analytics |
| Crash-free sessions | > 99.5% | macOS crash reports |

## Principles

Project-specific principles that override defaults:

1. **Invisible when working** — menu bar only, no dock icon, no windows unless needed
2. **Things 3 is source of truth** — on conflict, Things wins; never lose a user's task
3. **OAuth-only auth** — no API keys to paste, no database IDs to find
4. **Offline-resilient** — queue changes when network is down, sync when it's back

## Research Pointers

- `vector/research/` — User interviews, JTBD analysis, persona documents
- `vector/schemas/` — Data models, API specs
- `vector/decisions/` — Architecture Decision Records (ADRs)

## Open Questions

- [ ] Should we sync tags/labels between Things 3 and Notion?
- [ ] Support for recurring tasks?
- [ ] Notion database auto-creation during onboarding?

---

*Reading order: VECTOR.md → CLAUDE.md → ARCHITECTURE.md*
