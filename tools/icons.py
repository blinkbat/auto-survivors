"""Writes a placeholder icon for every level-up card into assets/icon_<name>.png: drawn at 16 px, outlined, doubled."""
from pathlib import Path
from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parent.parent / "assets"
INK = (16, 14, 20, 255)

STEEL = (190, 198, 212, 255)
DARK_STEEL = (110, 116, 130, 255)
GOLD = (232, 196, 90, 255)
WOOD = (150, 104, 52, 255)
BLUE = (70, 110, 200, 255)
PALE_BLUE = (150, 190, 255, 255)
RED = (200, 50, 44, 255)
GREEN = (110, 210, 100, 255)
PALE_GREEN = (180, 245, 170, 255)
WHITE = (240, 236, 220, 255)
FIRE = (255, 150, 40, 255)
FIRE_HOT = (255, 230, 140, 255)
FIRE_DEEP = (210, 60, 20, 255)
FEATHER = (230, 230, 230, 255)


def canvas():
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
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


def sword(d, x0, y0, x1, y1, blade=STEEL):
    d.line([(x0, y0), (x1, y1)], fill=blade, width=2)


def flame(d, cx, by, s=1.0):
    h = int(9 * s)
    w = int(4 * s)
    d.polygon([(cx - w, by), (cx, by - h), (cx + w, by)], fill=FIRE_DEEP)
    d.polygon([(cx - w + 1, by), (cx, by - h + 2), (cx + w - 1, by)], fill=FIRE)
    d.ellipse([cx - max(1, w // 2), by - max(2, h // 3), cx + max(1, w // 2), by], fill=FIRE_HOT)


def arrow(d, x0, y0, x1, y1, head=STEEL):
    d.line([(x0, y0), (x1, y1)], fill=WOOD, width=1)
    d.point([(x1, y1), (x1 - 1, y1), (x1, y1 + 1)], fill=head)
    d.point([(x0, y0), (x0 + 1, y0), (x0, y0 - 1)], fill=FEATHER)


def heart(d, x, y, col):
    d.ellipse([x, y, x + 5, y + 5], fill=col)
    d.ellipse([x + 4, y, x + 9, y + 5], fill=col)
    d.polygon([(x, y + 3), (x + 9, y + 3), (x + 4, y + 9)], fill=col)


def shield(d, x, y, w, h, col, rim=None):
    d.polygon([(x, y), (x + w, y), (x + w, y + h * 0.6), (x + w / 2, y + h), (x, y + h * 0.6)], fill=rim or col)
    if rim:
        d.polygon([(x + 1, y + 1), (x + w - 1, y + 1), (x + w - 1, y + h * 0.58), (x + w / 2, y + h - 2), (x + 1, y + h * 0.58)], fill=col)


def icons():
    out = {}

    def make(name):
        def wrap(f):
            img, d = canvas()
            f(d)
            out[name] = img
            return f
        return wrap

    @make("blade")
    def _(d):
        sword(d, 3, 12, 12, 3)
        d.line([(3, 9), (6, 12)], fill=GOLD, width=2)

    @make("tower")
    def _(d):
        d.rectangle([4, 2, 11, 13], fill=BLUE)
        d.rectangle([7, 3, 8, 12], fill=GOLD)

    @make("cleave")
    def _(d):
        d.arc([2, 2, 14, 14], 200, 340, fill=WHITE, width=2)
        for p in ((3, 11), (8, 13), (13, 11)):
            d.point([p], fill=RED)

    @make("echo")
    def _(d):
        d.arc([1, 1, 15, 15], 200, 340, fill=WHITE, width=2)
        d.arc([3, 5, 13, 15], 200, 340, fill=(180, 180, 200, 255), width=1)
        d.arc([5, 9, 11, 15], 200, 340, fill=(120, 120, 140, 255), width=1)

    @make("fortify")
    def _(d):
        shield(d, 3, 2, 10, 12, DARK_STEEL, STEEL)
        d.rectangle([7, 5, 8, 10], fill=GOLD)
        d.rectangle([5, 7, 10, 8], fill=GOLD)

    @make("riposte")
    def _(d):
        sword(d, 3, 12, 11, 4)
        d.arc([6, 6, 14, 14], 270, 90, fill=GOLD, width=1)
        d.point([(13, 10), (12, 11)], fill=GOLD)

    @make("longsword")
    def _(d):
        d.line([(8, 1), (8, 11)], fill=STEEL, width=2)
        d.line([(5, 11), (11, 11)], fill=GOLD, width=1)
        d.line([(8, 12), (8, 14)], fill=WOOD, width=2)

    @make("second_wind")
    def _(d):
        heart(d, 2, 4, RED)
        d.arc([8, 2, 15, 9], 180, 360, fill=GREEN, width=1)
        d.arc([9, 6, 15, 12], 0, 180, fill=GREEN, width=1)

    @make("executioner")
    def _(d):
        d.line([(4, 14), (10, 3)], fill=WOOD, width=2)
        d.pieslice([6, 1, 15, 10], 300, 90, fill=STEEL)

    @make("fletching")
    def _(d):
        d.line([(2, 13), (13, 2)], fill=WOOD, width=1)
        d.polygon([(2, 13), (2, 8), (5, 10)], fill=FEATHER)
        d.polygon([(2, 13), (7, 13), (5, 10)], fill=FEATHER)

    @make("quick_draw")
    def _(d):
        arrow(d, 4, 8, 14, 8)
        for y in (5, 8, 11):
            d.line([(1, y), (3, y)], fill=WHITE)

    @make("split_arrow")
    def _(d):
        arrow(d, 2, 13, 13, 2)
        arrow(d, 2, 13, 14, 9)
        arrow(d, 2, 13, 9, 1)

    @make("longbow")
    def _(d):
        d.arc([2, 0, 12, 15], 300, 60, fill=WOOD, width=2)
        d.line([(10, 1), (10, 14)], fill=WHITE)

    @make("keen_eye")
    def _(d):
        d.ellipse([1, 4, 14, 11], fill=WHITE)
        d.ellipse([5, 4, 10, 11], fill=BLUE)
        d.ellipse([7, 6, 8, 9], fill=INK)

    @make("hunters_mark")
    def _(d):
        d.ellipse([2, 2, 13, 13], outline=RED, width=1)
        d.ellipse([5, 5, 10, 10], outline=RED, width=1)
        d.line([(7, 0), (7, 4)], fill=RED)
        d.line([(7, 11), (7, 15)], fill=RED)
        d.line([(0, 7), (4, 7)], fill=RED)
        d.line([(11, 7), (15, 7)], fill=RED)

    @make("wide_volley")
    def _(d):
        d.pieslice([0, 0, 15, 15], 200, 340, fill=(120, 170, 110, 255))
        arrow(d, 7, 12, 7, 2)

    @make("mending")
    def _(d):
        d.rectangle([6, 2, 9, 13], fill=GREEN)
        d.rectangle([2, 6, 13, 9], fill=GREEN)

    @make("vigor")
    def _(d):
        heart(d, 3, 3, RED)
        d.point([(5, 5)], fill=WHITE)

    @make("smite")
    def _(d):
        d.polygon([(9, 1), (4, 8), (8, 8), (6, 15), (12, 6), (8, 6)], fill=GOLD)

    @make("radiance")
    def _(d):
        d.ellipse([5, 5, 10, 10], fill=GOLD)
        for a, b in (((7, 0), (7, 3)), ((7, 12), (7, 15)), ((0, 7), (3, 7)), ((12, 7), (15, 7)), ((2, 2), (4, 4)), ((11, 11), (13, 13)), ((13, 2), (11, 4)), ((2, 13), (4, 11))):
            d.line([a, b], fill=GOLD)

    @make("aegis")
    def _(d):
        d.ellipse([1, 1, 14, 14], outline=PALE_BLUE, width=2)
        d.ellipse([5, 5, 10, 10], fill=BLUE)

    @make("lifeline")
    def _(d):
        d.line([(2, 13), (13, 2)], fill=PALE_GREEN, width=2)
        d.ellipse([0, 11, 4, 15], fill=WHITE)
        d.ellipse([11, 0, 15, 4], fill=GREEN)

    @make("consecrate")
    def _(d):
        d.ellipse([1, 7, 14, 14], outline=GOLD, width=2)
        d.rectangle([7, 1, 8, 9], fill=GOLD)
        d.rectangle([5, 3, 10, 4], fill=GOLD)

    @make("kindling")
    def _(d):
        d.line([(3, 14), (12, 11)], fill=WOOD, width=2)
        d.line([(3, 11), (12, 14)], fill=WOOD, width=2)
        flame(d, 8, 11, 0.8)

    @make("ember")
    def _(d):
        flame(d, 9, 14, 1.2)
        for y in (6, 9, 12):
            d.line([(0, y), (3, y)], fill=FIRE)

    @make("fireball")
    def _(d):
        d.polygon([(0, 15), (6, 6), (9, 9)], fill=FIRE_DEEP)
        d.ellipse([5, 2, 14, 11], fill=FIRE)
        d.ellipse([8, 4, 12, 8], fill=FIRE_HOT)

    @make("twin_flame")
    def _(d):
        flame(d, 5, 14, 1.2)
        flame(d, 11, 14, 1.2)

    @make("immolate")
    def _(d):
        d.ellipse([4, 7, 11, 14], fill=(110, 124, 92, 255))
        flame(d, 8, 9, 1.0)

    @make("quickening")
    def _(d):
        d.polygon([(3, 1), (12, 1), (8, 7)], fill=PALE_BLUE)
        d.polygon([(3, 14), (12, 14), (8, 8)], fill=PALE_BLUE)
        d.line([(2, 1), (13, 1)], fill=WOOD)
        d.line([(2, 14), (13, 14)], fill=WOOD)
        d.polygon([(6, 13), (10, 13), (8, 10)], fill=GOLD)

    @make("stillness")
    def _(d):
        d.ellipse([1, 1, 14, 14], fill=WHITE)
        d.ellipse([3, 3, 12, 12], fill=(200, 220, 255, 255))
        d.line([(7, 7), (7, 3)], fill=INK)
        d.line([(7, 7), (10, 9)], fill=INK)

    @make("expanse")
    def _(d):
        d.ellipse([0, 0, 15, 15], outline=PALE_BLUE, width=1)
        d.ellipse([3, 3, 12, 12], outline=BLUE, width=1)
        d.ellipse([6, 6, 9, 9], fill=PALE_BLUE)

    @make("shatter")
    def _(d):
        d.polygon([(7, 0), (13, 6), (8, 15), (2, 6)], fill=PALE_BLUE)
        d.line([(7, 2), (6, 7), (9, 9), (7, 13)], fill=INK)
        d.point([(13, 1), (1, 12), (14, 13)], fill=WHITE)

    @make("long_tendrils")
    def _(d):
        d.line([(2, 14), (6, 8), (10, 6), (14, 1)], fill=GREEN, width=2)
        d.polygon([(11, 1), (15, 0), (14, 4)], fill=PALE_GREEN)

    @make("thicket")
    def _(d):
        for x in (3, 8, 13):
            d.line([(x, 15), (x, 6)], fill=GREEN, width=2)
            d.ellipse([x - 2, 3, x + 2, 7], fill=PALE_GREEN)

    @make("verdant")
    def _(d):
        d.ellipse([1, 4, 11, 14], fill=GREEN)
        d.line([(2, 13), (9, 6)], fill=(60, 120, 50, 255))
        d.rectangle([11, 1, 12, 8], fill=PALE_GREEN)
        d.rectangle([8, 4, 15, 5], fill=PALE_GREEN)

    @make("venom")
    def _(d):
        d.polygon([(8, 1), (13, 9), (3, 9)], fill=(150, 200, 40, 255))
        d.ellipse([3, 6, 13, 15], fill=(150, 200, 40, 255))
        d.ellipse([5, 8, 8, 11], fill=(220, 250, 140, 255))

    @make("enchanting_air")
    def _(d):
        d.ellipse([2, 9, 7, 14], fill=(240, 150, 220, 255))
        d.line([(6, 11), (6, 2)], fill=(240, 150, 220, 255), width=1)
        d.line([(6, 2), (12, 4)], fill=(240, 150, 220, 255), width=2)
        heart(d, 8, 7, (230, 90, 160, 255))

    @make("wide_song")
    def _(d):
        d.ellipse([0, 0, 15, 15], outline=(240, 150, 220, 255), width=1)
        d.ellipse([3, 3, 12, 12], outline=(200, 110, 190, 255), width=1)
        d.ellipse([5, 8, 8, 11], fill=WHITE)
        d.line([(8, 9), (8, 4)], fill=WHITE)

    @make("crescendo")
    def _(d):
        d.polygon([(1, 8), (14, 2), (14, 14)], fill=(232, 196, 90, 255))
        d.polygon([(4, 8), (13, 4), (13, 12)], fill=(250, 230, 150, 255))

    @make("tempo")
    def _(d):
        d.polygon([(4, 15), (7, 1), (9, 1), (12, 15)], fill=WOOD)
        d.line([(8, 12), (12, 3)], fill=WHITE, width=1)
        d.ellipse([10, 2, 13, 5], fill=GOLD)

    @make("legion")
    def _(d):
        for x in (2, 6, 10):
            d.ellipse([x, 3, x + 4, 7], fill=(226, 220, 200, 255))
            d.line([(x + 2, 7), (x + 2, 13)], fill=(226, 220, 200, 255))

    @make("bone_armor")
    def _(d):
        shield(d, 3, 2, 10, 12, (120, 116, 104, 255), (226, 220, 200, 255))
        d.line([(5, 6), (11, 6)], fill=(120, 116, 104, 255))
        d.line([(5, 9), (11, 9)], fill=(120, 116, 104, 255))

    @make("grave_strength")
    def _(d):
        d.line([(3, 13), (12, 3)], fill=(226, 220, 200, 255), width=3)
        d.ellipse([10, 1, 14, 5], fill=(226, 220, 200, 255))
        d.ellipse([1, 11, 5, 15], fill=(226, 220, 200, 255))

    @make("deathly_precision")
    def _(d):
        d.ellipse([3, 2, 12, 11], fill=(226, 220, 200, 255))
        d.point([(5, 6), (6, 6), (9, 6), (10, 6)], fill=(60, 220, 120, 255))
        d.ellipse([10, 9, 15, 14], outline=RED, width=1)

    @make("bulwark")
    def _(d):
        shield(d, 1, 1, 13, 14, BLUE, GOLD)
        d.rectangle([7, 4, 8, 11], fill=GOLD)

    @make("vanguard")
    def _(d):
        d.line([(2, 14), (12, 4)], fill=WOOD, width=2)
        d.polygon([(10, 1), (15, 1), (15, 6), (12, 4)], fill=STEEL)

    @make("sniper")
    def _(d):
        d.ellipse([3, 3, 12, 12], outline=WHITE, width=1)
        d.point([(7, 7), (8, 7), (7, 8), (8, 8)], fill=RED)
        arrow(d, 0, 15, 6, 9)

    @make("skirmisher")
    def _(d):
        arrow(d, 8, 8, 15, 2)
        arrow(d, 8, 8, 15, 14)
        arrow(d, 8, 8, 1, 8)

    @make("saint")
    def _(d):
        d.ellipse([2, 1, 13, 6], outline=GOLD, width=2)
        d.ellipse([5, 7, 10, 12], fill=WHITE)
        d.polygon([(3, 15), (7, 11), (12, 15)], fill=WHITE)

    @make("martyr")
    def _(d):
        heart(d, 3, 2, RED)
        d.line([(7, 3), (6, 7), (8, 9)], fill=INK)
        d.point([(7, 13), (7, 14), (10, 14)], fill=RED)

    @make("move")
    def _(d):
        for a, b, tip in (((7, 7), (7, 1), [(5, 3), (7, 0), (10, 3)]), ((7, 7), (7, 14), [(5, 12), (7, 15), (10, 12)]),
                          ((7, 7), (1, 7), [(3, 5), (0, 7), (3, 10)]), ((7, 7), (14, 7), [(12, 5), (15, 7), (12, 10)])):
            d.line([a, b], fill=WHITE, width=2)
            d.polygon(tip, fill=WHITE)

    @make("rest")
    def _(d):
        d.ellipse([2, 2, 13, 13], fill=(230, 220, 160, 255))
        d.ellipse([6, 0, 16, 11], fill=(0, 0, 0, 0))

    for name, img in out.items():
        img = outlined(img).resize((32, 32), Image.NEAREST)
        img.save(OUT / f"icon_{name}.png")
    return sorted(out)


print("icons", icons())
