# Shared substrate for the hypogeios suite: the cross-library locale loader.
#
# Carries the `locale` module (prose / term over each library's .assets/locale).
# Game libraries consume it with `use pelos locale *`. Session persistence and the
# shared turn contract land here as later modules.

export use ./locale.nu
