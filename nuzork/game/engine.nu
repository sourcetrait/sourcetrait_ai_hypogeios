# nuzork game engine: verb handlers plus the turn dispatcher. The world model
# (world.nu) is re-exported so turn.nu / runner.nu get it via `use ./engine.nu
# *`; the MDL parser (parser.nu) turns input into (action, prso, prsi, dir).
# step() runs the C++ rdcom turn shape: parse -> object-function intercept
# (PRSI then PRSO) -> the verb handler (keyed on the syntax sfcn). Handlers are
# ported against ~/repo/zork (working knowledge in iter/nuzork/working/zorkcpp)
# and expand incrementally; unported verbs fall through to a stub.
export use ./world.nu *
use ./parser.nu *

# --- movement -------------------------------------------------------------
# Enter a destination room: describe it (LOOK phase), then run the room's
# ENTER phase (room-fn-enter), appending its output after the description.
def enter-room [state: record, dest: string]: nothing -> record {
    let ri = (room-info ($state | update here $dest))
    let en = (room-fn-enter $ri.state)
    { state: $en.state, out: ($ri.out | append $en.out) }
}
export def do-walk [state: record, dir: any]: nothing -> record {
    if $dir == null { return { state: $state, out: ["You can't go that way."] } }
    let rm = (find-room $state.here)
    let exm = ($rm.exits | where dir == $dir)
    if ($exm | is-empty) { return { state: $state, out: ["You can't go that way."] } }
    let to = ($exm | first | get to)
    if $to.kind == "room" {
        let ri = (enter-room $state $to.to)
        { state: $ri.state, out: $ri.out }
    } else if $to.kind == "nexit" {
        { state: $state, out: [$to.msg] }
    } else if $to.kind == "door" {
        if (oflag $state $to.obj "openbit") {
            let dest = (if $to.rm1 == $state.here { $to.rm2 } else { $to.rm1 })
            let ri = (enter-room $state $dest)
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

# C++ act1.cpp:open_close - toggle openbit with the given messages. The
# already-open / already-closed paths render pick_one(dummy) as a fixed
# deterministic stand-in (the dummy message table is not yet ported).
def open-close-obj [state: record, oid: string, verb: string, openmsg: string, closemsg: string]: nothing -> record {
    if $verb == "OPEN" {
        if (oflag $state $oid "openbit") { { handled: true, state: $state, out: ["It is already open."] }
        } else { { handled: true, state: (set-oflag $state $oid "openbit" true), out: [$openmsg] } }
    } else if $verb == "CLOSE" {
        if (oflag $state $oid "openbit") { { handled: true, state: (set-oflag $state $oid "openbit" false), out: [$closemsg] }
        } else { { handled: true, state: $state, out: ["It is already closed."] } }
    } else { { handled: false, state: $state, out: [] } }
}

# --- object functions: a ported obj_func may intercept a verb ----------------
# handled=false -> fall through to the generic verb handler. `verb` is the
# syntax sfcn verb (prsa()->w(): OPEN/CLOSE/MOVE/RAISE/TAKE/LKUND/...), which is
# what the C++ verbq() tests. Extension point as obj_funcs are ported.
export def obj-fn [state: record, oid: string, verb: string]: nothing -> record {
    let fn = ((find-obj $oid).objfn? | default null)
    if $fn == "window_function" {
        open-close-obj $state $oid $verb "With great effort, you open the window far enough to allow entry." "The window closes (more easily than it opened)."
    } else if $fn == "ddoor_function" {
        if $verb == "OPEN" { { handled: true, state: $state, out: ["The door cannot be opened."] }
        } else { { handled: false, state: $state, out: [] } }
    } else if $fn == "rug" {
        if $verb == "RAISE" {
            { handled: true, state: $state, out: ["The rug is too heavy to lift, but in trying to take it you have\nnoticed an irregularity beneath it."] }
        } else if $verb == "MOVE" {
            if (gflag $state "rug_moved") {
                { handled: true, state: $state, out: ["Having moved the carpet previously, you find it impossible to move\nit again."] }
            } else {
                let st = (set-gflag (set-oflag $state "DOOR" "ovison" true) "rug_moved" true)
                { handled: true, state: $st, out: ["With a great effort, the rug is moved to one side of the room.\nWith the rug moved, the dusty cover of a closed trap-door appears."] }
            }
        } else if $verb == "TAKE" {
            { handled: true, state: $state, out: ["The rug is extremely heavy and cannot be carried."] }
        } else if $verb == "LKUND" {
            if ((not (gflag $state "rug_moved")) and (not (oflag $state "DOOR" "openbit"))) {
                { handled: true, state: $state, out: ["Underneath the rug is a closed trap door."] }
            } else { { handled: false, state: $state, out: [] } }
        } else { { handled: false, state: $state, out: [] } }
    } else if $fn == "trap_door" {
        if (($verb in ["OPEN" "CLOSE"]) and ($state.here == "LROOM")) {
            open-close-obj $state $oid $verb "The door reluctantly opens to reveal a rickety staircase descending\ninto darkness." "The door swings shut and closes."
        } else if ($state.here == "CELLA") {
            if $verb == "OPEN" { { handled: true, state: $state, out: ["The door is locked from above."] }
            } else { { handled: true, state: $state, out: ["You can't do that."] } }
        } else { { handled: false, state: $state, out: [] } }
    } else { { handled: false, state: $state, out: [] } }
}

# --- verb handlers --------------------------------------------------------
export def do-open [state: record, oid: any]: nothing -> record {
    if $oid == null { return { state: $state, out: ["You can't see that here."] } }
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
export def do-light [state: record, oid: any]: nothing -> record {
    if $oid == null { return { state: $state, out: ["You can't see that here."] } }
    let o = (find-obj $oid)
    if ((not (oflag $state $oid "lightbit")) or ($oid not-in (player-inv $state))) {
        { state: $state, out: ["You can't turn that on."] }
    } else if (oflag $state $oid "onbit") {
        { state: $state, out: ["It is already on."] }
    } else {
        { state: (set-oflag $state $oid "onbit" true), out: [$"The ($o.desc) is now on."] }
    }
}
export def do-extinguish [state: record, oid: any]: nothing -> record {
    if $oid == null { return { state: $state, out: ["You can't see that here."] } }
    let o = (find-obj $oid)
    if ((not (oflag $state $oid "lightbit")) or ($oid not-in (player-inv $state))) {
        { state: $state, out: ["You can't turn that off."] }
    } else if (not (oflag $state $oid "onbit")) {
        { state: $state, out: ["It is already off."] }
    } else {
        let st = (set-oflag $state $oid "onbit" false)
        if (lit $st $st.here) { { state: $st, out: [$"The ($o.desc) is now off."] }
        } else { { state: $st, out: [$"The ($o.desc) is now off.", "It is now pitch black."] } }
    }
}
# put PRSO in/on PRSI (a container).
export def do-put [state: record, prso: any, prsi: any]: nothing -> record {
    if ($prso == null) { return { state: $state, out: ["You can't see that here."] } }
    if ($prsi == null) { return { state: $state, out: ["You can't see that here."] } }
    let o = (find-obj $prso)
    let c = (find-obj $prsi)
    if ($prso not-in (player-inv $state)) {
        { state: $state, out: [$"You don't have the ($o.desc)."] }
    } else if ($prso == $prsi) {
        { state: $state, out: ["You can't put something in itself."] }
    } else if (not (oflag $state $prsi "contbit")) {
        { state: $state, out: [$"You can't put anything in the ($c.desc)."] }
    } else if (not (oflag $state $prsi "openbit")) {
        { state: $state, out: [$"The ($c.desc) is closed."] }
    } else {
        { state: (set-loc (set-oflag $state $prso "touchbit" true) $prso { at: "cont", id: $prsi }), out: ["Done."] }
    }
}
# move PRSO (the generic case; object-specific reveals live in obj_funcs).
export def do-move [state: record, oid: any]: nothing -> record {
    if $oid == null { return { state: $state, out: ["You can't see that here."] } }
    let o = (find-obj $oid)
    { state: $state, out: [$"Moving the ($o.desc) reveals nothing."] }
}
# EXAMINE / LOOK AT an object (basic: containers show state; else nothing).
export def describe-obj [state: record, oid: any]: nothing -> record {
    if ($oid == null) { return { state: $state, out: ["You can't see that here."] } }
    let o = (find-obj $oid)
    if (oflag $state $oid "contbit") {
        if (oflag $state $oid "openbit") {
            let c = (cont-of $state $oid)
            if ($c | is-empty) { { state: $state, out: [$"The ($o.desc) is empty."] }
            } else {
                let names = ($c | each {|x| $"a ((find-obj $x).desc)" })
                { state: $state, out: [$"The ($o.desc) contains (print-list $names)."] }
            }
        } else {
            { state: $state, out: [$"The ($o.desc) is closed."] }
        }
    } else {
        { state: $state, out: [$"There is nothing special about the ($o.desc)."] }
    }
}
export def do-inven [state: record]: nothing -> record {
    let inv = (player-inv $state)
    if ($inv | is-empty) { { state: $state, out: ["You are empty handed."] }
    } else { { state: $state, out: (["You are carrying:"] | append ($inv | each {|oid| $"A ((find-obj $oid).desc)" })) } }
}

# --- handler dispatch (syntax sfcn -> a verb handler) ---------------------
def dispatch [state: record, sfcn: any, action: any, prso: any, prsi: any]: nothing -> record {
    if ($sfcn in ["room_desc" "room_info" "look_inside" "look_under"]) {
        if ($prso != null) { describe-obj $state $prso
        } else { let ri = (room-info $state); { state: $ri.state, out: $ri.out } }
    } else if $sfcn == "invent" { do-inven $state
    } else if $sfcn == "opener" { do-open $state $prso
    } else if $sfcn == "closer" { do-close $state $prso
    } else if $sfcn == "takefn" { do-take $state $prso
    } else if $sfcn == "dropper" { do-drop $state $prso
    } else if $sfcn == "reader" { do-read $state $prso
    } else if $sfcn == "lamp_on" { do-light $state $prso
    } else if $sfcn == "lamp_off" { do-extinguish $state $prso
    } else if $sfcn == "putter" { do-put $state $prso $prsi
    } else if $sfcn == "move" { do-move $state $prso
    } else if $sfcn == "walk" { do-walk $state null
    } else {
        { state: $state, out: [$"You can't ($action | str downcase) that yet."] }
    }
}

# --- one turn: parse -> obj-fn intercept (PRSI, PRSO) -> verb handler ------
export def step [state: record, input: string]: nothing -> record {
    let st0 = ($state | update moves ($state.moves + 1))
    let p = (parse-input $st0 $input)
    if (not $p.ok) { return { state: $p.state, out: $p.out } }
    mut st = $p.state
    let out0 = $p.out
    if (($p.sfcn == "walk") and ($p.dir != null)) {
        let r = (do-walk $st $p.dir)
        return { state: $r.state, out: ($out0 | append $r.out) }
    }
    if ($p.prsi != null) {
        let f = (obj-fn $st $p.prsi $p.sverb)
        if $f.handled { return { state: $f.state, out: ($out0 | append $f.out) } }
        $st = $f.state
    }
    if ($p.prso != null) {
        let f = (obj-fn $st $p.prso $p.sverb)
        if $f.handled { return { state: $f.state, out: ($out0 | append $f.out) } }
        $st = $f.state
    }
    let r = (dispatch $st $p.sfcn $p.action $p.prso $p.prsi)
    { state: $r.state, out: ($out0 | append $r.out) }
}
