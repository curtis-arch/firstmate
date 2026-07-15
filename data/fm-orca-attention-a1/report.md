# Orca attention-state supervision

- Commit: `e2391db`
- Contract: preserve exact terminal → exact worktree → exact pane identity joins and fail-closed unknown/duplicate/cross-worktree behavior; map Orca `waiting` and `blocked` to alive attention states, with `waiting`/`blocked` detail threaded through backend, crew-state, watcher, and daemon abstractions. Non-Orca backends remain unchanged. The mapping is evidence-limited to the observed Orca agent states and exact `paneKey` match.
- Files: `bin/backends/orca.sh`, `bin/fm-backend.sh`, `bin/fm-crew-state.sh`, `bin/fm-supervise-daemon.sh`, `bin/fm-wake-lib.sh`, `bin/fm-watch.sh`, `docs/orca-backend.md`, and focused backend/state/daemon/watcher tests.
- Tests: `tests/fm-backend-orca.test.sh`, `tests/fm-crew-state.test.sh`, `tests/fm-watch-triage.test.sh`, `tests/fm-daemon.test.sh` all pass; changed scripts pass `bash -n` except direct `bash -n bin/fm-watch.sh`, which the protected-watcher hook rejects before execution; `git diff --check` passes.
