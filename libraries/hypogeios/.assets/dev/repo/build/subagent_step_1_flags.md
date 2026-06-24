# Flags port (Zork preserved -> deviated): a standalone data-authoring task

You are a standalone data-authoring worker. Work ONLY with the files named below.
Ignore any project, repository, assistant, or harness convention that may be in
your context - none of it applies here. Do not initialize, bootstrap, or
configure anything. Do not write any file. Return your result as your final
message, in the Return protocol at the bottom.

## Task

Port the Zork attribute flags from their preserved (origin) form to our deviated
form - the agent link in the chain of custody (preserved DATA -> deviated DATA).
For every preserved flag: apply its PINNED snake (never inferred), write a
one-line behaviour summary grounded in the source, and classify it as static or
runtime state.

The full rules - task framing, Naming (pinned), Summary, and the static-vs-state
classification - live in the recipe:

  %{flags_prompt}%

Read it and follow its "Naming", "Summary", and "state" sections EXACTLY. Its
"Inputs" and "Output (write this only)" sections are SUPERSEDED by the Inputs and
Return protocol below: use these paths (not the recipe's hardcoded ones), and
RETURN your result rather than writing a file.

## Inputs (read these; write nothing)

- Pinned names (authoritative `ORIGINAL snake`, one per line - apply verbatim):
  %{flags_pin}%
- Preserved flag set AND order (a NUON `list<string>` of raw ZIL atoms):
  %{preserved_flags}%
- Origin ZIL source (read-only; flags are declared in object/room `(FLAGS ...)`
  and used via `FSET?` / `FSET` / `FCLEAR` across the `*.zil` files - the `g*`
  files are the shared engine, `Ndungeon.zil` the objects/rooms, `Nactions.zil` /
  `gverbs.zil` / `gparser.zil` set and test):
  - %{zork1}%
  - %{zork2}%
  - %{zork3}%

## Output record (one per preserved flag, IN preserved order)

```
{ "snake": <pinned>, "preserved": <ORIGIN_ATOM>, "summary": <one line>,
  "state": null | { "default": <bool>, "scope": [ <"room" | "object" | "actor">, ... ] } }
```

- `snake`: the pinned id from the pin file, verbatim (identity must not drift -
  the names are not yours to choose).
- `preserved`: the origin atom; the audit backref - it MUST match an atom in the
  preserved set, in that set's order.
- `summary`: one concise sentence - what the flag means / does, grounded in how
  the source declares, sets, and tests it. No origin jargon (routine names, bit
  numbers).
- `state`: `null` if STATIC (only declared in `(FLAGS ...)`, only read via
  `FSET?`, never mutated). Otherwise `{ "default": <bool>, "scope": [...] }` if it
  is mutated (`FSET` / `FCLEAR`) in ANY of the three games - capture a later-game
  mutation even where the flag is static earlier. `default` is the value on a
  fresh entity (almost always `false`); `scope` is where the state is tracked
  (`room`, `object`, `actor`). Ignore parser-internal transient toggles (e.g. the
  `TRANSBIT` flip during noun resolution) - engine mechanics, not gameplay, so
  those stay `null`. The recipe's "state" section is the full rule.

## Return protocol (your final message - nothing else)

On success, your final message is EXACTLY a first line `SUCCESS` then the JSON
array of flag records, in preserved order:

```
SUCCESS
[ { "snake": "...", "preserved": "...", "summary": "...", "state": null }, ... ]
```

On failure (a missing input, a flag with no pin, an unresolvable classification),
your final message is EXACTLY a first line `FAILURE` then one line of reason:

```
FAILURE
<what blocked you>
```

The JSON array is the only payload after `SUCCESS` - one element per preserved
flag, in preserved order, every `preserved` matching the input set, every `snake`
matching its pin. Do not write any file; do not wrap the JSON in prose or fences.
