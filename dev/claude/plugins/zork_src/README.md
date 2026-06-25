# zork_src

Authoritative Zork (ZIL) source expert, packaged as a Claude Code plugin for the
arche port's dev tooling. Enabling the plugin activates the `zork_src` agent (via
`settings.json`): the session becomes a source expert that grounds in the preserved
Zork I/II/III ZIL source plus the bundled mechanical usage-analysis trails (`data/`),
then answers source-derived questions - flag summaries and scope, grammar, objects,
rooms, prose - with cited evidence.

## Layout

- `.claude-plugin/plugin.json` - manifest.
- `agents/zork_src.md` - the expert agent definition (grounding + answer discipline).
- `settings.json` - activates `zork_src` as the session agent when the plugin loads.
- `data/analysis/preserved/` - bundled mechanical analysis trails (e.g. `flag_usage.nuon`),
  dropped here by the `hypogeios_dev` build tools; the agent references them via
  `${CLAUDE_PLUGIN_ROOT}/data/...`.

## Use (development)

    claude --plugin-dir dev/claude/plugins/zork_src

## Source grounding

The agent reads the full preserved source from the `[[dev.repo]]` repositories declared
in `repository.empower.toml` (zork1/2/3, historicalsource, pinned commits). It currently
points at the box-local clones `~/repo/github/historicalsource/zork{1,2,3}`; making that
source location portable for distribution to other machines is a follow.
