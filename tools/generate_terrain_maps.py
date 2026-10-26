"""Generate the fixed mountain and canyon demonstration maps (offset coordinates)."""
import json
from pathlib import Path

DATA = Path(__file__).resolve().parents[1] / 'necromancer-test/data'

def save(name, heights, rocks):
    (DATA / name).write_text(json.dumps({'heights': heights, 'obstacles': {
        f'{c},{r}': True for c, r in rocks
    }}, indent=2) + '\n', encoding='utf-8')

save('terrain_flat.json', {}, [])
mountain = {}
for r in range(10):
    for c in range(5, 15):
        h = min(c-4, 15-c, 3)
        # Separate summits above the continuous ridge, linked by lower saddles.
        if 7 <= c <= 12:
            summit = max(max(0, 2-abs(c-pc)-abs(r-pr)) for pc, pr in [(8,2),(11,5),(8,8)])
            h += summit
        mountain[f'{c},{r}'] = h
save('terrain_mountains.json', mountain, [(8,1),(10,2),(12,1),(8,8),(11,8),(13,7)])

canyon = {}
for c in range(20):
    center = 5 if 7 <= c <= 12 else 4
    for r in range(10):
        h = min(3, max(0, abs(r-center)-1))
        if h:
            canyon[f'{c},{r}'] = h
save('terrain_canyon.json', canyon, [(5,2),(10,2),(14,7),(8,8),(12,8)])
