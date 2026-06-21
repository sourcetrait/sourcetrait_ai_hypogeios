# nuzork game engine: verb handlers plus the turn dispatcher. The world model
# (world.nu) is re-exported so turn.nu / runner.nu get it via `use ./engine.nu
# *`; the MDL parser (parser.nu) turns input into (action, prso, prsi, dir).
# step() runs the C++ rdcom turn shape: parse -> object-function intercept
# (PRSI then PRSO) -> the verb handler (keyed on the syntax sfcn). Handlers are
# ported against ~/repo/zork (working knowledge in iter/nuzork/working/zorkcpp)
# and expand incrementally; unported verbs fall through to a stub.
export use ./world.nu *
use ./parser.nu *
use ./combat.nu *
use ./clocks.nu *

# --- movement -------------------------------------------------------------
# Enter a destination room: describe it (LOOK phase), then run the room's
# ENTER phase (room-fn-enter), appending its output after the description.
def enter-room [state: record, dest: string]: nothing -> record {
    let st = (score-room ($state | update here $dest) $dest)
    let ri = (room-info $st)
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
            let ri = (enter-room $state $to.to)
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
export def obj-fn [state: record, oid: string, verb: string, prso: any, prsi: any]: nothing -> record {
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
    } else if $fn == "lantern" {
        # manage the lamp dimming clock; not handled, so the generic light
        # handler (do-light / do-extinguish) still runs and reports.
        if ($verb in ["LIGHT", "TRNON"]) { { handled: false, state: (lamp-on $state), out: [] }
        } else if ($verb == "TRNOF") { { handled: false, state: (lamp-off $state), out: [] }
        } else { { handled: false, state: $state, out: [] } }
    } else if $fn == "cyclops" {
        cyclops-fn $state $oid $verb $prso
    } else { { handled: false, state: $state, out: [] } }
}

# act1.cpp:cyclops obj_func - the Cyclops Room villain. Weapon-proof (ATTACK is
# shrugged off); the solutions are GIVE food then water (sleep) or saying
# "Ulysses"/"Odysseus" (sinbad, flee). `prso` is the verb's direct object (the
# thing given). cyclowrath: 0 neutral, <0 fed-and-thirsty, >0 angered. The cycin
# anger clock (escalation -> cyclokill) is deferred with the full fight_demon.
def cyclops-fn [state: record, oid: string, verb: string, prso: any]: nothing -> record {
    let count = ($state.cyclowrath? | default 0)
    if (oflag $state $oid "sleepbit") {
        if ($verb in ["WAKE" "KICK" "ATTAC" "BURN" "DESTR"]) {
            let s0 = ($state | upsert cyclowrath ($count | math abs))
            let s1 = (set-oflag $s0 $oid "sleepbit" false)
            let s2 = (set-oflag $s1 $oid "fightbit" true)
            let s3 = (set-gflag $s2 "cyclops_flag" false)
            { handled: true, state: $s3, out: ["The cyclops yawns and stares at the thing that woke him up."] }
        } else { { handled: false, state: $state, out: [] } }
    } else if $verb == "GIVE" {
        cyclops-give $state $count $prso
    } else if ($verb in ["KILL" "THROW" "ATTAC" "DESTR" "POKE"]) {
        let msg = (if $verb == "POKE" { "'Do you think I'm as stupid as my father was?', he says, dodging." } else { "The cyclops ignores all injury to his body with a shrug." })
        { handled: true, state: $state, out: [$msg] }
    } else if $verb == "TAKE" {
        { handled: true, state: $state, out: ["The cyclops doesn't take kindly to being grabbed."] }
    } else if $verb == "TIE" {
        { handled: true, state: $state, out: ["You cannot tie the cyclops, though he is fit to be tied."] }
    } else { { handled: false, state: $state, out: [] } }
}
# The GIVE branch: the hot-pepper lunch makes him thirsty (cyclowrath ->
# min(-1, -count)); water then puts him to sleep (cyclops_flag set -> the Up
# staircase to the treasure room opens). Garlic / anything else is refused.
def cyclops-give [state: record, count: int, prso: any]: nothing -> record {
    if ($prso == "FOOD") {
        if ($count >= 0) {
            let st = (set-loc ($state | upsert cyclowrath ([(-1), (0 - $count)] | math min)) "FOOD" { at: "gone", id: "" })
            { handled: true, state: $st, out: ["The cyclops says 'Mmm Mmm.  I love hot peppers!  But oh, could I use\na drink.  Perhaps I could drink the blood of that thing'.  From the\ngleam in his eye, it could be surmised that you are 'that thing'."] }
        } else { { handled: true, state: $state, out: [] } }
    } else if ($prso == "WATER") {
        if ($count < 0) {
            let s0 = (set-loc $state "WATER" { at: "gone", id: "" })
            let s1 = (set-oflag $s0 "CYCLO" "sleepbit" true)
            let s2 = (set-oflag $s1 "CYCLO" "fightbit" false)
            let s3 = (set-gflag $s2 "cyclops_flag" true)
            { handled: true, state: $s3, out: ["The cyclops looks tired and quickly falls fast asleep (what did you\nput in that drink, anyway?)."] }
        } else {
            { handled: true, state: $state, out: ["The cyclops apparently is not thirsty and refuses your generosity."] }
        }
    } else if ($prso == "GARLI") {
        { handled: true, state: $state, out: ["The cyclops may be hungry, but there is a limit."] }
    } else {
        { handled: true, state: $state, out: ["The cyclops is not so stupid as to eat THAT!"] }
    }
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
        { state: (score-take $st $oid), out: ["Taken."] }
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
# EAT food / DRINK liquid (act1.cpp:eat). Food must be in hand (consumed);
# a drink must be reachable - a global, or in an open container in inventory.
# A removed object goes to a `gone` location (out of every room/inv/container).
export def do-eat [state: record, sverb: string, oid: any]: nothing -> record {
    if $oid == null { return { state: $state, out: ["You can't see that here."] } }
    let o = (find-obj $oid)
    let is_food = (oflag $state $oid "foodbit")
    let is_drink = (oflag $state $oid "drinkbit")
    if ($is_food and ($oid in (player-inv $state))) {
        if $sverb == "DRINK" {
            { state: $state, out: ["How can I drink that?"] }
        } else {
            { state: (set-loc $state $oid { at: "gone", id: "" }), out: ["Thank you very much.  It really hit the spot."] }
        }
    } else if $is_drink {
        let cont = (container-of $state $oid)
        let reachable = (($o.is_global? | default false) or (($cont != null) and ($cont in (player-inv $state)) and (oflag $state $cont "openbit")))
        if $reachable {
            { state: (set-loc $state $oid { at: "gone", id: "" }), out: ["Thank you very much.  I was rather thirsty (from all this talking\nprobably)."] }
        } else {
            { state: $state, out: ["I'd like to, but I can't get to it."] }
        }
    } else if (not ($is_food or $is_drink)) {
        { state: $state, out: [$"I don't think the ($o.desc) would agree with you."] }
    } else {
        { state: $state, out: ["I think you should get that first."] }
    }
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
# SCORE (rooms.cpp:score, non-endgame): the score line + the player's rank.
def score-rank [pct: int]: nothing -> string {
    if $pct == 100 { "Cheater"
    } else if $pct > 95 { "Wizard"
    } else if $pct > 89 { "Master"
    } else if $pct > 79 { "Winner"
    } else if $pct > 60 { "Hacker"
    } else if $pct > 39 { "Adventurer"
    } else if $pct > 19 { "Junior Adventurer"
    } else if $pct > 9 { "Novice Adventurer"
    } else if $pct > 4 { "Amateur Adventurer"
    } else if $pct >= 0 { "Beginner"
    } else { "Incompetent" }
}
export def do-score [state: record]: nothing -> record {
    let smax = (score-max)
    let sc = (displayed-score $state)
    let pct = (if ($smax == 0) { 0 } else { ($sc * 100) // $smax })
    let mv = (if ($state.moves == 1) { "move" } else { "moves" })
    { state: $state, out: [
        $"Your score is ($sc) [total of ($smax) points], in ($state.moves) ($mv).",
        $"This score gives you the rank of (score-rank $pct)."
    ] }
}

# act1.cpp:sinbad - saying "Ulysses"/"Odysseus" routs the cyclops: he flees and
# knocks down the north wall (magic_flag -> the north hole; cyclops_flag -> the
# Up staircase to the treasure room), and is removed from the room.
def do-sinbad [state: record]: nothing -> record {
    if (($state.here == "CYCLO") and ("CYCLO" in (room-objs $state $state.here))) {
        let s0 = (set-gflag $state "cyclops_flag" true)
        let s1 = (set-gflag $s0 "magic_flag" true)
        let s2 = (set-oflag $s1 "CYCLO" "fightbit" false)
        let s3 = (set-loc $s2 "CYCLO" { at: "gone", id: "" })
        { state: $s3, out: ["The cyclops, hearing the name of his father's deadly nemesis, flees the room\nby knocking down the wall on the north of the room."] }
    } else {
        { state: $state, out: ["Wasn't he a sailor?"] }
    }
}

# --- handler dispatch (syntax sfcn -> a verb handler) ---------------------
# Fixed-message flavor verbs (act1/act3/act4): each sfcn -> one canned line.
const FLAVOR_MSGS = {
    jargon: "Well, FOO, BAR, and BLETCH to you too!",
    zork: "At your service!",
    frobozz: "The FROBOZZ Corporation created, owns, and operates this dungeon.",
    yell: "Aaaarrrrrrrrgggggggggggggghhhhhhhhhhhhhh!",
    win: "Naturally!",
    chomp: "I don't know how to do that.  I win in all cases!",
    advent: "A hollow voice says 'Cretin.'",
    repent: "It could very well be too late!",
    mumbler: "You'll have to speak up if you expect me to hear you!"
}
def dispatch [state: record, sfcn: any, sverb: any, action: any, prso: any, prsi: any]: nothing -> record {
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
    } else if $sfcn == "eat" { do-eat $state $sverb $prso
    } else if $sfcn == "score" { do-score $state
    } else if $sfcn == "diagnose" { do-diagnose $state
    } else if $sfcn == "attacker" { do-attack $state "attack" $prso $prsi
    } else if $sfcn == "killer" { do-attack $state "kill" $prso $prsi
    } else if $sfcn == "sinbad" { do-sinbad $state
    } else if $sfcn == "walk" { do-walk $state null
    } else if ($sfcn in ($FLAVOR_MSGS | columns)) { { state: $state, out: [($FLAVOR_MSGS | get $sfcn)] }
    } else {
        { state: $state, out: [$"You can't ($action | str downcase) that yet."] }
    }
}

# The per-turn demon phase after a parse-won command: villains strike (the fight
# phase), then the clock events tick (the lamp dimming).
def run-demons [state: record, out: list]: nothing -> record {
    let fr = (fight-phase $state)
    if $fr.finished {
        { state: $fr.state, out: ($out | append $fr.out), finished: true }
    } else {
        let ct = (clock-tick $fr.state)
        { state: $ct.state, out: ($out | append $fr.out | append $ct.out), finished: false }
    }
}

# --- one turn: parse -> obj-fn intercept (PRSI, PRSO) -> verb handler ->
# the fight phase (villains strike). Returns {state, out, finished}.
export def step [state: record, input: string]: nothing -> record {
    # zoom <ROOMID>: faithful rdcom debug-teleport - pre-parse, counts no move,
    # LOOK-only (no enter-phase), matching the port's (currently unscored) entry.
    let z = ($input | str trim)
    if ($z | str downcase | str starts-with "zoom ") {
        let rid = ($z | str substring 5.. | str trim | str upcase)
        if ((find-room $rid) == null) {
            return { state: $state, out: [$"Room ($rid) not found."], finished: false }
        }
        let ri = (room-info ($state | update here $rid))
        return { state: $ri.state, out: $ri.out, finished: false }
    }
    let st0 = ($state | update moves ($state.moves + 1))
    let p = (parse-input $st0 $input)
    if (not $p.ok) { return { state: $p.state, out: $p.out, finished: false } }
    mut st = $p.state
    let out0 = $p.out
    if (($p.sfcn == "walk") and ($p.dir != null)) {
        let r = (do-walk $st $p.dir)
        return (run-demons $r.state ($out0 | append $r.out))
    }
    if ($p.prsi != null) {
        let f = (obj-fn $st $p.prsi $p.sverb $p.prso $p.prsi)
        if $f.handled { return (run-demons $f.state ($out0 | append $f.out)) }
        $st = $f.state
    }
    if ($p.prso != null) {
        let f = (obj-fn $st $p.prso $p.sverb $p.prso $p.prsi)
        if $f.handled { return (run-demons $f.state ($out0 | append $f.out)) }
        $st = $f.state
    }
    let r = (dispatch $st $p.sfcn $p.sverb $p.action $p.prso $p.prsi)
    if (($r.finished? | default false)) { return { state: $r.state, out: ($out0 | append $r.out), finished: true } }
    run-demons $r.state ($out0 | append $r.out)
}
