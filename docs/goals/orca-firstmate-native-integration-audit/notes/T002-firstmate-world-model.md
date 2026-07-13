# T002 — Firstmate world model receipt

Primary evidence: [`data/firstmate-world-model-b1/report.md`](../../../../data/firstmate-world-model-b1/report.md) (2026-07-12).

Firstmate is the safety-and-delivery control plane. Its durable task identity, home lock, brief/backlog/status records, watcher/recovery logic, PR/landing proof, and guarded teardown are deliberately independent of any one terminal runtime. Orca is currently an experimental backend: Firstmate creates one isolated Orca worktree and one recorded terminal per task, then operates it through helper wrappers.

The report establishes the current limitation relevant to the captain's concern: Firstmate has no shared-worktree mode and no native enumeration of Orca team members, semantic agent state, process liveness, or event stream. Live observation during T002 also showed that harness-internal child agents remain one Orca-visible parent terminal and zero Firstmate-visible children.

All material citations, lifecycle traces, and candidate seams are in the linked report.
