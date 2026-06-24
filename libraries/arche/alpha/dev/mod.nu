# Dev tools for arche alpha (Zork I) - read the source to use them.
#
# Organizational, run-invoked only (NOT call() targets, not on the bin surface).
# Re-exports each tool; consume from a run() body, e.g. `use arche alpha dev world *`
# (rooms/conditions) or `use arche alpha dev objects *` (objects).

export use ./world.nu
export use ./objects.nu
