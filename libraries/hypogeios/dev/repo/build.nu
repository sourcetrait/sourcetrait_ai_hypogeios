# Reproducible build machine for the hypogeios suite (a step machine).
#
# main IS the call-target hypogeios:dev/repo:build: it regenerates all
# preserved/deviated data + the engine consts from the external ZIL source repos
# into a staging tree (generate), then copies the owned arche subtrees back into
# the project repo (inline). The mechanical phases are deterministic; a clean-tree
# build that reproduces the committed data yields an EMPTY gstat. The flag
# dictionary is an AGENT step (re-authored, may drift) - wired next as a build
# pause; SLICE 2 runs the mechanical pipeline with the CURRENT committed flags
# (the no-agent reproduction mode).
#
# WRITE TARGET IS ALWAYS THE EXPLICIT hypogeios_repo_dir (the project repo on
# disk), NEVER path-self: a committed library serves from the MCP's signed store
# copy, so path-self would resolve into the store and write generated data into
# the MCP's own git repo. Every artifact path derives from the explicit args;
# only the dev TOOLS resolve from the promoted store (use arche). path-self stays
# in the pelos runtime loaders.
#
# Phases (composed by main; individually runnable for stage -> review -> accept):
# - generate: preserve (4 ZIL extractors -> staging preserved/) + the flags input
#   + deviate (map/objects/syntax -> staging deviated/) + derive (the engine/
#   conditions/vocabulary consts) into <generated_tmp_dir>/libraries/arche.
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

# The step_data.flags schema (the flags agent step's typed output) - the canonical
# source, hand-synced to build's step_data positional and (next slice) filled into
# the driver template via %{step_schema}%, the way ENGINE_TYPE mirrors model_engine.
const STEP_3_TYPE: string = "record<flags: table<snake: string, preserved: string, summary: string, state: oneof<nothing, record<default: bool, scope: list<string>>>>>"

# <repo>/libraries/arche - the project arche library root (the inline target).
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

# DEVIATE + DERIVE (mechanical): map preserved -> deviated through the staging
# deviated/flags.nuon, then code-gen the engine/conditions/vocabulary consts into
# the staging arche root. Assumes deviated/flags.nuon is already staged.
def deviate-derive [s_arche: directory, world: directory]: nothing -> nothing {
    arche alpha dev world zil deviate $world "alpha"
    arche alpha dev objects zil objects deviate $world "alpha"
    arche dev syntax zil syntax deviate $world
    arche dev derive derive_engine (arche dev model model_engine $world) $s_arche
    arche dev derive derive_conditions (arche dev model model_conditions $world "alpha") "alpha" $s_arche
    arche dev derive derive_vocabulary (arche dev model model_vocabulary $world "alpha") "alpha" $s_arche | ignore
}

# Run the full mechanical regen into a fresh staging tree.
#
# Carries the CURRENT committed deviated/flags.nuon as the flag input (the
# no-agent reproduction mode; the step machine substitutes the agent-authored
# flags). Writes only under generated_tmp_dir; returns the staging arche root.
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
    mkdir ($world | path join "deviated")
    cp ($r_arche | path join ".assets" "world" "deviated" "flags.nuon") ($world | path join "deviated" "flags.nuon")
    deviate-derive $s_arche $world
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

# The build step machine - the hypogeios:dev/repo:build call-target.
#
# See the file header for the phases, the explicit-repo-dir (never path-self)
# write rule, and the reproducibility model. Dispatches on step: 1 = PRESERVE +
# pause for the flags agent; 3 = the agent's step_data.flags + DEVIATE/DERIVE +
# inline. (Prompt templating for the pause lands next slice.)
export def main [
    args: record<
        hypogeios_repo_dir: directory,
        preserved_repo_dirs: record<zork1: directory, zork2: directory, zork3: directory>,
        generated_tmp_dir: directory,
        step: int,
        step_data: oneof<nothing, record<flags: table<snake: string, preserved: string, summary: string, state: oneof<nothing, record<default: bool, scope: list<string>>>>>>
    >
]: nothing -> record<step: int, paused: bool, gstat: record<modified: list<string>, added: list<string>, deleted: list<string>>, next_step: oneof<int, nothing>, next_step_prompt: oneof<string, nothing>, next_step_prompt_shm: oneof<string, nothing>, generated_tmp_dir: string> {
    assert-clean $args.hypogeios_repo_dir
    if (($args.step != 1) and ($args.step != 3)) {
        error make {msg: $"build: unknown step ($args.step) - expected 1 or 3"}
    }
    let s_arche = (staging-arche $args.generated_tmp_dir)
    let world = ($s_arche | path join ".assets" "world")
    if $args.step == 1 {
        # STEP 1: fresh staging + mechanical PRESERVE, then PAUSE for the flags agent.
        let locale = ($s_arche | path join ".assets" "locale" "en_us")
        if ($s_arche | path exists) { rm --recursive --force $s_arche }
        mkdir $world
        mkdir $locale
        preserve $world $locale $args.preserved_repo_dirs
        {
            step: 1,
            paused: true,
            gstat: {modified: [], added: [], deleted: []},
            next_step: 3,
            next_step_prompt: "flags agent step: author the deviated flags table from staging preserved/flags.nuon + the arche flags recipe, then call build(step 3, ..., step_data={flags: <table>}). Prompt templating lands next slice.",
            next_step_prompt_shm: null,
            generated_tmp_dir: ($args.generated_tmp_dir | into string),
        }
    } else {
        # STEP 3: write the agent flags into staging, then DEVIATE + DERIVE + inline.
        if $args.step_data == null {
            error make {msg: "build step 3: step_data (record<flags>) is required - the flags agent output"}
        }
        mkdir ($world | path join "deviated")
        $args.step_data.flags | to nuon --list-of-records --indent 2 | save -f ($world | path join "deviated" "flags.nuon")
        deviate-derive $s_arche $world
        inline $args
        {
            step: 3,
            paused: false,
            gstat: (git-drift $args.hypogeios_repo_dir),
            next_step: null,
            next_step_prompt: null,
            next_step_prompt_shm: null,
            generated_tmp_dir: ($args.generated_tmp_dir | into string),
        }
    }
}
