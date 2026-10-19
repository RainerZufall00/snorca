"""Compares the firmware macro sequence of Snarwal G-code with the
official Snapmaker Orca U1 machine profile (test plan step 1).

Usage:
  python3 test/compare-orca.py "Snapmaker U1 (0.4 nozzle).json" test/out/cube.gcode

The profile lives in github.com/Snapmaker/OrcaSlicer under
resources/profiles/Snapmaker/machine/. It is only read, never copied.
"""
import json, re, sys, difflib
orca = json.load(open(sys.argv[1]))
gcode = open(sys.argv[2]).read().split('\n')

MACRO = re.compile(r'^([A-Z]+_[A-Z0-9_]+|[A-Z]{5,})\b')
def macros(lines):
    out = []
    for line in lines:
        line = line.split(';')[0].strip()
        if MACRO.match(line):
            out.append(line.split()[0])
    return out

def orca_lines(key):
    text = orca[key].replace('\\n', '\n')
    # drop the {if}/{else} template branches: keep the default (last) branch of BED_MESH etc.
    lines = []
    skip = False
    for raw in text.split('\n'):
        l = raw.strip()
        if l.startswith('{if') or l.startswith('{elsif'):
            skip = True; continue
        if l.startswith('{else}'):
            skip = False; continue
        if l.startswith('{endif'):
            skip = False; continue
        if not skip:
            lines.append(l)
    return lines

start_end = next(i for i, l in enumerate(gcode) if l.startswith(';BEFORE_LAYER_CHANGE'))
ours_start = gcode[:start_end]
post_start = max(i for i, l in enumerate(gcode) if l.startswith('PRINT_END')) - 3
ours_end = gcode[post_start:]

for name, a, b in [('start', macros(orca_lines('machine_start_gcode')), macros(ours_start)),
                   ('end', macros(orca_lines('machine_end_gcode')), macros(ours_end))]:
    print(f'== {name}: orca {len(a)} macros, snarwal {len(b)} macros, identical order: {a == b}')
    for d in difflib.unified_diff(a, b, 'orca', 'snarwal', lineterm='', n=0):
        print('   ', d)
