# Portal hub turn: one step of the Fourth Wall front (stub).
#
# Every game portal is a death stub; only the arche (blue) portal at the main hub
# navigates - to the arche sub-hub. Session state persists as NUON keyed by the
# session id. Display/interaction follow the Zork I idiom: a room-title line, a
# description, and terse command results.
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
        $out = "This session has ended. Begin a new session to return to the Fourth Wall."
    } else if (not $st.started) {
        $st.started = true
        $out = $"(intro)\n\n(describe $st.here)"
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
        $out = (describe $s.here)
    } else if (($cmd == "quit") or ($cmd == "q")) {
        $s.moves = ($s.moves + 1)
        $s.finished = true
        $out = "You turn from the wall, and the worlds wink out. Goodbye."
    } else if (($cmd == "out") or ($cmd == "back") or ($cmd == "leave") or ($cmd == "exit")) {
        $s.moves = ($s.moves + 1)
        if ($s.here == "arche") {
            $s.here = "main"
            $out = (describe "main")
        } else {
            $out = "There is no way out of the Fourth Wall but through a portal."
        }
    } else if ($color != "") {
        $s.moves = ($s.moves + 1)
        let r = (enter-portal $s.here $color)
        $s.here = $r.here
        $s.finished = $r.finished
        $out = $r.output
    } else {
        $out = "Nothing here answers to that. Try \"look\", a portal color (green, blue, red), or \"out\"."
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
        { here: "arche", finished: false, output: $"You step through the blue portal.\n\n(describe 'arche')" }
    } else {
        { here: $here, finished: true, output: (stub-death $color) }
    }
}

def stub-death [color: string] {
    $"You step into the ($color) portal. It is unfinished - a doorway opening onto raw void, with nothing woven beyond to catch you. You fall out of every world at once, and are unmade.\n\n    ****  You have died  ****"
}

def room-title [here: string] {
    if ($here == "main") { "Fourth Wall" } else { "Fourth Wall of Arche" }
}

def describe [here: string] {
    if ($here == "main") { (desc-main) } else { (desc-arche) }
}

def intro [] {
    "HYPOGEIOS\nA preservation suite of underworlds. You come to yourself at the Fourth Wall."
}

def desc-main [] {
    "Fourth Wall
This is a dark chamber of rough black brick, the seam between the worlds. Three
portals hang in the still air, each glowing a steady color beneath a drifting,
half-legible glyph. They stand in the order their worlds were born:
  a green portal - the cave where it all began;
  a blue portal - the underground empire that came after;
  a red portal - the deep labyrinth, youngest of the three.
You may enter a portal by its color."
}

def desc-arche [] {
    "Fourth Wall of Arche
A deeper seam, beyond the blue portal. Three spheres of light hang here, a single
burning glyph in each:
  a green sphere, marked α;
  a blue sphere, marked β;
  a red sphere, marked γ.
The way out leads back to the Fourth Wall. Enter a sphere by its color, or go
out."
}
