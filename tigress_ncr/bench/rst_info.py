#!/usr/bin/env python3
"""Print 'nbtotal time dt ncycle' from the header of an Athena++ restart file.

Layout (src/outputs/restart.cpp): parameter text ending with '<par_end>\\n', then
int nbtotal, int root_level, RegionSize mesh_size (12 doubles + 3 ints, padded to
112 bytes), Real time, Real dt, int ncycle. Assumes double precision.
"""
import struct
import sys

with open(sys.argv[1], 'rb') as f:
    head = f.read(1 << 20)
i = head.find(b'<par_end>')
if i < 0:
    sys.exit(f"{sys.argv[1]}: no <par_end> in the first MB; not an Athena++ restart file?")
j = head.find(b'\n', i) + 1
nbtotal, _root_level = struct.unpack_from('ii', head, j)
time, dt, ncycle = struct.unpack_from('ddi', head, j + 8 + 112)
print(nbtotal, repr(time), repr(dt), ncycle)
