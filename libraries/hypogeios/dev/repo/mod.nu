# Reproducible build machine: regenerate the suite data from the ZIL source.
#
# Owns the chain-of-custody build for the suite (followups #5): build (the
# call-target step machine) composes the generate (mechanical preserve/deviate/
# derive into a staging tree) and inline (scoped staging -> repo) phases. build is
# the single advertised call-target; generate/inline land as organizational,
# run-invoked exports beside it.
export use ./build.nu
