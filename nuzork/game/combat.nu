# nuzork combat (melee), ported from ~/repo/zork melee.cpp + the ATTACK/KILL
# handlers (act1.cpp killer/attacker) + jigs_up (rooms.cpp). Faithful to the
# port's NON-determinism: every roll uses nushell `random` (the C++ seeds
# rand() from the clock, so combat varies per playthrough). Player wound level
# is state.pstr (0 healthy, negative wounded); villain current strength is the
# state.vstr override over the static ostrength.
#
# Scoped to the troll fight (strength <=2, so only the def1/def2 tables apply):
# the player's attack, the troll's counter-attack (fight-phase), and a minimal
# death (jigs-up: herald, score-10, the 3-death limit, revive at LLD1).
# Deferred (followups): the full fight_demon (multi-villain, vout/probs, the
# out free-swing), cure-clock timing, diagnose, item-scatter on death, and the
# other villains (thief, cyclops).
use ./world.nu *
use ./data_melee.nu *
use ./clocks.nu *

# prob(good) with the default lucky flag set: a percent roll under `good`.
def prob1 [good: int]: nothing -> bool { (random int 0..99) < $good }
def subst [msg: string, dname: string, aname: string, wname: string]: nothing -> string {
    $msg | str replace --all "%D%" $dname | str replace --all "%A%" $aname | str replace --all "%W%" $wname
}
def pres [group: list, dname: string, aname: string, wname: string]: nothing -> string {
    subst ($group | get (random int 0..(($group | length) - 1))) $dname $aname $wname
}
def melee-table [ofmsgs: any]: nothing -> any {
    if $ofmsgs == "&sword_melee" { $SWORD_MELEE
    } else if $ofmsgs == "&troll_melee" { $TROLL_MELEE
    } else { null }
}

# fight_strength(hero): base from the score percentile (smin 2 .. smax 7) plus
# the wound adjust (pstr).
export def fight-strength [state: record, adjust: bool]: nothing -> int {
    let smax = (score-max)
    let pct = (if ($smax == 0) { 0 } else { ($state.score * 100) // $smax })
    let base = ((($pct * 5) + 50) // 100) + 2
    if $adjust { $base + ($state.pstr? | default 0) } else { $base }
}

def vstr-of [state: record, vid: string]: nothing -> int {
    let v = ($state.vstr? | default {})
    if ($vid in ($v | columns)) { $v | get $vid } else { ((find-obj $vid).ostrength? | default 0) }
}
def set-vstr [state: record, vid: string, val: int]: nothing -> record {
    $state | update vstr (($state.vstr? | default {}) | upsert $vid $val)
}
# villain_strength: current strength, reduced by 1 when attacked with its best
# weapon (TROLL<-SWORD, THIEF<-KNIFE).
export def villain-strength [state: record, vid: string, weapon: any]: nothing -> int {
    let cur = (vstr-of $state $vid)
    if ($cur <= 0) { return $cur }
    let bestmap = { TROLL: "SWORD", THIEF: "KNIFE" }
    let best = (if ($vid in ($bestmap | columns)) { $bestmap | get $vid } else { null })
    if (($weapon != null) and ($best == $weapon)) { [1, ($cur - 1)] | math max } else { $cur }
}

# Select the def-table span (the 9 outcomes to roll among) from att vs def.
def select-tbl [att: int, def: int]: nothing -> list {
    if ($def == 1) {
        $DEF1_RES | get ((if ($att > 2) { 3 } else { $att }) - 1)
    } else if ($def == 2) {
        $DEF2_RES | get ((if ($att > 3) { 4 } else { $att }) - 1)
    } else {
        let a = (if (($att - $def) < -1) { -2 } else { $att - $def })
        $DEF3_RES | get ([([($a + 2), 0] | math max), 4] | math min)
    }
}

# Player death (rooms.cpp:jigs_up, minimal): lose 10, the 3rd death ends the
# game, otherwise the death herald and revival at the Land of the Living Dead.
def jigs-up [state: record, desc: string]: nothing -> record {
    let st0 = ($state | update score ($state.score - 10))
    if (($st0.deaths) >= 2) {
        { state: $st0, out: [$desc, $SUICIDAL_HERALD], finished: true }
    } else {
        let st = ($st0 | update deaths ($st0.deaths + 1) | update pstr 0 | update here "LLD1"
            | update flags (($st0.flags) | upsert "pstag" false))
        { state: $st, out: [$desc, $DEATH_HERALD], finished: false }
    }
}

# One blow. heroq=true: the player strikes villain `vid` with `weapon`.
# heroq=false: the villain strikes the player. Returns {state, out, finished}.
export def blow [state: record, vid: string, weapon: any, heroq: bool]: nothing -> record {
    let v = (find-obj $vid)
    let vdesc = $v.desc
    mut st = $state
    mut out = []
    # staggered actors skip / recover (the C++ guards at the top of blow).
    if $heroq {
        if (($st.flags.pstag? | default false)) {
            return { state: $st, out: ["You are still recovering from that last blow, so your attack is\nineffective."], finished: false }
        }
    } else {
        if (($st.flags.pstag? | default false)) { $st = ($st | update flags ($st.flags | upsert "pstag" false)) }
        if (oflag $st $vid "staggered") {
            return { state: (set-oflag $st $vid "staggered" false), out: [$"The ($vdesc) slowly regains his feet."], finished: false }
        }
    }
    let att = (if $heroq { [1, (fight-strength $st true)] | math max } else { (villain-strength $st $vid null) })
    let def = (if $heroq { (villain-strength $st $vid $weapon) } else { (fight-strength $st true) })
    if ($heroq and ($def == 0)) { return { state: $st, out: [$"Attacking the ($vdesc) is pointless."], finished: false } }
    if ((not $heroq) and ($def <= 0)) { return { state: $st, out: [], finished: false } }
    let od = (if $heroq { $def } else { (fight-strength $st false) })
    # the weapon whose %W% / lose-weapon applies: the villain's (heroq) or the
    # player's (villain attacking).
    let dweapon = (if $heroq {
        let c = (($v.contents? | default []) | where {|o| "weaponbit" in ((find-obj $o).bits? | default []) })
        if ($c | is-empty) { null } else { $c | first }
    } else {
        let w = ((player-inv $st) | where {|o| "weaponbit" in ((find-obj $o).bits? | default []) })
        if ($w | is-empty) { null } else { $w | first }
    })
    let wname = (if ($dweapon == null) { "" } else { (find-obj $dweapon).desc })
    # resolve the outcome (attack_state).
    mut res = 2
    if ($def < 0) {
        $res = 2
        if $heroq { $out = ($out | append $"The unconscious ($vdesc) cannot defend himself: He dies.") }
    } else {
        let r0 = ((select-tbl $att $def) | get (random int 0..8))
        $res = (if (($r0 == 5) and ($dweapon != null) and (prob1 25)) { 6 } else { $r0 })
        let tbl = (if $heroq { (melee-table ((find-obj $weapon).ofmsgs? | default null)) } else { (melee-table ($v.ofmsgs? | default null)) })
        $out = ($out | append (pres ($tbl | get $res) (if $heroq { $vdesc } else { "Adventurer" }) (if $heroq { "Adventurer" } else { $vdesc }) $wname))
    }
    # apply the outcome to the defender strength.
    let newdef = (if ($res in [0, 7]) { $def
        } else if ($res == 1) { (if $heroq { 0 - $def } else { $def })
        } else if ($res in [2, 8]) { 0
        } else if ($res == 3) { [0, ($def - 1)] | math max
        } else if ($res == 4) { [0, ($def - 2)] | math max
        } else { $def })
    # stagger / lose-weapon side effects.
    if ($res == 5) {
        if $heroq { $st = (set-oflag $st $vid "staggered" true)
        } else { $st = ($st | update flags ($st.flags | upsert "pstag" true)) }
    }
    if (($res == 6) and ($dweapon != null)) {
        $st = (set-loc $st $dweapon { at: "room", id: $st.here })
    }
    if (not $heroq) {
        let np = (if ($newdef == 0) { -10000 } else { $newdef - $od })
        $st = ($st | update pstr $np)
        if ($np < 0) { $st = (cure-on $st) }
        if ((fight-strength $st true) < 0) {
            return (jigs-up $st "It appears that that last blow was too much for you.  I'm afraid you\nare dead.")
        }
        { state: $st, out: $out, finished: false }
    } else {
        $st = (set-vstr $st $vid $newdef)
        if ($newdef == 0) {
            $st = (set-gflag (set-loc (set-oflag $st $vid "fightbit" false) $vid { at: "gone", id: "" }) "troll_flag" true)
            $out = ($out | append $"Almost as soon as the ($vdesc) breathes his last breath, a cloud\nof sinister black fog envelops him, and when the fog lifts, the\ncarcass has disappeared.")
        }
        { state: $st, out: $out, finished: false }
    }
}

# ATTACK / KILL (act1.cpp:killer). `verbword` is "attack" or "kill" (messages).
export def do-attack [state: record, verbword: string, prso: any, prsi: any]: nothing -> record {
    if ($prso == null) { return { state: $state, out: [$"There is nothing here to ($verbword)."], finished: false } }
    let o = (find-obj $prso)
    if (not (oflag $state $prso "villain")) {
        if (oflag $state $prso "vicbit") { { state: $state, out: ["Nothing happens."], finished: false }
        } else { { state: $state, out: [$"I've known strange people, but fighting a ($o.desc)?"], finished: false } }
    } else if ($prsi == null) {
        { state: $state, out: [$"Trying to ($verbword) a ($o.desc) with your bare hands is suicidal."], finished: false }
    } else if (not (oflag $state $prsi "weaponbit")) {
        { state: $state, out: [$"Trying to ($verbword) a ($o.desc) with a ((find-obj $prsi).desc) is suicidal."], finished: false }
    } else {
        blow $state $prso $prsi true
    }
}

# The fight phase (a minimal fight_demon): a present, living troll strikes back
# each turn. Run by step after the verb handler.
export def fight-phase [state: record]: nothing -> record {
    if (("TROLL" in (room-objs $state $state.here)) and ((vstr-of $state "TROLL") > 0) and (not ($state.flags.dead? | default false))) {
        blow $state "TROLL" null false
    } else {
        { state: $state, out: [], finished: false }
    }
}

# DIAGNOSE (melee.cpp): wound level + cure time + survivability + death count.
export def do-diagnose [state: record]: nothing -> record {
    let pstr = ($state.pstr? | default 0)
    let ci = (cure-info $state)
    let rs = ((fight-strength $state false) + $pstr + $pstr)
    let wd = (if $ci.enabled { 0 - $pstr } else { 0 })
    mut out = []
    if ($wd == 0) {
        $out = ($out | append "You are in perfect health.")
    } else {
        let lvl = (if ($wd == 1) { "a light wound" } else if ($wd == 2) { "a serious wound" } else if ($wd == 3) { "several wounds" } else { "serious wounds" })
        $out = ($out | append $"You have ($lvl), which will be cured after ((30 * ($wd - 1)) + $ci.tick) moves.")
    }
    if ($rs >= 0) {
        let msgs = ["You are at death's door.", "You can be killed by one more light wound.", "You can be killed by a serious wound.", "You can survive one serious wound.", "You are strong enough to take several wounds."]
        $out = ($out | append ($msgs | get (if ($rs < (($msgs | length) - 1)) { $rs } else { (($msgs | length) - 1) })))
    }
    if (($state.deaths) > 0) {
        let kmsg = (if (($state.deaths) == 1) { "once." } else { "twice." })
        $out = ($out | append $"You have been killed ($kmsg)")
    }
    { state: $state, out: $out }
}
