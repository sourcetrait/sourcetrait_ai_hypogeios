# ZIL -> arche alpha (Zork I) world dataset extractor (dev tool; read source to use).
#
# Consume from a run()/interact() body: `use arche alpha dev world *` then
# `zil world <zil_path> <out_dir>`. Writes <out_dir>/map.nuon ({rooms: [{name,
# links: [{room, name, conditions}], flags, value, globals, action}]}) and
# conditions.nuon ({conditions: [{name, kind}]}, kind flag|door|fn). Blocked
# dead-ends (message-only exits) are not links; their prose belongs in locale. PER
# (function) exits resolve to a static target via the zork1 routine map in zw-per.
# All "..." strings are stripped before parsing (message prose drops to locale),
# leaving a skeleton parseable with native parse --regex + split - no char-level
# tokenizer. Re-runnable; the data is segmented per episode (out_dir = the
# episode's world dir). Working knowledge: emptwo iter/hypogeios/working/06.

# Parse a ZIL dungeon and write the world dataset; returns a summary.
export def "zil world" [
    zil_path: string,
    out_dir: string,
]: nothing -> record<rooms: int, conditions: int, links: int, blocked: int, warnings: list<string>> {
    let raw = (open --raw $zil_path | decode)
    let nostr = ($raw | str replace --all --regex '"(?:\\.|[^"\\])*"' '""')
    let room_blocks = ($nostr | parse --regex '(?s)<ROOM\s+(?<body>[^>]*)>')
    mut rooms = []
    mut cond_kinds = {}
    mut warnings = []
    mut link_total = 0
    mut blocked_total = 0
    for rb in $room_blocks {
        let rname = (zw-snake ($rb.body | str trim | split row --regex '\s+' | first))
        let props = ($rb.body | parse --regex '\((?<p>[^)]*)\)')
        mut links = []
        mut flags = []
        mut globals = []
        mut value = 0
        mut action = null
        for pp in $props {
            let toks = ($pp.p | str trim | split row --regex '\s+' | where {|t| $t != "" })
            if ($toks | is-empty) { continue }
            let head = ($toks | first)
            let rest = ($toks | skip 1)
            if ($head in (zw-directions)) {
                let r = (zw-exit $head $rest $rname)
                if ($r.link != null) {
                    $links = ($links | append $r.link)
                    $link_total = $link_total + 1
                }
                if $r.blocked { $blocked_total = $blocked_total + 1 }
                for cd in $r.conds { $cond_kinds = ($cond_kinds | merge {($cd.name): $cd.kind}) }
                if ($r.warn != "") { $warnings = ($warnings | append $r.warn) }
            } else if ($head == "FLAGS") {
                $flags = ($rest | each {|x| zw-snake $x})
            } else if ($head == "VALUE") {
                $value = (try { $rest | first | into int } catch { 0 })
            } else if ($head == "GLOBAL") {
                $globals = ($rest | each {|x| zw-snake $x})
            } else if ($head == "ACTION") {
                $action = (if ($rest | is-empty) { null } else { zw-snake ($rest | first) })
            }
        }
        $rooms = ($rooms | append {name: $rname, links: $links, flags: $flags, value: $value, globals: $globals, action: $action})
    }
    let conditions = ($cond_kinds | transpose name kind | sort-by name)
    mkdir $out_dir
    {rooms: $rooms} | to nuon | save -f ($out_dir | path join "map.nuon")
    {conditions: $conditions} | to nuon | save -f ($out_dir | path join "conditions.nuon")
    {rooms: ($rooms | length), conditions: ($conditions | length), links: $link_total, blocked: $blocked_total, warnings: $warnings}
}

# Snake-case a ZIL atom: lowercase, dashes to underscores.
def zw-snake [s: string]: nothing -> string {
    $s | str downcase | str replace --all "-" "_"
}

# The ZIL movement directions that head a room exit prop.
def zw-directions []: nothing -> list<string> {
    ["NORTH" "SOUTH" "EAST" "WEST" "NE" "NW" "SE" "SW" "UP" "DOWN" "IN" "OUT" "LAND"]
}

# Resolve a PER (function) exit to its static target room (zork1 routines).
def zw-per [routine: string, room: string]: nothing -> any {
    let maze = {maze_2: "maze_4", maze_7: "dead_end_1", maze_9: "maze_11", maze_12: "maze_5"}
    let fixed = {"GRATING-EXIT": "grating_room", "TRAP-DOOR-EXIT": "cellar", "UP-CHIMNEY-FUNCTION": "kitchen"}
    if $routine == "MAZE-DIODES" { $maze | get -i $room } else { $fixed | get -i $routine }
}

# Parse one direction prop's tokens into {link, conds, blocked, warn}.
def zw-exit [dir: string, toks: list<string>, room: string]: nothing -> record {
    if ($toks | is-empty) { return {link: null, conds: [], blocked: false, warn: ""} }
    let t0 = ($toks | first)
    if ($t0 | str starts-with '"') { return {link: null, conds: [], blocked: true, warn: ""} }
    if $t0 == "TO" {
        let target = (zw-snake ($toks | get 1))
        mut conds = []
        mut conddefs = []
        mut k = 2
        let n = ($toks | length)
        while $k < $n {
            let a = ($toks | get $k)
            if $a == "IF" {
                let cname = (zw-snake ($toks | get ($k + 1)))
                if ((($k + 3) < $n) and (($toks | get ($k + 2)) == "IS") and (($toks | get ($k + 3)) == "OPEN")) {
                    $conds = ($conds | append $cname)
                    $conddefs = ($conddefs | append {name: $cname, kind: "door"})
                    $k = $k + 4
                } else {
                    $conds = ($conds | append $cname)
                    $conddefs = ($conddefs | append {name: $cname, kind: "flag"})
                    $k = $k + 2
                }
            } else if $a == "ELSE" { break } else { $k = $k + 1 }
        }
        return {link: {room: $target, name: (zw-snake $dir), conditions: $conds}, conds: $conddefs, blocked: false, warn: ""}
    }
    if $t0 == "PER" {
        let routine = ($toks | get 1)
        let cond = (zw-snake $routine)
        let target = (zw-per $routine $room)
        let warn = (if ($target == null) { $"($room): unresolved PER ($routine) for ($dir)" } else { "" })
        let link = (if ($target == null) { null } else { {room: $target, name: (zw-snake $dir), conditions: [$cond]} })
        return {link: $link, conds: [{name: $cond, kind: "fn"}], blocked: false, warn: $warn}
    }
    return {link: null, conds: [], blocked: false, warn: ""}
}
