#!/usr/bin/env nu
# Start hypogeios interactively. Run from anywhere:
#   nu .non/bin/hypogeios/play.nu            # new game
#   nu .non/bin/hypogeios/play.nu <session>  # continue a saved session
# Reaches the repo-root hypogeios library via a file-relative use (no install).
def main [session?: string] {
    use ../../../hypogeios game
    if ($session | is-empty) { game run } else { game run $session }
}
