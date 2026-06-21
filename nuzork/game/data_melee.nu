# Combat data, hand-ported from ~/repo/zork. The attack-outcome def tables
# (dung.cpp def1/def2/def3 + the *_res spans) and the per-weapon/villain melee
# message tables (strings.cpp tofmsgs; D="%D%" defender, W="%W%" weapon). Only
# the tables the troll fight needs (sword + troll) are ported so far; the other
# villains (cyclops/knife/thief) follow with the rest of melee.

# attack_state indices (melee.h): missed 0, unconscious 1, killed 2,
# light_wound 3, serious_wound 4, stagger 5, lose_weapon 6, hesitate 7,
# sitting_duck 8. A def-table span is the first 9 outcomes blow() rolls among.

# def1 (defender strength 1): att clamped to 1..3 -> span index att-1.
export const DEF1_RES = [
    [0, 0, 0, 0, 5, 5, 1, 1, 2],
    [0, 0, 0, 5, 5, 1, 1, 2, 2],
    [0, 0, 5, 5, 1, 1, 2, 2, 2]
]
# def2 (defender strength 2): att clamped to 1..4 -> span index att-1.
export const DEF2_RES = [
    [0, 0, 0, 0, 0, 5, 5, 3, 3],
    [0, 0, 0, 5, 5, 3, 3, 3, 1],
    [0, 0, 5, 5, 3, 3, 3, 1, 2],
    [0, 5, 5, 3, 3, 3, 1, 2, 2]
]
# def3 (defender strength >2): span index (att-def)+2, clamped to 0..4.
export const DEF3_RES = [
    [0, 0, 0, 0, 0, 5, 5, 3, 3],
    [0, 0, 0, 0, 5, 5, 3, 3, 4],
    [0, 0, 0, 5, 5, 3, 3, 3, 4],
    [0, 0, 5, 5, 3, 3, 3, 4, 4],
    [0, 5, 5, 3, 3, 3, 3, 4, 4]
]

# Per outcome (index = attack_state), a list of message variants. One is chosen
# at random; %D% -> defender, %W% -> weapon. SWORD_MELEE (the player's weapon)
# omits hesitate/sitting_duck - those only arise from the demon free-swing.
export const SWORD_MELEE = [
    [
        "Your swing misses the %D% by an inch.",
        "A mighty blow, but it misses the %D% by a mile.",
        "You charge, but the %D% jumps nimbly aside.",
        "Clang! Crash! The %D% parries.",
        "A good stroke, but it's too slow, the %D% dodges."
    ],
    [
        "Your sword crashes down, knocking the %D% into dreamland.",
        "The %D% is battered into unconsciousness.",
        "A furious exchange, and the %D% is knocked out!"
    ],
    [
        "It's curtains for the %D% as your sword removes his head.",
        "The fatal blow strikes the %D% square in the heart:  He dies.",
        "The %D% takes a final blow and slumps to the floor dead."
    ],
    [
        "The %D% is struck on the arm, blood begins to trickle down.",
        "Your sword pinks the %D% on the wrist, but it's not serious.",
        "Your stroke lands, but it was only the flat of the blade.",
        "The blow lands, making a shallow gash in the %D%'s arm!"
    ],
    [
        "The %D% receives a deep gash in his side.",
        "A savage blow on the thigh!  The %D% is stunned but can still fight!",
        "Slash!  Your blow lands!  That one hit an artery, it could be serious!"
    ],
    [
        "The %D% is staggered, and drops to his knees.",
        "The %D% is momentarily disoriented and can't fight back.",
        "The force of your blow knocks the %D% back, stunned."
    ],
    [
        "The %D%'s weapon is knocked to the floor, leaving him unarmed."
    ]
]
export const TROLL_MELEE = [
    [
        "The troll swings his axe, but it misses.",
        "The troll's axe barely misses your ear.",
        "The axe sweeps past as you jump aside.",
        "The axe crashes against the rock, throwing sparks!"
    ],
    [
        "The flat of the troll's axe hits you delicately on the head, knocking\nyou out."
    ],
    [
        "The troll lands a killing blow.  You are dead.",
        "The troll neatly removes your head.",
        "The troll's axe stroke cleaves you from the nave to the chops.",
        "The troll's axe removes your head."
    ],
    [
        "The axe gets you right in the side.  Ouch!",
        "The flat of the troll's axe skins across your forearm.",
        "The troll's swing almost knocks you over as you barely parry\nin time.",
        "The troll swings his axe, and it nicks your arm as you dodge."
    ],
    [
        "The troll charges, and his axe slashes you on your %W% arm.",
        "An axe stroke makes a deep wound in your leg.",
        "The troll's axe swings down, gashing your shoulder.",
        "The troll sees a hole in your defense, and a lightning stroke\nopens a wound in your left side."
    ],
    [
        "The troll hits you with a glancing blow, and you are momentarily\nstunned.",
        "The troll swings; the blade turns on your armor but crashes\nbroadside into your head.",
        "You stagger back under a hail of axe strokes.",
        "The troll's mighty blow drops you to your knees."
    ],
    [
        "The axe hits your %W% and knocks it spinning.",
        "The troll swings, you parry, but the force of his blow disarms you.",
        "The axe knocks your %W% out of your hand.  It falls to the floor.",
        "Your %W% is knocked out of your hands, but you parried the blow."
    ],
    [
        "The troll strikes at your unconscious form, but misses in his rage.",
        "The troll hesitates, fingering his axe.",
        "The troll scratches his head ruminatively:  Might you be magically\nprotected, he wonders? ",
        "The troll seems afraid to approach your crumpled form."
    ],
    [
        "Conquering his fears, the troll puts you to death."
    ]
]

export const DEATH_HERALD = "As you take your last breath, you feel relieved of your burdens. The\nfeeling passes as you find yourself before the gates of Hell, where\nthe spirits jeer at you and deny you entry.  Your senses are\ndisturbed.  The objects in the dungeon appear indistinct, bleached of\ncolor, even unreal."
export const SUICIDAL_HERALD = "You clearly are a suicidal maniac.  We don't allow psychotics in the\ncave, since they may harm other adventurers.  Your remains will be\ninstalled in the Land of the Living Dead, where your fellow\nadventurers may gloat over them."
