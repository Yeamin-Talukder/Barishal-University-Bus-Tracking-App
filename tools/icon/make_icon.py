"""Generate the BU Bus Tracker app icon sources and PNG layers.

Design: a red location pin holding a white double-decker, on a dark map with
the river, the bridge and a red route running under the pin's tip.

Writes to assets/icons/:
  app_icon.svg / .png              full icon (iOS, legacy Android, store listing)
  app_icon_background.svg / .png   Android adaptive background layer (map)
  app_icon_foreground.svg / .png   Android adaptive foreground layer (pin), transparent
  app_icon_monochrome.svg / .png   Android 13+ themed icon layer, transparent

The adaptive layers draw the same artwork scaled to ADAPTIVE_SCALE around the
pin's middle (ADAPTIVE_CENTRE_Y), so the 72 dp area a launcher shows matches
the full icon and the pin stays inside the 66 dp safe circle. Map lines extend past the canvas so the
background still bleeds to the edge after scaling.

PNGs are rendered with Microsoft Edge in headless mode (no Python packages
needed). Run from the project root:

    python tools/icon/make_icon.py

Then regenerate the platform icons:

    dart run flutter_launcher_icons
"""
import os
import struct
import subprocess
import sys
import zlib

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "icons")
EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"

SIZE = 1024
ADAPTIVE_SCALE = 0.70
# The adaptive layers are centred on the pin (the middle of its height, 60 to
# 900), not on the canvas, so the bigger pin stays inside the 66 dp safe circle.
ADAPTIVE_CENTRE_Y = 480

# Pin: head circle centre (512, 380), radius 320, rounded tip at (512, 900).
# (Enlarged on 11 November 2026 from radius 280; the route moved down with it.)
PIN = ("M259.8 576.9 A320 320 0 1 1 764.2 576.9 "
       "L530.5 876.4 Q512 900 493.5 876.4 Z")

# Double-decker glyph, drawn in its own space then placed inside the pin head.
BUS_PLACE = "translate(512 380) scale(1.03) translate(-512 -428)"
BUS_BODY = ('<rect x="380" y="258" width="264" height="306" rx="62"/>'
            '<rect x="408" y="540" width="56" height="58" rx="18"/>'
            '<rect x="560" y="540" width="56" height="58" rx="18"/>')
BUS_HOLES = ('<rect x="414" y="294" width="196" height="86" rx="26"/>'
             '<rect x="414" y="406" width="196" height="94" rx="26"/>'
             '<rect x="414" y="520" width="44" height="22" rx="11"/>'
             '<rect x="566" y="520" width="44" height="22" rx="11"/>')

# Teal Mint (11 November 2026): mint pin, orange route (route 01's colour),
# on the app's slate. The keys red0/red1 are the pin's gradient stops.
C = dict(bg0="#1A2028", bg1="#0F1318", street="#27303A", river="#1C3A52",
         casing="#0F1318", route="#F2994A", red0="#7FE0CB", red1="#0A7563")

# Each map line starts and ends with a straight lead-in along its tangent,
# well outside the canvas, so scaled-down copies still reach the edges.
STREETS = [
    "M-297 287 L-40 250 C 240 210, 760 300, 1064 230 L1317 172",
    "M874 -298 L842 -40 C 800 300, 900 640, 860 1064 L836 1323",
    "M116 -298 L150 -40 C 190 260, 120 520, 180 760",
]
RIVER = "M-336 513 L-80 560 C 140 600, 300 760, 300 1100 L300 1360"
ROUTE = "M-294 1038 L-40 980 C 180 930, 340 900, 512 902 S 860 870, 1064 700 L1264 534"
STOP = (776, 865)

DEFS = f"""<defs>
  <linearGradient id="bg" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="0" y2="{SIZE}">
    <stop offset="0" stop-color="{C['bg0']}"/><stop offset="1" stop-color="{C['bg1']}"/>
  </linearGradient>
  <linearGradient id="red" x1="0.15" y1="0" x2="0.85" y2="1">
    <stop offset="0" stop-color="{C['red0']}"/><stop offset="1" stop-color="{C['red1']}"/>
  </linearGradient>
  <radialGradient id="gloss" cx="0.32" cy="0.18" r="0.62">
    <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.26"/>
    <stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
  </radialGradient>
  <filter id="blur" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="12"/></filter>
  <mask id="buscut" maskUnits="userSpaceOnUse" x="-2000" y="-2000" width="5000" height="5000">
    <rect x="-2000" y="-2000" width="5000" height="5000" fill="#fff"/><g fill="#000">{BUS_HOLES}</g>
  </mask>
  <mask id="monocut" maskUnits="userSpaceOnUse" x="-2000" y="-2000" width="5000" height="5000">
    <rect x="-2000" y="-2000" width="5000" height="5000" fill="#fff"/>
    <g transform="{BUS_PLACE}"><g fill="#000">{BUS_BODY}</g><g fill="#fff">{BUS_HOLES}</g></g>
  </mask>
</defs>"""


def background():
    lines = "".join(f'<path d="{d}"/>' for d in STREETS)
    return f"""<rect x="-2000" y="-2000" width="5000" height="5000" fill="url(#bg)"/>
<g fill="none" stroke="{C['street']}" stroke-width="44" stroke-linecap="round">{lines}</g>
<path d="{RIVER}" fill="none" stroke="{C['river']}" stroke-width="100" stroke-linecap="round"/>
<path d="{ROUTE}" fill="none" stroke="{C['casing']}" stroke-width="54" stroke-linecap="round"/>
<path d="{ROUTE}" fill="none" stroke="{C['route']}" stroke-width="26" stroke-linecap="round"/>
<circle cx="{STOP[0]}" cy="{STOP[1]}" r="22" fill="{C['casing']}" stroke="{C['route']}" stroke-width="12"/>"""


def foreground():
    return f"""<ellipse cx="512" cy="906" rx="86" ry="19" fill="#263238" opacity="0.55" filter="url(#blur)"/>
<path d="{PIN}" fill="url(#red)"/>
<path d="{PIN}" fill="url(#gloss)"/>
<g transform="{BUS_PLACE}"><g fill="#FFFFFF" mask="url(#buscut)">{BUS_BODY}</g></g>"""


def monochrome():
    return f'<path d="{PIN}" fill="#FFFFFF" mask="url(#monocut)"/>'


def svg(body, scale, comment):
    t = "" if scale == 1 else f' transform="translate(512 512) scale({scale}) translate(-512 -{ADAPTIVE_CENTRE_Y})"'
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE}" height="{SIZE}" '
            f'viewBox="0 0 {SIZE} {SIZE}">\n<!-- {comment} -->\n{DEFS}\n<g{t}>\n{body}\n</g>\n</svg>\n')


LAYERS = {
    "app_icon": (background() + "\n" + foreground(), 1,
                 "BU Bus Tracker app icon (full). Generated by tools/icon/make_icon.py.", False),
    "app_icon_background": (background(), ADAPTIVE_SCALE,
                            "Android adaptive icon background layer. Generated by tools/icon/make_icon.py.", False),
    "app_icon_foreground": (foreground(), ADAPTIVE_SCALE,
                            "Android adaptive icon foreground layer. Generated by tools/icon/make_icon.py.", True),
    "app_icon_monochrome": (monochrome(), ADAPTIVE_SCALE,
                            "Android themed (monochrome) icon layer. Generated by tools/icon/make_icon.py.", True),
}


def png_info(path):
    """Width, height, colour type and the alpha at the four corners (8-bit, non-interlaced PNG)."""
    data = open(path, "rb").read()
    pos, idat = 8, b""
    w = h = ctype = 0
    while pos < len(data):
        n, kind = struct.unpack(">I4s", data[pos:pos + 8])
        chunk = data[pos + 8:pos + 8 + n]
        if kind == b"IHDR":
            w, h, _, ctype = struct.unpack(">IIBB", chunk[:10])
        elif kind == b"IDAT":
            idat += chunk
        pos += 12 + n
    if ctype != 6:
        return w, h, ctype, None
    raw, bpp, stride = zlib.decompress(idat), 4, w * 4
    rows, prev, i = [], bytearray(stride), 0
    for _ in range(h):
        f, line = raw[i], bytearray(raw[i + 1:i + 1 + stride])
        i += 1 + stride
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0
            b, c = prev[x], prev[x - bpp] if x >= bpp else 0
            if f == 1:
                line[x] = (line[x] + a) & 255
            elif f == 2:
                line[x] = (line[x] + b) & 255
            elif f == 3:
                line[x] = (line[x] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append(line)
        prev = line
    corners = [rows[y][x * 4 + 3] for y in (0, h - 1) for x in (0, w - 1)]
    return w, h, ctype, corners


def render(name, transparent):
    src = os.path.join(OUT, name + ".svg")
    dst = os.path.join(OUT, name + ".png")
    args = [EDGE, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
            f"--window-size={SIZE},{SIZE}", f"--screenshot={dst}"]
    if transparent:
        args.append("--default-background-color=00000000")
    args.append("file:///" + src.replace("\\", "/").replace(" ", "%20"))
    subprocess.run(args, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    w, h, ctype, corners = png_info(dst)
    ok = (w, h) == (SIZE, SIZE) and (not transparent or (corners is not None and max(corners) == 0))
    print(f"{name}.png  {w}x{h}  colour type {ctype}  corner alpha {corners}  {'OK' if ok else 'CHECK'}")
    return ok


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, (body, scale, comment, _) in LAYERS.items():
        with open(os.path.join(OUT, name + ".svg"), "w", encoding="utf-8") as f:
            f.write(svg(body, scale, comment))
    if "--svg-only" in sys.argv:
        return 0
    results = [render(name, transparent) for name, (_, _, _, transparent) in LAYERS.items()]
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
