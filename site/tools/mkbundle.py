#!/usr/bin/env python3
"""Writes the std the playground's compiler reads (`make site`): the std's
top-level modules and its haxe/, sys/ and eval/ packages (what --interp,
macros and HXB need), as one file the page's worker unpacks into its file
system at /lib/haxe/std (site/src/Worker.hx):

    python3 site/tools/mkbundle.py <std dir> <out>

Format: a little-endian u32 n, n bytes of UTF-8 JSON [[path, size], ...]
(paths relative to the std, sorted), then the files' bytes in that order.
"""
import json, os, struct, sys

std, out = sys.argv[1], sys.argv[2]
files = []
for name in sorted(os.listdir(std)):
    p = os.path.join(std, name)
    if os.path.isfile(p) and name.endswith(".hx"):
        files.append(name)
for pack in ("haxe", "sys", "eval"):
    for d, dirs, names in os.walk(os.path.join(std, pack)):
        dirs.sort()
        for name in sorted(names):
            files.append(os.path.relpath(os.path.join(d, name), std).replace(os.sep, "/"))
data = [open(os.path.join(std, f), "rb").read() for f in files]
index = json.dumps([[f, len(b)] for f, b in zip(files, data)], separators=(",", ":")).encode()
with open(out, "wb") as o:
    o.write(struct.pack("<I", len(index)))
    o.write(index)
    for b in data:
        o.write(b)
print(f"mkbundle: {len(files)} files, {os.path.getsize(out)} bytes")
