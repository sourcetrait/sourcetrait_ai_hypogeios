# Shared substrate for the hypogeios suite: cross-library locale + data loaders.
#
# Carries the `locale` module (prose / term over each library's .assets/locale), the
# `data` module (per-file structured data, e.g. objects, over .assets/world/deviated),
# and the `render` module (the suite's markdown render conventions, design deviation
# #2). Game libraries consume them with `use pelos locale *` / `use pelos data *` /
# `use pelos render *`. Session persistence and the shared turn contract land here as
# later modules.

export use ./locale.nu
export use ./data.nu
export use ./render.nu
