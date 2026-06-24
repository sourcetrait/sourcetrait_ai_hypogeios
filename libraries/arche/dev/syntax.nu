# ZIL -> arche syntax/grammar extractor: the preserve/deviate split for the verb
# grammar (dev tool; read source to use).
#
# Consume from a run()/interact() body: `use arche dev syntax *`. gsyntax is a
# SERIES engine file (the trilogy share one grammar), so syntax is SERIES data like
# flags - one extract, each rule/synonym/buzz tagged with its applicable games via
# the ZORK-NUMBER conditionals (alpha = games containing 1). Chain of custody
# (design.md; working/06,08):
#
#   zil syntax <gsyntax_zil> <world_dir>
#     PRESERVE. Parse every <SYNTAX>/<SYNONYM>/<BUZZ> form -> a raw grammar record
#     at <world_dir>/preserved/syntax.nuon (verbs/actions/find-bits/loc-flags raw;
#     games tagged). rules = the verb-pattern table; verb_synonyms / prepositions /
#     directions / buzzwords are the vocab dictionaries.
#
#   zil syntax deviate <world_dir>
#     LIGHT. Read the preserved record + deviated/flags.nuon; snake verbs / actions
#     / preps / dirs / synonyms / loc-flags; map each FIND-bit (required_flag)
#     through the flag dictionary (raw atom -> deviated snake, like an object's
#     vehicle_type). Write <world_dir>/deviated/syntax.nuon.
#
# The rules row: record<verb, object_slots, direct_preposition, direct_required_flag,
#   direct_search_locations, indirect_preposition, indirect_required_flag,
#   indirect_search_locations, action, pre_action, games>. Slot 1 = the direct object
#   (PRSO), slot 2 = the indirect (PRSI); the preposition is the bare atom before each
#   OBJECT. action = the V- handler routine; pre_action = the PRE- routine. Re-runnable.

def zw-snake [s: string]: nothing -> string {
    $s | str downcase | str replace --all "-" "_" | str replace --regex '^[^a-z0-9]+' ''
}
def zw-norm [s: string]: nothing -> string { $s | str replace --all --regex '\s+' ' ' | str trim }

# Games for a conditional op: ==? n -> [n]; N==? n -> the trilogy minus n.
def zw-games [op: string, n: int]: nothing -> list<int> {
    if $op == "==?" { [$n] } else { [1 2 3] | where {|g| $g != $n} }
}

# Look up a form's applicable games from the conditional index; default [1 2 3].
def zw-form-games [conds: table, kind: string, body: string]: nothing -> list<int> {
    let hit = ($conds | where {|c| ($c.kind == $kind) and ($c.body == $body)})
    if (($hit | length) > 0) { $hit | first | get games } else { [1 2 3] }
}

# Parse one SYNTAX body (verb [prep] OBJECT (FIND bit) (locs) ... = action [pre]).
def zw-parse-rule [body: string]: nothing -> record {
    let parts = ($body | split row "=")
    let pattern = ($parts | first | str trim)
    let acts = (if (($parts | length) > 1) { ($parts | get 1 | str trim | split row --regex '\s+' | where {|t| $t != ""}) } else { [] })
    let toks = ($pattern | parse --regex '(?<t>\([^)]*\)|[^\s()]+)' | get t)
    let verb = ($toks | first)
    mut slot = 0
    mut pend: any = null
    mut d_prep: any = null
    mut d_find: any = null
    mut d_locs: list<string> = []
    mut i_prep: any = null
    mut i_find: any = null
    mut i_locs: list<string> = []
    for tok in ($toks | skip 1) {
        if $tok == "OBJECT" {
            $slot = $slot + 1
            if $slot == 1 { $d_prep = $pend } else if $slot == 2 { $i_prep = $pend }
            $pend = null
        } else if ($tok | str starts-with "(") {
            let inner = ($tok | str replace --regex '^\((.*)\)$' '$1' | str trim)
            let itoks = ($inner | split row --regex '\s+' | where {|t| $t != ""})
            if (($itoks | first) == "FIND") {
                if $slot == 1 { $d_find = ($itoks | get 1? | default null) } else if $slot == 2 { $i_find = ($itoks | get 1? | default null) }
            } else {
                if $slot == 1 { $d_locs = $itoks } else if $slot == 2 { $i_locs = $itoks }
            }
        } else {
            $pend = $tok
        }
    }
    {verb: $verb, object_slots: $slot, direct_preposition: $d_prep, direct_required_flag: $d_find, direct_search_locations: $d_locs, indirect_preposition: $i_prep, indirect_required_flag: $i_find, indirect_search_locations: $i_locs, action: ($acts | get 0? | default null), pre_action: ($acts | get 1? | default null)}
}

# Parse the whole gsyntax file into the raw grammar record (game-tagged).
def zw-parse-grammar [gpath: string]: nothing -> record {
    let raw = (open --raw $gpath | decode)
    let conds = ($raw
        | parse --regex '(?s)<(?<op>N?==\?)\s+,ZORK-NUMBER\s+(?<n>\d+)>\s*<(?<kind>SYNTAX|SYNONYM|BUZZ)\s+(?<body>[^>]*)>'
        | each {|r| {kind: $r.kind, body: (zw-norm $r.body), games: (zw-games $r.op ($r.n | into int))} })
    let syntaxes = ($raw | parse --regex '(?s)<SYNTAX\s+(?<b>[^>]*)>' | get b | each {|s| zw-norm $s })
    let rules = ($syntaxes | each {|b| (zw-parse-rule $b) | insert games (zw-form-games $conds "SYNTAX" $b) })
    let head_end = ($raw | str index-of "<SYNTAX")
    let head = ($raw | str substring 0..$head_end)
    let compass = [NORTH SOUTH EAST WEST NE NW SE SW UP DOWN]
    let head_syn = ($head | parse --regex '(?s)<SYNONYM\s+(?<b>[^>]*)>' | get b | each {|s| zw-norm $s })
    let all_syn = ($raw | parse --regex '(?s)<SYNONYM\s+(?<b>[^>]*)>' | get b | each {|s| zw-norm $s })
    let preps = ($head_syn | where {|s| not (($s | split row " " | first) in $compass)} | each {|s| {preposition: ($s | split row " " | first), synonyms: ($s | split row " " | skip 1), games: [1 2 3]}})
    let dirs = ($head_syn | where {|s| (($s | split row " " | first) in $compass)} | each {|s| {direction: ($s | split row " " | first), synonyms: ($s | split row " " | skip 1), games: [1 2 3]}})
    let verb_syn = ($all_syn | skip ($head_syn | length) | each {|s| {verb: ($s | split row " " | first), synonyms: ($s | split row " " | skip 1), games: (zw-form-games $conds "SYNONYM" $s)}})
    let buzz = ($raw | parse --regex '(?s)<BUZZ\s+(?<b>[^>]*)>' | get b | each {|s| zw-norm $s }
        | each {|b| {words: ($b | split row " "), games: (zw-form-games $conds "BUZZ" $b)} }
        | each {|g| $g.words | each {|w| {word: $w, games: $g.games}} } | flatten)
    {rules: $rules, verb_synonyms: $verb_syn, prepositions: $preps, directions: $dirs, buzzwords: $buzz}
}

# Parse gsyntax and write the PRESERVED raw grammar record (idempotent).
export def "zil syntax" [
    gsyntax_zil: string,
    world_dir: directory,
]: nothing -> record<rules: int, verb_synonyms: int, prepositions: int, directions: int, buzzwords: int, conditional: int> {
    let g = (zw-parse-grammar $gsyntax_zil)
    let dir = ($world_dir | path join "preserved")
    mkdir $dir
    $g | to nuon --list-of-records --indent 2 | save -f ($dir | path join "syntax.nuon")
    {
        rules: ($g.rules | length), verb_synonyms: ($g.verb_synonyms | length),
        prepositions: ($g.prepositions | length), directions: ($g.directions | length),
        buzzwords: ($g.buzzwords | length),
        conditional: ($g.rules | where {|r| $r.games != [1 2 3]} | length)
    }
}

# Derive the DEVIATED grammar from the preserved form: snake everything, map the
# FIND-bit through the flag dictionary. Buzz tokens that snake to empty (the
# parser punctuation \. \, \") are dropped. Re-runnable.
export def "zil syntax deviate" [
    world_dir: directory,
]: nothing -> record<rules: int, verb_synonyms: int, prepositions: int, directions: int, buzzwords: int, unmapped_flags: list<string>> {
    let pre = (open ($world_dir | path join "preserved" "syntax.nuon"))
    let flag_map = (open ($world_dir | path join "deviated" "flags.nuon") | reduce --fold {} {|r, acc| $acc | merge {($r.preserved): $r.snake}})
    def mapflag [a: any]: nothing -> any { if $a == null { null } else { $flag_map | get -i $a } }
    mut unmapped: list<string> = []
    for r in $pre.rules {
        for f in [$r.direct_required_flag, $r.indirect_required_flag] {
            if (($f != null) and ((mapflag $f) == null)) { $unmapped = ($unmapped | append $f) }
        }
    }
    let rules = ($pre.rules | each {|r| {
        verb: (zw-snake $r.verb),
        object_slots: $r.object_slots,
        direct_preposition: (if $r.direct_preposition == null { null } else { zw-snake $r.direct_preposition }),
        direct_required_flag: (mapflag $r.direct_required_flag),
        direct_search_locations: ($r.direct_search_locations | each {|l| zw-snake $l}),
        indirect_preposition: (if $r.indirect_preposition == null { null } else { zw-snake $r.indirect_preposition }),
        indirect_required_flag: (mapflag $r.indirect_required_flag),
        indirect_search_locations: ($r.indirect_search_locations | each {|l| zw-snake $l}),
        action: (if $r.action == null { null } else { zw-snake $r.action }),
        pre_action: (if $r.pre_action == null { null } else { zw-snake $r.pre_action }),
        games: $r.games
    }})
    let verb_synonyms = ($pre.verb_synonyms | each {|s| {verb: (zw-snake $s.verb), synonyms: ($s.synonyms | each {|w| zw-snake $w}), games: $s.games}})
    let prepositions = ($pre.prepositions | each {|s| {preposition: (zw-snake $s.preposition), synonyms: ($s.synonyms | each {|w| zw-snake $w}), games: $s.games}})
    let directions = ($pre.directions | each {|s| {direction: (zw-snake $s.direction), synonyms: ($s.synonyms | each {|w| zw-snake $w}), games: $s.games}})
    let buzzwords = ($pre.buzzwords | each {|b| {word: (zw-snake $b.word), games: $b.games}} | where {|b| $b.word != ""})
    let dev = {rules: $rules, verb_synonyms: $verb_synonyms, prepositions: $prepositions, directions: $directions, buzzwords: $buzzwords}
    let dir = ($world_dir | path join "deviated")
    mkdir $dir
    $dev | to nuon --list-of-records --indent 2 | save -f ($dir | path join "syntax.nuon")
    {
        rules: ($rules | length), verb_synonyms: ($verb_synonyms | length),
        prepositions: ($prepositions | length), directions: ($directions | length),
        buzzwords: ($buzzwords | length), unmapped_flags: ($unmapped | uniq)
    }
}
