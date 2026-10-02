"""Writes the placeholder body and floor sprites into assets/ (icons are tools/icons.py): drawn at half size, outlined, doubled. Facing right."""
import random
from pathlib import Path
from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parent.parent / "assets"
INK = (16, 14, 20, 255)


def canvas(n):
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def outlined(img):
    w, h = img.size
    src = img.load()
    out = img.copy()
    dst = out.load()
    for y in range(h):
        for x in range(w):
            if src[x, y][3]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                sx, sy = x + dx, y + dy
                if 0 <= sx < w and 0 <= sy < h and src[sx, sy][3]:
                    dst[x, y] = INK
                    break
    return out


def save(img, name):
    img = outlined(img)
    img = img.resize((img.width * 2, img.height * 2), Image.NEAREST)
    img.save(OUT / name)


def knight():
    img, d = canvas(32)
    d.rectangle([12, 24, 14, 29], fill=(70, 72, 84, 255))
    d.rectangle([17, 24, 19, 29], fill=(70, 72, 84, 255))
    d.rectangle([11, 14, 20, 24], fill=(150, 158, 172, 255))
    d.rectangle([11, 19, 20, 20], fill=(110, 84, 50, 255))
    d.ellipse([11, 5, 20, 14], fill=(176, 184, 198, 255))
    d.rectangle([11, 10, 20, 14], fill=(176, 184, 198, 255))
    d.rectangle([15, 9, 20, 10], fill=(30, 30, 40, 255))
    d.polygon([(19, 13), (26, 13), (26, 21), (22, 26), (19, 21)], fill=(52, 84, 160, 255))
    d.rectangle([22, 15, 23, 22], fill=(214, 180, 82, 255))
    d.rectangle([20, 17, 25, 18], fill=(214, 180, 82, 255))
    save(img, "knight.png")


def archer():
    img, d = canvas(32)
    d.rectangle([12, 24, 14, 29], fill=(74, 56, 40, 255))
    d.rectangle([17, 24, 19, 29], fill=(74, 56, 40, 255))
    d.rectangle([11, 14, 19, 24], fill=(120, 88, 54, 255))
    d.polygon([(10, 15), (15, 4), (21, 15)], fill=(66, 124, 62, 255))
    d.rectangle([14, 10, 18, 14], fill=(222, 182, 146, 255))
    d.polygon([(10, 15), (19, 15), (19, 18), (10, 18)], fill=(66, 124, 62, 255))
    d.arc([16, 6, 28, 28], start=-80, end=80, fill=(150, 104, 52, 255), width=2)
    d.line([(23, 7), (23, 27)], fill=(220, 214, 190, 255), width=1)
    save(img, "archer.png")


def cleric():
    img, d = canvas(32)
    d.polygon([(10, 29), (13, 13), (19, 13), (22, 29)], fill=(226, 220, 204, 255))
    d.rectangle([15, 13, 16, 29], fill=(214, 180, 82, 255))
    d.ellipse([12, 5, 20, 14], fill=(226, 220, 204, 255))
    d.rectangle([15, 8, 19, 12], fill=(222, 182, 146, 255))
    d.line([(24, 6), (24, 29)], fill=(130, 96, 56, 255), width=2)
    d.ellipse([22, 3, 27, 8], fill=(240, 206, 96, 255))
    d.rectangle([19, 17, 23, 19], fill=(226, 220, 204, 255))
    save(img, "cleric.png")


def pyromancer():
    img, d = canvas(32)
    d.polygon([(10, 29), (13, 14), (19, 14), (22, 29)], fill=(156, 40, 36, 255))
    d.rectangle([10, 27, 22, 29], fill=(96, 24, 26, 255))
    d.rectangle([14, 10, 18, 14], fill=(222, 182, 146, 255))
    d.polygon([(10, 11), (15, 1), (22, 11)], fill=(120, 30, 32, 255))
    d.rectangle([9, 10, 23, 11], fill=(96, 24, 26, 255))
    d.rectangle([19, 17, 23, 19], fill=(156, 40, 36, 255))
    d.ellipse([22, 13, 28, 19], fill=(255, 150, 40, 255))
    d.ellipse([23, 14, 26, 17], fill=(255, 230, 140, 255))
    save(img, "pyromancer.png")


def mystic():
    img, d = canvas(32)
    d.polygon([(10, 29), (12, 14), (20, 14), (22, 29)], fill=(52, 92, 176, 255))
    d.polygon([(12, 29), (14, 17), (18, 17), (20, 29)], fill=(74, 118, 204, 255))
    d.rectangle([12, 18, 20, 19], fill=(214, 180, 82, 255))
    d.ellipse([12, 5, 20, 13], fill=(222, 182, 146, 255))
    d.ellipse([15, 3, 18, 6], fill=(40, 60, 120, 255))
    d.point([(18, 9)], fill=(30, 30, 40, 255))
    d.rectangle([20, 15, 23, 18], fill=(74, 118, 204, 255))
    d.rectangle([23, 13, 25, 17], fill=(222, 182, 146, 255))
    for x, y in ((13, 21), (15, 22), (17, 22), (19, 21)):
        d.point([(x, y)], fill=(160, 220, 255, 255))
    save(img, "mystic.png")


def druid():
    img, d = canvas(32)
    d.polygon([(10, 29), (12, 14), (20, 14), (22, 29)], fill=(78, 104, 54, 255))
    d.polygon([(12, 29), (14, 18), (18, 18), (20, 29)], fill=(110, 84, 50, 255))
    d.rectangle([12, 18, 20, 19], fill=(150, 190, 80, 255))
    d.ellipse([12, 6, 20, 14], fill=(222, 182, 146, 255))
    d.rectangle([12, 6, 20, 8], fill=(78, 104, 54, 255))
    d.line([(13, 6), (10, 2), (8, 3)], fill=(170, 140, 100, 255))
    d.line([(19, 6), (22, 2), (24, 3)], fill=(170, 140, 100, 255))
    d.point([(18, 10)], fill=(30, 30, 40, 255))
    d.line([(24, 5), (24, 29)], fill=(110, 80, 50, 255), width=2)
    d.ellipse([22, 3, 27, 8], fill=(110, 190, 80, 255))
    d.rectangle([20, 16, 23, 18], fill=(78, 104, 54, 255))
    save(img, "druid.png")


def vine():
    img, d = canvas(32)
    d.ellipse([7, 25, 25, 30], fill=(60, 44, 30, 255))
    d.line([(16, 28), (14, 20), (17, 13), (15, 6)], fill=(60, 120, 50, 255), width=3)
    d.line([(15, 22), (9, 17), (7, 11)], fill=(70, 140, 56, 255), width=2)
    d.line([(16, 19), (22, 15), (25, 9)], fill=(70, 140, 56, 255), width=2)
    for x, y in ((15, 5), (7, 10), (25, 8)):
        d.ellipse([x - 2, y - 2, x + 2, y + 2], fill=(130, 200, 90, 255))
    d.point([(12, 18), (20, 21), (18, 10)], fill=(200, 230, 120, 255))
    d.ellipse([12, 9, 15, 12], fill=(200, 80, 140, 255))
    save(img, "vine.png")


def bard():
    img, d = canvas(32)
    d.rectangle([12, 24, 14, 29], fill=(90, 50, 80, 255))
    d.rectangle([17, 24, 19, 29], fill=(90, 50, 80, 255))
    d.polygon([(11, 25), (12, 14), (20, 14), (21, 25)], fill=(170, 70, 140, 255))
    d.rectangle([12, 18, 20, 19], fill=(232, 196, 90, 255))
    d.ellipse([12, 6, 20, 14], fill=(222, 182, 146, 255))
    d.polygon([(11, 8), (16, 3), (21, 8)], fill=(70, 120, 90, 255))
    d.line([(17, 4), (24, 1)], fill=(240, 236, 220, 255), width=1)
    d.point([(18, 10)], fill=(30, 30, 40, 255))
    d.arc([19, 12, 29, 26], 270, 90, fill=(232, 196, 90, 255), width=2)
    d.line([(24, 12), (24, 26)], fill=(232, 196, 90, 255))
    for y in (15, 18, 21):
        d.line([(24, y), (27, y)], fill=(240, 236, 220, 255))
    save(img, "bard.png")


def necromancer():
    img, d = canvas(32)
    d.polygon([(9, 29), (12, 13), (20, 13), (23, 29)], fill=(34, 32, 40, 255))
    d.polygon([(12, 29), (14, 17), (18, 17), (20, 29)], fill=(52, 48, 62, 255))
    d.polygon([(11, 13), (16, 4), (21, 13)], fill=(34, 32, 40, 255))
    d.ellipse([13, 8, 19, 13], fill=(200, 196, 180, 255))
    d.point([(15, 10), (17, 10)], fill=(90, 255, 140, 255))
    d.line([(24, 5), (24, 29)], fill=(90, 80, 70, 255), width=2)
    d.ellipse([21, 1, 27, 7], fill=(220, 214, 196, 255))
    d.point([(23, 4), (25, 4)], fill=(40, 30, 30, 255))
    d.rectangle([20, 16, 23, 18], fill=(34, 32, 40, 255))
    save(img, "necromancer.png")


def skeleton():
    img, d = canvas(32)
    bone = (226, 220, 200, 255)
    d.line([(13, 22), (12, 29)], fill=bone, width=2)
    d.line([(18, 22), (19, 29)], fill=bone, width=2)
    d.rectangle([12, 20, 19, 22], fill=bone)
    d.line([(15, 12), (15, 20)], fill=bone, width=2)
    for y in (14, 16, 18):
        d.line([(12, y), (19, y)], fill=bone)
    d.ellipse([11, 4, 20, 12], fill=bone)
    d.point([(16, 7), (18, 7)], fill=(60, 200, 110, 255))
    d.rectangle([14, 10, 18, 11], fill=(150, 144, 130, 255))
    d.line([(19, 14), (25, 11)], fill=bone, width=1)
    d.line([(25, 5), (25, 17)], fill=(150, 156, 170, 255), width=2)
    d.line([(23, 14), (27, 14)], fill=(120, 90, 60, 255))
    save(img, "skeleton.png")


def ghoul():
    img, d = canvas(32)
    d.rectangle([12, 24, 14, 29], fill=(66, 74, 60, 255))
    d.rectangle([17, 24, 19, 29], fill=(66, 74, 60, 255))
    d.polygon([(10, 25), (12, 13), (20, 12), (21, 25)], fill=(104, 124, 92, 255))
    d.ellipse([14, 6, 23, 15], fill=(124, 144, 108, 255))
    d.rectangle([19, 9, 20, 10], fill=(220, 60, 40, 255))
    d.line([(19, 16), (27, 18)], fill=(104, 124, 92, 255), width=3)
    d.line([(18, 20), (27, 21)], fill=(90, 108, 80, 255), width=2)
    save(img, "ghoul.png")


def bat():
    img, d = canvas(24)
    d.polygon([(2, 8), (9, 11), (8, 16), (5, 13), (2, 15)], fill=(92, 60, 120, 255))
    d.polygon([(22, 8), (15, 11), (16, 16), (19, 13), (22, 15)], fill=(92, 60, 120, 255))
    d.ellipse([8, 9, 16, 18], fill=(120, 84, 150, 255))
    d.polygon([(9, 10), (10, 6), (12, 10)], fill=(120, 84, 150, 255))
    d.polygon([(12, 10), (14, 6), (15, 10)], fill=(120, 84, 150, 255))
    d.point([(13, 12), (15, 12)], fill=(255, 220, 90, 255))
    save(img, "bat.png")


def spitter():
    img, d = canvas(32)
    d.ellipse([5, 14, 25, 29], fill=(150, 160, 60, 255))
    d.ellipse([8, 17, 18, 25], fill=(176, 186, 84, 255))
    d.ellipse([17, 9, 27, 21], fill=(150, 160, 60, 255))
    d.ellipse([23, 13, 28, 18], fill=(60, 30, 30, 255))
    d.point([(21, 12)], fill=(250, 250, 200, 255))
    save(img, "spitter.png")


def brute():
    img, d = canvas(48)
    d.rectangle([16, 36, 21, 45], fill=(96, 40, 36, 255))
    d.rectangle([27, 36, 32, 45], fill=(96, 40, 36, 255))
    d.ellipse([10, 14, 38, 40], fill=(168, 62, 50, 255))
    d.ellipse([22, 6, 36, 20], fill=(188, 76, 60, 255))
    d.polygon([(23, 8), (20, 1), (26, 7)], fill=(230, 220, 190, 255))
    d.polygon([(33, 8), (36, 1), (31, 7)], fill=(230, 220, 190, 255))
    d.rectangle([30, 11, 33, 12], fill=(255, 220, 80, 255))
    d.line([(34, 24), (44, 30)], fill=(168, 62, 50, 255), width=5)
    d.rectangle([40, 24, 46, 40], fill=(110, 80, 50, 255))
    save(img, "brute.png")


def boss():
    img, d = canvas(64)
    d.polygon([(12, 62), (22, 22), (42, 22), (52, 62)], fill=(58, 30, 82, 255))
    d.polygon([(18, 62), (26, 30), (38, 30), (46, 62)], fill=(80, 44, 110, 255))
    d.ellipse([22, 8, 42, 28], fill=(214, 206, 186, 255))
    d.rectangle([27, 15, 30, 18], fill=(120, 255, 170, 255))
    d.rectangle([35, 15, 38, 18], fill=(120, 255, 170, 255))
    d.rectangle([28, 23, 37, 25], fill=(60, 40, 40, 255))
    d.polygon([(23, 12), (14, 0), (27, 9)], fill=(70, 50, 60, 255))
    d.polygon([(41, 12), (50, 0), (37, 9)], fill=(70, 50, 60, 255))
    d.line([(52, 6), (52, 62)], fill=(90, 70, 50, 255), width=3)
    d.ellipse([47, 1, 57, 11], fill=(120, 255, 170, 255))
    d.line([(40, 34), (51, 30)], fill=(58, 30, 82, 255), width=4)
    save(img, "boss.png")


def husk():
    img, d = canvas(32)
    d.rectangle([11, 25, 14, 29], fill=(70, 74, 64, 255))
    d.rectangle([18, 25, 21, 29], fill=(70, 74, 64, 255))
    d.ellipse([7, 10, 25, 27], fill=(122, 128, 104, 255))
    d.ellipse([10, 14, 20, 24], fill=(146, 150, 124, 255))
    d.ellipse([15, 4, 24, 13], fill=(122, 128, 104, 255))
    d.point([(21, 8)], fill=(220, 200, 60, 255))
    d.line([(23, 16), (27, 21)], fill=(122, 128, 104, 255), width=3)
    for x, y in ((12, 13), (18, 21), (9, 19)):
        d.ellipse([x - 1, y - 1, x + 1, y + 1], fill=(100, 60, 60, 255))
    save(img, "husk.png")


def shellback():
    img, d = canvas(48)
    for x in (12, 20, 28, 36):
        d.line([(x, 34), (x - 2, 42)], fill=(50, 46, 60, 255), width=3)
    d.chord([4, 10, 44, 44], 180, 360, fill=(70, 80, 120, 255))
    d.rectangle([4, 26, 44, 34], fill=(70, 80, 120, 255))
    for x in (12, 22, 32):
        d.polygon([(x, 14), (x + 6, 14), (x + 8, 24), (x - 2, 24)], fill=(96, 110, 156, 255))
    d.rectangle([4, 30, 44, 34], fill=(50, 58, 90, 255))
    d.ellipse([38, 22, 47, 32], fill=(110, 100, 80, 255))
    d.point([(44, 25)], fill=(255, 220, 90, 255))
    save(img, "shellback.png")


def charger():
    img, d = canvas(32)
    for x in (9, 13, 19, 23):
        d.line([(x, 22), (x, 28)], fill=(70, 46, 34, 255), width=2)
    d.ellipse([5, 11, 25, 24], fill=(120, 72, 48, 255))
    d.polygon([(6, 12), (10, 8), (14, 12)], fill=(90, 54, 36, 255))
    d.ellipse([20, 12, 29, 21], fill=(140, 86, 56, 255))
    d.polygon([(27, 18), (31, 15), (28, 20)], fill=(236, 226, 196, 255))
    d.point([(25, 14)], fill=(255, 60, 40, 255))
    save(img, "charger.png")


def hound():
    img, d = canvas(32)
    for x in (9, 12, 19, 22):
        d.line([(x, 21), (x, 27)], fill=(40, 34, 36, 255), width=2)
    d.ellipse([6, 14, 24, 23], fill=(64, 56, 60, 255))
    d.ellipse([19, 9, 28, 17], fill=(74, 64, 68, 255))
    d.polygon([(25, 13), (31, 14), (26, 16)], fill=(74, 64, 68, 255))
    d.polygon([(21, 9), (22, 5), (24, 9)], fill=(54, 46, 50, 255))
    d.line([(6, 16), (2, 12)], fill=(64, 56, 60, 255), width=2)
    d.point([(25, 11)], fill=(255, 200, 60, 255))
    save(img, "hound.png")


def imp():
    img, d = canvas(24)
    d.ellipse([7, 9, 17, 21], fill=(190, 70, 50, 255))
    d.ellipse([8, 3, 16, 11], fill=(210, 84, 60, 255))
    d.polygon([(9, 4), (8, 0), (11, 3)], fill=(60, 40, 40, 255))
    d.polygon([(15, 4), (16, 0), (13, 3)], fill=(60, 40, 40, 255))
    d.polygon([(4, 10), (8, 12), (6, 15)], fill=(150, 50, 40, 255))
    d.ellipse([17, 9, 22, 14], fill=(40, 36, 36, 255))
    d.point([(19, 8)], fill=(255, 200, 60, 255))
    d.point([(14, 6)], fill=(255, 230, 120, 255))
    save(img, "imp.png")


def warlock():
    img, d = canvas(32)
    d.polygon([(9, 29), (12, 13), (20, 13), (23, 29)], fill=(70, 34, 90, 255))
    d.polygon([(12, 29), (14, 17), (18, 17), (20, 29)], fill=(98, 50, 122, 255))
    d.polygon([(11, 13), (16, 3), (21, 13)], fill=(70, 34, 90, 255))
    d.rectangle([14, 9, 18, 12], fill=(30, 20, 30, 255))
    d.point([(15, 10), (17, 10)], fill=(255, 90, 90, 255))
    d.line([(24, 6), (24, 29)], fill=(60, 46, 40, 255), width=2)
    d.ellipse([21, 2, 27, 8], fill=(220, 60, 90, 255))
    d.rectangle([20, 16, 23, 18], fill=(70, 34, 90, 255))
    save(img, "warlock.png")


def brazier():
    img, d = canvas(32)
    d.line([(11, 30), (16, 18)], fill=(60, 56, 60, 255), width=2)
    d.line([(21, 30), (16, 18)], fill=(60, 56, 60, 255), width=2)
    d.line([(16, 18), (16, 30)], fill=(60, 56, 60, 255), width=2)
    d.polygon([(8, 14), (24, 14), (21, 19), (11, 19)], fill=(84, 78, 84, 255))
    d.rectangle([10, 12, 22, 14], fill=(120, 60, 30, 255))
    d.point([(12, 12), (15, 11), (18, 12), (20, 11)], fill=(255, 180, 70, 255))
    save(img, "brazier.png")


def banner():
    img, d = canvas(32)
    d.line([(10, 3), (10, 30)], fill=(110, 80, 50, 255), width=2)
    d.polygon([(11, 4), (25, 4), (25, 18), (18, 15), (11, 18)], fill=(200, 160, 60, 255))
    d.rectangle([16, 7, 19, 12], fill=(140, 40, 40, 255))
    d.ellipse([7, 1, 12, 5], fill=(230, 200, 100, 255))
    d.rectangle([6, 28, 15, 30], fill=(80, 60, 40, 255))
    save(img, "banner.png")


def floor():
    rng = random.Random(7)
    n = 32
    img = Image.new("RGBA", (n, n), (24, 30, 26, 255))
    px = img.load()
    for _ in range(10):
        cx, cy, r = rng.randrange(n), rng.randrange(n), rng.randrange(3, 7)
        tone = rng.choice([(20, 25, 22), (28, 35, 29), (30, 30, 30)])
        for y in range(-r, r + 1):
            for x in range(-r, r + 1):
                if x * x + y * y <= r * r and rng.random() < 0.7:
                    px[(cx + x) % n, (cy + y) % n] = tone + (255,)
    for _ in range(40):
        x, y = rng.randrange(n), rng.randrange(n)
        px[x, y] = rng.choice([(40, 52, 40), (16, 20, 18), (36, 44, 34)]) + (255,)
    img.resize((n * 2, n * 2), Image.NEAREST).save(OUT / "floor.png")


for f in (knight, archer, cleric, pyromancer, mystic, druid, bard, necromancer, skeleton, vine, ghoul, bat, spitter, husk, shellback, charger, hound, imp, warlock, brute, boss, brazier, banner, floor):
    f()
print("painted", sorted(p.name for p in OUT.glob("*.png")))
