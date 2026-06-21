# Advance one non-interactive turn for a session and return the result.
#
# A fresh session id starts a new game (the player at West-of-House); empty
# input yields the opening room with no command. Session state persists as NUON
# at $XDG_STATE_HOME/sourcetrait/hypogeios/<session>.nuon (the C++ save/restore
# delta model). `output` is the turn's accumulated text; `finished` flags game
# end (quit / final death).
use ./engine.nu *

export def main [args: record<session: string, input: string>]: nothing -> record<output: string, room: string, score: int, moves: int, finished: bool> {
    let dir = ($env.XDG_STATE_HOME | path join "sourcetrait" "hypogeios")
    mkdir $dir
    let path = ($dir | path join $"($args.session).nuon")
    let fresh = (not ($path | path exists))
    mut state = (if $fresh { new-state } else { open $path })
    mut out = []
    if $fresh {
        let ri = (room-info $state)
        $state = $ri.state
        $out = ([$BANNER] | append $ri.out)
    }
    mut finished = false
    if (($args.input | str trim) != "") {
        let r = (step $state $args.input)
        $state = $r.state
        $out = ($out | append $r.out)
        $finished = ($r.finished? | default false)
    }
    $state | save -f $path
    {
        output: ($out | str join (char nl)),
        room: (find-room $state.here | get desc2),
        score: (displayed-score $state),
        moves: $state.moves,
        finished: $finished
    }
}
