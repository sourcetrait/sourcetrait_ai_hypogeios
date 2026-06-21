# Interactive play entrypoint, re-exported by mod.nu as `run` (NOT a
# call-target). With a session id, continue that saved game; otherwise start a
# new one. Reads commands from stdin, prints each turn's output, persists after
# every turn, exits on QUIT / Q. Shares the engine (and session format) with
# the `turn` call.
use ./engine.nu *

export def run [session?: string]: nothing -> nothing {
    let dir = ($env.XDG_STATE_HOME | path join "sourcetrait" "nuzork")
    mkdir $dir
    let sid = ($session | default "play")
    let path = ($dir | path join $"($sid).nuon")
    let fresh = (not ($path | path exists))
    mut state = (if $fresh { new-state } else { open $path })
    let ri = (room-info $state)
    $state = $ri.state
    $state | save -f $path
    let intro = (if $fresh { [$BANNER] | append $ri.out } else { $ri.out })
    print ($intro | str join (char nl))
    loop {
        let line = (input "> ")
        if ($line | is-empty) { continue }
        let cmd = ($line | str trim)
        if (($cmd | str downcase) in ["quit", "q"]) { break }
        let r = (step $state $cmd)
        $state = $r.state
        $state | save -f $path
        print ($r.out | str join (char nl))
        if ($r.finished? | default false) {
            print "** You have died. **"
            break
        }
    }
}
