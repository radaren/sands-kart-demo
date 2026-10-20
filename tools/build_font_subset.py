"""Rebuild assets/fonts/NotoSansSC-Bold-subset.otf so it covers every non-ASCII
character used in the game's scripts/scenes (plus what the old subset had).
Source: Noto Sans CJK SC Bold (SIL OFL 1.1). Needs fontTools.
   python3 tools/build_font_subset.py [/path/NotoSansCJK-Bold.ttc]"""
import glob, os, sys
from fontTools.ttLib import TTFont, TTCollection
from fontTools import subset

ROOT = os.path.join(os.path.dirname(__file__), "..")
OUT = os.path.join(ROOT, "assets", "fonts", "NotoSansSC-Bold-subset.otf")
SRC = sys.argv[1] if len(sys.argv) > 1 else "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc"

chars = set(chr(c) for c in range(0x20, 0x7F))
chars |= set("·—…“”‘’！？，。：；（）【】、←→↑↓▲▼★☆●○")
for pat in ("scripts/**/*.gd", "scenes/**/*.tscn", "data/*.json"):
    for f in glob.glob(os.path.join(ROOT, pat), recursive=True):
        chars |= {c for c in open(f, encoding="utf-8").read() if ord(c) > 0x7F}
if os.path.exists(OUT):
    chars |= {chr(c) for c in TTFont(OUT).getBestCmap()}

coll = TTCollection(SRC)
font = next(f for f in coll.fonts if "SC" in f["name"].getDebugName(1))
opts = subset.Options()
opts.layout_features = ["*"]
opts.name_IDs = ["*"]
opts.notdef_outline = True
sub = subset.Subsetter(opts)
cm = font.getBestCmap()
missing = sorted(c for c in chars if ord(c) not in cm and c.strip())
sub.populate(unicodes=[ord(c) for c in chars if ord(c) in cm])
sub.subset(font)
font.save(OUT)
print(f"wrote {OUT}: {len(chars) - len(missing)} chars, {os.path.getsize(OUT) // 1024} KB; not in source: {''.join(missing)}")
