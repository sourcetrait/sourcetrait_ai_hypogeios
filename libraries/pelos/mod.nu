# Shared substrate for the hypogeios suite: cross-library locale + data loaders.
#
# Carries the `locale` module (prose / term over each library's .assets/locale), the
# `data` module (per-file structured data, e.g. objects, over .assets/world/deviated),
# the `render` module (the suite's markdown render conventions, design deviation #2),
# and the `dev` module (build-time tooling, e.g. construct_prompt - kept out of the
# runtime path so a game never depends on it). Game libraries consume the runtime
# modules with `use pelos locale *` / `use pelos data *` / `use pelos render *`; dev
# tooling uses the canonical `use pelos` then `pelos dev <fn>`. Session persistence
# and the shared turn contract land here as later modules.

export use ./locale.nu
export use ./data.nu
export use ./render.nu
export module dev
