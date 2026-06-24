# flags.nuon port prompt (preserved -> deviated: the agent step of the chain)

A standalone data-authoring task. Work ONLY with the files named below. Do not
read, load, infer, or act on any CLAUDE.md, constitution, memory, project
bootstrap, or repository convention that may be in context - none of it applies
here. Do not initialize or bootstrap anything. Produce exactly one output file.

## Goal

Port the Zork attribute flags from their preserved (origin) form to our deviated
form - the agent link in the chain of custody (preserved DATA -> deviated DATA).
Flags are SERIES-WIDE: zork1-3 share one engine, so the flag set is the union
across all three (the common 32 + one game-specific each: NWALLBIT in II, VICBIT
in III). You are given the mechanically-extracted union; for each flag choose our
expanded name, write a one-line behavior summary, and classify it as static or
runtime state.

## Inputs (read these)

- Origin source (ZIL, read-only) - all three repos:
  - `/home/box/repo/github/historicalsource/zork1`
  - `/home/box/repo/github/historicalsource/zork2`
  - `/home/box/repo/github/historicalsource/zork3`
  Flags are declared in object/room `(FLAGS ...)` and used via `FSET?` (test) /
  `FSET` / `FCLEAR` (mutate) across the `*.zil` files. The `g*` files are the
  shared engine (gglobals declares the bit set); `Ndungeon.zil` holds object +
  room definitions; `Nactions.zil` / `gverbs.zil` / `gparser.zil` set + test.
- Preserved flag list (authoritative - the set AND the order):
  `/home/box/proj/sourcetrait/sourcetrait_ai_hypogeios/libraries/arche/.assets/world/preserved/flags.nuon`
  A NUON `list<string>` of raw ZIL flag atoms (one per line), alphabetical.
- Fixed renames (human-decided overrides; apply verbatim):
  `/home/box/proj/sourcetrait/sourcetrait_ai_hypogeios/libraries/arche/.assets/dev/flags/flags.rename.txt`
  One per line, `ORIGINAL new`.

## Output (write this only)

`/home/box/proj/sourcetrait/sourcetrait_ai_hypogeios/libraries/arche/.assets/world/deviated/flags.nuon`
- a NUON list, one record per preserved flag, IN preserved order:

```
[
    { snake: <our_name>, preserved: <ORIGIN_ATOM>, summary: <one line>, state: <null | record> },
    ...
]
```

`snake` is our deviated flag id (the engine works in these terms); `preserved` is
the origin atom (the audit backref to preserved/flags.nuon).

## Naming (origin atom -> snake)

Drop the trailing `BIT`; expand abbreviations to whole words; lowercase
`snake_case`; use the bare dropped word, not an -able/-ed adjective (`take` not
`takeable`, `burn` not `flammable`). Apply flags.rename.txt verbatim; infer the
rest on the same principle.

## Summary

A single concise sentence: what the flag means / does, grounded in how the source
declares, sets, and tests it. Describe behavior; no origin jargon (routine names,
bit numbers).

## state (static vs runtime)

- `state: null` if the flag is a STATIC attribute - it describes what a thing IS
  and is never mutated at runtime (only declared in `(FLAGS ...)`, only read via
  `FSET?`).
- `state: { default: <bool>, scope: list<string> }` if the flag is RUNTIME STATE
  - mutated (`FSET`/`FCLEAR`) in ANY of the three games (capture a later-game
  mutation even when the flag is static in earlier games).
  - `default`: the value on a fresh entity before any change (almost always
    `false`, the bit's natural off; per-entity initial values come from the
    object/room definitions, not here). Pick a default that does not conflict
    with the mechanics of games where the flag is static.
  - `scope`: where the state is tracked - any of `"room"`, `"object"`, `"actor"`.
- Judgment exception: ignore parser-internal transient toggles (e.g. the
  `FSET`/`FCLEAR ,PLAYER ,TRANSBIT` flip during noun resolution) - engine
  mechanics, not gameplay state - so such a flag stays `state: null`.

## Done when

One entry per preserved flag, in order, every `preserved` matching the input,
every `snake` expanded, every `summary` accurate, every `state` either `null` or a
`{default, scope}` record. Report the output path and entry count.
