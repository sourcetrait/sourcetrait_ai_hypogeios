# Typed world/engine accessors for arche (the model_ layer; read source to use).
#
# Organizational, run-invoked only (NOT call() targets). Each model_ fn reads the
# derived .nuon data assets and composes the strict typed record - its
# `-> record<...>` return IS the schema (mirror it in derive's *_TYPE). Consume
# from a run() body: `use arche dev model *`. The derive layer code-gens the typed
# consts from these records.

# Compose the series ENGINE record from <world_dir>/flags.nuon (the series
# attribute-flag dictionary, shared across the trilogy). Series-wide (one ENGINE
# for arche); flags only for now, extensible. The return IS the strict ENGINE schema.
export def model_engine [
    world_dir: directory
]: nothing -> record<flags: table<name: string, preserved: string, summary: string, state: oneof<nothing, record<default: bool, scope: list<string>>>>> {
    let flags = (open ($world_dir | path join "flags.nuon"))
    {flags: $flags}
}

# Compose an episode's WORLD record from <world_dir>/<episode>/{conditions,map}.nuon.
# map.nuon is record<rooms, links, blocked> (flat/relational; links/blocked are
# sibling tables keyed by room). <episode> is a snake (alpha|beta|gamma). The
# return IS the strict WORLD schema.
export def model_world [
    world_dir: directory,
    episode: string
]: nothing -> record<conditions: table<name: string, kind: string>, rooms: table<name: string, flags: list<string>, value: int, globals: list<string>, action: oneof<string, nothing>>, links: table<room: string, name: string, target: string, conditions: list<oneof<string, nothing>>>, blocked: table<room: string, name: string>> {
    let ep = ($world_dir | path join $episode)
    let conditions = (open ($ep | path join "conditions.nuon"))
    let map = (open ($ep | path join "map.nuon"))
    {conditions: $conditions, rooms: $map.rooms, links: $map.links, blocked: $map.blocked}
}
