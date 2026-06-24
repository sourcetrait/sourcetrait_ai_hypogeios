# Dev-support tooling for the hypogeios front (build-time, not runtime).
#
# Build-time methods for the suite, kept out of the runtime path (game/cli) so a
# game never depends on them. First + only member: repo (the reproducible build
# machine). Consume canonically - use hypogeios, then hypogeios dev repo build.
export module repo
