# Parser vocabulary. DIRS / PREPS / BUZZ / BUNCHERS mirror the C++ init_dung
# (directions_pobl + dir_syns; add_zork kPrep + synonym; add_buzz;
# add_buncher). The verb words live in data_syntax.nu (VERB_WORDS, generated).
# Keys are 5-char-uppercased input words.

# direction word -> the exit `dir` value (directions_pobl + dir_syns).
export const DIRS = {
    "NORTH": "North", "N": "North", "SOUTH": "South", "S": "South",
    "EAST": "East", "E": "East", "WEST": "West", "W": "West",
    "NE": "Ne", "NW": "Nw", "SE": "Se", "SW": "Sw",
    "UP": "Up", "U": "Up", "DOWN": "Down", "D": "Down",
    "ENTER": "Enter", "IN": "Enter",
    "EXIT": "Exit", "OUT": "Exit", "LEAVE": "Exit",
    "CROSS": "Cross", "TRAVE": "Cross", "LAND": "Land", "LAUNC": "Launc"
}

# preposition word -> canonical prep (add_zork kPrep + synonym aliases). The
# syntax tables store the canonical form (THROU/USING -> WITH, INTO/INSID -> IN).
export const PREPS = {
    "OVER": "OVER", "WITH": "WITH", "AT": "AT", "TO": "TO", "IN": "IN",
    "FOR": "FOR", "DOWN": "DOWN", "UP": "UP", "UNDER": "UNDER", "OF": "OF",
    "FROM": "FROM", "ON": "ON", "OFF": "OFF", "OUT": "OUT",
    "USING": "WITH", "THROU": "WITH", "INSID": "IN", "INTO": "IN"
}

# noise words, silently skipped (add_buzz). AND / THEN are handled in the lexer.
export const BUZZ = ["BY", "IS", "A", "THE", "AN", "TODAY", "HOW", "CHIMN"]

# verbs that accept a bunch (AND-list); bunching itself is not yet ported.
export const BUNCHERS = ["TAKE", "DROP", "PUT", "COUNT"]
