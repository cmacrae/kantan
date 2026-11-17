# Cuts the Tabler icon fonts down to the icons the plugin previews draw, as
# kantan resolves them: "bell" is the outline font's glyph named "bell", and
# "bell-filled" the filled font's. Writes icons.css, with each font inlined,
# and icons.json, mapping each icon to its font, character and the scale
# kantan draws it at, so its height fills 85% of the em, at most 1.6 times
# its size. Fails on an icon neither font has.
#
# usage: preview-icons.py <outline.ttf> <filled.ttf> <out> <icon>...
import base64
import io
import json
import sys

from fontTools.pens.boundsPen import BoundsPen
from fontTools.subset import Options, Subsetter
from fontTools.ttLib import TTFont

TARGET_RATIO = 0.85
MAX_SCALE = 1.6
FAMILIES = {"outline": "kantan-preview-icons", "filled": "kantan-preview-icons-filled"}

outline_path, filled_path, out, *names = sys.argv[1:]
paths = {"outline": outline_path, "filled": filled_path}
fonts = {kind: TTFont(path) for kind, path in paths.items()}


def scale(font, glyph):
    pen = BoundsPen(font.getGlyphSet())
    font.getGlyphSet()[glyph].draw(pen)
    if pen.bounds is None:
        return 1.0
    height = pen.bounds[3] - pen.bounds[1]
    ratio = font["head"].unitsPerEm * TARGET_RATIO / height
    return round(min(ratio, MAX_SCALE), 4) if ratio > 1 else 1.0


icons, wanted, missing = {}, {kind: set() for kind in fonts}, []
for name in sorted(set(names)):
    kind, glyph = ("filled", name[: -len("-filled")]) if name.endswith("-filled") else ("outline", name)
    font = fonts[kind]
    codes = [code for code, g in font.getBestCmap().items() if g == glyph]
    if not codes:
        missing.append(name)
        continue
    icons[name] = {"font": FAMILIES[kind], "char": chr(min(codes)), "scale": scale(font, glyph)}
    wanted[kind].add(min(codes))

if missing:
    sys.exit(f"no Tabler icon is named {', '.join(missing)}")

css = []
for kind, path in paths.items():
    if not wanted[kind]:
        continue
    font = TTFont(path)
    options = Options()
    options.flavor = "woff2"
    options.layout_features = []
    subsetter = Subsetter(options)
    subsetter.populate(unicodes=wanted[kind])
    subsetter.subset(font)
    data = io.BytesIO()
    font.flavor = "woff2"
    font.save(data)
    # Saving measures each glyph's outline afresh. A glyph is drawn where
    # its outline sits only while its left side bearing says the same as
    # that measure, so each bearing is set to match and the font saved again.
    font = TTFont(io.BytesIO(data.getvalue()))
    for name in font.getGlyphOrder():
        glyph = font["glyf"][name]
        if glyph.numberOfContours:
            font["hmtx"][name] = (font["hmtx"][name][0], glyph.xMin)
    data = io.BytesIO()
    font.flavor = "woff2"
    font.save(data)
    encoded = base64.b64encode(data.getvalue()).decode()
    css.append(
        f'@font-face{{font-family:"{FAMILIES[kind]}";'
        f'src:url(data:font/woff2;base64,{encoded}) format("woff2");}}'
    )

with open(f"{out}/icons.css", "w") as f:
    f.write("\n".join(css) + "\n")
with open(f"{out}/icons.json", "w") as f:
    json.dump(icons, f, indent=2, ensure_ascii=False)
