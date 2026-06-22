use ./turn.nu

# Interactive play loop for hypogeios; not a call() target.
#
# Drives game:turn turn-by-turn over stdin/stdout: with no session a fresh id is
# generated and printed (resume later via `play <id>`), then each iteration
# renders the turn output, reads a line, and advances until the turn reports
# finished. A positional arg plus side-effecting I/O keep it off the call()
# surface - no `main`, no schema contract.
export def play [session?: string] {
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
