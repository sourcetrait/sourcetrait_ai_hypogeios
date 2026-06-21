# nuzork game engine: verb handlers plus the turn dispatcher. The world model
# (static data lookups, the session-state delta layer, and room display) lives
# in world.nu and is re-exported here so turn.nu / runner.nu get it via
# `use ./engine.nu *`. Ported against ~/repo/zork (working knowledge in
# iter/nuzork/working/zorkcpp). Verb handlers expand incrementally.
export use ./world.nu *
use ./data_vocab.nu *

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
    } else if ($v in ["OPEN", "CLOSE", "TAKE", "DROP", "READ", "LIGHT", "EXTIN"]) {
        let oid = (resolve-name $st ($p.rest? | default []))
        if $v == "OPEN" { do-open $st $oid
        } else if $v == "CLOSE" { do-close $st $oid
        } else if $v == "TAKE" { do-take $st $oid
        } else if $v == "DROP" { do-drop $st $oid
        } else if $v == "READ" { do-read $st $oid
        } else if $v == "LIGHT" { do-light $st $oid
        } else { do-extinguish $st $oid }
    } else {
        { state: $st, out: [$"You can't ($v | str downcase) that yet."] }
    }
}
