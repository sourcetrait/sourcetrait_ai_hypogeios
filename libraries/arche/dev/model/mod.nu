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

# Compose an episode's VOCABULARY table - the parser word dictionary, a PROJECTION
# (union over the already-deviated sources; no preserve/deviate, no preserved form -
# the audit trail is this reproducible derive). Reads every <episode>/objects/*.nuon +
# series objects/*.nuon (synonyms -> noun, adjectives -> adjective) + deviated/
# syntax.nuon (rule-verbs + verb_synonyms -> verb canonical; prepositions / directions
# canonical+synonyms -> their canonical; buzzwords), grammar alpha-filtered by the
# episode's game; in/out/land come from the WORLD links' directions minus the grammar
# directions. A word UNIONS its roles (in -> direction+preposition; light -> verb+noun);
# noun/adjective carry no canonical (the word is the id, the parser matches in-scope
# objects dynamically). Errors if a word maps to >1 canonical for one POS. Rows sorted
# by word, parts_of_speech in a fixed order. The return IS the strict schema (mirror in
# derive's VOCABULARY_TYPE).
export def model_vocabulary [
    world_dir: directory,
    episode: string
]: nothing -> table<word: string, parts_of_speech: list<string>, verb: oneof<string, nothing>, preposition: oneof<string, nothing>, direction: oneof<string, nothing>> {
    let dev = ($world_dir | path join "deviated")
    let game = ({alpha: 1, beta: 2, gamma: 3} | get -i $episode)
    if $game == null { error make {msg: $"vocabulary: unknown episode '($episode)'"} }
    let obj_files = ((glob ($dev | path join $episode "objects" "*.nuon")) ++ (glob ($dev | path join "objects" "*.nuon")))
    let objs = ($obj_files | each {|f| open $f })
    let noun_c = ($objs | each {|o| $o.synonyms } | flatten | each {|w| {word: $w, pos: "noun", canon: null}})
    let adj_c = ($objs | each {|o| $o.adjectives } | flatten | each {|w| {word: $w, pos: "adjective", canon: null}})
    let syntax = (open ($dev | path join "syntax.nuon"))
    let rule_verbs = ($syntax.rules | where {|r| $game in $r.games } | get verb | uniq | each {|v| {word: $v, pos: "verb", canon: $v}})
    let verb_syns = ($syntax.verb_synonyms | where {|s| $game in $s.games } | each {|s| $s.synonyms | each {|w| {word: $w, pos: "verb", canon: $s.verb}}} | flatten)
    let preps = ($syntax.prepositions | where {|s| $game in $s.games } | each {|s| ([{word: $s.preposition, pos: "preposition", canon: $s.preposition}] ++ ($s.synonyms | each {|w| {word: $w, pos: "preposition", canon: $s.preposition}}))} | flatten)
    let dirs = ($syntax.directions | where {|s| $game in $s.games } | each {|s| ([{word: $s.direction, pos: "direction", canon: $s.direction}] ++ ($s.synonyms | each {|w| {word: $w, pos: "direction", canon: $s.direction}}))} | flatten)
    let buzz = ($syntax.buzzwords | where {|b| $game in $b.games } | each {|b| {word: $b.word, pos: "buzzword", canon: null}})
    let gdirs = ($syntax.directions | where {|s| $game in $s.games } | get direction)
    let map = (open ($dev | path join $episode "map.nuon"))
    let extra_dirs = ($map.links | get direction | uniq | where {|d| $d not-in $gdirs } | each {|d| {word: $d, pos: "direction", canon: $d}})
    let contribs = ($noun_c ++ $adj_c ++ $rule_verbs ++ $verb_syns ++ $preps ++ $dirs ++ $buzz ++ $extra_dirs)
    let order = [verb noun adjective preposition direction buzzword]
    $contribs | group-by {|r| $r.word} | transpose word rows | each {|g|
        let cs = $g.rows
        let present = ($cs | get pos | uniq)
        let vc = ($cs | where pos == "verb" | get canon | uniq)
        let pc = ($cs | where pos == "preposition" | get canon | uniq)
        let dc = ($cs | where pos == "direction" | get canon | uniq)
        if (($vc | length) > 1) { error make {msg: $"vocabulary: '($g.word)' has multiple verb canonicals: ($vc)"} }
        if (($pc | length) > 1) { error make {msg: $"vocabulary: '($g.word)' has multiple preposition canonicals: ($pc)"} }
        if (($dc | length) > 1) { error make {msg: $"vocabulary: '($g.word)' has multiple direction canonicals: ($dc)"} }
        {
            word: $g.word,
            parts_of_speech: ($order | where {|p| $p in $present}),
            verb: ($vc | get 0?),
            preposition: ($pc | get 0?),
            direction: ($dc | get 0?)
        }
    } | sort-by word
}
