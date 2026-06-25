# Reproducible build machine for the hypogeios suite.
#
# main IS the call-target hypogeios:dev/repo:build: it regenerates all
# preserved/deviated data + the engine consts from the external ZIL source repos
# into a staging tree (generate), then mirrors the owned arche subtrees back into
# the project repo (inline), and returns the git drift. Every step is MECHANICAL
# and byte-deterministic, so a clean-tree build that reproduces the committed data
# yields an EMPTY gstat. (The future marked-up prose/terms locale is the first
# genuine AGENT step - followups #5; it will reintroduce a pause/resume around its
# authoring. Flags are mechanical - `arche dev flags zil flags deviate` assembles
# the deviated dictionary from committed inputs + a source scan, no pause.)
#
# WRITE TARGET IS ALWAYS THE EXPLICIT hypogeios_repo_dir (the project repo on
# disk), NEVER path-self: a committed library serves from the MCP's signed store
# copy, so path-self would resolve into the store and write generated data into
# the MCP's own git repo. Every artifact path derives from the explicit args;
# only the dev TOOLS resolve from the promoted store (use arche). path-self stays
# in the pelos runtime loaders.
#
# Phases (composed by main; individually runnable for stage -> review -> accept):
# - generate: preserve (4 ZIL extractors -> staging preserved/) + deviate (flags/
#   map/objects/syntax -> staging deviated/) + derive (the engine/conditions/
#   vocabulary consts) into <generated_tmp_dir>/libraries/arche.
# - inline: scoped rm-then-cp of the 6 owned arche subtrees staging -> repo, so a
#   dropped/renamed artifact leaves no stale file.

use arche

# The owned arche subtrees the build regenerates + inline mirrors (arche-root-
# relative): the preserved + deviated world data, the preserved locale rip, and
# the three generated const dir-modules.
const OWNED_SUBS: list<string> = [
    ".assets/world/preserved",
    ".assets/world/deviated",
    ".assets/locale/en_us/preserved",
    "engine",
    "alpha/conditions",
    "alpha/vocabulary"
]

# <repo>/libraries/arche - the project arche library root (the inline target +
# the home of the committed build inputs: .assets/dev/flags/{gloss,pin}).
def repo-arche [hypogeios_repo_dir: directory]: nothing -> string {
    $hypogeios_repo_dir | path join "libraries" "arche"
}

# <generated_tmp_dir>/libraries/arche - the staging arche root (mirrors the repo).
def staging-arche [generated_tmp_dir: directory]: nothing -> string {
    $generated_tmp_dir | path join "libraries" "arche"
}

# Abort unless the repo git tree is clean (the build's precondition: the post-
# build gstat must show exactly the build's own changes).
def assert-clean [repo: directory]: nothing -> nothing {
    let status = (^git -C $repo status --porcelain | str trim)
    if (not ($status | is-empty)) {
        error make {msg: $"build: ($repo) has a dirty git tree - commit or stash before a build"}
    }
}

# The repo porcelain status as the build's drift report (added / modified /
# deleted). Porcelain XY code: contains D -> deleted, ? or A -> added, else modified.
def git-drift [
    repo: directory
]: nothing -> record<modified: list<string>, added: list<string>, deleted: list<string>> {
    let rows = (^git -C $repo status --porcelain
        | lines
        | where {|l| ($l | str length) > 3 }
        | each {|l| ($l | parse --regex '^(?<code>..) (?<path>.+)$' | get 0) }
        | each {|r| {
            path: $r.path,
            kind: (if ($r.code | str contains "D") {
                "deleted"
            } else if (($r.code | str contains "?") or ($r.code | str contains "A")) {
                "added"
            } else {
                "modified"
            }),
        } })
    {
        added: ($rows | where kind == "added" | get path),
        deleted: ($rows | where kind == "deleted" | get path),
        modified: ($rows | where kind == "modified" | get path),
    }
}

# PRESERVE (mechanical): the 4 ZIL extractors -> staging preserved/ world data +
# the preserved locale rip. Series flags first (deviate depends on it).
def preserve [
    world: directory,
    locale: directory,
    preserved_repo_dirs: record<zork1: directory, zork2: directory, zork3: directory>
]: nothing -> nothing {
    let z1 = $preserved_repo_dirs.zork1
    arche dev flags zil flags [$z1 $preserved_repo_dirs.zork2 $preserved_repo_dirs.zork3] $world
    arche alpha dev world zil preserve ($z1 | path join "1dungeon.zil") $world $locale "alpha"
    arche alpha dev objects zil objects ($z1 | path join "1dungeon.zil") ($z1 | path join "gglobals.zil") $world $locale "alpha"
    arche dev syntax zil syntax ($z1 | path join "gsyntax.zil") $world | ignore
}

# DEVIATE + DERIVE (mechanical): assemble deviated/flags.nuon (flags deviate over
# the committed inputs + a source scan), map preserved -> deviated, then code-gen
# the engine/conditions/vocabulary consts into the staging arche root. Reads the
# committed flag inputs (gloss + pin) from the REPO arche; scans the ZIL repos for
# the runtime-flag presence.
def deviate-derive [
    s_arche: directory,
    world: directory,
    r_arche: directory,
    preserved_repo_dirs: record<zork1: directory, zork2: directory, zork3: directory>
]: nothing -> nothing {
    let z = $preserved_repo_dirs
    let flags_dir = ($r_arche | path join ".assets" "dev" "flags")
    arche dev flags zil flags deviate [$z.zork1 $z.zork2 $z.zork3] $world ($flags_dir | path join "flags.gloss.nuon") ($flags_dir | path join "flags.pin.txt")
    arche alpha dev world zil deviate $world "alpha"
    arche alpha dev objects zil objects deviate $world "alpha"
    arche dev syntax zil syntax deviate $world
    arche dev derive derive_engine (arche dev model model_engine $world) $s_arche
    arche dev derive derive_conditions (arche dev model model_conditions $world "alpha") "alpha" $s_arche
    arche dev derive derive_vocabulary (arche dev model model_vocabulary $world "alpha") "alpha" $s_arche | ignore
}

# Run the full mechanical regen into a fresh staging tree.
#
# Writes only under generated_tmp_dir; returns the staging arche root. The flag
# inputs (gloss + pin) are read from the repo arche; everything else regenerates.
export def generate [
    args: record<hypogeios_repo_dir: directory, preserved_repo_dirs: record<zork1: directory, zork2: directory, zork3: directory>, generated_tmp_dir: directory>
]: nothing -> record<staging_arche: string> {
    let s_arche = (staging-arche $args.generated_tmp_dir)
    let r_arche = (repo-arche $args.hypogeios_repo_dir)
    if ($s_arche | path exists) { rm --recursive --force $s_arche }
    let world = ($s_arche | path join ".assets" "world")
    let locale = ($s_arche | path join ".assets" "locale" "en_us")
    mkdir $world
    mkdir $locale
    preserve $world $locale $args.preserved_repo_dirs
    deviate-derive $s_arche $world $r_arche $args.preserved_repo_dirs
    { staging_arche: $s_arche }
}

# Scoped mirror of the owned arche subtrees staging -> repo.
#
# rm-then-cp per subtree, so a dropped or renamed artifact leaves no stale file in
# the repo. Only the OWNED_SUBS are touched - the blast radius is exactly those.
export def inline [
    args: record<hypogeios_repo_dir: directory, generated_tmp_dir: directory>
]: nothing -> record<inlined: list<string>> {
    let s_arche = (staging-arche $args.generated_tmp_dir)
    let r_arche = (repo-arche $args.hypogeios_repo_dir)
    for sub in $OWNED_SUBS {
        let s = ($s_arche | path join $sub)
        let r = ($r_arche | path join $sub)
        if ($r | path exists) { rm --recursive --force $r }
        if ($s | path exists) {
            mkdir ($r | path dirname)
            cp --recursive $s $r
        }
    }
    { inlined: $OWNED_SUBS }
}

# The build call-target - the hypogeios:dev/repo:build mechanical reproduction.
#
# See the file header for the explicit-repo-dir (never path-self) write rule and
# the reproducibility model. Clean-gates the repo, regenerates into staging
# (generate), mirrors the owned arche subtrees back (inline), and returns the git
# drift - empty on a faithful clean-tree reproduction.
export def main [
    args: record<
        hypogeios_repo_dir: directory,
        preserved_repo_dirs: record<zork1: directory, zork2: directory, zork3: directory>,
        generated_tmp_dir: directory
    >
]: nothing -> record<gstat: record<modified: list<string>, added: list<string>, deleted: list<string>>, generated_tmp_dir: string> {
    assert-clean $args.hypogeios_repo_dir
    generate $args
    inline $args
    {
        gstat: (git-drift $args.hypogeios_repo_dir),
        generated_tmp_dir: ($args.generated_tmp_dir | into string),
    }
}
