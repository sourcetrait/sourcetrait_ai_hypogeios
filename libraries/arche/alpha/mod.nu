# Arche alpha = Zork I.
#
# Holds the generated VOCABULARY const (vocabulary/, the parser word dictionary derived
# from the deviated objects + grammar) + the generated CONDITIONS const (conditions/,
# the per-episode gate-kind dictionary). The map (rooms/links/blocked) is per-file
# loader data under .assets/world/deviated/alpha/rooms/ (pelos data `room`), NOT a const.
# Plus the episode's dev tooling (dev). The engine (parser, verbs, turn) and the
# localized markdown front land later.

export module vocabulary
export module conditions
export module dev
