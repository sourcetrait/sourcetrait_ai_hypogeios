#!/usr/bin/env nu
# Start nuzork interactively. Run from the repo root:
#   nu play.nu            # new game
#   nu play.nu <session>  # continue a saved session
# Uses the sibling nuzork library directly (no install required).
def main [session?: string] {
    use ./nuzork game
    if ($session | is-empty) { game run } else { game run $session }
}
