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
    mut loc = {}
    for rm in $ROOMS {
        for oid in $rm.contents { $loc = ($loc | upsert $oid { at: "room", id: $rm.rid }) }
    }
    for o in $OBJECTS {
        for oid in $o.contents { $loc = ($loc | upsert $oid { at: "cont", id: $o.oid }) }
    }
    mut oflags = {}
    for o in $OBJECTS { $oflags = ($oflags | upsert $o.oid $o.bits) }
    {
        here: "WHOUS", moves: 0, score: 0, deaths: 0,
        seen: [], inv: [], loc: $loc, oflags: $oflags, flags: {}
    }
}

# --- flag helpers ---------------------------------------------------------
export def oflag [state: record, oid: string, bit: string]: nothing -> bool {
    if ($oid in ($state.oflags | columns)) { $bit in ($state.oflags | get $oid) } else { false }
}
export def gflag [state: record, name: string]: nothing -> bool {
    ($name in ($state.flags | columns)) and (($state.flags | get $name) == true)
}

# --- objects currently in a room -----------------------------------------
export def room-objs [state: record, rid: string]: nothing -> list {
    $state.loc | transpose oid place | where {|r| ($r.place.at == "room") and ($r.place.id == $rid) } | get oid
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

# --- one turn -------------------------------------------------------------
export def step [state: record, input: string]: nothing -> record {
    let p = (parse-cmd $state $input)
    let st = ($state | update moves ($state.moves + 1))
    if ($p.verb == null) {
        { state: $st, out: [($p.msg? | default "I don't understand that.")] }
    } else if $p.verb == "WALK" {
        do-walk $st ($p.dir? | default null)
    } else if $p.verb == "LOOK" {
        let ri = (room-info $st)
        { state: $ri.state, out: $ri.out }
    } else if $p.verb == "INVEN" {
        if ($st.inv | is-empty) {
            { state: $st, out: ["You are empty handed."] }
        } else {
            { state: $st, out: (["You are carrying:"] | append ($st.inv | each {|oid| $"A ((find-obj $oid).desc)" })) }
        }
    } else {
        { state: $st, out: [$"You can't ($p.verb | str downcase) that yet."] }
    }
}
