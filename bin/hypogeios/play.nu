#!/usr/bin/env nu
# Start hypogeios interactively. Run from anywhere:
#   nu bin/hypogeios/play.nu            # new game
#   nu bin/hypogeios/play.nu <session>  # continue a saved session
# Adds the repo root to NU_LIB_DIRS via a parse-time const so `hypogeios` and
# its `pelos` dependency resolve by name without an install (path self -> the
# repo root, three dirs up from this file).
const ROOT = (path self | path dirname | path dirname | path dirname)
const NU_LIB_DIRS = [$ROOT]
use hypogeios cli
def main [session?: string] {
    if ($session | is-empty) { cli play } else { cli play $session }
}
