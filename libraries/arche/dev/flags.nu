# ZIL -> arche (Zork trilogy) flag extractor + deviator (dev tool; read source).
#
# Consume from a run()/interact() body: `use arche dev flags *`. The flag port's
# chain of custody - BOTH steps mechanical, no agent (followups #5):
#
#   zil flags <zil_dirs> <out_dir>
#     PRESERVE. A mechanical capture of every object/room attribute bit across the
#     given ZIL repos -> <out_dir>/preserved/flags.nuon (list<string>, raw ZIL
#     atoms, alphabetical, union over all repos). Series-generic - zork1-3 share the
#     engine, so the set is captured once (the common 32 + one game-specific each:
#     NWALLBIT in II, VICBIT in III = 34). A flag is any atom in a (FLAGS ...)
#     property plus every ,<NAME>BIT reference; a ;"..." comment token is filtered.
#
#   zil flags deviate <zil_dirs> <out_dir> <gloss_path> <pin_path>
#     ASSEMBLE -> <out_dir>/deviated/flags.nuon (table<snake, preserved, summary,
#     state>). Mechanical assembly over committed inputs + a source scan:
#       - snake:     from the pins (pin_path = flags.pin.txt: preserved -> snake).
#       - preserved: the raw atom (preserved/flags.nuon supplies the set + order).
#       - summary:   from the committed gloss (the one-time human one-liner).
#       - state:     null (STATIC) or {default: false, scope} (RUNTIME). Presence is
#         DERIVED: a flag is runtime iff it is FSET/FCLEAR'd (BSET/BCLEAR macros
#         included) on a target OTHER than ,PLAYER - the ,PLAYER flips are the
#         parser's own noun-resolution toggles (e.g. TRANSBIT), engine-internal not
#         gameplay state. scope is the committed gloss scope (does not mechanize -
#         object-vs-actor + computed targets need judgment); default is always false.
#         Verified: reproduces the committed 18 runtime / 16 static split, 0 error.
#     The gloss (summary + scope) is the only human-authored input, lifted once into
#     .assets/dev/flags/flags.gloss.nuon beside the pins; both are committed INPUTS,
#     never regenerated. preserved/ is audit-only, never read at runtime. Re-runnable.
#     Working: iter/hypogeios/working/06.

# The COMPILED *.zil of one game repo: the master zork<N>.zil plus every file it
# INSERT-FILEs (the G* engine + <N>dungeon + <N>actions). Excludes the loose
# legacy *.zil a repo may carry uncompiled (zork3's verbs/syntax/etc.), so flags
# only ever come from what actually ships. INSERT-FILE names are uppercase with no
# extension; on-disk files are lowercase + .zil.
def zw-compiled-zils [zil_dir: directory]: nothing -> list<string> {
    mut files: list<string> = []
    for master in (glob ($zil_dir | path join "zork*.zil")) {
        let inserts = (open --raw $master | decode
            | parse --regex '<INSERT-FILE\s+"(?<n>[^"]+)"' | get n)
        if (($inserts | length) > 0) {
            $files = ($files | append $master)
            for n in $inserts {
                let f = ($zil_dir | path join $"($n | str downcase).zil")
                if ($f | path exists) { $files = ($files | append $f) }
            }
        }
    }
    $files | uniq
}

# Scan the COMPILED *.zil under each zil_dir for attribute flags; write the union
# to <out_dir>/preserved/flags.nuon. Only INSERT-FILE'd files are scanned (via
# zw-compiled-zils), so an atom from an uncompiled legacy file (e.g. zork3
# verbs.zil's VICBIT) never enters the dictionary.
export def "zil flags" [
    zil_dirs: list<string>,
    out_dir: directory,
]: nothing -> record<flags: int, names: list<string>> {
    mut text: string = ""
    for d in $zil_dirs {
        for f in (zw-compiled-zils $d) {
            $text = ($text + (open --raw $f | decode) + (char nl))
        }
    }
    # Atoms declared inside (FLAGS ...) on objects/rooms (catches the non-BIT
    # flags INVISIBLE + STAGGERED); a comment token like ;"CANT-HAVE-ONBIT" is
    # dropped by the bare-atom filter.
    let in_flags: list<string> = ($text
        | parse --regex '\(FLAGS\s+(?<b>[^)]*)\)'
        | get b
        | each {|s| $s | split row --regex '\s+' | where {|t| ($t | str trim) != "" } }
        | flatten
        | where {|t| $t =~ '^[A-Z][A-Z0-9]*$' })
    # ,<NAME>BIT references in FSET?/FSET/FCLEAR and tests.
    let bit_refs: list<string> = ($text
        | parse --regex ',(?<f>[A-Z][A-Z0-9]*BIT)'
        | get f)
    let names: list<string> = ($in_flags | append $bit_refs | uniq | sort)
    let preserved_dir = ($out_dir | path join "preserved")
    mkdir $preserved_dir
    $names | to nuon --indent 2 | save -f ($preserved_dir | path join "flags.nuon")
    {flags: ($names | length), names: $names}
}

# Union the COMPILED *.zil text across the given source dirs (the trilogy) - only
# the files each game INSERT-FILEs (zw-compiled-zils), never the loose uncompiled
# legacy *.zil.
def zw-flags-text [zil_dirs: list<string>]: nothing -> string {
    mut text: string = ""
    for d in $zil_dirs {
        for f in (zw-compiled-zils $d) {
            $text = ($text + (open --raw $f | decode) + (char nl))
        }
    }
    $text
}

# The RUNTIME flag atoms: any bit FSET/FCLEAR'd (BSET/BCLEAR macros included) on a
# target OTHER than ,PLAYER. The ,PLAYER mutations are the parser's own internal
# flips (e.g. the TRANSBIT noun-resolution toggle), engine-internal not gameplay
# state, so they are excluded - this reproduces the committed null-vs-runtime split.
def zw-runtime-flags [zil_dirs: list<string>]: nothing -> list<string> {
    (zw-flags-text $zil_dirs)
    | parse --regex '(?s)<(?:FSET|FCLEAR|BSET|BCLEAR)\s+(?<target>,[A-Z0-9-]+|\.[A-Z0-9-]+|<[^>]*>)\s+,(?<bit>[A-Z][A-Z0-9-]*)\s*>'
    | where {|e| $e.target != ",PLAYER"}
    | get bit
    | uniq
}

# Parse the pin file ("PRESERVED snake" per line) into a {preserved: snake} map.
def zw-pin-map [pin_path: path]: nothing -> record {
    open --raw $pin_path | decode | lines
    | where {|l| ($l | str trim) != ""}
    | reduce --fold {} {|l, acc|
        let p = ($l | split row --regex '\s+' | where {|t| $t != ""})
        $acc | merge {($p | first): ($p | get 1)}
    }
}

# Assemble the DEVIATED flag dictionary from committed inputs + a source scan.
#
# preserved/flags.nuon supplies the atom set + order; pin_path the snakes; gloss_path
# the summary + scope (the human-authored bits); a FSET/FCLEAR scan over zil_dirs the
# runtime-vs-static presence (default always false). Writes deviated/flags.nuon
# (table<snake, preserved, summary, state>, preserved order). Hard-errors on a missing
# pin, a missing gloss, or a runtime flag with no committed scope - surfacing input
# drift rather than emitting a wrong dictionary.
export def "zil flags deviate" [
    zil_dirs: list<string>,
    out_dir: directory,
    gloss_path: path,
    pin_path: path,
]: nothing -> record<flags: int, runtime: int, static: int> {
    let atoms = (open ($out_dir | path join "preserved" "flags.nuon"))
    let pin_map = (zw-pin-map $pin_path)
    let gloss_map = (open $gloss_path
        | reduce --fold {} {|r, acc| $acc | merge {($r.snake): {summary: $r.summary, scope: $r.scope}}})
    let runtime = (zw-runtime-flags $zil_dirs)
    let rows = ($atoms | each {|atom|
        let snake = ($pin_map | get -i $atom)
        let gloss = (if ($snake == null) { null } else { $gloss_map | get -i $snake })
        {atom: $atom, snake: $snake, gloss: $gloss, runtime: ($atom in $runtime)}
    })
    let missing_pin = ($rows | where {|r| $r.snake == null} | get atom)
    if (($missing_pin | length) > 0) {
        error make {msg: $"zil flags deviate: no pin for ($missing_pin | str join ', ')"}
    }
    let missing_gloss = ($rows | where {|r| $r.gloss == null} | get snake)
    if (($missing_gloss | length) > 0) {
        error make {msg: $"zil flags deviate: no gloss for ($missing_gloss | str join ', ')"}
    }
    let unscoped = ($rows | where {|r| $r.runtime and ($r.gloss.scope | is-empty)} | get snake)
    if (($unscoped | length) > 0) {
        error make {msg: $"zil flags deviate: runtime flag missing a committed scope: ($unscoped | str join ', ')"}
    }
    let deviated = ($rows | each {|r|
        let state = (if $r.runtime { {default: false, scope: $r.gloss.scope} } else { null })
        {snake: $r.snake, preserved: $r.atom, summary: $r.gloss.summary, state: $state}
    })
    let dir = ($out_dir | path join "deviated")
    mkdir $dir
    $deviated | to nuon --list-of-records --indent 2 | save -f ($dir | path join "flags.nuon")
    {
        flags: ($deviated | length),
        runtime: ($deviated | where {|r| $r.state != null} | length),
        static: ($deviated | where {|r| $r.state == null} | length),
    }
}

# Build the per-flag SOURCE-ANALYSIS TRAIL for every preserved atom across the
# COMPILED trilogy; write <out_dir>/preserved/flag_usage.nuon. A "preserved"
# analysis: pure mechanical grep evidence, audit-only, never loaded by the engine.
# It grounds the summary/scope authoring - the subagent READS this file instead of
# re-deriving each flag's usage blind. Per atom: declared_on (<FLAGS ...> static
# attribute, with its OBJECT/ROOM owner), references (FSET/FCLEAR/FSET? + B* macros
# on a target: operation set|clear|test + the operand + its form global,X|local.X +
# the enclosing routine), grammar_finds (<SYNTAX ... (FIND atom) ...>), value_refs
# (the atom used as a bare value, e.g. GWIM mapping it to ,ROOMS). `games` is the
# set of games (1|2|3) whose compiled source carries the logically-identical site -
# a shared engine file merges to [1 2 3], a per-episode file stays [N]. Targets are
# captured raw (a local .var is resolved by reading its routine, not here).
# Re-runnable. (Multi-line (FLAGS ...) is captured across continuation lines; a
# multi-line FSET form may still leave a continuation fragment as a value_ref.)
export def analyze_flag_usage [
    zil_dirs: list<string>,
    preserved_flags: list<string>,
    out_dir: directory,
]: nothing -> record<written: string, flags: int, declarations: int, references: int, grammar_finds: int, value_refs: int> {
    let flagset = ($preserved_flags | uniq)
    let needles = (["BIT"] ++ ($flagset | where {|a| not ($a | str ends-with "BIT")}))
    mut decl = []
    mut refs = []
    mut gfinds = []
    mut vals = []
    for d in $zil_dirs {
        let game = ($d | path basename | parse --regex 'zork(?<n>\d)' | get n.0 | into int)
        for f in (zw-compiled-zils $d) {
            let base = ($f | path basename)
            mut ctx = ""
            mut in_flags = false
            mut flags_owner = ""
            for raw in (open --raw $f | decode | lines) {
                let t = ($raw | str trim)
                if (($t | str starts-with "<ROUTINE ") or ($t | str starts-with "<OBJECT ") or ($t | str starts-with "<ROOM ")) {
                    $ctx = ($t | parse --regex '^<[A-Z]+\s+(?<name>[A-Z0-9?-]+)' | get name.0? | default $ctx)
                    $in_flags = false
                }
                if $in_flags {
                    for a in (($t | split row ")" | first) | split row --regex '\s+' | where {|x| $x != ""}) {
                        if ($a in $flagset) { $decl = ($decl | append {atom: $a, owner: $flags_owner, game: $game, file: $base}) }
                    }
                    if ($t | str contains ")") { $in_flags = false }
                    continue
                }
                if not ($needles | any {|nd| $t | str contains $nd}) { continue }
                let pflags = ($t | parse --regex '\(FLAGS\s+(?<body>[^)]*)')
                let pfset = ($t | parse --regex '<(?<o>FSET\?|FSET|FCLEAR|BSET\?|BSET|BCLEAR)\s+(?<tg>\S+)\s+,(?<bit>[A-Z][A-Z0-9-]*)')
                let pfind = ($t | parse --regex '\(FIND\s+(?<bit>[A-Z][A-Z0-9-]*)')
                if (($pflags | length) > 0) {
                    for a in ($pflags | get body | first | split row --regex '\s+' | where {|x| $x != ""}) {
                        if ($a in $flagset) { $decl = ($decl | append {atom: $a, owner: $ctx, game: $game, file: $base}) }
                    }
                    if not ($t | str contains ")") { $in_flags = true; $flags_owner = $ctx }
                } else if (($pfset | length) > 0) {
                    for m in $pfset {
                        if ($m.bit in $flagset) {
                            let oper = (if ($m.o | str ends-with "?") { "test" } else if (($m.o | str starts-with "FC") or ($m.o | str starts-with "BC")) { "clear" } else { "set" })
                            let form = (if ($m.tg | str starts-with ",") { "global" } else if ($m.tg | str starts-with ".") { "local" } else { "other" })
                            $refs = ($refs | append {atom: $m.bit, operation: $oper, target: $m.tg, target_form: $form, routine: $ctx, game: $game, file: $base, source: $t})
                        }
                    }
                } else if (($pfind | length) > 0) {
                    for m in $pfind {
                        if ($m.bit in $flagset) { $gfinds = ($gfinds | append {atom: $m.bit, rule: $t, game: $game, file: $base}) }
                    }
                } else {
                    for m in ($t | parse --regex ',(?<bit>[A-Z][A-Z0-9-]*)') {
                        if ($m.bit in $flagset) { $vals = ($vals | append {atom: $m.bit, routine: $ctx, game: $game, file: $base, source: $t}) }
                    }
                }
            }
        }
    }
    let dedup = {|rows, keys|
        if ($rows | is-empty) { [] } else {
            $rows | group-by {|r| $keys | each {|k| ($r | get $k | into string)} | str join "\u{1e}"} | values | each {|grp|
                ($grp | first | reject game | merge {games: ($grp | get game | uniq | sort)})
            }
        }
    }
    let decl_d = (do $dedup $decl [atom owner file])
    let refs_d = (do $dedup $refs [atom operation target target_form routine file source])
    let gfinds_d = (do $dedup $gfinds [atom rule file])
    let vals_d = (do $dedup $vals [atom routine file source])
    let trail = ($flagset | sort | each {|a|
        {
            preserved: $a,
            declared_on: ($decl_d | where atom == $a | each {|r| {owner: $r.owner, games: $r.games, file: $r.file}}),
            references: ($refs_d | where atom == $a | each {|r| {operation: $r.operation, target: $r.target, target_form: $r.target_form, routine: $r.routine, games: $r.games, file: $r.file, source: $r.source}}),
            grammar_finds: ($gfinds_d | where atom == $a | each {|r| {rule: $r.rule, games: $r.games, file: $r.file}}),
            value_refs: ($vals_d | where atom == $a | each {|r| {routine: $r.routine, games: $r.games, file: $r.file, source: $r.source}})
        }
    })
    let dir = ($out_dir | path join "preserved")
    mkdir $dir
    let path = ($dir | path join "flag_usage.nuon")
    $trail | to nuon --indent 2 | save -f $path
    {
        written: $path,
        flags: ($trail | length),
        declarations: ($decl_d | length),
        references: ($refs_d | length),
        grammar_finds: ($gfinds_d | length),
        value_refs: ($vals_d | length)
    }
}
