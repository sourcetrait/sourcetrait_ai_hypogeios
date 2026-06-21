# nuzork game engine. Increment 0: session state, parser core, LOOK, movement,
# and the room display. Ported against ~/repo/zork (see the harness working
# knowledge iter/nuzork/working/zorkcpp). Verb handlers expand incrementally.
use ./data_rooms.nu *
use ./data_objects.nu *
use ./data_vocab.nu *

# --- static-world lookups -------------------------------------------------
export def find-room [rid: string]: nothing -> any {
    let m = ($ROOMS | where rid == $rid)
    if ($m | is-empty) { null } else { $m | first }
}
export def find-obj [oid: string]: nothing -> any {
    let m = ($OBJECTS | where oid == $oid)
    if ($m | is-empty) { null } else { $m | first }
}

# --- new game -------------------------------------------------------------
# Materialize the live world: loc (oid -> {at,id}) from static placement, and
# oflags (oid -> [bit]) from static bits. Mutations overwrite these in place.
export def new-state []: nothing -> record {
    { here: "WHOUS", moves: 0, score: 0, deaths: 0, seen: [], moved: {}, oflags: {}, flags: {} }
}

# Object location is the static data placement, overridden by `moved` for any
# object that has moved (shared boundary objects stay in both static rooms).
export def obj-moved [state: record, oid: string]: nothing -> any {
    if ($oid in ($state.moved | columns)) { $state.moved | get $oid } else { null }
}

# --- flag helpers ---------------------------------------------------------
export def oflag [state: record, oid: string, bit: string]: nothing -> bool {
    let cur = (if ($oid in ($state.oflags | columns)) { $state.oflags | get $oid } else { (find-obj $oid).bits })
    $bit in $cur
}
export def gflag [state: record, name: string]: nothing -> bool {
    ($name in ($state.flags | columns)) and (($state.flags | get $name) == true)
}

# --- objects currently in a room -----------------------------------------
export def room-objs [state: record, rid: string]: nothing -> list {
    let r = (find-room $rid)
    let stat = (if $r == null { [] } else { $r.contents | where {|o|
        let m = (obj-moved $state $o); ($m == null) or (($m.at == "room") and ($m.id == $rid))
    } })
    let movedin = ($state.moved | transpose o p | where {|x| ($x.p.at == "room") and ($x.p.id == $rid) } | get o)
    ($stat | append $movedin | uniq)
}

# --- one object's listing line (room_info full=3 path) --------------------
export def obj-line [state: record, oid: string]: nothing -> string {
    let o = (find-obj $oid)
    let odesco = ($o.odesco? | default "")
    let odesc1 = ($o.odesc1? | default "")
    if ((not (oflag $state $oid "touchbit")) and ($odesco != "")) { $odesco
    } else if ($odesc1 != "") { $odesc1
    } else { $"There is a ($o.desc) here." }
}

# --- room-function descriptions (empty-desc1 rooms that are reachable) ----
export def room-fn-desc [state: record, roomf: string]: nothing -> list {
    if $roomf == "east_house" {
        let w = (if (oflag $state "WINDO" "openbit") { "open." } else { "slightly ajar." })
        [$"You are behind the white house.  In one corner of the house there\nis a small window which is ($w)"]
    } else if $roomf == "clearing" {
        mut o = ["You are in a clearing, with a forest surrounding you on the west\nand south."]
        if (oflag $state "GRATE" "openbit") {
            $o = ($o | append "There is an open grating, descending into darkness.")
        } else if (gflag $state "grate_revealed") {
            $o = ($o | append "There is a grating securely fastened into the ground.")
        }
        $o
    } else if $roomf == "kitchen" {
        let w = (if (oflag $state "WINDO" "openbit") { "open." } else { "slightly ajar." })
        [$"You are in the kitchen of the white house.  A table seems to have\nbeen used recently for the preparation of food.  A passage leads to\nthe west and a dark staircase can be seen leading upward.  To the\neast is a small window which is ($w)"]
    } else if $roomf == "living_room" {
        let door_open = (oflag $state "DOOR" "openbit")
        let rug_moved = (gflag $state "rug_moved")
        let base = (if (gflag $state "magic_flag") {
            "You are in the living room.  There is a door to the east.  To the\nwest is a cyclops-shaped hole in an old wooden door, above which is\nsome strange gothic lettering "
        } else {
            "You are in the living room.  There is a door to the east, a wooden\ndoor with strange gothic lettering to the west, which appears to be\nnailed shut, "
        })
        let status = (if ($rug_moved and $door_open) { "and a rug lying beside an open trap-door."
            } else if $rug_moved { "and a closed trap-door at your feet."
            } else if $door_open { "and an open trap-door at your feet."
            } else { "and a large oriental rug in the center of the room." })
        [($base + $status)]
    } else { [] }
}

# --- room display (room_info, full=3) -------------------------------------
export def room-info [state: record]: nothing -> record {
    let rm = (find-room $state.here)
    mut out = [$rm.desc2]
    if ($rm.desc1 == "") {
        if ($rm.roomf != null) { $out = ($out | append (room-fn-desc $state $rm.roomf)) }
    } else {
        $out = ($out | append $rm.desc1)
    }
    for oid in (room-objs $state $state.here) {
        if ((oflag $state $oid "ovison") and (not (oflag $state $oid "ndescbit"))) {
            $out = ($out | append (obj-line $state $oid))
        }
    }
    { state: ($state | update seen ($state.seen | append $state.here | uniq)), out: $out }
}

# --- lexer: input -> tokens (uppercase, 5-char truncated) -----------------
export def lex [input: string]: nothing -> list {
    $input | str upcase | split row -r '[^A-Z0-9]+' | where {|w| $w != "" } | each {|w| $w | split chars | first 5 | str join }
}

# --- parse: input -> {verb, dir?, rest?, msg?} ----------------------------
export def parse-cmd [state: record, input: string]: nothing -> record {
    let toks = (lex $input)
    if ($toks | is-empty) { return { verb: null, msg: null } }
    let first = ($toks | first)
    if ($first in ($DIRS | columns)) { return { verb: "WALK", dir: ($DIRS | get $first) } }
    if ($first not-in ($VERBS | columns)) {
        return { verb: null, msg: $"I don't know the word '($first | str downcase)'." }
    }
    let v = ($VERBS | get $first)
    let rest = ($toks | skip 1 | where {|t| $t not-in $NOISE })
    if $v == "WALK" {
        let d = (if ($rest | is-empty) { null
            } else if (($rest | first) in ($DIRS | columns)) { $DIRS | get ($rest | first)
            } else { null })
        return { verb: "WALK", dir: $d }
    }
    { verb: $v, rest: $rest }
}

# --- movement -------------------------------------------------------------
export def do-walk [state: record, dir: any]: nothing -> record {
    if $dir == null { return { state: $state, out: ["You can't go that way."] } }
    let rm = (find-room $state.here)
    let exm = ($rm.exits | where dir == $dir)
    if ($exm | is-empty) { return { state: $state, out: ["You can't go that way."] } }
    let to = ($exm | first | get to)
    if $to.kind == "room" {
        let ri = (room-info ($state | update here $to.to))
        { state: $ri.state, out: $ri.out }
    } else if $to.kind == "nexit" {
        { state: $state, out: [$to.msg] }
    } else if $to.kind == "door" {
        if (oflag $state $to.obj "openbit") {
            let dest = (if $to.rm1 == $state.here { $to.rm2 } else { $to.rm1 })
            let ri = (room-info ($state | update here $dest))
            { state: $ri.state, out: $ri.out }
        } else {
            { state: $state, out: [(if ($to.msg == "") { "You can't go that way." } else { $to.msg })] }
        }
    } else if $to.kind == "cexit" {
        if (($to.flag != null) and (gflag $state $to.flag) and ($to.to != null)) {
            let ri = (room-info ($state | update here $to.to))
            { state: $ri.state, out: $ri.out }
        } else {
            { state: $state, out: [(if ($to.msg == "") { "You can't go that way." } else { $to.msg })] }
        }
    } else {
        { state: $state, out: ["You can't go that way."] }
    }
}

# --- object resolution ----------------------------------------------------
export def player-inv [state: record]: nothing -> list {
    $state.moved | transpose o p | where {|r| $r.p.at == "player" } | get o
}
export def cont-of [state: record, oid: string]: nothing -> list {
    let o = (find-obj $oid)
    let stat = (if $o == null { [] } else { $o.contents | where {|c|
        let m = (obj-moved $state $c); ($m == null) or (($m.at == "cont") and ($m.id == $oid))
    } })
    let movedin = ($state.moved | transpose o2 p | where {|x| ($x.p.at == "cont") and ($x.p.id == $oid) } | get o2)
    ($stat | append $movedin | uniq)
}
export def resolve-obj [state: record, name: string]: nothing -> any {
    let reach = ((room-objs $state $state.here) | append (player-inv $state))
    let nested = ($reach | each {|oid|
        if ((oflag $state $oid "openbit") or (oflag $state $oid "transbit")) { cont-of $state $oid } else { [] }
    } | flatten)
    let m = (($reach | append $nested | uniq) | where {|oid| $name in (find-obj $oid).syns })
    if ($m | is-empty) { null } else { $m | first }
}
export def resolve-name [state: record, names: list]: nothing -> any {
    mut found = null
    for n in $names { if ($found == null) { $found = (resolve-obj $state $n) } }
    $found
}

# --- state mutators -------------------------------------------------------
export def set-oflag [state: record, oid: string, bit: string, on: bool]: nothing -> record {
    let cur = (if ($oid in ($state.oflags | columns)) { $state.oflags | get $oid } else { (find-obj $oid).bits })
    let new = (if $on { $cur | append $bit | uniq } else { $cur | where {|b| $b != $bit } })
    $state | update oflags ($state.oflags | upsert $oid $new)
}
export def set-loc [state: record, oid: string, place: record]: nothing -> record {
    $state | update moved ($state.moved | upsert $oid $place)
}

# --- "a X, a Y, and a Z" / "a X and a Y" / "a X" (C++ print_contents) ------
export def print-list [items: list]: nothing -> string {
    mut s = ""
    mut count = ($items | length)
    for it in $items {
        $s = $s + $it
        if $count > 2 { $s = $s + ", " } else if $count == 2 { $s = $s + " and " }
        $count = $count - 1
    }
    $s
}

# --- object verbs ---------------------------------------------------------
# Dispatch a verb to a ported object-function. handled=false -> generic verb.
export def obj-fn [state: record, oid: string, verb: string]: nothing -> record {
    let fn = ((find-obj $oid).objfn? | default null)
    if $fn == "window_function" {
        if $verb == "OPEN" {
            if (oflag $state $oid "openbit") { { handled: true, state: $state, out: ["It is already open."] }
            } else { { handled: true, state: (set-oflag $state $oid "openbit" true), out: ["With great effort, you open the window far enough to allow entry."] } }
        } else if $verb == "CLOSE" {
            { handled: true, state: (set-oflag $state $oid "openbit" false), out: ["The window closes (more easily than it opened)."] }
        } else { { handled: false, state: $state, out: [] } }
    } else if $fn == "ddoor_function" {
        if $verb == "OPEN" { { handled: true, state: $state, out: ["The door cannot be opened."] }
        } else { { handled: false, state: $state, out: [] } }
    } else { { handled: false, state: $state, out: [] } }
}
export def do-open [state: record, oid: any]: nothing -> record {
    if $oid == null { return { state: $state, out: ["You can't see that here."] } }
    let f = (obj-fn $state $oid "OPEN")
    if $f.handled { return { state: $f.state, out: $f.out } }
    let o = (find-obj $oid)
    if (not (oflag $state $oid "contbit")) {
        { state: $state, out: [$"You must tell me how to do that to a ($o.desc)."] }
    } else if (($o.ocapac? | default 0) == 0) {
        { state: $state, out: [$"The ($o.desc) cannot be opened."] }
    } else if (oflag $state $oid "openbit") {
        { state: $state, out: ["It is already open."] }
    } else {
        let st = (set-oflag $state $oid "openbit" true)
        let contents = (cont-of $st $oid)
        if (($contents | is-empty) or (oflag $st $oid "transbit")) {
            { state: $st, out: ["Opened."] }
        } else {
            let names = ($contents | each {|c| $"a ((find-obj $c).desc)" })
            { state: $st, out: [$"Opening the ($o.desc) reveals (print-list $names)."] }
        }
    }
}
export def do-close [state: record, oid: any]: nothing -> record {
    if $oid == null { return { state: $state, out: ["You can't see that here."] } }
    let o = (find-obj $oid)
    if (not (oflag $state $oid "contbit")) {
        { state: $state, out: [$"You must tell me how to do that to a ($o.desc)."] }
    } else if (oflag $state $oid "openbit") {
        { state: (set-oflag $state $oid "openbit" false), out: ["Closed."] }
    } else {
        { state: $state, out: ["It is already closed."] }
    }
}
export def do-take [state: record, oid: any]: nothing -> record {
    if $oid == null { return { state: $state, out: ["You can't see that here."] } }
    let o = (find-obj $oid)
    if ($oid in (player-inv $state)) {
        { state: $state, out: ["You already have it."] }
    } else if (not (oflag $state $oid "takebit")) {
        { state: $state, out: ["You can't take that."] }
    } else {
        let st = (set-loc (set-oflag $state $oid "touchbit" true) $oid { at: "player", id: "" })
        { state: $st, out: ["Taken."] }
    }
}
export def do-drop [state: record, oid: any]: nothing -> record {
    if $oid == null { return { state: $state, out: ["You can't see that here."] } }
    let o = (find-obj $oid)
    if ($oid not-in (player-inv $state)) {
        { state: $state, out: [$"You don't have the ($o.desc)."] }
    } else {
        { state: (set-loc $state $oid { at: "room", id: $state.here }), out: ["Dropped."] }
    }
}
export def do-read [state: record, oid: any]: nothing -> record {
    if $oid == null { return { state: $state, out: ["You can't see that here."] } }
    let o = (find-obj $oid)
    if (not (oflag $state $oid "readbit")) {
        { state: $state, out: [$"How can I read a ($o.desc)?"] }
    } else {
        { state: $state, out: [($o.oread? | default "")] }
    }
}

# --- one turn -------------------------------------------------------------
export def step [state: record, input: string]: nothing -> record {
    let p = (parse-cmd $state $input)
    let st = ($state | update moves ($state.moves + 1))
    let v = $p.verb
    if ($v == null) {
        { state: $st, out: [($p.msg? | default "I don't understand that.")] }
    } else if $v == "WALK" {
        do-walk $st ($p.dir? | default null)
    } else if $v == "LOOK" {
        let ri = (room-info $st); { state: $ri.state, out: $ri.out }
    } else if $v == "INVEN" {
        let inv = (player-inv $st)
        if ($inv | is-empty) { { state: $st, out: ["You are empty handed."] }
        } else { { state: $st, out: (["You are carrying:"] | append ($inv | each {|oid| $"A ((find-obj $oid).desc)" })) } }
    } else if ($v in ["OPEN", "CLOSE", "TAKE", "DROP", "READ"]) {
        let oid = (resolve-name $st ($p.rest? | default []))
        if $v == "OPEN" { do-open $st $oid
        } else if $v == "CLOSE" { do-close $st $oid
        } else if $v == "TAKE" { do-take $st $oid
        } else if $v == "DROP" { do-drop $st $oid
        } else { do-read $st $oid }
    } else {
        { state: $st, out: [$"You can't ($v | str downcase) that yet."] }
    }
}
