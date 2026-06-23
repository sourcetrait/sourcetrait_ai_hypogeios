# ZIL -> arche alpha (Zork I) world dataset extractor (dev tool; read source to use).
#
# Consume from a run()/interact() body: `use arche alpha dev world *` then
# `zil world <zil_path> <out_dir>`. <out_dir> is the episode dir
# (.../world/<episode>); the series flags.nuon (.../world/flags.nuon, one level
# up) is read so each room's raw ZIL attribute atom maps to our redesigned flag
# name - map.nuon is the FINAL product, never preserved atoms.
#
# Writes <out_dir>/map.nuon (record<rooms, links, blocked>) + conditions.nuon
# (table<name, kind>). The map is FLAT/relational: rooms carry scalar fields
# (flags, value, globals, action); links + blocked are sibling tables keyed by
# room (a room with none contributes no rows). The nested per-room table-column
# form is deliberately avoided - an empty [] for a table-typed column infers
# list<any> and cannot be strict-typed as a generated const (working/06).
# rooms.flags are redesigned names (preserved atom -> flags.nuon name),
# bareword-filtered so a ;"..." comment inside (FLAGS ...) is dropped. blocked
# captures message-only exit directions per room (the prose is locale, keyed by
# room+direction). PER (function) exits resolve to a static target via the zork1
# routine map in zw-per; an unmapped PER warns. All "..." strings are stripped
# before parsing (message prose drops to locale), leaving a skeleton parseable
# with native parse --regex + split. Re-runnable. Working: iter/hypogeios/working/06.

# Parse a ZIL dungeon and write the flat world dataset; returns a summary.
export def "zil world" [
    zil_path: string,
    out_dir: string,
]: nothing -> record<rooms: int, links: int, blocked: int, conditions: int, warnings: list<string>, unmapped_flags: list<string>> {
    let flags_path = ($out_dir | path dirname | path join "flags.nuon")
    if not ($flags_path | path exists) {
        error make {msg: $"zil world: series flags.nuon not found at ($flags_path) - generate + author it first"}
    }
    let flag_map = (open $flags_path | reduce --fold {} {|row, acc| $acc | merge {($row.preserved): $row.name}})
    let raw = (open --raw $zil_path | decode)
    let nostr = ($raw | str replace --all --regex '"(?:\\.|[^"\\])*"' '""')
    let room_blocks = ($nostr | parse --regex '(?s)<ROOM\s+(?<body>[^>]*)>')
    mut rooms = []
    mut links = []
    mut blocked = []
    mut cond_kinds = {}
    mut warnings = []
    mut unmapped = []
    for rb in $room_blocks {
        let rname = (zw-snake ($rb.body | str trim | split row --regex '\s+' | first))
        let props = ($rb.body | parse --regex '\((?<p>[^)]*)\)')
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
                    $links = ($links | append {room: $rname, name: $r.link.name, target: $r.link.room, conditions: $r.link.conditions})
                }
                if $r.blocked {
                    $blocked = ($blocked | append {room: $rname, name: (zw-snake $head)})
                }
                for cd in $r.conds { $cond_kinds = ($cond_kinds | merge {($cd.name): $cd.kind}) }
                if ($r.warn != "") { $warnings = ($warnings | append $r.warn) }
            } else if ($head == "FLAGS") {
                let atoms = ($rest | where {|t| $t =~ '^[A-Z][A-Z0-9]*$'})
                $unmapped = ($unmapped | append ($atoms | where {|a| ($flag_map | get -i $a) == null}))
                $flags = ($atoms | each {|a| $flag_map | get -i $a} | where {|n| $n != null})
            } else if ($head == "VALUE") {
                $value = (try { $rest | first | into int } catch { 0 })
            } else if ($head == "GLOBAL") {
                $globals = ($rest | each {|x| zw-snake $x})
            } else if ($head == "ACTION") {
                $action = (if ($rest | is-empty) { null } else { zw-snake ($rest | first) })
            }
        }
        $rooms = ($rooms | append {name: $rname, flags: $flags, value: $value, globals: $globals, action: $action})
    }
    let conditions: table<name: string, kind: string> = ($cond_kinds | transpose name kind | sort-by name)
    let rooms_out: table<name: string, flags: list<string>, value: int, globals: list<string>, action: oneof<string, nothing>> = $rooms
    let links_out: table<room: string, name: string, target: string, conditions: list<oneof<string, nothing>>> = $links
    let blocked_out: table<room: string, name: string> = $blocked
    let map_out: record<rooms: table<name: string, flags: list<string>, value: int, globals: list<string>, action: oneof<string, nothing>>, links: table<room: string, name: string, target: string, conditions: list<oneof<string, nothing>>>, blocked: table<room: string, name: string>> = {rooms: $rooms_out, links: $links_out, blocked: $blocked_out}
    mkdir $out_dir
    $map_out | to nuon --list-of-records --indent 2 | save -f ($out_dir | path join "map.nuon")
    $conditions | to nuon --list-of-records --indent 2 | save -f ($out_dir | path join "conditions.nuon")
    {rooms: ($rooms | length), links: ($links | length), blocked: ($blocked | length), conditions: ($conditions | length), warnings: $warnings, unmapped_flags: ($unmapped | uniq)}
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
