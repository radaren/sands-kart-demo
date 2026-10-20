"""Item slot icons (H1/I-presentation) -> assets/ui/items/<key>.png, 128x128 RGBA.
Drawn at 4x and downsampled for anti-aliasing. Re-run to regenerate."""
import math, os
from PIL import Image, ImageDraw, ImageFilter

S = 512
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "ui", "items")
INK = (40, 24, 12, 255)


def canvas():
    return Image.new("RGBA", (S, S), (0, 0, 0, 0))


def finish(im, name):
    # dark outline from the alpha, then downsample
    a = im.split()[3].filter(ImageFilter.MaxFilter(25))
    base = Image.new("RGBA", (S, S), INK)
    base.putalpha(a)
    base.alpha_composite(im)
    base.resize((128, 128), Image.LANCZOS).save(os.path.join(OUT, name + ".png"))


def poly(d, pts, fill):
    d.polygon([(x * S, y * S) for x, y in pts], fill=fill)


def nitro():
    im = canvas(); d = ImageDraw.Draw(im)
    d.rounded_rectangle([170, 110, 342, 440], 60, fill=(60, 140, 255))
    d.rounded_rectangle([205, 70, 307, 125], 20, fill=(200, 210, 225))
    d.rectangle([170, 230, 342, 270], fill=(240, 240, 255))
    poly(d, [(.44, .86), (.5, .99), (.56, .86)], (255, 150, 30))
    return im


def missile():
    im = canvas(); d = ImageDraw.Draw(im)
    im2 = canvas(); d2 = ImageDraw.Draw(im2)
    d2.rounded_rectangle([200, 120, 312, 400], 50, fill=(235, 235, 240))
    poly(d2, [(.39, .26), (.5, .06), (.61, .26)], (230, 40, 30))
    d2.rectangle([200, 300, 312, 340], fill=(230, 40, 30))
    poly(d2, [(.39, .62), (.25, .82), (.39, .78)], (230, 40, 30))
    poly(d2, [(.61, .62), (.75, .82), (.61, .78)], (230, 40, 30))
    poly(d2, [(.43, .78), (.5, .97), (.57, .78)], (255, 160, 30))
    return im2.rotate(-35, resample=Image.BICUBIC)


def magnet():
    im = canvas(); d = ImageDraw.Draw(im)
    d.arc([110, 80, 402, 372], 180, 360, fill=(230, 50, 80), width=95)
    d.rectangle([110, 225, 205, 380], fill=(230, 50, 80))
    d.rectangle([307, 225, 402, 380], fill=(230, 50, 80))
    d.rectangle([110, 380, 205, 440], fill=(225, 225, 230))
    d.rectangle([307, 380, 402, 440], fill=(225, 225, 230))
    return im


def banana():
    im = canvas(); d = ImageDraw.Draw(im)
    # three drooping flaps around a stub
    for ang in (-60, 0, 60):
        f = canvas(); fd = ImageDraw.Draw(f)
        fd.ellipse([215, 210, 297, 460], fill=(255, 215, 50))
        fd.ellipse([238, 430, 274, 466], fill=(110, 70, 25))
        im.alpha_composite(f.rotate(ang, center=(256, 230), resample=Image.BICUBIC))
    d.rounded_rectangle([222, 90, 290, 260], 34, fill=(255, 225, 70))
    d.rectangle([243, 60, 270, 100], fill=(110, 70, 25))
    return im


def cloud():
    im = canvas(); d = ImageDraw.Draw(im)
    for x, y, r in [(170, 300, 95), (260, 240, 115), (350, 300, 95), (250, 330, 100)]:
        d.ellipse([x - r, y - r, x + r, y + r], fill=(60, 45, 80))
    for x, y, r in [(200, 410, 22), (290, 440, 18), (360, 405, 15)]:
        d.ellipse([x - r, y - r, x + r, y + r], fill=(60, 45, 80))
    d.ellipse([215, 255, 245, 285], fill=(240, 240, 255)); d.ellipse([285, 255, 315, 285], fill=(240, 240, 255))
    return im


def shield():
    im = canvas(); d = ImageDraw.Draw(im)
    poly(d, [(.2, .18), (.5, .08), (.8, .18), (.78, .55), (.5, .92), (.22, .55)], (40, 200, 220))
    poly(d, [(.3, .25), (.5, .18), (.7, .25), (.68, .52), (.5, .8), (.32, .52)], (150, 240, 250))
    return im


def lightning():
    im = canvas(); d = ImageDraw.Draw(im)
    poly(d, [(.58, .04), (.24, .56), (.47, .56), (.36, .96), (.78, .40), (.54, .40), (.70, .04)], (190, 130, 255))
    poly(d, [(.6, .1), (.33, .52), (.52, .52), (.45, .80), (.70, .44), (.5, .44), (.64, .1)], (250, 240, 255))
    return im


def ufo():
    im = canvas(); d = ImageDraw.Draw(im)
    poly(d, [(.34, .55), (.66, .55), (.85, .95), (.15, .95)], (120, 255, 140, 140))
    d.ellipse([60, 200, 452, 330], fill=(170, 180, 195))
    d.pieslice([160, 110, 352, 300], 180, 360, fill=(110, 240, 150))
    for i in range(5):
        x = 120 + i * 68
        d.ellipse([x - 16, 255, x + 16, 287], fill=(255, 235, 90))
    return im


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, fn in [("nitro", nitro), ("missile", missile), ("magnet", magnet), ("banana", banana),
                     ("cloud", cloud), ("shield", shield), ("lightning", lightning), ("ufo", ufo)]:
        finish(fn(), name)


if __name__ == "__main__":
    main()
