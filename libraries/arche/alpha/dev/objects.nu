# ZIL -> arche object extractor: the preserve/deviate split for OBJECTs (dev tool;
# read source to use).
#
# Consume from a run()/interact() body: `use arche alpha dev objects *`. Objects
# are PER-FILE data (NOT a const, no model/derive): one .nuon record per object,
# loaded lazily at runtime by the pelos data loader. Chain of custody mirrors the
# world (design.md; working/06):
#
#   zil objects <dungeon_zil> <gglobals_zil> <world_dir> <locale_dir> <episode>
#     PRESERVE. Parses both files: the episode dungeon -> per-file records under
#     <world_dir>/preserved/<episode>/objects/<snake>.nuon; the series globals
#     (gglobals, shared across the trilogy) -> <world_dir>/preserved/objects/
#     <snake>.nuon (NO episode segment). Plus the preserved object locale rip under
#     <locale_dir>/preserved/[<episode>/]object/. Flags + vehicle_type kept RAW;
#     ids (synonyms/adjectives/location/action/*_fn) snaked. ALL objects emitted
#     incl. engine plumbing (the engine hard-codes those worst-case).
#
#   zil objects deviate <world_dir> <episode>
#     LIGHT. Reads the preserved records + the deviated flag dictionary
#     (<world_dir>/deviated/flags.nuon) and writes deviated/[<episode>/]objects/
#     <snake>.nuon: re-map the flag column + vehicle_type (raw atom -> deviated
#     name); carry the rest through.
#
# The per-file record (snake = the filename, the id; not duplicated inside):
#   record<synonyms: list<string>, adjectives: list<string>, flags: list<string>,
#     location: oneof<string,nothing>, capacity: int, size: int, value: int,
#     trophy_value: int, strength: oneof<int,nothing>, vehicle_type: oneof<string,
#     nothing>, action: oneof<string,nothing>, description_fn: oneof<string,nothing>,
#     container_fn: oneof<string,nothing>>
# Prose -> locale: DESC -> object/names.yaml (snake->name); FDESC/LDESC/TEXT ->
# object/{first_description,long_description,text}/<snake>.md (snake-keyed, raw
# values; the deviated marked-up locale is authored later with the game code).
# (Self-contained helpers for now; the shared block-prop parser with world.nu is a
# DRY-factor follow.) Re-runnable. Working: iter/hypogeios/working/06.

def zw-snake [s: string]: nothing -> string { $s | str downcase | str replace --all "-" "_" }

def zw-norm [s: string]: nothing -> string {
    $s
    | str replace --regex '(?s)^"(.*)"$' '$1'
    | str replace --all '\"' '"'
    | str replace --all --regex '\s*\n\s*' ' '
    | str replace --all '|' (char nl)
    | str trim
}

def zw-midx [tok: string]: nothing -> int { $tok | parse --regex '@@S(?<n>\d+)@@' | get n.0 | into int }

# A ZIL routine-ref field value: "0" means no routine (null); else snake it.
def zw-fn [v: string]: nothing -> any { if $v == "0" { null } else { zw-snake $v } }

# Parse every <OBJECT> block in one ZIL file into per-object records + locale rows.
def zw-parse-objects [zil: string]: nothing -> record<recs: table, names: table, proses: table> {
    let raw = (open --raw $zil | decode)
    let qs = ($raw | parse --regex '(?s)(?<q>"(?:\\.|[^"\\])*")' | get q)
    mut text = $raw
    mut qi = 0
    for q in $qs { $text = ($text | str replace $q $"@@S($qi)@@"); $qi = $qi + 1 }
    let blocks = ($text | parse --regex '(?s)<OBJECT\s+(?<body>[^>]*)>')
    mut recs = []
    mut names = []
    mut proses = []
    for b in $blocks {
        let snake = (zw-snake ($b.body | str trim | split row --regex '\s+' | first))
        let props = ($b.body | parse --regex '\((?<p>[^)]*)\)' | get p)
        mut rec = {snake: $snake, synonyms: [], adjectives: [], flags: [], location: null, capacity: 0, size: 0, value: 0, trophy_value: 0, strength: null, vehicle_type: null, action: null, description_fn: null, container_fn: null}
        for p in $props {
            let toks = ($p | str trim | split row --regex '\s+' | where {|t| $t != ""})
            if ($toks | is-empty) { continue }
            let head = ($toks | first)
            let rest = ($toks | skip 1)
            if $head == "SYNONYM" {
                $rec.synonyms = ($rest | each {|x| zw-snake $x})
            } else if $head == "ADJECTIVE" {
                $rec.adjectives = ($rest | each {|x| zw-snake $x})
            } else if $head == "FLAGS" {
                $rec.flags = ($rest | where {|t| $t =~ '^[A-Z][A-Z0-9]*$'})
            } else if $head == "IN" {
                $rec.location = (if (($rest | first) == "TO") { zw-snake ($rest | get 1) } else { zw-snake ($rest | first) })
            } else if $head == "CAPACITY" {
                $rec.capacity = (try { $rest | first | into int } catch { 0 })
            } else if $head == "SIZE" {
                $rec.size = (try { $rest | first | into int } catch { 0 })
            } else if $head == "VALUE" {
                $rec.value = (try { $rest | first | into int } catch { 0 })
            } else if $head == "TVALUE" {
                $rec.trophy_value = (try { $rest | first | into int } catch { 0 })
            } else if $head == "STRENGTH" {
                $rec.strength = (try { $rest | first | into int } catch { null })
            } else if $head == "VTYPE" {
                $rec.vehicle_type = (if ($rest | is-empty) { null } else { $rest | first })
            } else if $head == "ACTION" {
                $rec.action = (if ($rest | is-empty) { null } else { zw-fn ($rest | first) })
            } else if $head == "DESCFCN" {
                $rec.description_fn = (if ($rest | is-empty) { null } else { zw-fn ($rest | first) })
            } else if $head == "CONTFCN" {
                $rec.container_fn = (if ($rest | is-empty) { null } else { zw-fn ($rest | first) })
            } else if $head == "DESC" {
                if ((not ($rest | is-empty)) and (($rest | first) | str starts-with "@@S")) {
                    $names = ($names | append {snake: $snake, name: (zw-norm ($qs | get (zw-midx ($rest | first))))})
                }
            } else if $head == "FDESC" {
                if ((not ($rest | is-empty)) and (($rest | first) | str starts-with "@@S")) {
                    $proses = ($proses | append {snake: $snake, field: "first_description", text: (zw-norm ($qs | get (zw-midx ($rest | first))))})
                }
            } else if $head == "LDESC" {
                if ((not ($rest | is-empty)) and (($rest | first) | str starts-with "@@S")) {
                    $proses = ($proses | append {snake: $snake, field: "long_description", text: (zw-norm ($qs | get (zw-midx ($rest | first))))})
                }
            } else if $head == "TEXT" {
                if ((not ($rest | is-empty)) and (($rest | first) | str starts-with "@@S")) {
                    $proses = ($proses | append {snake: $snake, field: "text", text: (zw-norm ($qs | get (zw-midx ($rest | first))))})
                }
            }
        }
        $recs = ($recs | append $rec)
    }
    {recs: $recs, names: $names, proses: $proses}
}

# Write a parsed object set to its preserved per-file data + locale (idempotent).
def zw-write-objects [data: record, world_subdir: directory, locale_subdir: directory] {
    let objdir = ($world_subdir | path join "objects")
    if ($objdir | path exists) { rm --recursive --force $objdir }
    mkdir $objdir
    for o in $data.recs {
        ($o | reject snake) | to nuon --indent 2 | save -f ($objdir | path join $"($o.snake).nuon")
    }
    let locdir = ($locale_subdir | path join "object")
    if ($locdir | path exists) { rm --recursive --force $locdir }
    mkdir $locdir
    let names_rec = ($data.names | reduce --fold {} {|r, acc| $acc | merge {($r.snake): $r.name}})
    $names_rec | to yaml | save -f ($locdir | path join "names.yaml")
    for pr in $data.proses {
        let fdir = ($locdir | path join $pr.field)
        mkdir $fdir
        ($pr.text + (char nl)) | save -f ($fdir | path join $"($pr.snake).md")
    }
}

# Parse the episode dungeon + the series globals and write the PRESERVED objects.
export def "zil objects" [
    dungeon_zil: string,
    gglobals_zil: string,
    world_dir: directory,
    locale_dir: directory,
    episode: string,
]: nothing -> record<episode_objects: int, series_objects: int, names: int, proses: int> {
    let ep = (zw-parse-objects $dungeon_zil)
    let sr = (zw-parse-objects $gglobals_zil)
    zw-write-objects $ep ($world_dir | path join "preserved" $episode) ($locale_dir | path join "preserved" $episode)
    zw-write-objects $sr ($world_dir | path join "preserved") ($locale_dir | path join "preserved")
    {
        episode_objects: ($ep.recs | length),
        series_objects: ($sr.recs | length),
        names: (($ep.names | append $sr.names) | length),
        proses: (($ep.proses | append $sr.proses) | length)
    }
}

# Map one preserved objects dir -> its deviated mirror (flags + vehicle_type).
def zw-deviate-dir [pre_objdir: directory, dev_objdir: directory, flag_map: record]: nothing -> int {
    if not ($pre_objdir | path exists) { return 0 }
    if ($dev_objdir | path exists) { rm --recursive --force $dev_objdir }
    mkdir $dev_objdir
    mut n = 0
    for f in (glob ($pre_objdir | path join "*.nuon")) {
        let o = (open $f)
        let dev = ($o
            | update flags {|r| $r.flags | each {|a| $flag_map | get -i $a} | where {|x| $x != null}}
            | update vehicle_type {|r| if ($r.vehicle_type == null) { null } else { ($flag_map | get -i $r.vehicle_type | default $r.vehicle_type) }})
        $dev | to nuon --indent 2 | save -f ($dev_objdir | path join ($f | path basename))
        $n = $n + 1
    }
    $n
}

# Derive the deviated per-file objects from the preserved form.
export def "zil objects deviate" [
    world_dir: directory,
    episode: string,
]: nothing -> record<episode_objects: int, series_objects: int> {
    let flag_map = (open ($world_dir | path join "deviated" "flags.nuon") | reduce --fold {} {|r, acc| $acc | merge {($r.preserved): $r.snake}})
    let ep = (zw-deviate-dir ($world_dir | path join "preserved" $episode "objects") ($world_dir | path join "deviated" $episode "objects") $flag_map)
    let sr = (zw-deviate-dir ($world_dir | path join "preserved" "objects") ($world_dir | path join "deviated" "objects") $flag_map)
    {episode_objects: $ep, series_objects: $sr}
}
