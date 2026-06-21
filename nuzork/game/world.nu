# nuzork world model: static-data lookups plus the session-state delta layer
# (moved / oflags / flags overrides over the static tables) and the room
# display. Kept free of parsing and verb handlers so both the parser
# (parser.nu) and the engine (engine.nu) can use it without an import cycle.
use ./data_rooms.nu *
use ./data_objects.nu *

# The startup banner (mdlfun.cpp:run_zork -> version.h sVersion).
export const BANNER = "ZORK++ version 1.2"

# --- static-world lookups -------------------------------------------------
export def find-room [rid: string]: nothing -> any {
    let m = ($ROOMS | where rid == $rid)
    if ($m | is-empty) { null } else { $m | first }
}
export def find-obj [oid: string]: nothing -> any {
    let m = ($OBJECTS | where oid == $oid)
    if ($m | is-empty) { null } else { $m | first }
}
# Maximum attainable score (the C++ inc_score_max tally): every object's find +
# treasure value, every NON-endgame room's first-entry value (endgame rval goes
# to eg_score_max), plus the static +10 from the light shaft (act2.cpp).
export def score-max []: nothing -> int {
    let ov = ($OBJECTS | each {|o| (($o.ofval? | default 0) + ($o.otval? | default 0)) } | math sum)
    let rv = ($ROOMS | where {|r| "rendgame" not-in ($r.rbits? | default []) } | each {|r| ($r.rval? | default 0) } | math sum)
    $ov + $rv + 10
}

# --- new game -------------------------------------------------------------
# The session stores only deltas over the static world: `moved` (oid ->
# {at,id} placement overrides), `oflags` (oid -> [bit] flag overrides), and
# `flags` (game FlagId bools). Reads fall back to the static tables.
export def new-state []: nothing -> record {
    { here: "WHOUS", moves: 0, score: 0, deaths: 0, seen: [], moved: {}, oflags: {}, flags: {}, pstr: 0, vstr: {}, clocks: {}, cyclowrath: 0, scored: [] }
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

# A room is lit if it is self-lit (rlightbit) or an `on` light source is in the
# room or the player's inventory.
export def lit [state: record, rid: string]: nothing -> bool {
    let rm = (find-room $rid)
    if (($rm != null) and ("rlightbit" in $rm.rbits)) { return true }
    let all = ((room-objs $state $rid) | append (player-inv $state) | uniq)
    ($all | any {|oid| oflag $state $oid "onbit" })
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
    } else if $roomf == "cellar" {
        ["You are in a dark and damp cellar with a narrow passageway leading\neast, and a crawlway to the south.  On the west is the bottom of a\nsteep metal ramp which is unclimbable."]
    } else if $roomf == "cyclops_room" {
        mut o = ["This room has an exit on the west side, and a staircase leading up."]
        let wrath = ($state.cyclowrath? | default 0)
        if (gflag $state "magic_flag") {
            $o = ($o | append "The north wall, previously solid, now has a cyclops-sized hole in it.")
        } else if ((gflag $state "cyclops_flag") and (oflag $state "CYCLO" "sleepbit")) {
            $o = ($o | append "The cyclops is sleeping blissfully at the foot of the stairs.")
        } else if ($wrath == 0) {
            $o = ($o | append "A cyclops, who looks prepared to eat horses (much less mere\nadventurers), blocks the staircase.  From his state of health, and\nthe bloodstains on the walls, you gather that he is not very\nfriendly, though he likes people.")
        } else if ($wrath > 0) {
            $o = ($o | append "The cyclops is standing in the corner, eyeing you closely.  I don't\nthink he likes you very much.  He looks extremely hungry even for a\ncyclops.")
        } else {
            $o = ($o | append "The cyclops, having eaten the hot peppers, appears to be gasping.\nHis enflamed tongue protrudes from his man-sized mouth.")
        }
        $o
    } else { [] }
}

# --- room-function ENTER phase (GO-IN): runs as the player enters a room ----
# Mutates state and may prepend output, after the room is described. Companion
# to room-fn-desc (the LOOK phase); the incremental extension point for
# enter-triggered room behavior (e.g. the cellar trap door barring itself).
export def room-fn-enter [state: record]: nothing -> record {
    let roomf = ((find-room $state.here).roomf? | default null)
    if $roomf == "cellar" {
        if ((oflag $state "DOOR" "openbit") and (not (oflag $state "DOOR" "touchbit"))) {
            let st = (set-oflag (set-oflag $state "DOOR" "openbit" false) "DOOR" "touchbit" true)
            { state: $st, out: ["The trap door crashes shut, and you hear someone barring it."] }
        } else { { state: $state, out: [] } }
    } else { { state: $state, out: [] } }
}

# --- room display (room_info, full=3) -------------------------------------
export def room-info [state: record]: nothing -> record {
    let rm = (find-room $state.here)
    if (not (lit $state $state.here)) {
        return { state: $state, out: ["It is pitch black.  You are likely to be eaten by a grue."] }
    }
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

# --- object location helpers ----------------------------------------------
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

# --- state mutators -------------------------------------------------------
export def set-oflag [state: record, oid: string, bit: string, on: bool]: nothing -> record {
    let cur = (if ($oid in ($state.oflags | columns)) { $state.oflags | get $oid } else { (find-obj $oid).bits })
    let new = (if $on { $cur | append $bit | uniq } else { $cur | where {|b| $b != $bit } })
    $state | update oflags ($state.oflags | upsert $oid $new)
}
export def set-loc [state: record, oid: string, place: record]: nothing -> record {
    $state | update moved ($state.moved | upsert $oid $place)
}
export def set-gflag [state: record, name: string, val: bool]: nothing -> record {
    $state | update flags ($state.flags | upsert $name $val)
}
# C++ score_obj: taking a treasure adds its find value (ofval) to the score,
# once per object (tracked in state.scored, since the static ofval can't be
# zeroed in place). The deposit value (otval, via the trophy case) is separate.
export def score-take [state: record, oid: string]: nothing -> record {
    let ofval = ((find-obj $oid).ofval? | default 0)
    let scored = ($state.scored? | default [])
    if (($ofval > 0) and ($oid not-in $scored)) {
        $state | update score ($state.score + $ofval) | upsert scored ($scored | append $oid)
    } else {
        $state
    }
}
# The container currently holding oid (by moved override, else static), or null
# if oid is loose in a room / inventory / nowhere.
export def container-of [state: record, oid: string]: nothing -> any {
    let m = (obj-moved $state $oid)
    if ($m != null) {
        if ($m.at == "cont") { $m.id } else { null }
    } else {
        let c = ($OBJECTS | where {|o| $oid in ($o.contents? | default []) } | get oid)
        if ($c | is-empty) { null } else { $c | first }
    }
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
