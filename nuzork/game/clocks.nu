# nuzork clock events (the CLOCKER demon), ported from ~/repo/zork cevent.cpp +
# rooms.cpp (clock_int / clock_demon) + act1.cpp (light_int, the lantern fn).
# Per-turn timed events live in state.clocks (cid -> {tick, enabled, val}); the
# clock-tick phase decrements each enabled event and fires it on reaching 0.
# Only the lamp (LNTIN) is wired so far - the framework extends to the match,
# candles, the fuse, etc. as those items are ported.
use ./world.nu *

# The lamp dimming table (act1.cpp lamp_ticks / lamp_tells; dimmer = the warning).
const LAMP_TICKS = [50, 30, 20, 10, 4, 0]
const LAMP_TELLS = [
    "The lamp appears to be getting dimmer.",
    "The lamp appears to be getting dimmer.",
    "The lamp appears to be getting dimmer.",
    "The lamp appears to be getting dimmer.",
    "The lamp is dying."
]

def clock-get [state: record, cid: string]: nothing -> record {
    let cs = ($state.clocks? | default {})
    if ($cid in ($cs | columns)) { $cs | get $cid } else { { tick: 0, enabled: false, val: 0 } }
}
def clock-set [state: record, cid: string, c: record]: nothing -> record {
    $state | update clocks (($state.clocks? | default {}) | upsert $cid $c)
}

# Lamp lit (the lantern fn, TRNON/LIGHT): start the dimming clock if not already
# running. Lamp extinguished (TRNOF): pause it (val persists - the lamp is used).
export def lamp-on [state: record]: nothing -> record {
    let c = (clock-get $state "LNTIN")
    if $c.enabled { $state } else {
        clock-set $state "LNTIN" { tick: ($LAMP_TICKS | first), enabled: true, val: $c.val }
    }
}
export def lamp-off [state: record]: nothing -> record {
    clock-set $state "LNTIN" ((clock-get $state "LNTIN") | update enabled false)
}

# light_int: the lamp event fired - advance one dimming step (warn), or die at a
# 0 interval (clear lightbit/onbit -> the room may go dark).
def lamp-fire [state: record]: nothing -> record {
    let c = (clock-get $state "LNTIN")
    let cnt = ($c.val + 1)
    let tim = ($LAMP_TICKS | get ($cnt - 1))
    if ($tim == 0) {
        let st = (clock-set (set-oflag (set-oflag $state "LAMP" "lightbit" false) "LAMP" "onbit" false) "LNTIN" ($c | update val $cnt | update tick 0 | update enabled false))
        let dark = (not (lit $st $st.here))
        { state: $st, out: (["I hope you have more light than from a lamp."] | append (if $dark { ["It is now pitch black."] } else { [] })) }
    } else {
        { state: (clock-set $state "LNTIN" ($c | update val $cnt | update tick $tim)), out: [($LAMP_TELLS | get ($cnt - 1))] }
    }
}

# Fire an event whose tick reached 0: dispatch by cid to its action.
def clock-fire [state: record, cid: string]: nothing -> record {
    if ($cid == "LNTIN") { lamp-fire $state
    } else if ($cid == "CURIN") { cure-fire $state
    } else { { state: $state, out: [] } }
}

# The clock-tick demon phase (rooms.cpp clock_demon): tick each enabled event,
# fire it on reaching 0 (tick 0 is inactive; negative would be recurring).
export def clock-tick [state: record]: nothing -> record {
    mut st = $state
    mut out = []
    for cid in (($state.clocks? | default {}) | columns) {
        let c = (clock-get $st $cid)
        if ($c.enabled and ($c.tick > 0)) {
            let nt = ($c.tick - 1)
            $st = (clock-set $st $cid ($c | update tick $nt))
            if ($nt == 0) {
                let f = (clock-fire $st $cid)
                $st = $f.state
                $out = ($out | append $f.out)
            }
        }
    }
    { state: $st, out: $out }
}

# cure_clock (melee.cpp): heal one wound level per cure_wait (30) turns;
# reschedule while still wounded, else disable. Silent (DIAGNOSE reports it).
def cure-fire [state: record]: nothing -> record {
    let p = ($state.pstr? | default 0)
    if ($p < 0) {
        let np = ($p + 1)
        let st = ($state | update pstr $np)
        if ($np < 0) {
            { state: (clock-set $st "CURIN" ((clock-get $st "CURIN") | update tick 30 | update enabled true)), out: [] }
        } else {
            { state: (clock-set $st "CURIN" ((clock-get $st "CURIN") | update tick 0 | update enabled false)), out: [] }
        }
    } else {
        { state: (clock-set $state "CURIN" ((clock-get $state "CURIN") | update tick 0 | update enabled false)), out: [] }
    }
}
# Enable the cure clock when the player is wounded (combat.nu blow calls this).
export def cure-on [state: record]: nothing -> record {
    clock-set $state "CURIN" { tick: 30, enabled: true, val: 0 }
}
# {enabled, tick} of the cure clock - for DIAGNOSE.
export def cure-info [state: record]: nothing -> record {
    let c = (clock-get $state "CURIN")
    { enabled: $c.enabled, tick: $c.tick }
}
