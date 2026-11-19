# Prepares the Tabler icon fonts for the web, with icons named as kantan
# resolves them: "bell" is the outline font's glyph named "bell", and
# "bell-filled" the filled font's.
#
# Given icons, cuts the fonts down to them. Writes icons.css, with each
# font inlined, and icons.json, mapping each icon to its font, character,
# the scale kantan draws it at, so its height fills 85% of the em, at
# most 1.6 times its size, and how far into the em its outline starts, as
# a fraction of the em. Fails on an icon neither font has.
#
# Given --all, keeps every icon. Writes each font as a file beside
# icons.css, and icons.json mapping each font to its icons, each icon to
# its character's code, its scale and where its outline starts.
#
# usage: preview-icons.py <outline.ttf> <filled.ttf> <out> <icon>...
#        preview-icons.py <outline.ttf> <filled.ttf> <out> --all
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


def bounds(font, glyph):
    pen = BoundsPen(font.getGlyphSet())
    font.getGlyphSet()[glyph].draw(pen)
    return pen.bounds


def scale(font, glyph):
    box = bounds(font, glyph)
    if box is None:
        return 1.0
    height = box[3] - box[1]
    ratio = font["head"].unitsPerEm * TARGET_RATIO / height
    return round(min(ratio, MAX_SCALE), 4) if ratio > 1 else 1.0


def left(font, glyph):
    box = bounds(font, glyph)
    return 0 if box is None else round(box[0] / font["head"].unitsPerEm, 4)


everything = names == ["--all"]
if everything:
    names = [
        glyph + ("-filled" if kind == "filled" else "")
        for kind, font in fonts.items()
        for glyph in set(font.getBestCmap().values())
    ]

icons, wanted, missing = {}, {kind: set() for kind in fonts}, []
for name in sorted(set(names)):
    kind, glyph = ("filled", name[: -len("-filled")]) if name.endswith("-filled") else ("outline", name)
    font = fonts[kind]
    codes = [code for code, g in font.getBestCmap().items() if g == glyph]
    if not codes:
        missing.append(name)
        continue
    icons[name] = {"font": FAMILIES[kind], "char": chr(min(codes)), "scale": scale(font, glyph), "left": left(font, glyph)}
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
    if everything:
        with open(f"{out}/{FAMILIES[kind]}.woff2", "wb") as f:
            f.write(data.getvalue())
        source = f"{FAMILIES[kind]}.woff2"
    else:
        source = "data:font/woff2;base64," + base64.b64encode(data.getvalue()).decode()
    css.append(
        f'@font-face{{font-family:"{FAMILIES[kind]}";'
        f'src:url({source}) format("woff2");}}'
    )

with open(f"{out}/icons.css", "w") as f:
    f.write("\n".join(css) + "\n")
with open(f"{out}/icons.json", "w") as f:
    if everything:
        by_font = {family: {} for family in FAMILIES.values()}
        for name, icon in icons.items():
            by_font[icon["font"]][name] = [ord(icon["char"]), icon["scale"], icon["left"]]
        json.dump(by_font, f, separators=(",", ":"))
    else:
        json.dump(icons, f, indent=2, ensure_ascii=False)
