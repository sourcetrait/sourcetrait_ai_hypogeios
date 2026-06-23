# Shared markdown render conventions for the hypogeios suite (design deviation #2).
#
# Player-visible text is markdown; these helpers carry the markup that is CODE's
# job, not the locale author's - the structural pieces the assets cannot author
# themselves. Assets author their own inline markdown (category italics, named
# bold, navigation links, bullets); code owns the room-title heading and (with
# arche) engine-generated lists. Organizational module (plain exports, no
# call-target); consume with `use pelos render *`.

# A room-entry title as a markdown h1: the heading prefix only, no trailing newline
# (the caller joins it to the body).
export def h1 [text: string]: nothing -> string {
    $"# ($text)"
}
