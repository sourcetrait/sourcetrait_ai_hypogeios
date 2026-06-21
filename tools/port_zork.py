#!/usr/bin/env python3
# Port the C++ Zork static-world tables into structured JSON.
#
# Parses roomdefs.h (rooms), objdefs.h + gobject.h (objects), resolving the
# zstring.h description constants and the room.cpp exit `#define` macros, and
# mapping the Bits / RoomBit / direction enums. The C++ source is the
# behavior source-of-truth; this is durable nuzork build tooling - re-run it
# whenever ~/repo/zork changes. Emits rooms.json + objects.json to <out> and
# prints a summary (counts + anything left unresolved) to stdout.
#
# Usage: port_zork.py <zork_src_dir> <out_dir>
import re, json, sys, os

def read(p): return open(p, encoding='utf-8', errors='replace').read()

# --- low-level scanners (skip string + raw-string content) ----------------
def raw_end(s, i):            # s[i:i+3]=='R"~'; index past ')~"'
    j = s.find(')~"', i+3); return (j+3) if j >= 0 else len(s)
def str_end(s, i):            # s[i]=='"'; index past closing quote
    i += 1; n = len(s)
    while i < n:
        if s[i] == '\\': i += 2; continue
        if s[i] == '"': return i+1
        i += 1
    return n
def balanced(s, i, o, c):     # s[i]==o; index past matching close
    depth = 0; n = len(s)
    while i < n:
        if s[i:i+3] == 'R"~': i = raw_end(s, i); continue
        ch = s[i]
        if ch == '"': i = str_end(s, i); continue
        if ch == o: depth += 1
        elif ch == c:
            depth -= 1
            if depth == 0: return i+1
        i += 1
    return n
def paren_inner(t):
    k = t.find('('); return t[k+1:balanced(t, k, '(', ')')-1]

def split_top(s):             # split by top-level commas
    parts = []; depth = 0; i = 0; n = len(s); start = 0
    while i < n:
        if s[i:i+3] == 'R"~': i = raw_end(s, i); continue
        ch = s[i]
        if ch == '"': i = str_end(s, i); continue
        if ch in '([{': depth += 1
        elif ch in ')]}': depth -= 1
        elif ch == ',' and depth == 0:
            parts.append(s[start:i]); start = i+1
        i += 1
    parts.append(s[start:])
    return [p.strip() for p in parts]

ESC = {'n':'\n','t':'\t','\\':'\\','"':'"',"'":"'",'r':'\r','0':'\0','a':'\a','b':'\b','f':'\f','v':'\v'}
def unescape(s):
    out = []; i = 0; n = len(s)
    while i < n:
        if s[i] == '\\' and i+1 < n: out.append(ESC.get(s[i+1], s[i+1])); i += 2
        else: out.append(s[i]); i += 1
    return ''.join(out)

def cstr(expr):               # value of a C++ string literal expr (raw/regular/concat), or None
    expr = expr.strip()
    if expr.startswith('R"~('): return expr[4:expr.find(')~"')]
    if expr.startswith('"'):
        parts = re.findall(r'"((?:[^"\\]|\\.)*)"', expr, re.S)
        if parts: return ''.join(unescape(p) for p in parts)
    return None

def calls(text, name):        # contents of each balanced name(...) call
    out = []; i = 0; pat = name + '('
    while True:
        k = text.find(pat, i)
        if k < 0: break
        op = k + len(name); end = balanced(text, op, '(', ')')
        out.append(text[op+1:end-1]); i = end
    return out

def brace_rows(body):         # top-level {..} rows inside an array body
    rows = []; i = 0; n = len(body)
    while i < n:
        if body[i:i+3] == 'R"~': i = raw_end(body, i); continue
        ch = body[i]
        if ch == '"': i = str_end(body, i); continue
        if ch == '{':
            end = balanced(body, i, '{', '}'); rows.append(body[i+1:end-1]); i = end; continue
        i += 1
    return rows

def array_body(text, decl):
    k = text.find(decl); eq = text.find('{', k)
    return text[eq+1:balanced(text, eq, '{', '}')-1]

# --- field parsers --------------------------------------------------------
def strlist(brace):
    inner = brace.strip()
    if inner.startswith('{'): inner = inner[1:balanced(inner, 0, '{', '}')-1]
    return [cstr(p) for p in split_top(inner) if cstr(p) is not None]
def bitlist(brace, prefix): return re.findall(prefix + r'::(\w+)', brace)
def fnname(expr):
    expr = expr.strip()
    if expr in ('nullptr', ''): return None
    m = re.search(r'::(\w+)\s*\(', expr); return m.group(1) if m else None

# --- constants + macros ---------------------------------------------------
def parse_consts(zstr):
    c = {}
    for m in re.finditer(r'std::string_view\s+(\w+)\s*=\s*(R"~\(.*?\)~")\s*;', zstr, re.S):
        c[m.group(1)] = cstr(m.group(2))
    for m in re.finditer(r'std::string_view\s+(\w+)\s*=\s*("(?:[^"\\]|\\.)*")\s*;', zstr, re.S):
        c.setdefault(m.group(1), cstr(m.group(2)))
    return c
def parse_macros(roomcpp):
    m = {}
    for mm in re.finditer(r'^#define\s+(\w+)\s+(.*)$', roomcpp, re.M):
        m[mm.group(1)] = mm.group(2).strip()
    for k in list(m):                       # resolve macro->macro chains
        v = m[k]; seen = set()
        while v in m and v not in seen: seen.add(v); v = m[v]
        m[k] = v
    return m

def resolve_desc(expr, consts):
    s = cstr(expr)
    if s is not None: return s
    e = expr.strip()
    if e in consts: return consts[e]
    return '' if e in ('', 'nullptr') else {'_unresolved': e}

# --- exits ----------------------------------------------------------------
def exit_target(t, consts, macros, depth=0):
    t = t.strip()
    if depth > 6: return {'kind': 'raw', 'expr': t}
    if t in macros: return exit_target(macros[t], consts, macros, depth+1)
    s = cstr(t)
    if s is not None: return {'kind': 'room', 'to': s}
    if t.startswith('NExit'):
        return {'kind': 'nexit', 'msg': resolve_desc(paren_inner(t), consts)}
    if 'DoorExit' in t:
        a = split_top(paren_inner(t))
        return {'kind': 'door', 'obj': cstr(a[0]), 'rm1': cstr(a[1]), 'rm2': cstr(a[2]),
                'msg': resolve_desc(a[3], consts) if len(a) > 3 else '',
                'fn': fnname(a[4]) if len(a) > 4 else None}
    if 'CExit' in t:
        a = split_top(paren_inner(t)); flag = a[0].strip()
        fm = re.search(r'FlagId::(\w+)', flag)
        return {'kind': 'cexit', 'flag': fm.group(1) if fm else flag,
                'to': cstr(a[1]) if len(a) > 1 else None,
                'msg': resolve_desc(a[2], consts) if len(a) > 2 else '',
                'fn': next((fnname(x) for x in a[3:] if '::' in x), None)}
    if t in ('RoomP()', 'std::monostate()'): return {'kind': 'none'}
    return {'kind': 'raw', 'expr': t}
def parse_exits(brace, consts, macros):
    out = []
    for ex in calls(brace, 'Ex'):
        a = split_top(ex); d = re.search(r'direction::(\w+)', a[0])
        out.append({'dir': d.group(1) if d else a[0].strip(),
                    'to': exit_target(a[1], consts, macros) if len(a) > 1 else {'kind': 'none'}})
    return out

# --- props ----------------------------------------------------------------
def objprops(brace, consts):
    out = {}
    for op in calls(brace, 'OP'):
        a = split_top(op); m = re.search(r'ksl_(\w+)', a[0])
        if not m: continue
        slot = m.group(1); v = a[1].strip() if len(a) > 1 else ''
        s = cstr(v)
        if s is not None: out[slot] = s
        elif v in consts: out[slot] = consts[v]
        elif re.fullmatch(r'-?\d+', v): out[slot] = int(v)
        else: out[slot] = v
    return out
def roomprops(brace, consts):
    out = {}
    for rp in calls(brace, 'RP'):
        a = split_top(rp); m = re.search(r'ksl_(\w+)', a[0])
        if not m: continue
        slot = m.group(1); v = a[1] if len(a) > 1 else ''
        if slot == 'rglobal': out['rglobal'] = bitlist(v, 'Bits')
        elif slot == 'rval':
            mm = re.search(r'-?\d+', v); out['rval'] = int(mm.group()) if mm else 0
        else: out[slot] = v.strip()
    return out

# --- rooms / objects ------------------------------------------------------
def parse_rooms(roomdefs, consts, macros):
    rooms = []
    for call in calls(roomdefs, 'mr'):
        a = split_top(call)
        rooms.append({
            'rid': cstr(a[0]),
            'desc2': resolve_desc(a[2], consts) if len(a) > 2 else '',
            'desc1': resolve_desc(a[1], consts) if len(a) > 1 else '',
            'exits': parse_exits(a[3], consts, macros) if len(a) > 3 else [],
            'contents': strlist(a[4]) if len(a) > 4 else [],
            'roomf': fnname(a[5]) if len(a) > 5 else None,
            'rbits': bitlist(a[6], 'RoomBit') if len(a) > 6 else ['rlandbit'],
            **(roomprops(a[7], consts) if len(a) > 7 else {})})
    return rooms
def parse_objrow(a, consts, is_g):
    off = 1 if is_g else 0
    syns = strlist(a[off]);
    return {
        'oid': syns[0] if syns else None, 'syns': syns,
        'adj': strlist(a[off+1]) if len(a) > off+1 else [],
        'desc': cstr(a[off+2]) if len(a) > off+2 else '',
        'bits': bitlist(a[off+3], 'Bits') if len(a) > off+3 else [],
        'objfn': fnname(a[off+4]) if len(a) > off+4 else None,
        'contents': strlist(a[off+5]) if len(a) > off+5 else [],
        'is_global': is_g,
        **({'gbit': (re.search(r'Bits::(\w+)', a[0]).group(1) if re.search(r'Bits::(\w+)', a[0]) else None)} if is_g else {}),
        **(objprops(a[off+6], consts) if len(a) > off+6 else {})}
def parse_objects(objdefs, gobjs, consts):
    out = []
    for row in brace_rows(array_body(objdefs, 'objects[]')):
        out.append(parse_objrow(split_top(row), consts, False))
    for row in brace_rows(array_body(gobjs, 'gobjects[]')):
        out.append(parse_objrow(split_top(row), consts, True))
    return out

def to_nuon(v):
    if v is None: return 'null'
    if v is True: return 'true'
    if v is False: return 'false'
    if isinstance(v, int): return str(v)
    if isinstance(v, str):
        e = (v.replace('\\', '\\\\').replace('"', '\\"')
              .replace('\n', '\\n').replace('\t', '\\t').replace('\r', '\\r'))
        return '"' + e + '"'
    if isinstance(v, list): return '[' + ', '.join(to_nuon(x) for x in v) + ']'
    if isinstance(v, dict):
        return '{' + ', '.join(f'{k}: {to_nuon(val)}' for k, val in v.items()) + '}'
    return '"' + str(v) + '"'

def emit_nu(rows, name, path):
    body = '[\n' + '\n'.join('    ' + to_nuon(r) + ',' for r in rows) + '\n]'
    open(path, 'w').write(
        f'# Generated by tools/port_zork.py from ~/repo/zork - do not edit by hand.\n'
        f'export const {name} = {body}\n')

def main():
    z, out = sys.argv[1], sys.argv[2]
    game = sys.argv[3] if len(sys.argv) > 3 else None
    os.makedirs(out, exist_ok=True)
    consts = parse_consts(read(os.path.join(z, 'zstring.h')))
    macros = parse_macros(read(os.path.join(z, 'room.cpp')))
    rooms = parse_rooms(read(os.path.join(z, 'roomdefs.h')), consts, macros)
    objects = parse_objects(read(os.path.join(z, 'objdefs.h')),
                            read(os.path.join(z, 'gobject.h')), consts)
    json.dump(rooms, open(os.path.join(out, 'rooms.json'), 'w'), indent=1)
    json.dump(objects, open(os.path.join(out, 'objects.json'), 'w'), indent=1)
    if game:
        os.makedirs(game, exist_ok=True)
        emit_nu(rooms, 'ROOMS', os.path.join(game, 'data_rooms.nu'))
        emit_nu(objects, 'OBJECTS', os.path.join(game, 'data_objects.nu'))

    def unresolved_exits():
        u = []
        for r in rooms:
            for e in r['exits']:
                if isinstance(e['to'], dict) and e['to'].get('kind') == 'raw':
                    u.append((r['rid'], e['dir'], e['to']['expr'][:60]))
        return u
    bad_desc = [r['rid'] for r in rooms if isinstance(r['desc1'], dict)]
    ue = unresolved_exits()
    print(f"rooms={len(rooms)} objects={len(objects)} consts={len(consts)} macros={len(macros)}")
    print(f"unresolved_desc1={len(bad_desc)} {bad_desc[:10]}")
    print(f"unresolved_exits={len(ue)}")
    for x in ue[:25]: print("  ", x)
    whous = next((r for r in rooms if r['rid'] == 'WHOUS'), None)
    print("WHOUS:", json.dumps(whous))
    mailb = next((o for o in objects if o['oid'] == 'MAILB'), None)
    print("MAILB:", json.dumps(mailb))

if __name__ == '__main__': main()
