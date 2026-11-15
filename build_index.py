#!/usr/bin/env python3
"""Builds public/index.html from src/bin-to-bottle.html (the Claude prototype).
Usage: python3 build_index.py src/bin-to-bottle.html"""
import sys, pathlib
src = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "bin-to-bottle.html").read_text(encoding="utf-8")
head = ('<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n'
        '<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">\n'
        '<meta name="robots" content="noindex">\n'
        '<link rel="icon" href="data:image/svg+xml,%3Csvg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 32 32%22%3E%3Cpath d=%22M9 4h14l-2 13a5 5 0 0 1-10 0z%22 fill=%22%23E8B42C%22/%3E%3Cpath d=%22M16 22v6M11 28h10%22 stroke=%22%23333%22 stroke-width=%222%22/%3E%3C/svg%3E">\n'
        '<script src="config.js"></script>\n'
        '<style>*,*::before,*::after{box-sizing:border-box}html,body{margin:0}</style>\n')
out = head + src
# put the app's own <title>/<meta>/<link>/<style> inside <head>; everything else in <body>
i = out.find("<body")
if i == -1:
    cut = out.find('<div class="app"')
    if cut == -1: cut = out.find("<div")
    out = out[:cut] + "</head>\n<body>\n" + out[cut:] + "\n</body>\n</html>\n"
pathlib.Path(__file__).with_name("public").mkdir(exist_ok=True)
pathlib.Path(__file__).with_name("public").joinpath("index.html").write_text(out, encoding="utf-8")
print("wrote public/index.html", len(out), "bytes")
