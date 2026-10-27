#!/usr/bin/env python3
"""Import a curated SpriteCollab roster with pinned source and attribution.
Run: python3 tools/import_spritecollab.py [commit SHA]
Copies original PNG sheets unchanged; converts AnimData.xml to roster.json.
"""
import concurrent.futures
import json
from pathlib import Path
import re
import struct
import sys
import urllib.request
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'BasicNotch/Resources/Mons.bundle'
REV = sys.argv[1] if len(sys.argv) > 1 else json.load(urllib.request.urlopen('https://api.github.com/repos/PMDCollab/SpriteCollab/commits/master'))['sha']
BASE = f'https://raw.githubusercontent.com/PMDCollab/SpriteCollab/{REV}/'
ROSTER = {'0001':'Grass','0004':'Fire','0007':'Water','0025':'Electric', '0039':'Fairy', '0094':'Ghost', '0133':'Normal', '0147':'Dragon', '0155':'Fire', '0258':'Water', '0387':'Grass', '0448':'Fighting', '0471':'Ice', '0570':'Dark', '0700':'Fairy', '0722':'Grass', '0778':'Ghost', '0872':'Ice'}

def fetch(path):
    with urllib.request.urlopen(BASE + path, timeout=45) as response:
        return response.read()

OUT.mkdir(parents=True, exist_ok=True)
tracker = json.loads(fetch('tracker.json'))
names = fetch('credit_names.txt').decode()
(OUT/'SpriteCollab-LICENSE.md').write_bytes(fetch('LICENSE.md'))
(OUT/'credit_names.txt').write_text(names)
credit_ids = {}
for line in names.splitlines():
    fields = line.split('\t')
    if len(fields) >= 2:
        for field in fields:
            if field: credit_ids[field] = ' | '.join(f for f in fields if f)


def import_form(path, target):
    xml = fetch(path + '/AnimData.xml')
    elements = {a.findtext('Name'): a for a in ET.fromstring(xml).find('Anims')}
    target.mkdir(parents=True, exist_ok=True)
    (target/'AnimData.xml').write_bytes(xml)
    credits = fetch(path + '/credits.txt')
    (target/'credits.txt').write_bytes(credits)
    anims = {}
    extra = ('Shock', 'Sleep', 'Eat') if path.split('/')[1] == '0025' else ('Sleep',) if path.split('/')[1] == '0700' else ()
    for key in ('Walk','Idle','Attack','Hurt','Faint') + extra:
        if key not in elements: continue
        a = elements[key]
        seen = set()
        while a.findtext('CopyOf'):
            alias = a.findtext('CopyOf')
            if alias in seen: raise ValueError('Cyclic animation alias')
            seen.add(alias)
            a = elements[alias]
        source_name = a.findtext('Name')
        data = fetch(path + '/' + source_name + '-Anim.png')
        w, h = int(a.findtext('FrameWidth')), int(a.findtext('FrameHeight'))
        durations = [int(d.text) for d in a.find('Durations')]
        width, height = struct.unpack('>II', data[16:24])
        assert data.startswith(b'\x89PNG') and w > 0 and h > 0
        assert width // w >= len(durations) > 0 and height % h == 0 and min(durations) > 0
        file = key.lower()
        (target/(file+'.png')).write_bytes(data)
        anims[file] = dict(w=w,h=h,d=durations,file=file,hit=int(a.findtext('HitFrame','-1')))
    assert 'walk' in anims
    return anims


def import_mon(item):
    mid, kind = item
    node = tracker[mid]
    entry = dict(id=mid,name=node['name'],type=kind.lower(),anims=import_form('sprite/'+mid,OUT/mid))
    shiny = node.get('subgroups',{}).get('0000',{}).get('subgroups',{}).get('0001')
    if shiny and shiny.get('sprite_complete',0) > 0:
        entry['shiny'] = import_form('sprite/'+mid+'/0000/0001',OUT/mid/'s')
    return entry

with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
    entries = list(pool.map(import_mon,ROSTER.items()))
(OUT/'roster.json').write_text(json.dumps(entries,separators=(',',':')))
credits = ['# SpriteCollab artwork credits', '',f'Source: https://github.com/PMDCollab/SpriteCollab/tree/{REV}', 'License: CC BY-NC 4.0, https://creativecommons.org/licenses/by-nc/4.0/. See SpriteCollab-LICENSE.md.', 'Original PNG artwork copied unchanged; animation metadata converted from XML. No endorsement is implied.', 'CHUNSOFT credits identify original game artwork; underlying Pokémon rights remain with their owners.', 'This license does not grant trademark rights or rights beyond those the contributors control.', '']
for entry in entries:
    credits.append('## '+entry['name']+' ('+entry['id']+')')
    for label,folder in [('Normal',OUT/entry['id']),('Shiny',OUT/entry['id']/'s')]:
        file = folder/'credits.txt'
        if not file.exists(): continue
        credits.append(label+' — original credit log:')
        credits.append(file.read_text())
credits.extend(['## Contributor name directory',names])
(OUT/'CREDITS.md').write_text('\n'.join(credits))
(ROOT/'Docs/SPRITE-CREDITS.md').write_text('\n'.join(credits))
print(f'Imported {len(entries)} Pokémon, {sum("shiny" in e for e in entries)} shiny variants, revision {REV}')
