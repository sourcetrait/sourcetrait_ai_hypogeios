# Cross-library localization loader: prose (.md) and term (.yaml) over .assets/locale.
#
# Two consumer-facing defs - `prose` and `term` - read a sibling library's static
# locale data at serve time, located via `path self`. Neither is a call() target; a
# game library imports them with `use pelos locale *`.
#
# Data layout (per library):
#   <library>/.assets/locale/<locale>/<space>/<item>.md     (prose)
#   <library>/.assets/locale/<locale>/<space>/<item>.yaml    (term)
# <space> mirrors the codebase's types and may nest; <item> (the filename snake) is
# the key. Strings load lazily, one file per accessed item - never a whole corpus.
#
# Filling: prose values carry %{snake}% placeables filled literally from a `fills`
# table (single pass; inserted values are never rescanned); any leftover delimiter
# after fill is a hard error. `term` performs NO substitution - it is a pure lookup
# whose value, optionally tagged with a `fill` name, composes into prose's `fills`.

const SELF = (path self)

# Sibling-library root: the dir holding pelos/ (and arche/, hypogeios/, ...). pelos's
# locale.nu sits at <root>/pelos/locale.nu both MCP-served and repo-standalone, so two
# `path dirname` steps reach the shared root; <library>/.assets is resolved under it.
def sibling-root []: nothing -> string {
    $SELF | path dirname | path dirname
}

# A single path component must be a bare snake: [a-z0-9_]+ (no separators, no dots).
def assert-snake [value: string, what: string] {
    if not ($value =~ '^[a-z0-9_]+$') {
        error make {msg: $"locale: invalid ($what) '($value)' - expected [a-z0-9_]+"}
    }
}

# A space may nest as slash-joined snakes (e.g. combat/melee); validate each segment.
def assert-space [space: string] {
    for seg in ($space | split row "/") { assert-snake $seg "space segment" }
}

# Resolve the on-disk path of a locale item for a sibling library.
def asset-path [
    library: string, locale: string, space: string, item: string, ext: string
]: nothing -> string {
    assert-snake $library "library"
    assert-snake $locale "locale"
    assert-space $space
    assert-snake $item "item"
    (sibling-root) | path join $library ".assets" "locale" $locale $space $"($item).($ext)"
}

# Load prose items and fill their %{fill}% placeables.
#
# Reads <library>/.assets/locale/<locale>/<space>/<item>.md for each `query` row and
# fills %{fill}% from `fills` (a table<fill, value>, e.g. a `term` batch's output or a
# literal [{fill, value}]). The value is the file content minus a single trailing
# newline (the POSIX line terminator), so assets stay newline-terminated on disk while
# values compose without spurious blank lines. Fill is literal and single-pass per fill row; fill values
# are guarded against %{ so they cannot inject further placeables. After filling, any
# remaining %{ or }% (unfilled key, or malformed delimiter) is a hard error.
#
# Returns `query` augmented with a `value` column. With --single the query must hold
# exactly one row and the bare filled string is returned instead.
export def prose [
    library: string,
    locale: string,
    query: table<space: string, item: string>,
    fills?: table<fill: string, value: string>,
    --single
]: nothing -> any {
    let fills = ($fills | default [])
    for f in $fills {
        assert-snake $f.fill "fill"
        if (($f.value | str contains "%{") or ($f.value | str contains "}%")) {
            error make {msg: $"locale prose: fill value for '($f.fill)' contains a placeable delimiter"}
        }
    }
    let rows = ($query | each {|row|
        let path = (asset-path $library $locale $row.space $row.item "md")
        if not ($path | path exists) {
            error make {msg: $"locale prose: no item at ($library)/($locale)/($row.space)/($row.item).md"}
        }
        let raw = (open --raw $path | decode | str replace -r '\n$' '')
        let filled = ($fills | reduce --fold $raw {|f, acc|
            $acc | str replace --all $"%{($f.fill)}%" $f.value
        })
        if (($filled | str contains "%{") or ($filled | str contains "}%")) {
            error make {msg: $"locale prose: unfilled or malformed placeable in ($library)/($locale)/($row.space)/($row.item).md"}
        }
        $row | insert value $filled
    })
    if $single {
        if (($rows | length) != 1) {
            error make {msg: $"locale prose --single: query must be one row, got ($rows | length)"}
        }
        $rows | first | get value
    } else {
        $rows
    }
}

# Look up structured short strings by cell-path; no placeable substitution.
#
# Reads <library>/.assets/locale/<locale>/<space>/<item>.yaml for each `query` row and
# returns the value at `cell`. An optional `fill` column on a row is carried through to
# the output so a term batch drops straight into prose's `fills`. Values are markdown.
#
# Returns `query` augmented with a `value` column. With --single the query must hold
# exactly one row and the bare value is returned instead.
export def term [
    library: string,
    locale: string,
    query: table<space: string, item: string, cell: cell-path>,
    --single
]: nothing -> any {
    let rows = ($query | each {|row|
        let path = (asset-path $library $locale $row.space $row.item "yaml")
        if not ($path | path exists) {
            error make {msg: $"locale term: no item at ($library)/($locale)/($row.space)/($row.item).yaml"}
        }
        let doc = (open --raw $path | decode | from yaml)
        $row | insert value ($doc | get $row.cell)
    })
    if $single {
        if (($rows | length) != 1) {
            error make {msg: $"locale term --single: query must be one row, got ($rows | length)"}
        }
        $rows | first | get value
    } else {
        $rows
    }
}
