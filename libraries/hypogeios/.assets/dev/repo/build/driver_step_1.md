# Flags agent step (build paused at step 1 -> resume at step 3)

The mechanical PRESERVE phase ran; the staging tree now holds a freshly generated
`preserved/flags.nuon`. The deviated flags are an AGENT-authored artifact (summary
+ state, may drift), so the build paused here. Drive the flags subagent, audit its
output, then resume the build at step 3.

## 1. Launch the flags subagent (Explore only)

This call wrote the subagent's prompt to `next_step_prompt_shm` (join it with
`$env.XDGX_SHM_DIR` and read it with your Read tool). Launch EXACTLY ONE subagent
with that prompt verbatim:

- subagent_type MUST be `Explore` - a blank-slate, no-CLAUDE.md worker. NEVER
  `general-purpose` / `claude` (they boot a second fae over the shared store).
  NEVER shell `claude`.
- Pass NO CLAUDE.md, constitution, or memory path; the prompt is self-contained.
- Explore is read-only and returns its result in its final message.

## 2. Audit the return COMPLETELY before relying

The subagent returns `SUCCESS` then a JSON array, or `FAILURE` then a reason. On
FAILURE, stop and surface the reason. On SUCCESS, audit EVERY record yourself (a
subagent's self-report is not evidence):

- one record per preserved flag, in the preserved set's order; every `preserved`
  matches an atom in the staging `preserved/flags.nuon`; every `snake` matches its
  pin in `flags.pin.txt`;
- every `summary` is a single grounded line; every `state` is `null` or a
  well-formed `{ default: bool, scope: list<string> }` with scope drawn from
  `room` / `object` / `actor`.

## 3. Resume the build at step 3

Parse the audited array into a flags table and wrap it as
`step_data = { flags: <table> }`, matching:

  %{step_schema}%

Then call `hypogeios:dev/repo:build` with:

- `step`: `3`
- `hypogeios_repo_dir`: `%{hypogeios_repo_dir}%`
- `generated_tmp_dir`: `%{generated_tmp_dir}%`
- `preserved_repo_dirs`: `{ zork1: %{zork1}%, zork2: %{zork2}%, zork3: %{zork3}% }`
- `step_data`: `{ flags: <the audited table> }`

Step 3 writes the staging `deviated/flags.nuon`, runs DEVIATE + DERIVE, and
inlines the owned arche subtrees into the repo. It returns the git drift
(`gstat`) - review it: on a clean-tree reproduction with the committed flags the
drift is empty; with re-authored flags it is exactly your flag-driven changes
(`deviated/flags.nuon` + whatever the engine const re-derives). That completes the
build.
