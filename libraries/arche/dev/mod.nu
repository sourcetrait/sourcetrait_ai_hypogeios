# Series-level dev tools for arche (the Zork trilogy) - read the source to use.
#
# Organizational, run-invoked only (NOT call() targets, not on the bin surface).
# These generators are generic to the whole series; consume from a run() body,
# e.g. `use arche dev flags *`. (Per-episode world extraction currently lives at
# arche/alpha/dev/world.nu; it factors up here when beta/gamma land.)

export use ./flags.nu
