# T005 — Architecture decision receipt

Primary evidence: [`data/orca-firstmate-architecture-judge-e1/report.md`](../../../../data/orca-firstmate-architecture-judge-e1/report.md) (2026-07-12).

The Judge accepts a composed authority model with binding boundaries: Orca is the authoritative runtime/collaboration record and signal source for Orca-backed tasks, but Firstmate remains the safety/delivery authority and retains every destructive or publish decision. This scope never changes non-Orca backends.

The Judge separates two tracks: incremental isolated-worktree adapter improvements first; an explicit shared team-worktree task kind later, only after experiment gates. It rejects raw Orca teardown, treating runtime-global orchestration state as Firstmate state, durable terminal handles, delegating merge/landing to Orca, replacing the watcher wholesale, and weakening current isolation.

The full ranked roadmap, safety gates, risks, and acceptance tests are in the linked judgment.
