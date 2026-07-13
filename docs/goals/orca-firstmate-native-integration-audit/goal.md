# Orca-native Firstmate integration audit

## Objective

Produce a source-backed comparative architecture of Orca and Firstmate as agent/worktree orchestration systems, then identify the correct authority boundary and prioritized Firstmate changes needed for native Orca team visibility and lifecycle control without weakening Firstmate's safety, supervision, backlog, delivery, or non-Orca compatibility.

## Original Request

Deeply understand how Orca sees development agents, worktrees, subagents, panes, sessions, and its CLI versus how Firstmate currently operates; compare both systems and determine where Firstmate should use Orca more natively, where Firstmate is stronger, and how shared-worktree and isolated-worktree teams should behave.

## Intake Summary

- Input shape: `audit`
- Audience: Captain and future Firstmate maintainers
- Authority: `requested`
- Proof type: `source_backed_answer`
- Completion proof: A final report with source-cited world models, lifecycle traces, ownership matrix, gap analysis, and implementation-ready roadmap accepted by a final Judge audit.
- Goal oracle: Every material claim maps to current Orca or Firstmate docs/code; contradictions are resolved against source or safe CLI evidence; recommendations name the right authority, migration boundary, candidate files, and verification path.
- Likely misfire: Writing a generic feature comparison, treating docs as infallible, or recommending wholesale replacement rather than a coherent composition of the two systems.
- Blind spots considered: shared-worktree visibility, isolated-worktree ownership, terminal lineage, coordinator/direct-report semantics, session restoration, watcher/lock guarantees, state duplication, teardown safety, backend portability, and docs-versus-runtime drift.
- Existing plan facts: Start with `/Users/johncurtis/projects/ai-artifacts/ocra-docs/`; consult `/Users/johncurtis/projects/orca` when docs are incomplete or conflict with current behavior; inspect Firstmate at `/Users/johncurtis/projects/firstmate`; evaluate Orca CLI use for shared-worktree panes and compare Orca-native isolated worktrees with Firstmate's current backend machinery.

## Goal Oracle

The oracle for this goal is:

`A final Judge accepts a source-cited report that explains both systems end to end, resolves ownership overlaps, covers shared and isolated worktree modes, and provides a prioritized implementation roadmap precise enough to turn into bounded Firstmate changes.`

The PM must keep comparing task receipts to this oracle. Planning or collecting files is not enough. The goal finishes only when a final Judge audit records `full_outcome_complete: true` and maps the findings back to the captain's concern about native Orca behavior.

## Goal Kind

`audit`

## Current Tranche

Complete the comparative research and recommendation tranche only. Do not implement changes to Firstmate or Orca. The largest useful output is one coherent architecture report covering both systems, not a collection of disconnected notes.

## Non-Negotiable Constraints

- Read Orca docs before Orca implementation source.
- Use current Orca source only to resolve missing, ambiguous, or stale documentation and cite the exact source path.
- Inspect Firstmate docs and implementation source directly, including backend adapters and lifecycle scripts.
- Trace both shared-worktree and isolated-worktree modes end to end: intake, spawn, terminal/pane creation, prompts, coordination, status, supervision, recovery, delivery, and cleanup.
- Distinguish harness, runtime backend, orchestration protocol, worktree owner, session owner, and durable task-state owner.
- Compare actual guarantees, not only surface features.
- Preserve Firstmate's non-Orca backend compatibility unless evidence justifies a deliberate architecture change.
- Identify where duplicated state or split authority can produce stale terminals, invisible teams, unsafe teardown, or confusing recovery.
- Use safe read-only CLI probes only when docs/source do not establish behavior.
- Do not edit implementation files, configuration, or operational fleet state during this audit.
- Do not open PRs or issues during this tranche.

## Stop Rule

Stop only when the final Judge audit proves the source-backed comparative report satisfies the full research outcome.

Do not stop after separate Orca and Firstmate summaries; the comparison, authority model, and ranked roadmap are required.

## Slice Sizing

Each Scout task should produce a coherent system or lifecycle model. Avoid one task per command or file. The Judge should evaluate the complete ownership and integration model, not isolated findings.

## Canonical Board

Machine truth lives at:

`docs/goals/orca-firstmate-native-integration-audit/state.yaml`

If this charter and `state.yaml` disagree, `state.yaml` wins for task status, active task, receipts, verification freshness, and completion truth.

## Run Command

```text
/goal Follow docs/goals/orca-firstmate-native-integration-audit/goal.md.
```

## PM Loop

1. Read this charter and `state.yaml`.
2. Work only on the active board task.
3. Delegate with the installed Diligence Scout or Judge agent matching the task.
4. Record source paths and safe CLI evidence in compact receipts or `notes/`.
5. Advance immediately to the next task until the final Judge audit accepts the full report.
6. Do not implement recommendations in this audit tranche.
