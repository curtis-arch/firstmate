# Changelog

All notable changes to Firstmate are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses conventional commits for change history.

## [Unreleased]

### Documentation

- 2026-07-12: Recorded the Orca semantic-liveness E1 refusal from disposable Firstmate-created scout `orca-e1-runtime-scout-e1` against Orca `1.4.137`.
  The scout's exact recorded `orca_worktree_id` matched one `worktree ps --json` object, and its agent was directly observed in `working` and `done` states.
  That worktree had two live terminals but only one agent entry, and the JSON exposed no structural relation between Firstmate's recorded `terminal=term_93a44266-...` and the agent's `paneKey`.
  Idle, waiting/permission, and absent-agent/plain-shell behavior were not observed.
  The controlling Firstmate completed guarded scout teardown; the task meta became absent and an exact-path `worktree ps` query returned `[]`.
- 2026-07-12: Recorded the shipped-versus-thin Orca liveness boundary in the architecture documentation and added conservative refusal fixtures without changing production backend behavior.

### Deferred

- P1 semantic Orca busy/liveness mapping remains blocked and production retains conservative `unknown` results.
- E1 must be rerun with a proven endpoint-to-agent identity relation and direct idle plus no-agent/plain-shell observations before E2/P2 durable endpoint re-resolution becomes eligible.
