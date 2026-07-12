# Changelog

All notable changes to Firstmate are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses conventional commits for change history.

## [Unreleased]

### Documentation

- 2026-07-12: Recorded the Orca semantic-liveness E1 refusal.
  The required disposable Firstmate-created Orca scout was not executed because the delegated brief prohibited `bin/fm-spawn.sh`, `bin/fm-teardown.sh`, and fleet operations.
  A read-only diagnostic against Orca `1.4.137` matched the ship task's exact `orca_worktree_id`, but the result exposed two live terminals and only a `paneKey` for its one working agent, with no relation to Firstmate's recorded `terminal=term_...` handle.
  Working-to-idle transition, clean exit, and plain-shell/no-agent behavior were not observed in an accepted E1 experiment.
  No scout cleanup ran because no scout was created.
- 2026-07-12: Recorded the shipped-versus-thin Orca liveness boundary in the architecture documentation and added conservative refusal fixtures without changing production backend behavior.

### Deferred

- P1 semantic Orca busy/liveness mapping remains blocked and production retains conservative `unknown` results.
- E1 must be rerun with explicit authority for a disposable scout and guarded teardown before E2/P2 durable endpoint re-resolution becomes eligible.
