GOAL: Establish trustworthy semantic liveness for isolated Orca-backed Firstmate tasks by replacing the current `unknown`-only Orca path in `bin/fm-backend.sh` with a verified, fail-closed interpretation of `orca worktree ps --json` `agents[]` through `bin/backends/orca.sh`.
Today `bin/fm-crew-state.sh` and `bin/fm-watch.sh` fall back to terminal-tail regexes because Orca reports neither native busy state nor confident agent liveness.
Run the E1 runtime experiment in a disposable Orca worktree first, record exact evidence in `docs/orca-backend.md`, then implement only the mappings that experiment proves.
A tracked Orca task reports semantic `working`/`idle`/`waiting` or conservative `unknown`, and liveness `alive`/`dead`/`unknown`, with unrelated panes and plain shells never false-positive.
Headline: Liveness.

**Read first.**

- `/Users/johncurtis/projects/firstmate/docs/architecture.md` - contracts.
- `/Users/johncurtis/projects/firstmate/docs/orca-backend.md` - verified adapter evidence.
- `/Users/johncurtis/projects/firstmate/CHANGELOG.md` - history.
- `/Users/johncurtis/projects/firstmate/docs/goals/2026-07-12-1238-firstmate-orca-liveness-rider.md` - phases and tests.
- `/Users/johncurtis/projects/firstmate/docs/goals/orca-firstmate-native-integration-audit/notes/T006-final-report.md` - authority model.
- `/Users/johncurtis/projects/firstmate/bin/backends/orca.sh`, `/Users/johncurtis/projects/firstmate/bin/fm-backend.sh`, and `/Users/johncurtis/projects/firstmate/tests/fm-backend-orca.test.sh` - seam.

**Posture.**
Stay on the captain fork and preserve the current isolated-worktree task contract.
No Orca source, settings, hooks, CLI behavior, branch deletion behavior, worktree lineage, terminal-handle recovery, shared-team task kind, secondmates, event-watcher replacement, or status-board mirror changes.
No dependency, schema, GitHub mutation, or `git push`.
Do not treat runtime-global Orca orchestration state as Firstmate state.
If E1 is ambiguous, preserve `unknown`, document the exact missing proof, and stop rather than guessing.

**Liveness contract.**

- A task is matched only through its recorded Orca worktree identity and current endpoint metadata.
- `working`, `idle`, and `waiting` are returned only for a verified matching Orca agent state.
- `alive` is returned only for a verified matching agent session.
- A plain shell, missing agent, unrelated pane, malformed JSON, stale runtime object, or unverified state must be `unknown` or `dead` only where E1 proves it is safe.
- Existing tmux, herdr, zellij, and cmux behavior remains byte-for-byte unchanged.

**Phases.**
Eleven phases in the rider.
Each phase follows: named depth test first, observe it fail, implement the smallest slice, run focused tests plus the required full lanes, make one conventional local commit, and record the phase result.
E1 is actual delivery work with a hypothesis, disposable setup, captured command output, explicit acceptance/refusal rule, and a listed roadmap unlock.

**Verification.**

- `bash tests/fm-backend-orca.test.sh` and any changed focused backend tests exit 0.
- `for script in bin/*.sh bin/backends/*.sh; do bash -n "$script"; done` and `bin/fm-lint.sh` exit 0.
- `for test_script in tests/*.test.sh; do bash "$test_script"; done` exits 0.
- The E1 evidence block names the Orca version/runtime, exact safe commands, observed JSON fields, state mapping, plain-shell result, and the specific P1 unlock or refusal.
- `CHANGELOG.md` records E1, delivered behavior, and deferred-gate status truthfully.
- `git diff --check` is clean, only the rider-approved Firstmate files changed, and no non-Orca backend behavior is altered.

**Stop when** E1 has a durable evidence record, the accepted liveness mapping is implemented and fully verified or its conservative refusal is documented, the architecture doc records the shipped-versus-thin state, and the final local commit exists; otherwise stop after 28 turns and report the unmet gate.
