# Parser vocabulary (hand-authored; grows as verbs are ported from the C++ act
# files). Keys are 5-char-uppercased input words.
export const DIRS = {
    "NORTH": "North", "N": "North", "SOUTH": "South", "S": "South",
    "EAST": "East", "E": "East", "WEST": "West", "W": "West",
    "NE": "Ne", "NW": "Nw", "SE": "Se", "SW": "Sw",
    "UP": "Up", "U": "Up", "DOWN": "Down", "D": "Down",
    "ENTER": "Enter", "IN": "Enter", "INSID": "Enter", "INTO": "Enter",
    "EXIT": "Exit", "OUT": "Exit", "LEAVE": "Exit",
    "CROSS": "Cross", "TRAVE": "Cross", "LAND": "Land", "LAUNC": "Launc"
}
export const VERBS = {
    "LOOK": "LOOK", "L": "LOOK", "STARE": "LOOK", "GAZE": "LOOK",
    "WALK": "WALK", "GO": "WALK", "RUN": "WALK", "PROCE": "WALK",
    "INVEN": "INVEN", "I": "INVEN", "LIST": "INVEN",
    "OPEN": "OPEN", "CLOSE": "CLOSE", "READ": "READ",
    "TAKE": "TAKE", "GET": "TAKE", "GRAB": "TAKE", "HOLD": "TAKE",
    "CARRY": "TAKE", "REMOV": "TAKE", "DROP": "DROP", "PUT": "DROP"
}
export const NOISE = ["THE", "A", "AN", "MY", "AT", "OF", "UP"]
