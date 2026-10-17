#!/usr/bin/env python3
"""Copy PMD-style sprite sheets (walk, idle, attack, hurt, faint) into BasicNotch.

Usage: python3 tools/import_pokebrawl_sprites.py path/to/sprite-project

Writes BasicNotch/Resources/Mons.bundle/<id>/ walk, idle, attack, hurt and faint sheets (+ s/ for shiny or Galar forms)
and Mons.bundle/roster.json with each Pokémon's frame sizes and durations from public/data.js.
Re-run it whenever the sprite project adds Pokémon.
"""
import json
import shutil
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
if len(sys.argv) < 2:
    sys.exit("Usage: python3 tools/import_pokebrawl_sprites.py path/to/sprite-project")
brawl = Path(sys.argv[1]).expanduser()
data_js = brawl / "public" / "data.js"
mons_dir = brawl / "public" / "assets" / "mons"
out = root / "BasicNotch" / "Resources" / "Mons.bundle"

text = data_js.read_text()
start = text.index("[")
roster, _ = json.JSONDecoder().raw_decode(text[start:])

if out.exists():
    shutil.rmtree(out)
out.mkdir(parents=True)


def pick(anims):
    keep = {}
    for key in ("walk", "idle", "attack", "hurt", "faint"):
        a = anims.get(key)
        if a:
            keep[key] = {"w": a["w"], "h": a["h"], "d": a["d"], "file": a["file"], "hit": a.get("hit", -1)}
    return keep


entries = []
for mon in roster:
    mid = mon["id"]
    anims = pick(mon.get("anims", {}))
    if "walk" not in anims:
        continue
    src = mons_dir / mid
    files = {a["file"] for a in anims.values()}
    if not all((src / f"{f}.png").exists() for f in files):
        continue
    (out / mid).mkdir()
    for f in files:
        shutil.copyfile(src / f"{f}.png", out / mid / f"{f}.png")

    entry = {"id": mid, "name": mon["name"], "type": mon.get("type", ""), "anims": anims}
    shiny = mon.get("shiny")
    if shiny and "anims" in shiny:
        s_anims = pick(shiny["anims"])
        s_files = {a["file"] for a in s_anims.values()}
        if "walk" in s_anims and all((src / "s" / f"{f}.png").exists() for f in s_files):
            (out / mid / "s").mkdir()
            for f in s_files:
                shutil.copyfile(src / "s" / f"{f}.png", out / mid / "s" / f"{f}.png")
            entry["shiny"] = s_anims
    entries.append(entry)

(out / "roster.json").write_text(json.dumps(entries, separators=(",", ":")))
size = sum(p.stat().st_size for p in out.rglob("*") if p.is_file())
print(f"Imported {len(entries)} Pokémon ({sum('shiny' in e for e in entries)} with shiny/alt forms), {size / 1e6:.1f} MB")
