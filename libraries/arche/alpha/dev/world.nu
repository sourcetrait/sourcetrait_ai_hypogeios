# ZIL -> arche alpha (Zork I) world extractor: the preserve/deviate split (dev
# tool; read source to use).
#
# Consume from a run()/interact() body: `use arche alpha dev world *`. Two steps
# of the chain of custody (design.md Data derivation & chain of custody):
#
#   zil preserve <zil_path> <world_dir> <locale_dir> <episode>
#     The HEAVY step. Parses the episode dungeon ZIL once and writes the PRESERVED
#     (audit) form: <world_dir>/preserved/<episode>/{map,conditions}.nuon plus the
#     preserved locale rip under <locale_dir>/preserved/<episode>/room/. Preserved
#     keeps the audit-significant columns RAW - rooms.flags hold raw ZIL atoms and
#     conditions hold raw names; ids / directions / targets / globals / action are
#     snaked (canonical id form, lossless). map is FLAT/relational: rooms carry
#     scalar fields; links + blocked are sibling tables keyed by room.
#
#   zil deviate <world_dir> <episode>
#     The LIGHT step. Reads the preserved form + the deviated flag dictionary
#     (<world_dir>/deviated/flags.nuon, the agent-authored step) and writes the
#     DEVIATED (runtime const source) form:
#     <world_dir>/deviated/<episode>/{map,conditions}.nuon. Deviation re-maps the
#     flag column (raw atom -> deviated name) and snakes the conditions; everything
#     else is carried through unchanged.
#
# Locale: snake-keyed in both categories. preserve writes the PRESERVED locale
# (raw string values): room/names.yaml (snake -> DESC title), room/<snake>.md (the
# LDESC long description, source-wrap collapsed, | -> newline), room/<snake>.yaml
# (blocked + failed-gate messages, keyed direction -> message). The deviated
# (marked-up) locale is authored later with the game code. Action-described rooms
# (M-LOOK prose in 1actions, no dungeon LDESC) get a name but no .md (a follow).
# PER (function) exits resolve to a static target via the zork1 routine map in
# zw-per; an unmapped PER warns. Re-runnable. Working: iter/hypogeios/working/06.

# Snake-case a ZIL atom: lowercase, dashes to underscores.
def zw-snake [s: string]: nothing -> string {
    $s | str downcase | str replace --all "-" "_"
}

# Recover a preserved locale string value from a raw ZIL string literal's inner
# content: unescape \", collapse source line-wrapping to single spaces, turn the
# ZIL | line-break into a real newline, trim. Faithful to the rendered value.
def zw-norm [s: string]: nothing -> string {
    $s
    | str replace --regex '(?s)^"(.*)"$' '$1'
    | str replace --all '\"' '"'
    | str replace --all --regex '\s*\n\s*' ' '
    | str replace --all '|' (char nl)
    | str trim
}

# The marker index embedded in a @@S<n>@@ placeholder token.
def zw-midx [tok: string]: nothing -> int {
    $tok | parse --regex '@@S(?<n>\d+)@@' | get n.0 | into int
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

# Parse one direction prop's tokens (markered) into {link, conds, blocked, warn}.
# Conditions are kept RAW (preserve); direction + target are snaked.
def zw-exit [dir: string, toks: list<string>, room: string]: nothing -> record {
    if ($toks | is-empty) { return {link: null, conds: [], blocked: false, warn: ""} }
    let t0 = ($toks | first)
    if ($t0 | str starts-with "@@S") { return {link: null, conds: [], blocked: true, warn: ""} }
    if $t0 == "TO" {
        let target = (zw-snake ($toks | get 1))
        mut conds = []
        mut conddefs = []
        mut k = 2
        let n = ($toks | length)
        while $k < $n {
            let a = ($toks | get $k)
            if $a == "IF" {
                let craw = ($toks | get ($k + 1))
                if ((($k + 3) < $n) and (($toks | get ($k + 2)) == "IS") and (($toks | get ($k + 3)) == "OPEN")) {
                    $conds = ($conds | append $craw)
                    $conddefs = ($conddefs | append {name: $craw, kind: "door"})
                    $k = $k + 4
                } else {
                    $conds = ($conds | append $craw)
                    $conddefs = ($conddefs | append {name: $craw, kind: "flag"})
                    $k = $k + 2
                }
            } else if $a == "ELSE" { break } else { $k = $k + 1 }
        }
        return {link: {room: $target, direction: (zw-snake $dir), conditions: $conds}, conds: $conddefs, blocked: false, warn: ""}
    }
    if $t0 == "PER" {
        let routine = ($toks | get 1)
        let target = (zw-per $routine $room)
        let warn = (if ($target == null) { $"($room): unresolved PER ($routine) for ($dir)" } else { "" })
        let link = (if ($target == null) { null } else { {room: $target, direction: (zw-snake $dir), conditions: [$routine]} })
        return {link: $link, conds: [{name: $routine, kind: "fn"}], blocked: false, warn: $warn}
    }
    return {link: null, conds: [], blocked: false, warn: ""}
}

# Parse the episode dungeon ZIL and write the preserved (audit) world + locale.
export def "zil preserve" [
    zil_path: string,
    world_dir: directory,
    locale_dir: directory,
    episode: string,
]: nothing -> record<rooms: int, links: int, blocked: int, conditions: int, names: int, ldescs: int, msg_rooms: int, msgs: int, warnings: list<string>, written: list<string>> {
    let dirs = (zw-directions)
    let exit_re = ('\((?<dir>' + ($dirs | str join "|") + ')\s+(?<rest>[^)]*)\)')
    let raw = (open --raw $zil_path | decode)
    # Replace every ZIL string literal with an indexed @@S<n>@@ placeholder so the
    # structural regex parse is safe (no embedded quotes / > / )) and the locale
    # rip can recover each string by index.
    let qs = ($raw | parse --regex '(?s)(?<q>"(?:\\.|[^"\\])*")' | get q)
    mut text = $raw
    mut qi = 0
    for q in $qs {
        $text = ($text | str replace $q $"@@S($qi)@@")
        $qi = $qi + 1
    }
    let room_blocks = ($text | parse --regex '(?s)<ROOM\s+(?<body>[^>]*)>')
    mut rooms = []
    mut links = []
    mut blocked = []
    mut cond_kinds = {}
    mut warnings = []
    mut names = []
    mut ldescs = []
    mut msgs = []
    for rb in $room_blocks {
        let rname = (zw-snake ($rb.body | str trim | split row --regex '\s+' | first))
        let props = ($rb.body | parse --regex '\((?<p>[^)]*)\)')
        mut flags = []
        mut globals = []
        mut value = 0
        mut action: any = null
        for pp in $props {
            let toks = ($pp.p | str trim | split row --regex '\s+' | where {|t| $t != "" })
            if ($toks | is-empty) { continue }
            let head = ($toks | first)
            let rest = ($toks | skip 1)
            if ($head in $dirs) {
                let r = (zw-exit $head $rest $rname)
                if ($r.link != null) {
                    $links = ($links | append {room: $rname, direction: $r.link.direction, target: $r.link.room, conditions: $r.link.conditions})
                }
                if $r.blocked {
                    $blocked = ($blocked | append {room: $rname, direction: (zw-snake $head)})
                }
                for cd in $r.conds { $cond_kinds = ($cond_kinds | merge {($cd.name): $cd.kind}) }
                if ($r.warn != "") { $warnings = ($warnings | append $r.warn) }
                if (not ($rest | is-empty)) {
                    let f = ($rest | first)
                    mut mi: any = null
                    if ($f | str starts-with "@@S") {
                        $mi = (zw-midx $f)
                    } else {
                        let ei = ($rest | enumerate | where item == "ELSE" | get index.0?)
                        if (($ei != null) and (($ei + 1) < ($rest | length)) and (($rest | get ($ei + 1)) | str starts-with "@@S")) {
                            $mi = (zw-midx ($rest | get ($ei + 1)))
                        }
                    }
                    if ($mi != null) {
                        $msgs = ($msgs | append {snake: $rname, direction: (zw-snake $head), msg: (zw-norm ($qs | get $mi))})
                    }
                }
            } else if ($head == "FLAGS") {
                $flags = ($rest | where {|t| $t =~ '^[A-Z][A-Z0-9]*$'})
            } else if ($head == "VALUE") {
                $value = (try { $rest | first | into int } catch { 0 })
            } else if ($head == "GLOBAL") {
                $globals = ($rest | each {|x| zw-snake $x})
            } else if ($head == "ACTION") {
                $action = (if ($rest | is-empty) { null } else { zw-snake ($rest | first) })
            } else if ($head == "DESC") {
                if ((not ($rest | is-empty)) and (($rest | first) | str starts-with "@@S")) {
                    $names = ($names | append {snake: $rname, name: (zw-norm ($qs | get (zw-midx ($rest | first))))})
                }
            } else if ($head == "LDESC") {
                if ((not ($rest | is-empty)) and (($rest | first) | str starts-with "@@S")) {
                    $ldescs = ($ldescs | append {snake: $rname, text: (zw-norm ($qs | get (zw-midx ($rest | first))))})
                }
            }
        }
        $rooms = ($rooms | append {snake: $rname, flags: $flags, value: $value, globals: $globals, action: $action})
    }
    let conditions: table<snake: string, kind: string> = ($cond_kinds | transpose snake kind | sort-by snake)
    let rooms_out: table<snake: string, flags: list<string>, value: int, globals: list<string>, action: oneof<string, nothing>> = $rooms
    let links_out: table<room: string, direction: string, target: string, conditions: list<oneof<string, nothing>>> = $links
    let blocked_out: table<room: string, direction: string> = $blocked
    let map_out: record<rooms: table<snake: string, flags: list<string>, value: int, globals: list<string>, action: oneof<string, nothing>>, links: table<room: string, direction: string, target: string, conditions: list<oneof<string, nothing>>>, blocked: table<room: string, direction: string>> = {rooms: $rooms_out, links: $links_out, blocked: $blocked_out}
    # write preserved structured data
    let wdir = ($world_dir | path join "preserved" $episode)
    mkdir $wdir
    $map_out | to nuon --list-of-records --indent 2 | save -f ($wdir | path join "map.nuon")
    $conditions | to nuon --list-of-records --indent 2 | save -f ($wdir | path join "conditions.nuon")
    # write preserved locale (snake-keyed, raw values)
    let ldir = ($locale_dir | path join "preserved" $episode "room")
    if ($ldir | path exists) { rm --recursive --force $ldir }
    mkdir $ldir
    let names_rec = ($names | reduce --fold {} {|r, acc| $acc | merge {($r.snake): $r.name}})
    $names_rec | to yaml | save -f ($ldir | path join "names.yaml")
    for l in $ldescs {
        ($l.text + (char nl)) | save -f ($ldir | path join $"($l.snake).md")
    }
    for grp in ($msgs | group-by snake | transpose snake rows) {
        let rec = ($grp.rows | reduce --fold {} {|m, acc| $acc | merge {($m.direction): $m.msg}})
        $rec | to yaml | save -f ($ldir | path join $"($grp.snake).yaml")
    }
    {
        rooms: ($rooms | length), links: ($links | length), blocked: ($blocked | length),
        conditions: ($conditions | length), names: ($names | length), ldescs: ($ldescs | length),
        msg_rooms: ($msgs | get snake | uniq | length), msgs: ($msgs | length),
        warnings: $warnings,
        written: [($wdir | path join "map.nuon"), ($wdir | path join "conditions.nuon"), $ldir]
    }
}

# Derive the deviated (runtime const source) world from the preserved form.
# Reads <world_dir>/preserved/<episode>/{map,conditions}.nuon + the deviated flag
# dictionary <world_dir>/deviated/flags.nuon; re-maps rooms.flags (raw atom ->
# deviated name) and snakes the conditions; writes <world_dir>/deviated/<episode>/.
export def "zil deviate" [
    world_dir: directory,
    episode: string,
]: nothing -> record<rooms: int, links: int, blocked: int, conditions: int, unmapped_flags: list<string>, written: list<string>> {
    let pre = ($world_dir | path join "preserved" $episode)
    let dev = ($world_dir | path join "deviated" $episode)
    let flag_map = (open ($world_dir | path join "deviated" "flags.nuon") | reduce --fold {} {|r, acc| $acc | merge {($r.preserved): $r.snake}})
    let map = (open ($pre | path join "map.nuon"))
    let conds = (open ($pre | path join "conditions.nuon"))
    mut unmapped = []
    for r in $map.rooms {
        $unmapped = ($unmapped | append ($r.flags | where {|a| ($flag_map | get -i $a) == null}))
    }
    let rooms_out: table<snake: string, flags: list<string>, value: int, globals: list<string>, action: oneof<string, nothing>> = ($map.rooms | each {|r| {snake: $r.snake, flags: ($r.flags | each {|a| $flag_map | get -i $a} | where {|n| $n != null}), value: $r.value, globals: $r.globals, action: $r.action}})
    let links_out: table<room: string, direction: string, target: string, conditions: list<oneof<string, nothing>>> = ($map.links | each {|l| {room: $l.room, direction: $l.direction, target: $l.target, conditions: ($l.conditions | each {|c| zw-snake $c})}})
    let blocked_out: table<room: string, direction: string> = $map.blocked
    let conds_out: table<snake: string, kind: string> = ($conds | each {|c| {snake: (zw-snake $c.snake), kind: $c.kind}})
    let map_out: record<rooms: table<snake: string, flags: list<string>, value: int, globals: list<string>, action: oneof<string, nothing>>, links: table<room: string, direction: string, target: string, conditions: list<oneof<string, nothing>>>, blocked: table<room: string, direction: string>> = {rooms: $rooms_out, links: $links_out, blocked: $blocked_out}
    mkdir $dev
    $map_out | to nuon --list-of-records --indent 2 | save -f ($dev | path join "map.nuon")
    $conds_out | to nuon --list-of-records --indent 2 | save -f ($dev | path join "conditions.nuon")
    {
        rooms: ($rooms_out | length), links: ($links_out | length), blocked: ($blocked_out | length),
        conditions: ($conds_out | length), unmapped_flags: ($unmapped | uniq),
        written: [($dev | path join "map.nuon"), ($dev | path join "conditions.nuon")]
    }
}
