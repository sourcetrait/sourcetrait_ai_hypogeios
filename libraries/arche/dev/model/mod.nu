# Typed world/engine accessors for arche (the model_ layer; read source to use).
#
# Organizational, run-invoked only (NOT call() targets). Each model_ fn reads the
# DEVIATED .nuon data assets (the runtime const source; preserved/ is audit-only
# and never loaded) and composes the strict typed record - its `-> record<...>`
# return IS the schema (mirror it in derive's *_TYPE). Consume from a run() body:
# `use arche dev model *`. The derive layer code-gens the typed consts from these
# records. id field is `snake`; a domain word wins where one exists (direction).

# Compose the series ENGINE record from <world_dir>/deviated/{flags,syntax}.nuon (the
# series data shared across the trilogy). Series-wide (one ENGINE for arche). flags =
# the attribute-flag dictionary; syntax_* = the grammar (the gsyntax verb-pattern rules
# + the verb-synonym / preposition / direction / buzzword vocab, game-tagged). The
# syntax sub-tables are FLAT siblings under ENGINE (not nested) to hold the generated
# const at the proven record>table depth (working/06,08). The return IS the strict
# ENGINE schema.
export def model_engine [
    world_dir: directory
]: nothing -> record<flags: table<snake: string, preserved: string, summary: string, state: oneof<nothing, record<default: bool, scope: list<string>>>>, syntax_rules: table<verb: string, object_slots: int, direct_preposition: oneof<string, nothing>, direct_required_flag: oneof<string, nothing>, direct_search_locations: list<string>, indirect_preposition: oneof<string, nothing>, indirect_required_flag: oneof<string, nothing>, indirect_search_locations: list<string>, action: string, pre_action: oneof<string, nothing>, games: list<int>>, syntax_verb_synonyms: table<verb: string, synonyms: list<string>, games: list<int>>, syntax_prepositions: table<preposition: string, synonyms: list<string>, games: list<int>>, syntax_directions: table<direction: string, synonyms: list<string>, games: list<int>>, syntax_buzzwords: table<word: string, games: list<int>>> {
    let flags = (open ($world_dir | path join "deviated" "flags.nuon"))
    let syntax = (open ($world_dir | path join "deviated" "syntax.nuon"))
    {flags: $flags, syntax_rules: $syntax.rules, syntax_verb_synonyms: $syntax.verb_synonyms, syntax_prepositions: $syntax.prepositions, syntax_directions: $syntax.directions, syntax_buzzwords: $syntax.buzzwords}
}

# Compose an episode's WORLD record from
# <world_dir>/deviated/<episode>/{conditions,map}.nuon. map.nuon is
# record<rooms, links, blocked> (flat/relational; links/blocked are sibling tables
# keyed by room). <episode> is a snake (alpha|beta|gamma). The return IS the strict
# WORLD schema.
export def model_world [
    world_dir: directory,
    episode: string
]: nothing -> record<conditions: table<snake: string, kind: string>, rooms: table<snake: string, flags: list<string>, value: int, globals: list<string>, action: oneof<string, nothing>>, links: table<room: string, direction: string, target: string, conditions: list<oneof<string, nothing>>>, blocked: table<room: string, direction: string>> {
    let ep = ($world_dir | path join "deviated" $episode)
    let conditions = (open ($ep | path join "conditions.nuon"))
    let map = (open ($ep | path join "map.nuon"))
    {conditions: $conditions, rooms: $map.rooms, links: $map.links, blocked: $map.blocked}
}
