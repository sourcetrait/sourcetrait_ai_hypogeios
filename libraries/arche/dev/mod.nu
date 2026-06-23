# Series-level dev tools for arche (the Zork trilogy) - read the source to use.
#
# Organizational, run-invoked only (NOT call() targets, not on the bin surface).
# Generic to the whole series; consume from a run() body, e.g. `use arche dev
# flags *`, `use arche dev model *`, `use arche dev derive *`. (Per-episode world
# extraction currently lives at arche/alpha/dev/world.nu; it factors up here when
# beta/gamma land.) model_ = typed accessors over the derived data; derive_ =
# code-gen of the typed in-code consts (arche/engine.nu, arche/<episode>/world.nu).

export use ./flags.nu
export module model
export module derive
