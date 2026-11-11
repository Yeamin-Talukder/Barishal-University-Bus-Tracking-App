"""Make the website's icons and social preview image from the app icon.

Writes to website/src/assets/:
  icons/favicon.svg            pin only, cropped tight, for browser tabs
  icons/favicon-32.png         PNG fallback for older browsers
  icons/apple-touch-icon.png   180 px full icon (iOS home screen)
  icons/icon-192.png, icon-512.png   web app manifest icons (also maskable)
  og-image.png                 1200 x 630 link preview (Facebook, WhatsApp, X, ...)

The app icon itself comes from tools/icon/make_icon.py. Renders with Microsoft
Edge in headless mode. Run from the project root:

    python website/tools/make_images.py
"""
import os
import re
import subprocess
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
APP_ICONS = os.path.join(ROOT, "assets", "icons")
SITE = os.path.join(ROOT, "website", "src", "assets")
TOOLS = os.path.join(ROOT, "website", "tools")
EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"


def url(path):
    return "file:///" + path.replace("\\", "/").replace(" ", "%20")


def shoot(src_url, out, w, h, transparent=False):
    args = [EDGE, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--allow-file-access-from-files",
            "--force-device-scale-factor=1", f"--window-size={w},{h}", f"--screenshot={out}"]
    if transparent:
        args.append("--default-background-color=00000000")
    subprocess.run(args + [src_url], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print(f"{os.path.relpath(out, ROOT)}  {w}x{h}  {os.path.getsize(out) // 1024} KB")


def sized_svg(svg_text, size, viewbox=None):
    s = re.sub(r'width="\d+" height="\d+"', f'width="{size}" height="{size}"', svg_text, count=1)
    if viewbox:
        s = re.sub(r'viewBox="[^"]+"', f'viewBox="{viewbox}"', s, count=1)
    return s


def main():
    icons = os.path.join(SITE, "icons")
    os.makedirs(icons, exist_ok=True)
    full = open(os.path.join(APP_ICONS, "app_icon.svg"), encoding="utf-8").read()
    fg = open(os.path.join(APP_ICONS, "app_icon_foreground.svg"), encoding="utf-8").read()

    # The foreground layer is drawn at 70% around the pin; crop to the pin
    # (x 288 to 736, y 218 to 810 in the layer, plus a little room).
    fav = sized_svg(fg, 64, viewbox="212 214 600 600")
    fav = fav.replace("Android adaptive icon foreground layer", "Website favicon (pin)")
    with open(os.path.join(icons, "favicon.svg"), "w", encoding="utf-8") as f:
        f.write(fav)
    print("website/src/assets/icons/favicon.svg")

    with tempfile.TemporaryDirectory(dir=os.path.join(ROOT, "build")) as tmp:
        jobs = [("favicon-32.png", fav, 32, True), ("apple-touch-icon.png", full, 180, False),
                ("icon-192.png", full, 192, False), ("icon-512.png", full, 512, False)]
        for name, svg, size, transparent in jobs:
            p = os.path.join(tmp, name + ".svg")
            with open(p, "w", encoding="utf-8") as f:
                f.write(sized_svg(svg, size))
            shoot(url(p), os.path.join(icons, name), size, size, transparent)

    shoot(url(os.path.join(TOOLS, "og-image.html")), os.path.join(SITE, "og-image.png"), 1200, 630)


if __name__ == "__main__":
    main()
