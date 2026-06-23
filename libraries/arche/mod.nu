# Zork port (alpha = Zork I): the Great Underground Empire as idiomatic nu.
#
# Data-first: the world dataset lives under .assets/world/ (series flags.nuon +
# per-episode <episode>/{map,conditions}.nuon) and is code-gen'd to typed in-code
# consts - the series ENGINE (engine.nu, re-exported here) + each episode's WORLD
# (alpha/world.nu) - via arche/dev (model_ accessors + derive_ code-gen). Episodes
# are submodules - alpha (Zork I), beta (II), gamma (III); each holds its engine
# (parser, verbs, turn), the localized markdown front, and its dev tooling. Depends
# on pelos by name.

export module engine
export module alpha
export module dev
