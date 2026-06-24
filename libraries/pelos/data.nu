# Per-file structured-data loader for the hypogeios suite (beside `locale`).
#
# One consumer-facing def - `object` - reads a sibling library's deviated per-file
# object data at serve time, located via `path self` (the same self-location as
# locale). Not a call() target; a game library imports it with `use pelos data *`.
#
# Data layout (per library, the chain-of-custody deviated form):
#   <library>/.assets/world/deviated/<episode>/objects/<snake>.nuon  (episode objects)
#   <library>/.assets/world/deviated/objects/<snake>.nuon            (series globals)
# Resolution is EPISODE-FIRST then series fallback: an episode object may shadow a
# same-named series global (normally disjoint). preserved/ is audit-only, never
# loaded. The id (snake) is the filename, not duplicated inside the record. The
# resolver is generic over the per-file CATEGORY (objects = the first consumer); the
# typed `object` accessor restates the per-file object schema as its return.

const SELF = (path self)

# Sibling-library root: the dir holding pelos/ (and arche/, ...). Two `path dirname`
# steps from this file reach the shared store root, both MCP-served and standalone -
# the same ascent locale.nu uses, so `library` selects any sibling's .assets.
def sibling-root []: nothing -> string {
    $SELF | path dirname | path dirname
}

# A single path component must be a bare snake: [a-z0-9_]+ (no separators, no dots).
def assert-snake [value: string, what: string] {
    if not ($value =~ '^[a-z0-9_]+$') {
        error make {msg: $"data: invalid ($what) '($value)' - expected [a-z0-9_]+"}
    }
}

# Resolve + open one deviated per-file record, episode dir FIRST then the series dir.
# Generic over the per-file `category` (e.g. objects); hard-errors when neither the
# episode nor the series path exists. preserved/ is never consulted (audit-only).
def deviated-file [
    library: string, category: string, episode: string, snake: string
]: nothing -> record {
    assert-snake $library "library"
    assert-snake $category "category"
    assert-snake $episode "episode"
    assert-snake $snake "snake"
    let base = ((sibling-root) | path join $library ".assets" "world" "deviated")
    let ep_path = ($base | path join $episode $category $"($snake).nuon")
    let series_path = ($base | path join $category $"($snake).nuon")
    if ($ep_path | path exists) {
        open $ep_path
    } else if ($series_path | path exists) {
        open $series_path
    } else {
        error make {msg: $"data: no ($category) '($snake)' for ($library)/($episode) (episode or series)"}
    }
}

# Load one deviated OBJECT record by id, episode-first then series-global fallback.
#
# The return type IS the per-file object schema (working/07): a runtime-open record
# whose values are OUR deviated vocabulary, never ZIL atoms. `flags` reuse the shared
# ENGINE flag dictionary; `action` / `*_fn` hold routine snakes (null = none);
# `location` is the initial containment parent (null = spawned at runtime);
# `vehicle_type` is a flag snake. snake = the file id, not duplicated in the record.
export def object [
    library: string,
    episode: string,
    snake: string
]: nothing -> record<synonyms: list<string>, adjectives: list<string>, flags: list<string>, location: oneof<string, nothing>, capacity: int, size: int, value: int, trophy_value: int, strength: oneof<int, nothing>, vehicle_type: oneof<string, nothing>, action: oneof<string, nothing>, description_fn: oneof<string, nothing>, container_fn: oneof<string, nothing>> {
    deviated-file $library "objects" $episode $snake
}
