# Shared substrate for the hypogeios suite: the cross-library locale loader.
#
# Carries the `locale` module (prose / term over each library's .assets/locale) and
# the `render` module (the suite's markdown render conventions, design deviation
# #2). Game libraries consume them with `use pelos locale *` / `use pelos render *`.
# Session persistence and the shared turn contract land here as later modules.

export use ./locale.nu
export use ./render.nu
