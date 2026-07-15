# Orca Backend

Orca is an experimental runtime backend for firstmate.
It is distinct from the crewmate harness: the harness is the agent process firstmate launches (`claude`, `codex`, `opencode`, `pi`, or `grok`), while Orca owns the task worktree and terminal endpoint underneath that process.
Firstmate agents operating this backend should load the agent-only [`firstmate-orca`](../.agents/skills/firstmate-orca/SKILL.md) checklist before switching to Orca, spawning or supervising Orca-backed work, smoke-testing, debugging task state, or reconciling Orca metadata.

## Setup

Pick Orca if you already run the Orca macOS app as your terminal environment and want firstmate tasks to live in Orca-managed worktrees and terminals instead of a treehouse/tmux pair.
Orca is macOS-only, explicit-only (never auto-detected), and has no secondmate support.

Prerequisites:

- The Orca app installed at `/Applications/Orca.app`, and **running**.
- The `orca` CLI: `brew install orca`.
- `node`, used by firstmate's adapter to parse Orca's JSON output and to gate spawns on runtime readiness.
- The universal firstmate prerequisites - a verified crew harness plus the required toolchain, owned by [`docs/configuration.md`](configuration.md) ("Harness support", "Toolchain") - with `orca` as the only backend-specific tool, since Orca replaces both the session multiplexer CLI and the `treehouse` worktree provider that the other backends require.

Select Orca by putting `orca` in a local `config/backend` file - the durable way to pick it - or by exporting `FM_BACKEND=orca` when you launch your harness for a one-off session; telling the first mate in chat to use Orca also works.
It is never auto-detected.

First run: before spawn mutates any repo or worktree state, firstmate runs `orca status --json` and requires the app to report `reachable=true` and `state="ready"` - start the Orca app and wait for it to finish loading before spawning.
Spawn fails closed if the runtime is not ready.
The first spawn against a given project also auto-registers that project's repo in Orca (`orca repo add --path`) if it is not already registered - no manual registration step is needed.

Watching and attaching: Orca owns both the worktree and the terminal for its tasks, so there is nothing to attach to outside the Orca app itself - open the app and find the terminal for the task (recorded as `terminal=<handle>` plus durable `orca_pane_key=<tabId>:<leafId>` in the task's meta, with `window=fm-<id>` as the shared firstmate alias).
You do not need to open the app for routine supervision: from an active firstmate session, `bin/fm-peek.sh <id>` reads a task's terminal without opening Orca, and `FM_HOME=<this-firstmate-home> bin/fm-send.sh <id> "<text>"` steers it unless `FM_HOME` is already set to the active firstmate home (the stable `fm-<id>` alias also works; Enter and Ctrl-C are supported; Escape is not).

Verify it works by spawning a trivial task with `--backend orca` and confirming the task's meta records `backend=orca`, `terminal=`, `orca_pane_key=`, `orca_worktree_id=`, and `worktree=`; the Orca app should show a new terminal for the task.

Limitations: `--secondmate` spawns refuse `backend=orca` (secondmate-home semantics need a separate design), Escape is unsupported, Orca is macOS-only and explicit-only, and it exposes no stable CLI version marker, so spawn gates on runtime reachability instead of a version floor - see "Limitations" below for the complete list.

## Status

PR #210 landed the primitive Orca terminal adapter: bounded capture, text send, Enter, Ctrl-C interrupt, and close for already-created Orca terminals.
This follow-up adds full ship/scout task lifecycle support for `backend=orca`: spawn, metadata, send/peek/watch/crew-state routing from metadata, and guarded teardown through Orca.

Orca remains explicit-only.
Select it by putting `orca` in a local `config/backend` file, by exporting `FM_BACKEND=orca`, or by telling the first mate in chat to use Orca.
It is not auto-detected from the current process environment.
Before spawn mutates any repo/worktree state, firstmate runs `orca status --json` and requires the Orca runtime to report reachable/ready.

## Task Shape

An Orca task is one Orca-managed git worktree plus one Orca terminal.
Unlike `tmux`, `herdr`, `zellij`, and `cmux`, Orca is not only a session provider; it also provides the task worktree, so `fm-spawn.sh` does not run `treehouse get` for Orca tasks.

The normal firstmate invariant still applies: a ship or scout task must run outside the project primary checkout, and teardown must refuse to discard unlanded ship work.

## Metadata

An Orca-spawned task records the normal task fields plus these Orca-specific fields:

```text
backend=orca
generation=<immutable task generation>
window=fm-<id>
terminal=<orca terminal handle>
orca_pane_key=<orca tab UUID>:<orca leaf UUID>
orca_worktree_id=<orca worktree id>
worktree=<absolute path to the Orca-created git worktree>
```

`window=` remains the shared firstmate alias used by selector-driven supervision tools after a task selector has resolved through metadata.
`fm-teardown.sh <id>` uses the same recorded fields after loading `state/<id>.meta`.
For Orca, `window=` keeps the stable firstmate alias, `terminal=` carries the runtime-epoch handle that backend operations use, and `orca_pane_key=` carries the remint-stable pane identity used to recover that handle.
The recorded `backend=orca` field tells shared call sites to route capture, send, interrupt, and close through `bin/backends/orca.sh` instead of tmux assumptions.

## Lifecycle

Spawn:

1. Ensure the project repo is registered in Orca, adding it with `orca repo add --path` when needed.
2. Create an independent Orca worktree with `orca worktree create --repo id:<repo> --name fm-<id> --no-parent --setup skip`.
3. Reuse the terminal returned by Orca worktree creation only when it appears in the verified `result.terminal.handle` shape, or create a titled terminal in that worktree when Orca returns only the worktree.
4. Record a validated `result.terminal.paneKey` when creation returns it, otherwise compose the same pane key from `terminal show`'s UUID `tabId` and `leafId`.
   Missing or invalid pane identity warns but does not block spawn, preserving compatibility with older Orca shapes.
5. Install firstmate's per-harness turn-end hooks in the Orca worktree.
6. Write metadata, then send `GOTMPDIR` export and the selected harness launch through the recorded Orca terminal.

Operation routing:

- `fm-peek.sh` captures with `orca terminal read`.
- `fm-send.sh` types text with `orca terminal send --text ...`, submits with Enter, and verifies the composer row cleared before returning; when Orca reports a limited page, the verifier follows `oldestCursor` and preserves the current tail so older text cannot hide still-pending composer input.
  A slash-command popup that closes by filling an argument-hint placeholder still reads as pending, so the retry loop sends the required second Enter rather than treating the first Enter as a submission.
  The bordered row is classified through the shared composer classifier; a bare shell prompt has no genuine composer row and reads `unknown`, not confirmed empty.
- `fm-send.sh --key Enter` and `--key C-c` are supported.
- `fm-watch.sh` joins the recorded terminal to Orca's native per-agent state through `terminal show` and `worktree ps`.
  A verified `working` agent is busy, a verified turn-complete `done` agent is idle, and an exact-match `waiting` or `blocked` agent is alive but emits a distinct `attention:` wake; every unknown result retains the existing terminal-tail fallback.
- `fm-crew-state.sh` reads the recorded Orca terminal when no no-mistakes run-step applies.
  Exact-match `waiting` and `blocked` states report actionable `state: blocked` with `source: backend-agent` and preserve the native state in the detail.

Stale-handle recovery:

- Recovery runs only when a handle operation returns exact error code `terminal_handle_stale` and the task meta has both a recorded `orca_worktree_id` and a valid `orca_pane_key`.
- Firstmate lists candidates with `orca terminal list --worktree id:<recorded-worktree> --json`, then resolves every candidate through `terminal show` because list results can contain non-joinable `pty:` placeholders.
- Exactly one connected candidate whose `worktreeId` and `tabId:leafId` equal the recorded identities replaces `terminal=` atomically only while the immutable task generation is unchanged, and the original operation is retried once.
- Zero matches, duplicate matches, disconnected matches, unreadable candidates, malformed JSON, list failure, and every non-stale error leave metadata unchanged and fail closed.
- Recovery never searches another worktree, guesses from titles or ordering, selects the first candidate, or creates a replacement terminal.
- Existing task metas without `orca_pane_key` retain their prior behavior: live handles continue to work, while a stale handle surfaces the original Orca error without attempting recovery.

Teardown:

- Teardown claims the recorded task generation before any destructive cleanup; recovery and metadata promotion refuse while that ownership is active.
- A teardown interrupted by process death remains inactive until an operator explicitly resumes it with the recorded owner token; a live owner cannot be taken over.
- Scout teardown still requires `data/<id>/report.md` unless `--force` is explicitly used.
- Ship teardown still refuses dirty or unlanded work before any terminal/worktree cleanup.
- Ship teardown resolves `orca_worktree_id` back through Orca and verifies it matches the inspected `worktree=` path before removing anything; mismatches or uninspectable paths preserve metadata and fail closed.
- After the existing firstmate safety checks pass, teardown closes the recorded Orca terminal and releases the recorded worktree through `orca worktree rm --worktree id:<orca_worktree_id> --force`.
- Teardown does not raw-delete Orca worktrees.

## Limitations

- `--secondmate` spawns still refuse `backend=orca`; secondmate-home semantics need a separate design.
- Escape is unsupported because the current Orca terminal send primitive exposes Enter and interrupt-style input but no verified Escape operation.
- Orca is explicit-only and is not selected by runtime auto-detection.
- Orca currently exposes no stable CLI version or protocol marker. Unlike the herdr/zellij/cmux docs, this backend intentionally gates spawn support on runtime reachability from `orca status --json` rather than a version floor.
- Pane-key durability across an actual observed app restart remains unverified.
  Orca source defines pane keys as persisted remint-stable identities and the recovery path is fail-closed, but the first natural or captain-approved restart still needs the documented post-restart smoke check.
- The `waiting` and `blocked` attention mapping is evidence-limited.
  The state names and requested supervision policy are fixture-backed, but this change did not perform a new live Orca transition capture proving what runtime conditions produce either state.

## Verification

### Semantic liveness E1 - refused for P1 (2026-07-12)

The controlling Firstmate created the disposable Orca-backed scout `orca-e1-runtime-scout-e1`, and the scout captured its own runtime state between `2026-07-12T18:32:09Z` and `2026-07-12T18:32:49Z`.
The delegated implementation crewmate did not spawn, supervise, or tear down the scout.
The complete scout-owned report is `/Users/johncurtis/projects/firstmate/data/orca-e1-runtime-scout-e1/report.md`.

The installed application version was read without modifying Orca:

```console
$ /usr/bin/defaults read /Applications/Orca.app/Contents/Info CFBundleShortVersionString
1.4.137
```

The scout reported a ready runtime with runtime ID `923315fe-d6cc-4bc1-9c1f-de30cd45c894`.
Its exact Firstmate metadata was:

```text
window=fm-orca-e1-runtime-scout-e1
worktree=/Users/johncurtis/orca/workspaces/firstmate/fm-orca-e1-runtime-scout-e1
project=/Users/johncurtis/projects/firstmate
harness=claude
kind=scout
mode=no-mistakes
yolo=off
tasktmp=/tmp/fm-orca-e1-runtime-scout-e1
model=fable
effort=medium
backend=orca
orca_worktree_id=69c04545-e3dd-467f-9b35-0eb698cc41a7::/Users/johncurtis/orca/workspaces/firstmate/fm-orca-e1-runtime-scout-e1
terminal=term_93a44266-2b0c-4f7a-9219-8628d0ae804b
```

While the scout was executing a Bash tool call, its exact-worktree query returned:

```json
{
  "worktreeId": "69c04545-e3dd-467f-9b35-0eb698cc41a7::/Users/johncurtis/orca/workspaces/firstmate/fm-orca-e1-runtime-scout-e1",
  "path": "/Users/johncurtis/orca/workspaces/firstmate/fm-orca-e1-runtime-scout-e1",
  "liveTerminalCount": 2,
  "agents": [
    {
      "paneKey": "a0c06606-27a5-4681-9872-1fd970006abd:4b750970-b01f-4207-82e4-b829ef033881",
      "state": "working",
      "agentType": "claude"
    }
  ]
}
```

After the scout wrote its report and its status log recorded `done: report at data/orca-e1-runtime-scout-e1/report.md`, the same agent entry was observed with `state: "done"`.
The scout's full seven-worktree JSON contained no structural `term_*` value and no value related to `93a44266` outside the scout's echoed `toolInput` free text.
The exact recorded `terminal=term_93a44266-2b0c-4f7a-9219-8628d0ae804b` therefore had no proven relation to `agents[0].paneKey`.
The worktree also had two live terminals but only one agent entry, so selecting the sole returned agent would be an unverified cross-pane guess.

The controlling Firstmate then used guarded scout teardown.
Cleanup was verified read-only: `state/orca-e1-runtime-scout-e1.meta` was absent, and this exact-path query returned an empty array:

```console
$ orca worktree ps --json | jq '[.result.worktrees[] | select((.path // "") | contains("orca-e1-runtime-scout-e1")) | {worktreeId,path,status,liveTerminalCount,agents:[.agents[] | {paneKey,state,agentType}]}]'
[]
```

#### E1 decision: refuse

E1 proves exact worktree matching plus directly observed `working` and `done` agent values.
It does not prove a stable terminal-to-agent identity relation, `idle`, waiting/permission, or a safe absent-agent/plain-shell mapping.
Those missing observations and the two-terminal ambiguity meet the rider's refusal rule.

P1 is therefore blocked and production remains unchanged: Orca busy state and agent liveness both report `unknown`, and existing terminal-tail fallback policy remains in place.
Fixture tests pin the conservative fallback, but fixtures are not E1 evidence.
The next eligible work is E1 again with a proven endpoint-to-agent relation and direct idle plus no-agent/plain-shell observations.
E2/P2 durable endpoint re-resolution is not unlocked.

### Semantic liveness E1b - P1 accepted (2026-07-14)

The E1 re-run against Orca application `1.4.139` proved the missing identity relation on disposable Firstmate-created task `orca-live-contract-e1`.
The complete scout report is `/Users/johncurtis/projects/firstmate/data/orca-live-contract-e1/report.md`.
The supervising Firstmate then completed the report's requested E1b transition observation from a shell that could reach the Orca runtime.

The exact read-only join commands were:

```console
$ orca terminal show --terminal term_362be563-3b68-4cb1-8ba8-70a90bf47f50 --json
{"ok":true,"result":{"terminal":{"worktreeId":"69c04545-e3dd-467f-9b35-0eb698cc41a7::/Users/johncurtis/orca/workspaces/firstmate/fm-orca-live-contract-e1","tabId":"6d34d759-95c6-4ecc-8c25-3eb6223b9e23","leafId":"7d4d7c59-b905-4b1c-8ebe-10225f653d46","connected":true,"writable":true}}}

$ orca worktree ps --json
{"ok":true,"result":{"worktrees":[{"worktreeId":"69c04545-e3dd-467f-9b35-0eb698cc41a7::/Users/johncurtis/orca/workspaces/firstmate/fm-orca-live-contract-e1","agents":[{"paneKey":"6d34d759-95c6-4ecc-8c25-3eb6223b9e23:7d4d7c59-b905-4b1c-8ebe-10225f653d46","state":"working","agentType":"claude"}]}]}}}
```

The exact recorded `orca_worktree_id` matched exactly one worktree, and `terminal show`'s `tabId:leafId` matched exactly one `agents[].paneKey` in that worktree.
`terminal list` is intentionally excluded from production because CLI-created terminals can expose non-joinable `pty:` placeholder ids there.
The matching worker reported `working` during a real turn.
After the turn completed while Claude remained open, the same matched agent reported `done`, and the recorded terminal remained connected and writable.
After a clean `/exit`, the same terminal remained connected and writable as a plain shell while the exact worktree's `agents[]` became empty.

P1 therefore maps only these observed shapes:

- Exact unique matched agent state `working` becomes semantic `busy` and liveness `alive`.
- Exact unique matched agent state `done` becomes semantic `idle` and liveness `alive`.
- An empty `agents[]` in the exact worktree after clean agent exit, while the exact terminal remains connected and writable, becomes liveness `dead`; a nonempty inventory without the recorded pane remains `unknown`.
- `ok:false`, malformed JSON, command failure, cross-worktree identity, `pty:` placeholders, duplicate worktrees, duplicate agents, disconnected or non-writable terminals, and unknown states remain `unknown`.

The normalized snapshot parser lives in `bin/backends/orca.sh` and is reached only through `bin/fm-backend.sh`.
Runtime-global aggregate worktree status and first-agent selection are never used.
Orca remains a pull backend, so this does not add event waits or replace the watcher loop.

### Attention-state extension - fixture-backed, evidence-limited (2026-07-15)

The attention extension preserves the E1b exact join unchanged: one connected, writable terminal resolves to one exact worktree and exactly one agent whose `paneKey` equals `tabId:leafId`.
Parent or child relationship fields do not participate in selection, and a child row cannot override the exact coordinator row.
Duplicate worktrees, duplicate exact pane matches, cross-worktree identities, absent exact matches, malformed rows, and unknown state strings remain `unknown` and retain the prior fail-closed fallback.

The backend-neutral busy-state vocabulary now includes `attention`, with a separate detail accessor returning `waiting` or `blocked`.
Both states map to semantic `attention` and liveness `alive`, never `dead`, `busy`, or ordinary `idle`.
The polling watcher emits and durably queues `attention: <terminal> (agent waiting|blocked)` once per state edge, and the away-mode daemon escalates that wake directly rather than aging it through the stale-pane wedge timer.

This section records an implementation policy and fixture evidence, not a new runtime observation.
No live Orca command was run for this change, so the causal meaning of `waiting` versus `blocked` remains evidence-limited until a disposable task captures both transitions with the exact E1b join commands.

### Durable endpoint E2 - P2 accepted (2026-07-14)

The read-only E2 scout ran against Orca application `1.4.139`, runtime ID `3a18045d-23fb-48b7-af03-6736761ad120`, and exact task worktree `69c04545-e3dd-467f-9b35-0eb698cc41a7::/Users/johncurtis/orca/workspaces/firstmate/fm-orca-p2-contract-e2`.
The complete evidence report is `/Users/johncurtis/projects/firstmate/data/orca-p2-contract-e2/report.md`.

The stale-handle probe returned the exact recovery trigger:

```console
$ orca terminal show --terminal term_00000000-0000-4000-8000-000000000000 --json
{"ok":false,"error":{"code":"terminal_handle_stale"}}
```

The scout then created one disposable terminal and observed creation-time pane identity directly; the report retained the handle in abbreviated form and the pane key in full:

```console
$ orca terminal create --worktree id:<recorded-worktree-id> --title fm-p2-probe --json
{"ok":true,"result":{"terminal":{"handle":"term_18858232-...","paneKey":"58f16f30-eee4-478c-8544-5b1d9547a953:acc89229-0849-4fbe-a6e9-8b9db1cb2da0"}}}
```

`terminal list` enumerated three worktree-scoped handles with `pty:` placeholder ids.
`terminal show` on all three returned real UUID identities, and exactly one candidate matched the recorded pane key and worktree id.
After the probe terminal was closed, list returned only the original two terminals; the just-closed handle briefly remained showable with `connected:false`, which is why recovery refuses disconnected matches.
The detached Orca terminal daemon was also directly observed to predate the current app process, but the exact pane-key transition across a controlled app restart was not performed because the app hosted the primary session.

The implementation therefore treats restart survival as source-backed and fail-closed rather than as directly observed runtime behavior.
If the pane key did not survive, recovery returns zero matches and preserves metadata; it cannot bind another endpoint without exact unique worktree and pane-key equality.

### Earlier adapter smoke

Real-Orca smoke verification was run against `/usr/local/bin/orca` with `/Applications/Orca.app` reporting bundle version `1.4.116`; `orca status --json` reported `result.runtime.reachable=true` and `result.runtime.state="ready"`.
The verified terminal creation handle field is `result.terminal.handle` from `orca terminal create --json`; worktree creation returned `result.worktree.id` and `result.worktree.path` in the same smoke run.
Firstmate intentionally ignores speculative terminal-handle shapes such as bare `result.id` and nested `result.worktree.terminal` until a real Orca smoke run proves them.

Fake-Orca tests cover:

- helper parsing for repo registration, worktree creation, verified implicit-terminal reuse, terminal creation, terminal sends, and worktree removal;
- rejection of undocumented terminal-handle result shapes;
- runtime readiness gating through `orca status --json`;
- exact `terminal show` to `worktree ps` semantic joins, including `working`, turn-complete `done`, and post-exit agent disappearance;
- exact-match `waiting` and `blocked` attention mapping, alive liveness, watcher/daemon escalation, and crew-state detail;
- parent-plus-child inventories where only exact `paneKey` equality selects the coordinator;
- fail-closed handling for malformed/error JSON, cross-worktree and duplicate identities, placeholder ids, disconnected terminals, and unknown states;
- creation-time and show-fallback `orca_pane_key` capture;
- exact stale-handle recovery, one-retry adoption, zero/duplicate/disconnected/unresolved outcomes, non-stale errors, and legacy metadata;
- `fm-spawn.sh --backend orca` metadata creation and harness launch;
- `fm-peek.sh`, `fm-send.sh`, and `fm-crew-state.sh` routing through recorded Orca metadata;
- slash-command popup placeholder handling that requires a second Enter before `fm-send.sh` reports submission;
- scout teardown releasing an Orca worktree through `orca worktree rm`;
- ship teardown failing closed when the recorded Orca worktree id is missing, cannot resolve to a path, or resolves to a different path than `worktree=`.

Run the focused suite with:

```sh
tests/fm-backend-orca.test.sh
tests/fm-backend.test.sh
tests/fm-bootstrap.test.sh
```
