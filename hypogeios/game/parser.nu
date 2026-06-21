# hypogeios MDL parser: turns an input line into (PRSA, PRSO, PRSI) and matches
# it against the verb syntax tables (data_syntax.nu). Ported from ~/repo/github/jclaar/zork
# parser.cpp (lex / sparse / get_object / search_list / syn_match / syn_equal /
# gwim / take_it) and makstr.cpp. The world model (world.nu) supplies object
# location, flags, and lighting; this module is pure of verb handlers.
#
# Faithful: verb/dir/prep/adj/object classification, get_object search order
# (lit room -> inventory -> reachable globals) with adjective disambiguation
# and open/transparent-container recursion, syn_match driver fallback + sflip,
# gwim/fwim implied-object fill, take_it auto-take (vtbit slots).
# Deferred (followups; do not affect single-command play): AND-bunching,
# EXCEPT/BUT, THEN chaining, OOPS/AGAIN, OF, cross-turn orphan reply, the IT
# referent, vehicle-relative reach, and the rarer take_it complaint branches.
use ./world.nu *
use ./data_objects.nu *
use ./data_syntax.nu *
use ./data_vocab.nu *

# --- tokenizer: input -> [{w (5-char upper), raw (original)}] --------------
export def lex-toks [input: string]: nothing -> list {
    $input | str downcase | split row -r '[^a-z0-9]+' | where {|x| $x != "" } | each {|word|
        { w: ($word | str upcase | split chars | first 5 | str join), raw: $word }
    }
}

# --- bit-set matching (trnn_bits = obj shares any acceptable bit) ----------
def cur-bits [state: record, oid: string]: nothing -> list {
    if ($oid in ($state.oflags | columns)) { $state.oflags | get $oid } else { (find-obj $oid).bits }
}
def vbit-match [bits: list, vbit: record]: nothing -> bool {
    if $vbit.any { true } else { ($vbit.bits | any {|b| $b in $bits }) }
}
def vbit-none [vbit: record]: nothing -> bool {
    (not $vbit.any) and ($vbit.bits | is-empty)
}

# --- object resolution (get_object / search_list / this_it) ---------------
def obj-adjs [oid: string]: nothing -> list {
    (find-obj $oid).adj? | default []
}
def this-it [state: record, name: string, oid: string, adj: any]: nothing -> bool {
    let o = (find-obj $oid)
    if ($o == null) { return false }
    if (not (oflag $state $oid "ovison")) { return false }
    if ($name not-in $o.syns) { return false }
    if ($adj == null) { true } else { $adj in ($o.adj? | default []) }
}
# Search an object list for `name`, with adjective disambiguation and
# recursion into open / transparent (or searchbit, when not first) containers.
# Returns { obj: oid|null, status: "found"|"none"|"ambig" }.
def search-list [state: record, name: string, oids: list, adj: any, first: bool]: nothing -> record {
    mut oobj: any = null
    mut ambig = false
    for oid in $oids {
        if (this-it $state $name $oid $adj) {
            if ($oobj != null) {
                if ($adj == null) {
                    let a_new = (obj-adjs $oid)
                    let a_old = (obj-adjs $oobj)
                    if (($a_old | is-empty) and ($a_new | is-empty)) {
                        return { obj: null, status: "ambig" }
                    } else if ($a_new | is-empty) {
                        $oobj = $oid
                    } else {
                        $ambig = true
                    }
                } else {
                    return { obj: null, status: "ambig" }
                }
            } else {
                $oobj = $oid
            }
        } else if ((oflag $state $oid "ovison") and ((oflag $state $oid "openbit") or (oflag $state $oid "transbit")) and ($first or (oflag $state $oid "searchbit"))) {
            let nobj = (search-list $state $name (cont-of $state $oid) $adj false)
            if ($nobj.obj != null) {
                if ($oobj != null) { return { obj: null, status: "ambig" } } else { $oobj = $nobj.obj }
            } else if ($nobj.status == "ambig") {
                return { obj: null, status: "ambig" }
            }
        }
    }
    if ($ambig and ($oobj != null) and (not ((obj-adjs $oobj) | is-empty))) {
        return { obj: null, status: "ambig" }
    }
    { obj: $oobj, status: (if ($oobj == null) { "none" } else { "found" }) }
}
# Reachable globals: GObjects whose gbit is in the room's rglobal (or null).
def reachable-globals [state: record]: nothing -> list {
    let rg = ((find-room $state.here).rglobal? | default [])
    $OBJECTS | where {|o|
        ($o.is_global? | default false) and (let g = ($o.gbit? | default null); ($g == null) or ($g in $rg))
    } | get oid
}
export def get-object [state: record, name: string, adj: any]: nothing -> record {
    if (lit $state $state.here) {
        let r = (search-list $state $name (room-objs $state $state.here) $adj true)
        if ($r.obj != null) { return { obj: $r.obj, status: "found" } }
        if ($r.status == "ambig") { return { obj: null, status: "ambig" } }
    }
    let inv = (search-list $state $name (player-inv $state) $adj true)
    if ($inv.obj != null) { return { obj: $inv.obj, status: "found" } }
    if ($inv.status == "ambig") { return { obj: null, status: "ambig" } }
    let g = (search-list $state $name (reachable-globals $state) $adj true)
    if ($g.obj != null) { return { obj: $g.obj, status: "found" } }
    { obj: null, status: "none" }
}

# --- gwim / fwim: fill an unfilled-but-required slot ----------------------
def fwim [state: record, vfwim: record, oids: list, no_care: bool]: nothing -> record {
    mut found: any = null
    for oid in $oids {
        if ((oflag $state $oid "ovison") and ($no_care or (oflag $state $oid "takebit")) and (vbit-match (cur-bits $state $oid) $vfwim)) {
            if ($found != null) { return { obj: null, status: "ambig" } } else { $found = $oid }
        }
        if ((oflag $state $oid "ovison") and (oflag $state $oid "openbit")) {
            for c in (cont-of $state $oid) {
                if ((oflag $state $c "ovison") and (vbit-match (cur-bits $state $c) $vfwim)) {
                    if ($found != null) { return { obj: null, status: "ambig" } } else { $found = $c }
                }
            }
        }
    }
    { obj: $found, status: (if ($found == null) { "none" } else { "found" }) }
}
def gwim [state: record, varg: record]: nothing -> record {
    let dont_care = (not $varg.vcbit)
    mut aobj: any = null
    if $varg.vabit {
        $aobj = (fwim $state $varg.vfwim (player-inv $state) $dont_care).obj
    }
    if (($aobj == null) and $varg.vrbit and (lit $state $state.here)) {
        let robj = (fwim $state $varg.vfwim (room-objs $state $state.here) $dont_care)
        if ($robj.obj != null) { return { obj: $robj.obj, status: "found" } }
        if ($robj.status == "ambig") { return { obj: null, status: "ambig" } }
    }
    { obj: $aobj, status: (if ($aobj == null) { "none" } else { "found" }) }
}

# --- take_it: auto-take vtbit slots before the verb runs ------------------
def take-it [state: record, oid: string, varg: record]: nothing -> record {
    if ($varg.vtbit and (oflag $state $oid "takebit") and ($oid in (room-objs $state $state.here)) and ($oid not-in (player-inv $state))) {
        if (lit $state $state.here) {
            let st = (set-loc (set-oflag $state $oid "touchbit" true) $oid { at: "player", id: "" })
            { ok: true, state: (score-take $st $oid), out: ["Taken."] }
        } else {
            { ok: false, state: $state, out: ["It is too dark in here to see."] }
        }
    } else {
        { ok: true, state: $state, out: [] }
    }
}
def take-slots [state: record, syn: record, p0: any, p1: any]: nothing -> record {
    mut st = $state
    mut out = []
    if ($p0 != null) {
        let r = (take-it $st $p0 ($syn.syn | get 0))
        $st = $r.state; $out = ($out | append $r.out)
        if (not $r.ok) { return { ok: false, state: $st, out: $out } }
    }
    if ($p1 != null) {
        let r = (take-it $st $p1 ($syn.syn | get 1))
        $st = $r.state; $out = ($out | append $r.out)
        if (not $r.ok) { return { ok: false, state: $st, out: $out } }
    }
    { ok: true, state: $st, out: $out }
}

# --- syntax matching (syn_equal / syn_match) ------------------------------
def syn-equal [state: record, varg: record, slot: any]: nothing -> bool {
    if ($slot == null) {
        (vbit-none $varg.vbit)
    } else {
        ($varg.vprep == $slot.prep) and (vbit-match (cur-bits $state $slot.obj) $varg.vbit)
    }
}
# Match the accumulated object slots against the verb's syntax table, applying
# the driver fallback and GWIM. Returns the resolved command for dispatch.
def syn-match [state: record, action: string, objs: list]: nothing -> record {
    let act = ($ACTIONS | get $action)
    let o1 = (if (($objs | length) >= 1) { $objs | get 0 } else { null })
    let o2 = (if (($objs | length) >= 2) { $objs | get 1 } else { null })
    mut winner: any = null; mut wp0: any = null; mut wp1: any = null
    mut dforce: any = null; mut drive: any = null
    for syn in $act.vdecl {
        let m0 = (syn-equal $state ($syn.syn | get 0) $o1)
        if ($m0 and (syn-equal $state ($syn.syn | get 1) $o2)) {
            if ($winner == null) {
                $winner = $syn
                if $syn.sflip { $wp0 = $o2; $wp1 = $o1 } else { $wp0 = $o1; $wp1 = $o2 }
            }
        } else if (($m0 and ($o2 == null)) or ($o1 == null)) {
            if ($syn.sdriver and ($dforce == null)) { $dforce = $syn
            } else if ($drive == null) { $drive = $syn }
        }
    }
    if ($winner != null) {
        return (finish-syntax $state $winner $action $wp0 $wp1)
    }
    let d = (if ($dforce != null) { $dforce } else { $drive })
    if ($d == null) {
        return { ok: false, sfcn: null, prso: null, prsi: null, dir: null, state: $state, out: ["I can't make sense out of that."] }
    }
    # GWIM-fill the driver's empty required slots.
    mut p0 = $o1
    mut p1 = $o2
    let s0 = ($d.syn | get 0)
    if (($p0 == null) and (not (vbit-none $s0.vbit))) {
        let g = (gwim $state $s0)
        if ($g.obj == null) {
            return { ok: false, sfcn: null, prso: null, prsi: null, dir: null, state: $state, out: [(ortell $s0 $act)] }
        }
        $p0 = { prep: $s0.vprep, obj: $g.obj }
    }
    let s1 = ($d.syn | get 1)
    if (($p1 == null) and (not (vbit-none $s1.vbit))) {
        let g = (gwim $state $s1)
        if ($g.obj == null) {
            return { ok: false, sfcn: null, prso: null, prsi: null, dir: null, state: $state, out: [(ortell $s1 $act)] }
        }
        $p1 = { prep: $s1.vprep, obj: $g.obj }
    }
    finish-syntax $state $d $action $p0 $p1
}
# A "<verb> what?" prompt for an unfilled required slot (ortell, simplified):
# a prep-led slot asks "with what?"; a bare slot asks "Open what?" (vstr kept).
def ortell [varg: record, act: record]: nothing -> string {
    if ($varg.vprep != null) {
        $"($varg.vprep | str downcase) what?"
    } else {
        $"($act.vstr) what?"
    }
}
# Auto-take the winning slots, then hand back the resolved command.
def finish-syntax [state: record, syn: record, action: string, p0: any, p1: any]: nothing -> record {
    let prso = (if ($p0 == null) { null } else { $p0.obj })
    let prsi = (if ($p1 == null) { null } else { $p1.obj })
    let t = (take-slots $state $syn $prso $prsi)
    { ok: $t.ok, sfcn: $syn.sfcn, sverb: $syn.sverb, action: $action, prso: $prso, prsi: $prsi, dir: null, state: $t.state, out: $t.out }
}

# --- sparse: classify tokens, build the parse vector, then syn_match ------
export def parse-input [state: record, input: string]: nothing -> record {
    let toks = (lex-toks $input)
    if ($toks | is-empty) {
        return { ok: false, sfcn: null, action: null, prso: null, prsi: null, dir: null, state: $state, out: [] }
    }
    let all_adj = ($OBJECTS | each {|o| $o.adj? | default [] } | flatten | uniq)
    let all_names = ($OBJECTS | each {|o| $o.syns } | flatten | uniq)
    mut action: any = null
    mut prep: any = null
    mut adj: any = null
    mut objs = []
    mut dir: any = null
    for tk in $toks {
        let w = $tk.w
        let lc = ($tk.raw | str downcase)
        if ($w in $BUZZ) { continue }
        if ($w == "AND") { continue }
        if ($w == "THEN") { break }
        if (($action == null) and ($w in ($VERB_WORDS | columns))) {
            $action = ($VERB_WORDS | get $w); continue
        }
        if ((($action == null) or (($action == "WALK") and ($prep == null))) and ($w in ($DIRS | columns))) {
            if ($action == null) { $action = "WALK" }
            $dir = ($DIRS | get $w); continue
        }
        if ($w in ($PREPS | columns)) { $prep = ($PREPS | get $w); $adj = null; continue }
        if ($w in $all_adj) { $adj = $w; continue }
        if ($w in $all_names) {
            let go = (get-object $state $w $adj)
            if ($go.obj != null) {
                $objs = ($objs | append { prep: $prep, obj: $go.obj }); $prep = null; $adj = null
            } else if ($go.status == "ambig") {
                let v = (if ($action == null) { "do that with" } else { ($ACTIONS | get $action | get vstr | str downcase) })
                return { ok: false, sfcn: null, action: $action, prso: null, prsi: null, dir: null, state: $state, out: [$"Which ($lc) should I ($v)?"] }
            } else if (lit $state $state.here) {
                let ap = (if ($adj == null) { "" } else { $"($adj | str downcase) " })
                return { ok: false, sfcn: null, action: $action, prso: null, prsi: null, dir: null, state: $state, out: [$"I can't see any ($ap)($lc) here."] }
            } else {
                return { ok: false, sfcn: null, action: $action, prso: null, prsi: null, dir: null, state: $state, out: ["It is too dark to see."] }
            }
        } else if (($action != null) and ($w in ($VERB_WORDS | columns))) {
            return { ok: false, sfcn: null, action: $action, prso: null, prsi: null, dir: null, state: $state, out: ["Two verbs in command?"] }
        } else {
            return { ok: false, sfcn: null, action: null, prso: null, prsi: null, dir: null, state: $state, out: [$"I don't know the word '($lc)'."] }
        }
    }
    if (($action == "WALK") and ($dir != null) and ($objs | is-empty)) {
        return { ok: true, sfcn: "walk", sverb: "WALK", action: "WALK", prso: null, prsi: null, dir: $dir, state: $state, out: [] }
    }
    if ($action == null) {
        if ($objs | is-empty) {
            return { ok: false, sfcn: null, action: null, prso: null, prsi: null, dir: null, state: $state, out: [$"I don't know the word '($toks | first | get raw | str downcase)'."] }
        }
        let oname = ((find-obj ($objs | first | get obj)).desc)
        return { ok: false, sfcn: null, action: null, prso: null, prsi: null, dir: null, state: $state, out: [$"What should I do with the ($oname)?"] }
    }
    if ($action not-in ($ACTIONS | columns)) {
        return { ok: false, sfcn: null, action: $action, prso: null, prsi: null, dir: null, state: $state, out: [$"I don't know how to ($action | str downcase) that yet."] }
    }
    syn-match $state $action $objs
}
