#!/usr/bin/env nu
# Start nuzork interactively. Run from anywhere:
#   nu .non/bin/nuzork/play.nu            # new game
#   nu .non/bin/nuzork/play.nu <session>  # continue a saved session
# Reaches the repo-root nuzork library via a file-relative use (no install).
def main [session?: string] {
    use ../../../nuzork game
    if ($session | is-empty) { game run } else { game run $session }
}
