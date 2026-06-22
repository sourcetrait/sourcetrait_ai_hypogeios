# Interactive CLI front for the hypogeios suite (not a call() target).
#
# Holds the stdin/stdout play loop that drives game:turn turn-by-turn. It lives
# in its own `cli` module rather than under `game` (which owns the `turn`
# call-target) so the command name does not collide with its module name: a
# module whose command matches its own name must be `main`, and `main` is the
# MCP's reserved call-target sentinel - so a `game/play.nu` exporting `play` is
# rejected, while `cli`'s `play` command is fine. The invocation is `cli play`;
# the standalone bin (bin/hypogeios/play.nu) drives it.
export def play [session?: string] {
    use ../game turn
    let sid = (if ($session | is-empty) { random uuid } else { $session })
    print $"hypogeios session: ($sid)"
    mut r = (turn { session: $sid, input: "" })
    print ""
    print $r.output
    while (not $r.finished) {
        let line = (input "> ")
        $r = (turn { session: $sid, input: $line })
        print ""
        print $r.output
    }
}
