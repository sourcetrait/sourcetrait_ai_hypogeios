# Dev-support tooling for the hypogeios suite (build-time, not runtime).
#
# Helpers that support BUILDING the suite rather than playing it, kept out of the
# runtime modules (locale / data / render) so a game never depends on them. Consume
# with the canonical form `use pelos` then `pelos dev <fn>` (module-qualified; never
# glob). First member: construct_prompt - the %{}% template filler the reproducible
# build (followups #5) uses to assemble its driver / subagent prompts; its code is
# deliberately separate from locale's prose filler so either can lift to the empower
# plugin independently.

# Fill a %{variable}% template and write the result to output_prompt_shm.
#
# Dev-time prompt assembler for the reproducible build. Reads prompt_template,
# replaces each %{variable}% with its fill value in a single pass (an inserted value
# is never rescanned, so it cannot smuggle a further placeable), writes the resolved
# text to output_prompt_shm, and returns it. variable keys are bare snakes [a-z0-9_]+;
# a fill value carrying a %{ or }% delimiter is rejected up front; after the pass any
# remaining %{ or }% (an unfilled key or malformed delimiter) is a hard error. Both
# args are full paths (the caller owns shm-root resolution); output_prompt_shm's
# parent is created if absent. Mirrors locale prose's fill discipline by intent, with
# its own code (independent empower-plugin lift).
export def construct_prompt [
    prompt_template: path,
    output_prompt_shm: path,
    fill: table<variable: string, value: string>
]: nothing -> string {
    if not ($prompt_template | path exists) {
        error make {msg: $"construct_prompt: no template at ($prompt_template)"}
    }
    for f in $fill {
        if not ($f.variable =~ '^[a-z0-9_]+$') {
            error make {msg: $"construct_prompt: invalid variable '($f.variable)' - expected [a-z0-9_]+"}
        }
        if (($f.value | str contains "%{") or ($f.value | str contains "}%")) {
            error make {msg: $"construct_prompt: fill value for '($f.variable)' carries a placeable delimiter"}
        }
    }
    let template = (open --raw $prompt_template | decode)
    let resolved = ($fill | reduce --fold $template {|f, acc|
        $acc | str replace --all $"%{($f.variable)}%" $f.value
    })
    if (($resolved | str contains "%{") or ($resolved | str contains "}%")) {
        error make {msg: $"construct_prompt: unfilled or malformed placeable in ($prompt_template)"}
    }
    mkdir ($output_prompt_shm | path dirname)
    $resolved | save -f $output_prompt_shm
    $resolved
}
