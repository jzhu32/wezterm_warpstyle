"""Rebuild the bundled logo font: python3 fonts/build.py (FontTools 4.61.1)."""
from pathlib import Path
from xml.etree import ElementTree

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.cu2quPen import Cu2QuPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.svgLib.path import SVGPath

ROOT = Path(__file__).resolve().parent
# Plane 16 avoids the codepoints already used by Nerd Fonts.
ICONS = {0x100001: "gemini", 0x100002: "qwen", 0x100003: "meta",
         0x100004: "deepseek", 0x100005: "ollama", 0x100006: "opencode"}

builder = FontBuilder(1000, isTTF=True)
builder.setupGlyphOrder([".notdef", *ICONS.values()])
builder.setupCharacterMap(ICONS)
glyphs = {".notdef": TTGlyphPen(None).glyph()}
metrics = {".notdef": (600, 0)}
for name in ICONS.values():
    svg = (ROOT / "source" / f"{name}.svg").read_text()
    x, y, width, height = map(float, ElementTree.fromstring(svg).attrib["viewBox"].split())
    scale = min(580 / width, 700 / height)
    # Center each original mark in one terminal cell without changing its shape.
    transform = (scale, 0, 0, -scale, (600 - width * scale) / 2 - x * scale,
                 (700 - height * scale) / 2 + 30 + (y + height) * scale)
    pen = TTGlyphPen(None)
    SVGPath.fromstring(svg).draw(TransformPen(Cu2QuPen(pen, max_err=0.5), transform))
    glyph = pen.glyph()
    glyph.recalcBounds(None)
    assert 0 <= glyph.xMin < glyph.xMax <= 600, name
    assert -200 <= glyph.yMin < glyph.yMax <= 800, name
    glyphs[name] = glyph
    metrics[name] = (600, glyph.xMin)

builder.setupGlyf(glyphs)
builder.setupHorizontalMetrics(metrics)
builder.setupHorizontalHeader(ascent=800, descent=-200)
builder.setupNameTable({
    "familyName": "WezTerm Agent Icons", "styleName": "Regular",
    "uniqueFontIdentifier": "WezTerm Agent Icons 1.0",
    "fullName": "WezTerm Agent Icons", "psName": "WezTermAgentIcons-Regular",
    "version": "Version 1.0", "copyright": "Copyright (c) 2023 LobeHub. MIT License.",
    "licenseDescription": (ROOT / "source" / "LICENSE").read_text(),
})
builder.setupOS2(sTypoAscender=800, sTypoDescender=-200, usWinAscent=800, usWinDescent=200)
builder.setupPost(isFixedPitch=1)
builder.setupMaxp()
builder.font["head"].created = builder.font["head"].modified = 3828988800
builder.font.recalcTimestamp = False
builder.save(ROOT / "WezTermAgentIcons.ttf")
print("Built WezTermAgentIcons.ttf (six logos; no runtime dependencies)")
