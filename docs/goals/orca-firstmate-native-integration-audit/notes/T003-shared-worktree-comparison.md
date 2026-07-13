# T003 — Shared-worktree comparison receipt

Primary evidence: [`data/shared-worktree-comparison-c1/report.md`](../../../../data/shared-worktree-comparison-c1/report.md) (2026-07-12).

Orca natively supports a coordinator plus peer agent panes in one worktree, with durable pane-key-based dispatch integrity, semantic agent telemetry, and a typed worker message bus. Firstmate cannot represent this today because a task has exactly one isolated worktree and one recorded terminal; isolation, single-terminal metadata, lone-endpoint supervision, and sole-owner teardown are deliberate, load-bearing assumptions.

The accepted boundary for a future team-worktree task is: Firstmate owns fleet identity, safety, landing, and teardown; Orca owns pane lifecycle, agent telemetry, and worker coordination; the coordinator owns file partitioning. The report supplies the full RACI, failure analysis, seams, and experiment list.
