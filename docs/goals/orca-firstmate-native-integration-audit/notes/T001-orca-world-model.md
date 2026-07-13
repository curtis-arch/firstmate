# T001 — Orca world model receipt

Primary evidence: [`data/orca-world-model-a1/report.md`](../../../../data/orca-world-model-a1/report.md) (2026-07-12).

Orca is authoritative for its runtime-owned, worktree-native surfaces: repository/worktree registration and lineage, terminal/pane layout and PTY lifecycle, managed agent session telemetry, and its runtime-global orchestration store. Its durable worktree metadata survives runtime restarts; terminal handles and runtime instances do not. Orca-created worktrees therefore offer materially better pane visibility and restore semantics than external worktrees.

The report establishes two integration constraints for Firstmate: it must not treat Orca orchestration as a private Firstmate queue, and it must preserve Firstmate's landed-work teardown guard rather than mapping it directly to `orca worktree rm`, which can delete branches by default. It also documents six source-vs-docs discrepancies and six runtime questions that the later comparison must resolve.

All material citations and the shared/isolated lifecycle traces are in the linked report.
