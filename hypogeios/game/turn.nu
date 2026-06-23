use pelos locale *
use pelos render *

# Portal hub turn: one step of the Fourth Wall front (stub).
#
# Every game portal is a death stub; only the arche (blue) portal at the main hub
# navigates - to the arche sub-hub. Session state persists as NUON keyed by the
# session id. Display/interaction follow the Zork I idiom: a room-title line, a
# description, and terse command results. All player-visible text loads from this
# library's .assets/locale via the pelos locale loader (no hardcoded strings).
export def main [
    args: record<session: string, input: string>
]: nothing -> record<output: string, room: string, score: int, moves: int, finished: bool> {
    let dir = (state-dir)
    mkdir $dir
    let path = ($dir | path join $"($args.session).nuon")
    let fresh = { here: "main", moves: 0, finished: false, started: false }
    mut st = $fresh
    if ($path | path exists) {
        let loaded = (open $path)
        if ("started" in ($loaded | columns)) { $st = $loaded }
    }
    let cmd = ($args.input | str downcase | str trim)
    mut out = ""
    if $st.finished {
        $out = (sys "ended")
    } else if (not $st.started) {
        $st.started = true
        $out = $"(sys 'intro')\n\n(room-desc $st.here)"
    } else {
        let r = (handle $st $cmd)
        $st = $r.state
        $out = $r.output
    }
    $st | save -f $path
    { output: $out, room: (room-title $st.here), score: 0, moves: $st.moves, finished: $st.finished }
}

def state-dir [] {
    let base = ($env.XDG_STATE_HOME? | default ($env.HOME | path join ".local" "state"))
    $base | path join "sourcetrait" "hypogeios"
}

def handle [st: record, cmd: string] {
    mut s = $st
    let words = ($cmd | split row " " | where {|w| $w != "" })
    let color = (color-in $words)
    mut out = ""
    if (($cmd == "") or ($cmd == "look") or ($cmd == "l")) {
        $out = (room-desc $s.here)
    } else if (($cmd == "quit") or ($cmd == "q")) {
        $s.moves = ($s.moves + 1)
        $s.finished = true
        $out = (sys "quit")
    } else if (($cmd == "out") or ($cmd == "back") or ($cmd == "leave") or ($cmd == "exit")) {
        $s.moves = ($s.moves + 1)
        if ($s.here == "arche") {
            $s.here = "main"
            $out = (room-desc "main")
        } else {
            $out = (sys "no_exit")
        }
    } else if ($color != "") {
        $s.moves = ($s.moves + 1)
        let r = (enter-portal $s.here $color)
        $s.here = $r.here
        $s.finished = $r.finished
        $out = $r.output
    } else {
        $out = (sys "unknown")
    }
    { state: $s, output: $out }
}

def color-in [words: list<string>] {
    if ("green" in $words) {
        "green"
    } else if ("blue" in $words) {
        "blue"
    } else if ("red" in $words) {
        "red"
    } else {
        ""
    }
}

def enter-portal [here: string, color: string] {
    if (($here == "main") and ($color == "blue")) {
        { here: "arche", finished: false, output: $"(portal-enter $color)\n\n(room-desc 'arche')" }
    } else {
        { here: $here, finished: true, output: (stub-death $color) }
    }
}

# Locale access: every player-visible string is an item under this library's
# .assets/locale/en_us/<space>/, loaded lazily through the pelos loader.
const LIB = "hypogeios"
const LOC = "en_us"

# A system-space message (intro, ended, quit, no_exit, unknown).
def sys [item: string]: nothing -> string {
    prose $LIB $LOC [{space: "system", item: $item}] --single
}

# A room's full view: the code-rendered h1 title (deviation #2.1) over the room's
# description prose. (item snake = the room key: main, arche.)
def room-desc [here: string]: nothing -> string {
    let body = (prose $LIB $LOC [{space: "room", item: $here}] --single)
    $"(h1 (room-title $here))\n($body)"
}

# A room's short title, looked up by room key in room/titles.yaml.
def room-title [here: string]: nothing -> string {
    term $LIB $LOC [{space: "room", item: "titles", cell: ([$here] | into cell-path)}] --single
}

# The (navigating) portal-entry line, color filled into the template.
def portal-enter [color: string]: nothing -> string {
    prose $LIB $LOC [{space: "portal", item: "enter"}] [{fill: "color", value: $color}] --single
}

# The unfinished-portal death, color filled into the template.
def stub-death [color: string]: nothing -> string {
    prose $LIB $LOC [{space: "portal", item: "stub_death"}] [{fill: "color", value: $color}] --single
}
