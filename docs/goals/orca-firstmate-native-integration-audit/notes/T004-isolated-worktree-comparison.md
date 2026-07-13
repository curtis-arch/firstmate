# T004 — Isolated-worktree comparison receipt

Primary evidence: [`data/isolated-worktree-comparison-d1/report.md`](../../../../data/isolated-worktree-comparison-d1/report.md) (2026-07-12).

Firstmate's isolated task contract is the correct default and should not be replaced. Orca already owns the right substrate for an Orca-backed task—worktree, terminal, pane layout, session restoration, and agent telemetry—but Firstmate currently bypasses or suppresses important Orca value: lineage (`--no-parent`), semantic busy/liveness state, event-driven coordination, and richer recovery data.

The report maps lifecycle ownership, R1–R8 risks, candidate seams, and E1–E8 required runtime experiments. Its central conclusion: evolve the Orca adapter incrementally while retaining Firstmate as the task/delivery/safety authority.
