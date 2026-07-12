# Firstmate - Orca liveness rider

This rider holds the prescriptive constraints for the goal at `/Users/johncurtis/projects/firstmate/docs/goals/2026-07-12-1238-firstmate-orca-liveness-goal.md`.
It supersedes nothing in prior riders.
The completed Orca-native integration audit at `/Users/johncurtis/projects/firstmate/docs/goals/orca-firstmate-native-integration-audit/notes/T006-final-report.md` remains the architecture authority.
This rider turns only E1 and roadmap P1 into bounded work.

All paths are absolute.
Source: `/Users/johncurtis/projects/firstmate`.
Runtime under observation: local Orca CLI and its existing running runtime.

## Posture (decided - do not redesign)

- Mature behavior stays experimental and explicit-only for `backend=orca`.
- Preserve one normal Firstmate task to one isolated worktree to one endpoint.
- Do not change Orca source, runtime configuration, managed hooks, branch deletion semantics, or the Orca CLI contract.
- Do not add a shared-team task kind, pane-key persistence, terminal-handle recovery, Orca secondmates, lineage, event waits, hibernation recovery, comments, workspace-status mirrors, or external-worktree import.
- Do not modify `AGENTS.md`, dispatch profiles, project data, user config, or fleet state as part of implementation.
- Do not add dependencies, write a new persistent schema, change `state/<id>.meta`, force-push, push, merge, or open a PR.
- If E1 cannot prove a mapping, retain the existing conservative `unknown` behavior and write the evidence/refusal rather than inferring semantics.

`CHANGELOG.md` is the canonical captain-facing record for this round's experiment state and delivered behavior.
P11 updates it with the actual E1 result and P1 behavior, while future experiments remain explicitly deferred.

## Data model (files, not fields)

No durable data model changes are allowed.

Existing inputs only:

- `state/<id>.meta` supplies `backend=orca`, `orca_worktree_id=`, `terminal=`, and `worktree=`.
- `orca worktree ps --json` supplies runtime observation only.
- `docs/orca-backend.md` is the sole durable evidence owner for the E1 command transcript and conclusion.

No new meta key, cache, ledger file, database entry, or configuration knob belongs in this round.

## Liveness algorithm and experiment contract

### Semantic contract

`fm_backend_orca_agent_snapshot <terminal> <worktree-id>` is the proposed internal adapter primitive.
It must run a read-only `orca worktree ps --json` query and return a normalized record only after strict JSON validation.

Pseudocode:

```text
read result.worktrees[]
select exactly one worktree whose durable id equals recorded orca_worktree_id
if no exact worktree or malformed/ok:false JSON: unknown
read agents[] only from that worktree
select the matching agent only if E1 proves a stable relation to the recorded terminal
if no unique verified matching agent:
  return no-agent, not a guessed unrelated agent
map only E1-observed values:
  working -> busy / alive
  idle -> idle / alive
  waiting -> idle-or-unknown only as E1 proves
  exited/no-agent/plain-shell -> dead-or-unknown only as E1 proves
  anything else -> unknown
```

The adapter must never choose the first agent in a worktree.
It must never treat a worktree with a live terminal but no verified agent as agent-alive.
It must never turn failed JSON inspection into `dead`.

### E1 - actual runtime experiment

| Item | Contract |
|---|---|
| Question | Can `orca worktree ps --json` accurately and uniquely identify a Firstmate-created Orca task's agent state and liveness without relying on terminal text? |
| Why | P1 is the prerequisite for trusted Orca supervision and later recovery work. |
| Disposable setup | Spawn one scratch Orca-backed scout through `bin/fm-spawn.sh`; use no existing captain task, shared worktree, secondmate, or project with unlanded work. |
| States to observe | working, idle, waiting/permission if safely reproducible, clean agent exit, and a plain shell or no-agent terminal. |
| Exact evidence | Orca CLI version/status, command lines, redacted `worktree ps --json` fragments, recorded Firstmate metadata, observed state transitions, timestamp, and cleanup result. |
| Pass | Exact worktree identity is present; a stable relation can identify the task's agent; working and idle are unambiguous; absent or plain-shell agent is never false-alive. |
| Refuse | Any ambiguous cross-pane match, missing stable identity, state-value ambiguity, malformed JSON, or a result that needs heuristic terminal-text correlation. |
| Unlock | P1 semantic busy/liveness implementation in this round only if pass; later P2 endpoint durability and P7 recovery remain separate goals. |
| Cleanup | Mark the scratch scout done, verify its report, then use `bin/fm-teardown.sh`; never raw-delete in Orca. |

### Future experiment ledger (tracked here, not executed in this round)

| Gate | Why it exists | What it unlocks | Deferred boundary |
|---|---|---|---|
| E2 pane identity through restart | `term_` handles rot across Orca runtime epochs. | P2 durable terminal re-resolution. | No pane-key/meta work now. |
| E3 hibernation x watcher | Two lifecycle managers could misclassify an idle hibernated agent. | P7 hibernation/restart recovery. | No hibernation changes now. |
| E4 native launch parity | Orca `--agent/--prompt` may lose Firstmate launch-template guarantees. | P8 launch integration. | Keep typed launch now. |
| E5 Orca-side deletion | Orca can delete a branch while Firstmate protects unlanded work. | P3 destruction detection. | No destructive test outside scratch worktree. |
| E6 hook/event cohabitation | Orca hooks and Firstmate hooks must coexist without lost signals. | P6 event source trial. | Do not replace watcher now. |
| E7 deeper terminal pagination | Current peeks retrieve bounded history. | Later ergonomics only. | No pagination redesign now. |
| E8 comment/status writes | Orca board is captain-visible but could clobber human edits. | P5 one-way status mirror. | No mirror writes now. |

## Verb signatures

No user-facing verb changes are permitted.

Internal adapter contract only:

```text
fm_backend_orca_busy_state <terminal> <worktree-id>
    stdout: busy | idle | unknown

fm_backend_orca_agent_alive <terminal> <worktree-id>
    stdout: alive | dead | unknown
```

The final argument shape may differ only if existing `fm_backend_*` dispatcher conventions require it.
No caller outside the generic backend dispatcher may invoke raw `orca worktree ps`.

## Phases (eleven)

Every P1-P10 phase starts by adding the named depth test and showing it fail.
Every completed code phase ends with the focused test, `bash -n`, `bin/fm-lint.sh`, relevant full behavior tests, one conventional local commit ending `(rider PN)`, and a short phase result appended to this rider while the branch is active.

### P1 - Baseline and fixture seam

- Read current Orca adapter JSON parsers and dispatcher call shapes at HEAD.
- Extend the fake Orca CLI harness only enough to express `worktree ps --json` fixtures.
- Capture the pre-change `unknown` behavior for Orca busy/liveness.

Depth tests in `/Users/johncurtis/projects/firstmate/tests/fm-backend-orca.test.sh`:

- `orca_liveness_baseline_returns_unknown_before_agents_snapshot_is_consumed`
- `orca_agents_snapshot_rejects_ok_false_and_malformed_json_without_liveness_claim`

### P2 - E1 disposable working and idle observations

- Create and supervise the scratch scout through Firstmate's Orca backend.
- Capture working and idle JSON state while matching it to Firstmate metadata.
- Record exact commands, Orca version/runtime, output fragments, and cleanup in `docs/orca-backend.md`.

Depth tests:

- `orca_e1_records_exact_worktree_identity_for_scratch_firstmate_task`
- `orca_e1_observes_distinct_working_and_idle_agent_states`

### P3 - E1 negative-state observations and gate

- Safely observe clean exit and plain-shell/no-agent behavior without touching a captain task.
- Decide pass/refuse from the table above before writing semantic production mapping.
- If refusal criteria trigger, document them, leave production semantics `unknown`, finish P11, and stop as blocked for implementation.

Depth tests:

- `orca_e1_plain_shell_or_absent_agent_never_claims_alive`
- `orca_e1_ambiguous_agent_identity_refuses_semantic_mapping`

### P4 - Strict snapshot parser

- Implement one Orca-adapter-owned parser for the E1-proven `worktree ps` JSON shape.
- Require exact recorded worktree identity and a unique agent match.
- Reject unknown JSON shape, duplicate match, and unrecognized state conservatively.

Depth tests:

- `orca_snapshot_selects_only_recorded_worktree_and_matching_agent`
- `orca_snapshot_rejects_unrelated_agent_and_duplicate_match`
- `orca_snapshot_unrecognized_state_is_unknown`

### P5 - Semantic busy-state dispatcher

- Add the Orca arm to `fm_backend_busy_state` only after P3 passes.
- Map only E1-proven working/idle semantics.
- Preserve `unknown` as fallback, including for read failure.

Depth tests:

- `orca_busy_state_reports_busy_only_for_verified_working_agent`
- `orca_busy_state_reports_idle_only_for_verified_idle_agent`
- `orca_busy_state_read_failure_remains_unknown`

### P6 - Conservative agent-liveness dispatcher

- Add the Orca arm to `fm_backend_agent_alive` only after P3 proves safe dead/no-agent semantics.
- Keep an ambiguous terminal, a missing worktree, and a parser failure at `unknown`.

Depth tests:

- `orca_agent_alive_reports_alive_for_verified_matching_agent`
- `orca_agent_alive_reports_dead_only_for_e1_proven_absence`
- `orca_agent_alive_never_converts_runtime_read_failure_to_dead`

### P7 - Consumer integration without watcher redesign

- Verify `bin/fm-crew-state.sh` consumes Orca's semantic busy result through the existing generic dispatcher.
- Verify `bin/fm-watch.sh` receives the same semantic result and retains its existing fallback policy.
- Do not add an Orca push/event implementation.

Depth tests:

- `orca_crew_state_prefers_verified_semantic_busy_over_tail_regex`
- `orca_watcher_falls_back_to_existing_regex_when_orca_state_is_unknown`

### P8 - Target-presence and non-Orca regression

- Enrich Orca target presence only if the E1 shape proves it safe.
- Prove tmux, herdr, zellij, and cmux dispatcher outputs and fallback paths are unchanged.

Depth tests:

- `orca_target_presence_requires_readable_recorded_endpoint`
- `non_orca_backend_busy_and_liveness_dispatch_remain_unchanged`

### P9 - Failure and teardown safety review

- Exercise `ok:false`, missing worktree, stale terminal, agent mismatch, and plain shell fixtures.
- Confirm this round never changes landed-work proof or Orca teardown id/path cross-check behavior.

Depth tests:

- `orca_liveness_failure_modes_preserve_teardown_fail_closed_contract`
- `orca_liveness_unknown_never_authorizes_secondmate_or_recovery_action`

### P10 - Full validation and fresh-context review

- Run the full repository behavior suite and lint/syntax lanes.
- Run a fresh-context review focused on accidental non-Orca behavior changes, false-positive liveness, raw Orca calls outside the adapter, and test deletion.
- Surface all outputs in the executor transcript.

Depth tests:

- `orca_liveness_full_suite_retains_existing_orca_teardown_coverage`

### P11 - Architecture evidence and milestone documentation

- Add a concise dated E1/P1 evidence subsection to `/Users/johncurtis/projects/firstmate/docs/orca-backend.md`.
- Update `/Users/johncurtis/projects/firstmate/docs/architecture.md` to state the shipped-versus-thin Orca liveness capability and its conservative fallback.
- Update `/Users/johncurtis/projects/firstmate/CHANGELOG.md` with E1's result, P1's delivered behavior or refusal, and the remaining experiment-gate status.
- List the next eligible goal: E2/P2 durable endpoint re-resolution, only after this round passes.

## Integration matrix

| Backend | Busy semantics after this round | Agent liveness after this round | Required preservation |
|---|---|---|---|
| Orca | E1-proven `busy`/`idle`, else `unknown` | E1-proven `alive`/`dead`, else `unknown` | Exact worktree match, no terminal-text guess. |
| tmux | Existing behavior | Existing behavior | Byte-for-byte unchanged. |
| herdr | Existing native behavior | Existing behavior | Byte-for-byte unchanged. |
| zellij | Existing unknown/fallback | Existing unknown | Byte-for-byte unchanged. |
| cmux | Existing unknown/fallback | Existing unknown | Byte-for-byte unchanged. |

## Error-footer canonical pairs

| Error | `try:` |
|---|---|
| Orca `worktree ps` JSON is malformed or `ok:false` | `try: start Orca, then rerun the focused Orca backend test` |
| Recorded Orca worktree is absent or does not uniquely identify an agent | `try: inspect the task with bin/fm-crew-state.sh <id>; do not respawn from unknown` |
| E1 cannot prove a safe state mapping | `try: preserve unknown and schedule the missing observation as the next experiment` |

## Out of scope (explicitly not in this milestone)

- E2/P2 durable pane identity and post-restart terminal re-resolution.
- E3/P7 hibernation, Restart, or resume recovery.
- E4/P8 Orca-native agent launch and prompt delivery.
- E5/P3 destructive-worktree deletion detection.
- E6/P6 watcher event waits or managed-hook consumption.
- E7 terminal history pagination.
- E8 comment/workspace-status mirror.
- Any `team-worktree` task kind, shared worktree, coordinator, worker pane, or Orca orchestration integration.
- Any Orca repository change.

## Dependencies (Tier 1 / 2 / 3 policy)

- Tier 1: installed `orca`, Bash, Node, existing fake Orca CLI test harness, and the existing Firstmate test/lint lanes.
- Tier 2: none expected.
- Tier 3: a missing ready Orca runtime or inability to produce the disposable E1 state observations blocks semantic implementation but not evidence capture/refusal documentation.

## Engineering invariants (do not violate)

- Orca is a signal source for `backend=orca`; Firstmate remains the task, watcher, landing, approval, and teardown authority.
- Unknown is safer than a false positive.
- A no-agent or plain shell is never `alive` without E1 proof.
- Existing `terminal=` metadata remains untouched in this round.
- No raw `orca worktree ps` calls outside `bin/backends/orca.sh` after the adapter primitive exists.
- No change to `fm-teardown.sh`, `fm-spawn.sh`, `state/<id>.meta`, branch removal, or merge behavior.
- New JSON fields are accepted only after the fake fixture and E1 live evidence agree on their shape.
- Do not weaken current tests; add coverage before behavior.
- No silent scope expansion; deferred items remain in the future experiment ledger.

## Process invariants

- Phased local commits only.
- No `git push`, merge, PR, remote mutation, or source edit in `/Users/johncurtis/projects/orca`.
- Run each named test red before implementation and show the focused test green afterward.
- Run the full commands stated in the goal before completion and retain their outputs in the execution transcript.
- Update the E1 evidence where backend evidence belongs, not in `AGENTS.md`.
- After P10, use a fresh-context reviewer before declaring the round complete.
- If a major design decision appears, stop and append it under this rider's Out-of-scope section with the exact evidence; do not implement it.
