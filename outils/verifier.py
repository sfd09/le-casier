#!/usr/bin/env python3
"""Refuse deux fonctions de même nom dans la portée principale d'index.html.

Une déclaration de fonction en écrase silencieusement une autre du même
nom : c'est ainsi que le téléversement des photos a appelé la messagerie
pendant une semaine, sans erreur et sans qu'une seule photo n'arrive.
Aucun outil ne le signalait ; celui-ci le fait.
"""
import collections
import io
import re
import sys

source = io.open("index.html", encoding="utf-8").read()
script = max(re.findall(r"<script>(.*?)</script>", source, re.S), key=len)
noms = re.findall(r"^  function ([A-Za-z0-9_$]+)\s*\(", script, re.M)
doubles = sorted(n for n, c in collections.Counter(noms).items() if c > 1)

print("%d fonctions au premier niveau" % len(noms))
if doubles:
    for n in doubles:
        lignes = [i + 1 for i, l in enumerate(script.split("\n"))
                  if re.match(r"  function %s\s*\(" % re.escape(n), l)]
        print("  HOMONYMES : %s, déclarée %d fois (lignes %s du script)"
              % (n, len(lignes), ", ".join(map(str, lignes))))
    sys.exit(1)
print("  aucun homonyme")
