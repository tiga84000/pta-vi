#!/usr/bin/env python3
"""Génère les textures et les affiches ORIGINALES de PTA VI (aucune ressource externe ni sous licence).

Usage : python3 tools/make_assets.py assets
Dépendances : numpy, Pillow. Les PNG produits sont versionnés dans le dépôt.
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = sys.argv[1] if len(sys.argv) > 1 else "assets"
TEX = os.path.join(OUT, "tex")
POS = os.path.join(OUT, "posters")
os.makedirs(TEX, exist_ok=True)
os.makedirs(POS, exist_ok=True)
rng = np.random.default_rng(2025)

FONT_PATH = "/usr/share/fonts/truetype/google-fonts/Poppins-Bold.ttf"


def font(size):
    return ImageFont.truetype(FONT_PATH, int(size))


# ------------------------------------------------------------------ outils

def pnoise(h, w, sigma):
    """Bruit lisse périodique (tileable) dans [0, 1]."""
    r = rng.standard_normal((h, w))
    f = np.fft.fft2(r)
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    f *= np.exp(-2.0 * math.pi ** 2 * sigma ** 2 * (fx ** 2 + fy ** 2))
    n = np.real(np.fft.ifft2(f))
    n = (n - n.min()) / (n.max() - n.min() + 1e-9)
    return n


def save_rgb(arr, name, folder=TEX):
    img = Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8), "RGB")
    path = os.path.join(folder, name)
    img.save(path, optimize=True)
    return path


# ------------------------------------------------------------------ textures

def make_grain():
    n = 128
    g = 0.88 + (pnoise(n, n, 1.2) - 0.5) * 0.10 + (pnoise(n, n, 6) - 0.5) * 0.08
    save_rgb(np.stack([g, g, g], -1), "grain.png")


def make_parquet():
    n, rh = 256, 32
    img = np.zeros((n, n, 3))
    gn = pnoise(n, n, 2.0)
    for r in range(n // rh):
        off = int(rng.integers(0, n))
        for k in range(2):
            x0 = (off + k * 128) % n
            tint = np.array([1.0, 0.98 + 0.04 * rng.random(), 0.95 + 0.10 * rng.random()])
            base = np.array([176, 146, 108]) / 255.0 * (0.86 + 0.24 * rng.random()) * tint
            xs = (np.arange(128) + x0) % n
            ys = np.arange(r * rh, (r + 1) * rh)
            phase = rng.random() * 6.0
            stripes = 1.0 + 0.05 * np.sin(ys * 0.75 + phase)[:, None]
            grain = 1.0 + (gn[np.ix_(ys, xs)] - 0.5) * 0.18
            img[np.ix_(ys, xs)] = base[None, None, :] * (stripes * grain)[:, :, None]
            img[ys[0], xs] *= 0.55
            img[np.ix_(ys, [xs[0]])] *= 0.55
    save_rgb(img, "parquet.png")


def make_tiles(name, count, base, grout, var):
    n = 256
    step = n // count
    img = np.zeros((n, n, 3))
    for i in range(count):
        for j in range(count):
            c = np.array(base) / 255.0 * (1.0 - var + 2 * var * rng.random())
            img[i * step:(i + 1) * step, j * step:(j + 1) * step] = c
    noise = (pnoise(n, n, 1.5) - 0.5) * 0.06
    img += noise[:, :, None]
    gr = np.array(grout) / 255.0
    for k in range(count):
        img[k * step:k * step + 2, :] = gr
        img[:, k * step:k * step + 2] = gr
    save_rgb(img, name)


def make_sky():
    h, w = 128, 256
    v = np.linspace(0, 1, h)[:, None]
    top = np.array([0.24, 0.50, 0.86])
    hor = np.array([0.80, 0.91, 0.98])
    t = np.clip(v / 0.5, 0, 1) ** 0.7
    col = top[None, None, :] * (1 - t)[:, :, None] + hor[None, None, :] * t[:, :, None]
    col = np.broadcast_to(col, (h, w, 3)).copy()
    below = np.clip((v - 0.5) / 0.5, 0, 1)[:, :, None]
    col = col * (1 - below) + np.array([0.95, 0.97, 1.0]) * below
    fb = 0.6 * pnoise(h, w, 9) + 0.4 * pnoise(h, w, 4)
    mask = np.clip(1 - np.abs(v - 0.33) / 0.22, 0, 1)
    c = np.clip((fb - 0.52) * 3.4, 0, 1) * mask
    shade = 1.0 - 0.10 * c
    col = col * (1 - c[:, :, None] * 0.92) + (np.array([1.0, 1.0, 1.0]) * shade[:, :, None]) * (c[:, :, None] * 0.92)
    save_rgb(col, "sky.png")


def make_glass():
    n = 128
    y, x = np.mgrid[0:n, 0:n]
    d = (x + y) % n
    s1 = np.exp(-((d - 30) / 7.0) ** 2)
    s2 = np.exp(-((d - 82) / 2.5) ** 2)
    a = 18 + 52 * s1 + 38 * s2
    a[0, :] = a[-1, :] = a[:, 0] = a[:, -1] = 85
    rgba = np.zeros((n, n, 4), dtype=np.uint8)
    rgba[..., 0] = 205
    rgba[..., 1] = 232
    rgba[..., 2] = 255
    rgba[..., 3] = np.clip(a, 0, 255).astype(np.uint8)
    Image.fromarray(rgba, "RGBA").save(os.path.join(TEX, "glass.png"), optimize=True)


def make_projector():
    n = 256
    img = np.ones((n, n))
    for cx in (0, 64, 128, 192, 255):
        img[:, max(cx - 3, 0):cx + 3] = 0.08
    for cy in (0, 85, 171, 255):
        img[max(cy - 3, 0):cy + 3, :] = 0.08
    im = Image.fromarray((img * 255).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(1.6))
    im.convert("RGB").save(os.path.join(TEX, "projector.png"), optimize=True)


def glow_text(img, xy, text, f, color, radius=7):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).text(xy, text, font=f, fill=color + (255,), anchor="mm")
    blur = layer.filter(ImageFilter.GaussianBlur(radius))
    img.alpha_composite(blur)
    img.alpha_composite(blur)
    img.alpha_composite(layer)


def make_neon():
    img = Image.new("RGBA", (256, 128), (16, 16, 20, 255))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([4, 4, 251, 123], radius=10, outline=(60, 60, 70, 255), width=2)
    glow_text(img, (128, 56), "PTA VI", font(64), (255, 70, 150))
    d = ImageDraw.Draw(img)
    d.text((128, 56), "PTA VI", font=font(64), fill=(255, 190, 220), anchor="mm")
    glow_text(img, (128, 102), "P'TITE TEUB AUTO", font(15), (255, 150, 60), 4)
    img.convert("RGB").save(os.path.join(TEX, "neon_pta.png"), optimize=True)


def make_tv():
    w, h = 256, 144
    img = Image.new("RGBA", (w, h), (20, 90, 40, 255))
    d = ImageDraw.Draw(img, "RGBA")
    for i in range(8):
        c = (34, 120, 52, 255) if i % 2 == 0 else (40, 134, 58, 255)
        d.rectangle([i * 32, 0, i * 32 + 32, h], fill=c)
    wh = (235, 245, 235, 230)
    d.rectangle([14, 16, w - 14, h - 22], outline=wh, width=2)
    d.line([w / 2, 16, w / 2, h - 22], fill=wh, width=2)
    d.ellipse([w / 2 - 20, h / 2 - 22, w / 2 + 20, h / 2 + 18], outline=wh, width=2)
    d.rectangle([14, 44, 40, h - 50], outline=wh, width=2)
    d.rectangle([w - 40, 44, w - 14, h - 50], outline=wh, width=2)
    for (x, y) in [(60, 50), (80, 80), (100, 60), (120, 95), (70, 100), (150, 70), (170, 55)]:
        d.ellipse([x - 4, y - 5, x + 4, y + 5], fill=(215, 50, 50, 255), outline=(255, 255, 255, 255))
    for (x, y) in [(110, 70), (140, 90), (160, 100), (185, 75), (125, 55), (200, 90)]:
        d.ellipse([x - 4, y - 5, x + 4, y + 5], fill=(50, 90, 215, 255), outline=(255, 255, 255, 255))
    d.ellipse([132, 74, 138, 80], fill=(255, 255, 255, 255))
    d.rectangle([8, 6, 118, 22], fill=(10, 10, 20, 210))
    d.text((12, 8), "PTA 2 - 1 RNK", font=font(11), fill=(255, 255, 255, 255))
    d.rectangle([w - 58, 6, w - 8, 22], fill=(10, 10, 20, 210))
    d.text((w - 54, 8), "67:12", font=font(11), fill=(255, 220, 90, 255))
    d.rectangle([w - 64, h - 20, w - 8, h - 6], fill=(10, 10, 20, 170))
    img.filter(ImageFilter.GaussianBlur(0.5)).convert("RGB").save(os.path.join(TEX, "tvscreen.png"), optimize=True)


# ------------------------------------------------------------------ affiches

PW, PH, SS = 320, 480, 2   # taille finale et sur-échantillonnage
W, H = PW * SS, PH * SS


def new_poster(c0, c1, diagonal=False):
    y = np.linspace(0, 1, H)[:, None]
    x = np.linspace(0, 1, W)[None, :]
    t = (y * 0.8 + x * 0.2) if diagonal else np.broadcast_to(y, (H, W))
    a = np.array(c0, dtype=float)[None, None, :]
    b = np.array(c1, dtype=float)[None, None, :]
    arr = a * (1 - t[:, :, None]) + b * t[:, :, None]
    img = Image.fromarray(arr.astype(np.uint8), "RGB").convert("RGBA")
    return img


def halftone(img, color, spacing=18, rmax=6, alpha=70, fade_top=True):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer, "RGBA")
    for j, yy in enumerate(range(0, H, spacing)):
        r = rmax * (1 - yy / H) if fade_top else rmax * (yy / H)
        for xx in range(spacing // 2 * (j % 2), W, spacing):
            d.ellipse([xx - r, yy - r, xx + r, yy + r], fill=color + (alpha,))
    img.alpha_composite(layer)


def vignette(img, strength=0.55):
    y, x = np.mgrid[0:H, 0:W]
    dx = (x - W / 2) / (W / 2)
    dy = (y - H / 2) / (H / 2)
    v = 1 - strength * np.clip(dx ** 2 * 0.6 + dy ** 2 * 0.6, 0, 1)
    arr = np.array(img.convert("RGB")).astype(float) * v[:, :, None]
    out = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB").convert("RGBA")
    img.paste(out)


def txt(img, xy, text, size, fill, stroke=0, stroke_fill=(0, 0, 0)):
    d = ImageDraw.Draw(img, "RGBA")
    d.text(xy, text, font=font(size * SS), fill=fill, anchor="mm", stroke_width=stroke * SS, stroke_fill=stroke_fill)


def beam(img, x, top_w, bottom_x, bottom_w, color, alpha=60):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer, "RGBA").polygon(
        [(x - top_w, 0), (x + top_w, 0), (bottom_x + bottom_w, H), (bottom_x - bottom_w, H)], fill=color + (alpha,))
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(10)))


POSES = {
    "stand": dict(head=(.5, .08), neck=(.5, .17), hip=(.5, .52), lk=(.46, .74), lf=(.46, .95), rk=(.54, .74), rf=(.55, .95),
                  le=(.40, .34), lh=(.38, .50), re=(.60, .34), rh=(.62, .50)),
    "kick": dict(head=(.44, .10), neck=(.47, .19), hip=(.50, .52), lk=(.45, .74), lf=(.42, .95), rk=(.66, .60), rf=(.88, .52),
                 le=(.30, .30), lh=(.14, .25), re=(.64, .32), rh=(.80, .22)),
    "dive": dict(head=(.80, .28), neck=(.71, .36), hip=(.36, .58), lk=(.20, .70), lf=(.04, .78), rk=(.24, .50), rf=(.04, .48),
                 le=(.84, .24), lh=(.98, .13), re=(.88, .42), rh=(1.0, .36)),
    "cheer": dict(head=(.5, .08), neck=(.5, .17), hip=(.5, .52), lk=(.38, .74), lf=(.30, .95), rk=(.62, .74), rf=(.70, .95),
                  le=(.34, .20), lh=(.28, .02), re=(.66, .20), rh=(.72, .02)),
    "run": dict(head=(.56, .09), neck=(.54, .18), hip=(.50, .52), lk=(.40, .70), lf=(.26, .88), rk=(.64, .64), rf=(.72, .86),
                le=(.38, .34), lh=(.26, .44), re=(.64, .30), rh=(.74, .20)),
}


def limb(d, p, q, w, col):
    d.line([p, q], fill=col, width=int(w))
    r = w / 2
    for (x, y) in (p, q):
        d.ellipse([x - r, y - r, x + r, y + r], fill=col)


def lerp(p, q, t):
    return (p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t)


def figure(img, pose, ox, oy, s, jersey, shorts, socks, skin=(196, 150, 112), flip=False, glove=None):
    J = POSES[pose]
    d = ImageDraw.Draw(img, "RGBA")

    def P(k):
        x, y = J[k]
        if flip:
            x = 1 - x
        return (ox + x * s, oy + y * s)

    dark = (20, 20, 24)
    # jambes
    for hk, kk, fk in (("hip", "lk", "lf"), ("hip", "rk", "rf")):
        hip, knee, foot = P(hk), P(kk), P(fk)
        limb(d, hip, knee, .105 * s, skin)
        limb(d, hip, lerp(hip, knee, .5), .135 * s, shorts)
        limb(d, knee, foot, .085 * s, socks)
        d.ellipse([foot[0] - .06 * s, foot[1] - .03 * s, foot[0] + .07 * s, foot[1] + .035 * s], fill=dark)
    # torse
    limb(d, P("neck"), P("hip"), .20 * s, jersey)
    # bras
    for sk, ek, hk in (("neck", "le", "lh"), ("neck", "re", "rh")):
        sh, el, ha = P(sk), P(ek), P(hk)
        limb(d, sh, el, .08 * s, jersey)
        limb(d, el, ha, .065 * s, skin)
        if glove:
            limb(d, lerp(el, ha, .55), ha, .10 * s, glove)
    # tête
    hx, hy = P("head")
    r = .065 * s
    d.ellipse([hx - r, hy - r, hx + r, hy + r], fill=skin)
    d.pieslice([hx - r, hy - r * 1.05, hx + r, hy + r * .9], 180, 360, fill=(30, 24, 22))


def ball(img, cx, cy, r, glow=None):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer, "RGBA")
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(246, 246, 242, 255))

    def pent(x, y, rr, rot):
        pts = [(x + rr * math.cos(rot + k * 2 * math.pi / 5), y + rr * math.sin(rot + k * 2 * math.pi / 5)) for k in range(5)]
        d.polygon(pts, fill=(24, 24, 28, 255))

    pent(cx, cy, r * .32, -math.pi / 2)
    for k in range(5):
        a = -math.pi / 2 + k * 2 * math.pi / 5 + math.pi / 5
        px, py = cx + r * .86 * math.cos(a), cy + r * .86 * math.sin(a)
        pent(px, py, r * .26, a)
        d.line([(cx + r * .32 * math.cos(a - math.pi / 5), cy + r * .32 * math.sin(a - math.pi / 5)),
                (cx + r * .62 * math.cos(a - math.pi / 5), cy + r * .62 * math.sin(a - math.pi / 5))], fill=(24, 24, 28, 255), width=int(r * .05))
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
    layer.putalpha(Image.composite(layer.getchannel("A"), Image.new("L", img.size, 0), mask))
    if glow:
        g = Image.new("RGBA", img.size, (0, 0, 0, 0))
        ImageDraw.Draw(g).ellipse([cx - r * 1.1, cy - r * 1.1, cx + r * 1.1, cy + r * 1.1], fill=glow + (140,))
        img.alpha_composite(g.filter(ImageFilter.GaussianBlur(r * .35)))
    img.alpha_composite(layer)
    d2 = ImageDraw.Draw(img, "RGBA")
    d2.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(20, 20, 24, 200), width=max(2, int(r * .03)))


def confetti(img, n, palette):
    d = ImageDraw.Draw(img, "RGBA")
    for _ in range(n):
        x, y = rng.integers(0, W), rng.integers(0, H)
        w, h = rng.integers(8, 22), rng.integers(5, 12)
        c = palette[rng.integers(0, len(palette))]
        d.rectangle([x, y, x + w, y + h], fill=c + (230,))


def finish(img, name):
    d = ImageDraw.Draw(img, "RGBA")
    d.rectangle([0, 0, W - 1, H - 1], outline=(245, 245, 240, 255), width=14 * SS // 2)
    out = img.convert("RGB").resize((PW, PH), Image.LANCZOS)
    q = out.quantize(colors=160, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.FLOYDSTEINBERG)
    path = os.path.join(POS, name)
    q.save(path, optimize=True)
    return path


def poster_derby():
    img = new_poster((150, 25, 40), (60, 10, 30), True)
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).polygon([(W, 0), (W, H), (int(W * .25), H), (int(W * .65), 0)], fill=(30, 70, 200, 255))
    img.alpha_composite(layer)
    halftone(img, (255, 255, 255), alpha=45)
    for x in (110, 530):
        d = ImageDraw.Draw(img, "RGBA")
        d.ellipse([x - 26, 30, x + 26, 82], fill=(255, 250, 220, 255))
        beam(img, x, 14, x + (60 if x < 300 else -60), 150, (255, 245, 200), 38)
    figure(img, "kick", 40, 330, 520, (214, 40, 48), (245, 245, 245), (214, 40, 48))
    figure(img, "run", 260, 380, 470, (240, 240, 245), (30, 60, 160), (240, 240, 245), flip=True)
    ball(img, 520, 640, 40)
    txt(img, (W / 2, 150), "DERBY", 74, (255, 255, 255, 255), 5, (20, 10, 30))
    txt(img, (W / 2, 232), "NIGHT", 38, (255, 220, 90, 255), 3, (20, 10, 30))
    txt(img, (W / 2, 880), "ARENA UNITED  VS  NORTHPORT FC", 15, (255, 255, 255, 255), 2, (10, 10, 20))
    txt(img, (W / 2, 918), "SAISON 25 · LE CHOC", 14, (255, 220, 90, 255), 2, (10, 10, 20))
    vignette(img)
    return finish(img, "poster_1_derby.png")


def poster_keeper():
    img = new_poster((8, 50, 35), (3, 14, 12))
    beam(img, W * .72, 20, W * .45, 190, (200, 255, 220), 55)
    halftone(img, (120, 255, 170), alpha=40)
    figure(img, "dive", 60, 360, 500, (30, 200, 90), (20, 20, 24), (30, 200, 90), glove=(255, 230, 60))
    d = ImageDraw.Draw(img, "RGBA")
    d.rectangle([40, 860, W - 40, 864], fill=(120, 255, 170, 220))
    txt(img, (W / 2, 140), "LE MUR", 80, (255, 255, 255, 255), 5, (3, 25, 15))
    txt(img, (W / 2, 225), "D'ACIER", 40, (120, 255, 170, 255), 3, (3, 25, 15))
    txt(img, (W / 2, 810), "K. SANTOS", 30, (255, 255, 255, 255), 3, (3, 25, 15))
    txt(img, (W / 2, 900), "GARDIEN · 91", 18, (255, 230, 60, 255), 2, (3, 25, 15))
    vignette(img)
    return finish(img, "poster_2_gardien.png")


def poster_card():
    img = new_poster((22, 20, 28), (70, 52, 14))
    halftone(img, (255, 210, 90), alpha=35, fade_top=False)
    d = ImageDraw.Draw(img, "RGBA")
    shield = [(W / 2, 70), (W - 90, 120), (W - 90, 800), (W / 2, 880), (90, 800), (90, 120)]
    d.polygon(shield, fill=(212, 170, 60, 255))
    inner = [(W / 2, 100), (W - 112, 140), (W - 112, 800), (W / 2, 845), (112, 800), (112, 140)]
    d.polygon(inner, fill=(38, 30, 22, 255))
    d.polygon(inner, outline=(255, 226, 140, 255), width=5)
    d.ellipse([W / 2 - 78, 300, W / 2 + 78, 456], fill=(196, 150, 112, 255))
    d.pieslice([W / 2 - 78, 296, W / 2 + 78, 440], 180, 360, fill=(26, 20, 18, 255))
    d.polygon([(W / 2 - 200, 600), (W / 2 - 95, 450), (W / 2 + 95, 450), (W / 2 + 200, 600), (W / 2 + 200, 700),
               (W / 2 - 200, 700)], fill=(200, 40, 50, 255))
    d.rectangle([W / 2 - 18, 450, W / 2 + 18, 490], fill=(196, 150, 112, 255))
    txt(img, (190, 210), "94", 70, (255, 226, 140, 255), 3, (20, 14, 8))
    txt(img, (190, 290), "ATT", 24, (255, 255, 255, 255), 2, (20, 14, 8))
    txt(img, (W / 2, 738), "R. VALENTE", 26, (255, 226, 140, 255), 2, (20, 14, 8))
    labels = ["PAC 92", "TIR 95", "PAS 88", "DRI 93", "DEF 41", "PHY 80"]
    for i, lab in enumerate(labels):
        x = W / 2 - 115 + (i % 3) * 115
        y = 775 + (i // 3) * 32
        txt(img, (x, y), lab, 11, (255, 255, 255, 255), 1, (20, 14, 8))
    txt(img, (W / 2, 928), "ÉDITION OR · SAISON 25", 14, (255, 226, 140, 255), 2, (10, 8, 6))
    vignette(img, .5)
    return finish(img, "poster_3_carte.png")


def poster_final():
    img = new_poster((8, 14, 44), (30, 24, 70))
    for x in (110, 250, 390, 530):
        d = ImageDraw.Draw(img, "RGBA")
        d.rectangle([x - 6, 150, x + 6, 420], fill=(60, 66, 90, 255))
        d.rectangle([x - 34, 100, x + 34, 150], fill=(230, 235, 255, 255))
        beam(img, x, 24, x + (W / 2 - x) * .5, 130, (235, 240, 255), 26)
    d = ImageDraw.Draw(img, "RGBA")
    for _ in range(500):
        x, y = rng.integers(0, W), rng.integers(700, H)
        r = rng.integers(3, 7)
        c = [(240, 70, 80), (250, 200, 60), (90, 150, 250), (240, 240, 240)][rng.integers(0, 4)]
        d.ellipse([x - r, y - r, x + r, y + r], fill=c + (200,))
    d.rectangle([0, 640, W, 700], fill=(26, 100, 52, 255))
    ball(img, W / 2, 500, 110, glow=(120, 180, 255))
    txt(img, (W / 2, 230), "FINALE", 78, (255, 255, 255, 255), 5, (10, 10, 40))
    txt(img, (W / 2, 800), "COUPE PTA · 2025", 22, (255, 220, 90, 255), 2, (10, 10, 40))
    txt(img, (W / 2, 850), "ESTADIO DEL SOL", 14, (210, 220, 255, 255), 2, (10, 10, 40))
    vignette(img)
    return finish(img, "poster_4_finale.png")


def poster_cheer():
    img = new_poster((255, 120, 60), (170, 30, 110))
    halftone(img, (255, 255, 255), alpha=55, spacing=22, rmax=8)
    confetti(img, 90, [(255, 255, 255), (255, 230, 90), (60, 40, 120), (30, 200, 200)])
    figure(img, "cheer", 110, 330, 560, (250, 250, 250), (40, 30, 90), (250, 250, 250))
    txt(img, (W / 2, 150), "BUUUT !", 66, (255, 255, 255, 255), 6, (80, 10, 60))
    txt(img, (W / 2, 222), "90+3'", 34, (255, 230, 90, 255), 3, (80, 10, 60))
    txt(img, (W / 2, 900), "LA VICTOIRE AU BOUT DU SUSPENS", 14, (255, 255, 255, 255), 2, (80, 10, 60))
    vignette(img, .4)
    return finish(img, "poster_5_but.png")


def poster_tactic():
    img = new_poster((16, 70, 40), (8, 36, 24))
    d = ImageDraw.Draw(img, "RGBA")
    x0, y0, x1, y1 = 80, 260, W - 80, 840
    stripes = Image.new("RGBA", img.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(stripes)
    for i in range(1, 6, 2):
        sd.rectangle([x0, y0 + i * (y1 - y0) / 6, x1, y0 + (i + 1) * (y1 - y0) / 6], fill=(255, 255, 255, 22))
    img.alpha_composite(stripes)
    d = ImageDraw.Draw(img, "RGBA")
    d.rectangle([x0, y0, x1, y1], outline=(235, 245, 235, 230), width=5)
    d.line([x0, (y0 + y1) / 2, x1, (y0 + y1) / 2], fill=(235, 245, 235, 230), width=5)
    cy = (y0 + y1) / 2
    d.ellipse([W / 2 - 70, cy - 70, W / 2 + 70, cy + 70], outline=(235, 245, 235, 230), width=5)
    d.rectangle([W / 2 - 130, y0, W / 2 + 130, y0 + 110], outline=(235, 245, 235, 230), width=5)
    d.rectangle([W / 2 - 130, y1 - 110, W / 2 + 130, y1], outline=(235, 245, 235, 230), width=5)
    pts = [(W / 2, 800), (200, 700), (W / 2 - 70, 720), (W / 2 + 70, 720), (W - 200, 700),
           (260, 560), (W / 2, 580), (W - 260, 560), (210, 400), (W / 2, 350), (W - 210, 400)]
    for (x, y) in pts:
        d.ellipse([x - 15, y - 15, x + 15, y + 15], fill=(255, 215, 70, 255), outline=(20, 20, 20, 255), width=3)
    for (a, b) in [((260, 560), (210, 400)), ((W / 2, 580), (W / 2, 350)), ((W - 260, 560), (W - 210, 400)),
                   ((200, 700), (260, 560)), ((W - 200, 700), (W - 260, 560))]:
        d.line([a, b], fill=(255, 255, 255, 230), width=6)
        ang = math.atan2(b[1] - a[1], b[0] - a[0])
        for s in (-.5, .5):
            d.line([b, (b[0] - 34 * math.cos(ang + s), b[1] - 34 * math.sin(ang + s))], fill=(255, 255, 255, 230), width=6)
    txt(img, (W / 2, 120), "4-3-3", 84, (255, 255, 255, 255), 5, (4, 30, 18))
    txt(img, (W / 2, 205), "PLAN DE JEU", 30, (255, 215, 70, 255), 3, (4, 30, 18))
    txt(img, (W / 2, 900), "PRESSING HAUT · JEU À UN TOUCHER", 14, (255, 255, 255, 255), 2, (4, 30, 18))
    vignette(img, .4)
    return finish(img, "poster_6_tactique.png")


def poster_trophy():
    img = new_poster((14, 22, 62), (6, 8, 26))
    cx = W / 2
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    for k in range(16):
        a = k * math.pi / 8
        ld.polygon([(cx, 500), (cx + 900 * math.cos(a - .06), 500 + 900 * math.sin(a - .06)),
                    (cx + 900 * math.cos(a + .06), 500 + 900 * math.sin(a + .06))], fill=(255, 220, 110, 40))
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(4)))
    d = ImageDraw.Draw(img, "RGBA")
    gold, gold2 = (240, 190, 50, 255), (255, 232, 140, 255)
    d.polygon([(cx - 130, 330), (cx + 130, 330), (cx + 100, 520), (cx + 40, 590), (cx - 40, 590), (cx - 100, 520)], fill=gold)
    d.polygon([(cx - 90, 340), (cx - 40, 340), (cx - 55, 560), (cx - 70, 520)], fill=gold2)
    d.arc([cx - 220, 340, cx - 90, 480], 90, 270, fill=gold, width=22)
    d.arc([cx + 90, 340, cx + 220, 480], 270, 90, fill=gold, width=22)
    d.rectangle([cx - 28, 590, cx + 28, 700], fill=gold)
    d.polygon([(cx - 120, 700), (cx + 120, 700), (cx + 150, 780), (cx - 150, 780)], fill=gold)
    d.rectangle([cx - 150, 780, cx + 150, 810], fill=(60, 40, 20, 255))
    ball(img, cx, 250, 62, glow=(255, 220, 110))
    txt(img, (W / 2, 120), "CHAMPIONS", 44, (255, 232, 140, 255), 4, (10, 8, 30))
    txt(img, (W / 2, 880), "COUPE PTA", 40, (255, 255, 255, 255), 3, (10, 8, 30))
    txt(img, (W / 2, 925), "ÉDITION 2025", 16, (255, 232, 140, 255), 2, (10, 8, 30))
    vignette(img)
    return finish(img, "poster_7_trophee.png")


def poster_ball():
    img = new_poster((255, 214, 60), (240, 120, 40))
    halftone(img, (200, 70, 20), spacing=20, rmax=8, alpha=80, fade_top=False)
    ball(img, W / 2, 470, 230, glow=(255, 255, 200))
    txt(img, (W / 2, 130), "FOOT", 90, (30, 20, 20, 255), 0)
    txt(img, (W / 2, 232), "TOUTE LA NUIT", 26, (120, 30, 10, 255), 0)
    txt(img, (W / 2, 850), "MANETTE EN MAIN", 26, (30, 20, 20, 255), 0)
    txt(img, (W / 2, 900), "SAISON 25", 16, (120, 30, 10, 255), 0)
    vignette(img, .35)
    return finish(img, "poster_8_ballon.png")


def main():
    make_grain()
    make_parquet()
    make_tiles("tile_light.png", 4, (232, 232, 226), (196, 196, 192), 0.025)
    make_tiles("tile_dark.png", 2, (96, 98, 100), (62, 64, 66), 0.05)
    make_sky()
    make_glass()
    make_projector()
    make_neon()
    make_tv()
    for fn in (poster_derby, poster_keeper, poster_card, poster_final, poster_cheer, poster_tactic, poster_trophy, poster_ball):
        print(fn())
    total = 0
    for folder in (TEX, POS):
        for f in sorted(os.listdir(folder)):
            s = os.path.getsize(os.path.join(folder, f))
            total += s
            print(f"{folder}/{f}: {s/1024:.0f} Ko")
    print(f"TOTAL: {total/1024:.0f} Ko")


if __name__ == "__main__":
    main()
