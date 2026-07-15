# Changelog

All notable changes to Firstmate are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses conventional commits for change history.

## [Unreleased]

### Documentation

- 2026-07-14: Completed the Orca `1.4.139` E1b semantic-liveness contract and shipped P1 exact endpoint-to-agent joins.
  `terminal show` now supplies the recorded terminal's joinable `tabId:leafId`, and the adapter selects exactly one matching agent from exactly one recorded `worktree ps` worktree.
  Verified `working` reports busy/alive, turn-complete `done` reports idle/alive, and post-exit agent disappearance in the still-connected writable terminal reports dead.
  Errors, malformed JSON, duplicates, cross-worktree identities, unknown states, and unverified terminal shapes remain unknown with existing fallback behavior intact.
- 2026-07-14: Shipped P2 durable Orca endpoint recovery from the E2 pane-identity contract.
  New Orca tasks record validated `orca_pane_key=` identity, and exact `terminal_handle_stale` failures enumerate only the recorded worktree and adopt only one connected exact pane match before retrying once.
  Zero, duplicate, disconnected, malformed, partially unreadable, legacy-meta, and non-stale cases preserve metadata and fail closed; teardown landing and worktree checks are unchanged.
- 2026-07-12: Recorded the Orca semantic-liveness E1 refusal from disposable Firstmate-created scout `orca-e1-runtime-scout-e1` against Orca `1.4.137`.
  The scout's exact recorded `orca_worktree_id` matched one `worktree ps --json` object, and its agent was directly observed in `working` and `done` states.
  That worktree had two live terminals but only one agent entry, and the JSON exposed no structural relation between Firstmate's recorded `terminal=term_93a44266-...` and the agent's `paneKey`.
  Idle, waiting/permission, and absent-agent/plain-shell behavior were not observed.
  The controlling Firstmate completed guarded scout teardown; the task meta became absent and an exact-path `worktree ps` query returned `[]`.
- 2026-07-12: Recorded the shipped-versus-thin Orca liveness boundary in the architecture documentation and added conservative refusal fixtures without changing production backend behavior.

### Deferred

- Native event-wait supervision and mappings for unobserved Orca agent states remain deferred.
