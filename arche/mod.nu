# Zork port (alpha = Zork I): the Great Underground Empire as idiomatic nu.
#
# Data-first: the world dataset lives under .assets/world/<episode> (map.nuon +
# conditions.nuon). Episodes are submodules - alpha (Zork I), beta (II), gamma
# (III); each holds its engine (parser, verbs, turn), the localized markdown
# front, and its dev tooling (e.g. alpha/dev). Depends on pelos by name.

export module alpha
