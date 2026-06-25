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

# Scan every *.zil under each zil_dir for attribute flags; write the union to
# <out_dir>/preserved/flags.nuon.
export def "zil flags" [
    zil_dirs: list<string>,
    out_dir: directory,
]: nothing -> record<flags: int, names: list<string>> {
    mut text: string = ""
    for d in $zil_dirs {
        for f in (glob ($d | path join "*.zil")) {
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

# Union the *.zil text across the given source dirs (the trilogy).
def zw-flags-text [zil_dirs: list<string>]: nothing -> string {
    mut text: string = ""
    for d in $zil_dirs {
        for f in (glob ($d | path join "*.zil")) {
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
