# ZIL -> arche (Zork trilogy) flag extractor (dev tool; read source to use).
#
# Consume from a run()/interact() body: `use arche dev flags *` then
# `zil flags <zil_dirs> <out_dir>`. Step 1 of the flag port's chain of custody:
# a MECHANICAL capture (no inference) of every object/room attribute bit used
# across the given ZIL repos, written to <out_dir>/preserved/flags.nuon
# ([{name}], raw ZIL atoms, alphabetical, union over all repos). Flags are
# series-generic - zork1-3 share the engine, so the set is captured once for the
# whole series (the common 32 + one game-specific each: NWALLBIT in II, VICBIT
# in III). Step 2 (<out_dir>/flags.nuon: our renamed + summarized + state-
# decorated flags) is authored from this + the source per flags.prompt.md;
# preserved is never modified and is not read at runtime - it documents A->B. A
# flag is any atom in a (FLAGS ...) property plus every ,<NAME>BIT reference; a
# ;"..." comment inside a FLAGS list is filtered. Re-runnable. Working:
# iter/hypogeios/working/06.

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
    let rows: table<name: string> = ($names | each {|n| {name: $n} })
    let preserved_dir = ($out_dir | path join "preserved")
    mkdir $preserved_dir
    $rows | to nuon --list-of-records --indent 2 | save -f ($preserved_dir | path join "flags.nuon")
    {flags: ($names | length), names: $names}
}
