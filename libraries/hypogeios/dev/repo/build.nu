# Reproducible build machine for the hypogeios suite (a step machine).
#
# main IS the call-target hypogeios:dev/repo:build: it regenerates all
# preserved/deviated data + the engine consts from the external ZIL source repos
# into a staging tree (generate), then copies the owned arche subtrees back into
# the project repo (inline) for review. It runs the MECHANICAL phases itself and
# PAUSES at the mid-pipeline AGENT step (the flag dictionary), returning a driver
# instruction for the caller to run an Explore subagent and resume via
# call(build, <next_step>, ..., step_data).
#
# WRITE TARGET IS ALWAYS THE EXPLICIT hypogeios_repo_dir (the project repo on
# disk), NEVER path-self: a committed library serves from the MCP's signed store
# copy, so path-self would resolve into the store and write generated data into
# the MCP's own git repo, not the project. Every artifact path derives from the
# explicit args; only the dev TOOLS resolve from the promoted store (use arche /
# use pelos, added with the phases). path-self stays in the pelos runtime loaders.
#
# Steps (alpha; flags is the single agent step, so build pauses preserve -> FLAGS
# (agent) -> deviate/derive): step 1 = clean-gate + mechanical PRESERVE into
# staging + emit the flags driver/subagent prompts, then PAUSE; step 3 = clean-
# gate + the typed step_data.flags self-validates + write it to staging + the
# mechanical DEVIATE + DERIVE + inline. SLICE 1 stubs the phases (clean-gate +
# gstat only) to prove the module wiring, the call-target, and the contract.

# Abort unless the repo git tree is clean. The build's precondition: the post-
# build gstat must show exactly the build's own changes, so the tree starts clean.
def assert-clean [repo: directory]: nothing -> nothing {
    let status = (^git -C $repo status --porcelain | str trim)
    if (not ($status | is-empty)) {
        error make {msg: $"build: ($repo) has a dirty git tree - commit or stash before a build"}
    }
}

# The repo porcelain status as the build's drift report: which files the build
# added / modified / deleted. Porcelain XY code: contains D -> deleted, ? or A ->
# added, else modified (refined when inline lands and the report is non-empty).
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

# The build step machine - the hypogeios:dev/repo:build call-target.
#
# See the file header for the steps, the pause/resume contract, and the
# explicit-repo-dir (never path-self) write rule.
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
    # SLICE 1: phases not yet wired - report a clean (empty) drift to prove the
    # plumbing (typed args, clean-gate, gstat, explicit repo dir).
    {
        step: $args.step,
        paused: false,
        gstat: (git-drift $args.hypogeios_repo_dir),
        next_step: null,
        next_step_prompt: null,
        next_step_prompt_shm: null,
        generated_tmp_dir: ($args.generated_tmp_dir | into string),
    }
}
