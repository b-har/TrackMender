# Draws the program icon: Kittles Island in the Georgia marsh, with a track
# down the road to the east end of the island.
#
#   python make_icon.py        writes TrackMender.ico and icon.png into resources
#
# Needs Pillow (pip install pillow).  Each icon size is drawn on its own, so
# the small ones keep thick lines and leave out the fine detail.
import io
import random
import struct
from pathlib import Path
from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent.parent      # the resources folder
SIZES = [16, 20, 24, 32, 40, 48, 64, 128, 256]

MARSH = (201, 228, 180)
REED = (120, 180, 226)
WATER = (120, 190, 236)
LAND = (245, 234, 214)
LAND_EDGE = (214, 196, 166)
WOOD = (140, 188, 120)
ROAD = (255, 255, 255)
ROAD_EDGE = (150, 150, 158)
TRACK = (20, 48, 138)
CASING = (255, 255, 255)
START = (30, 158, 84)
END = (217, 48, 37)

# The scene, in the pixels of the map picture it was drawn from.
# The icon shows the square that starts at ORIGIN and is SPAN wide.
ORIGIN = (6, 4)
SPAN = 350

RIVER = [(250, -20), (246, 60), (238, 140), (243, 215), (262, 285), (312, 328), (378, 330), (460, 300)]
RIVER_WIDTH = 36
CREEK_SOUTH = [(-20, 392), (60, 372), (130, 378), (200, 350), (262, 300)]
CREEK_SOUTH_WIDTH = 22
CREEK_WEST = [(40, 150), (62, 175), (50, 215), (70, 245)]
CREEK_WEST_WIDTH = 7

UPLAND = [(-30, -30), (285, -30), (262, 22), (215, 58), (168, 72), (140, 104), (98, 116), (58, 96), (-30, 132)]
SEABREEZE = [(160, 142), (196, 150), (204, 178), (182, 212), (160, 246), (128, 268), (92, 276), (80, 258),
             (104, 232), (128, 196), (140, 160)]
KITTLES = [(122, 282), (150, 262), (192, 246), (232, 226), (246, 236), (236, 252), (196, 268), (152, 292),
           (126, 304)]
WOODS = [(246, 330), (262, 326), (276, 344), (270, 360), (250, 356)]

# the road: down from the mainland, across Seabreeze Island, out along Kittles Island
TRACK_LINE = [(70, 35), (104, 32), (148, 58), (165, 108), (171, 150), (166, 200), (144, 240),
              (152, 266), (188, 254), (231, 238)]
ROAD_WEST = [(144, 240), (112, 256), (88, 262)]          # the rest of the Seabreeze road


def smooth(points, steps=14, closed=False):
    """A rounded line through the points (Catmull-Rom)."""
    pts = list(points)
    n = len(pts)
    out = []
    last = n if closed else n - 1
    for i in range(last):
        if closed:
            p0, p1, p2, p3 = pts[(i - 1) % n], pts[i], pts[(i + 1) % n], pts[(i + 2) % n]
        else:
            p0, p1, p2, p3 = pts[max(i - 1, 0)], pts[i], pts[i + 1], pts[min(i + 2, n - 1)]
        for s in range(steps):
            t = s / steps
            out.append(tuple(
                0.5 * (2 * b + (c - a) * t + (2 * a - 5 * b + 4 * c - d) * t * t + (3 * b - a - 3 * c + d) * t ** 3)
                for a, b, c, d in zip(p0, p1, p2, p3)))
    if not closed:
        out.append(pts[-1])
    return out


def render(size):
    scale = 8 if size <= 64 else 4
    px = size * scale
    k = px / SPAN                      # map pixels to drawing pixels

    def at(p):
        return ((p[0] - ORIGIN[0]) * k, (p[1] - ORIGIN[1]) * k)

    def width(map_width, least=0.0):
        """Line width in drawing pixels, never thinner than 'least' icon pixels."""
        return max(map_width * k, least * scale)

    img = Image.new('RGB', (px, px), MARSH)
    d = ImageDraw.Draw(img)

    def line(points, color, w):
        pts = [at(p) for p in smooth(points)]
        d.line(pts, fill=color, width=int(round(w)), joint='curve')
        r = w / 2
        for x, y in (pts[0], pts[-1]):
            d.ellipse((x - r, y - r, x + r, y + r), fill=color)

    def blob(points, color, edge=None, edge_width=0.0):
        pts = [at(p) for p in smooth(points, closed=True)]
        d.polygon(pts, fill=color)
        if edge and edge_width > 0:
            d.line(pts + [pts[0]], fill=edge, width=int(round(edge_width)), joint='curve')

    def dot(p, radius, color):
        x, y = at(p)
        r = radius + width(0, 1.0)
        d.ellipse((x - r, y - r, x + r, y + r), fill=CASING)
        d.ellipse((x - radius, y - radius, x + radius, y + radius), fill=color)

    detail = size >= 40

    # marsh: short blue strokes, as on the map
    if detail:
        rnd = random.Random(7)
        step = 15
        for row, y in enumerate(range(ORIGIN[1] - step, ORIGIN[1] + SPAN + step, step)):
            for x in range(ORIGIN[0] - step, ORIGIN[0] + SPAN + step, step):
                cx = x + (step / 2 if row % 2 else 0) + rnd.uniform(-2, 2)
                cy = y + rnd.uniform(-2, 2)
                a, b = at((cx - 3.2, cy)), at((cx + 3.2, cy))
                d.line([a, b], fill=REED, width=max(1, int(round(width(1.5)))))

    line(RIVER, WATER, width(RIVER_WIDTH))
    line(CREEK_SOUTH, WATER, width(CREEK_SOUTH_WIDTH))
    if detail:
        line(CREEK_WEST, WATER, width(CREEK_WEST_WIDTH))
        blob(WOODS, WOOD)

    edge = width(1.6) if detail else 0
    for land in (UPLAND, SEABREEZE, KITTLES):
        blob(land, LAND, LAND_EDGE, edge)

    if detail:
        line(ROAD_WEST, ROAD_EDGE, width(6.5))
        line(ROAD_WEST, ROAD, width(4.2))

    # the track, drawn the way the program draws one
    track = width(9.5, 1.7)
    line(TRACK_LINE, CASING, track + width(5, 1.6))
    line(TRACK_LINE, TRACK, track)
    dot(TRACK_LINE[-1], width(10.5, 1.8), END)
    if size >= 24:
        dot((70, 35), width(11.5, 2.0), START)

    # rounded corners
    mask = Image.new('L', (px, px), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, px - 1, px - 1), radius=int(px * 0.2), fill=255)
    img.putalpha(mask)
    return img.resize((size, size), Image.LANCZOS)


def ico_bitmap(img):
    """One icon picture the classic way: 32-bit pixels, bottom row first,
    followed by the 1-bit mask that marks the see-through pixels."""
    w, h = img.size
    rgba = img.convert('RGBA')
    pixels = rgba.transpose(Image.FLIP_TOP_BOTTOM).tobytes('raw', 'BGRA')
    row = ((w + 31) // 32) * 4
    alpha = rgba.getchannel('A').transpose(Image.FLIP_TOP_BOTTOM).load()
    mask = bytearray(row * h)
    for y in range(h):
        for x in range(w):
            if alpha[x, y] == 0:
                mask[y * row + x // 8] |= 0x80 >> (x % 8)
    header = struct.pack('<IiiHHIIiiII', 40, w, h * 2, 1, 32, 0, len(pixels) + len(mask), 0, 0, 0, 0)
    return header + pixels + bytes(mask)


def write_ico(name, images):
    """Sizes below 256 as bitmaps, 256 as PNG: what Windows and the resource
    compilers expect."""
    parts = []
    for img in images:
        if img.width >= 256:
            buf = io.BytesIO()
            img.save(buf, format='PNG')
            parts.append(buf.getvalue())
        else:
            parts.append(ico_bitmap(img))
    out = struct.pack('<HHH', 0, 1, len(images))
    offset = 6 + 16 * len(images)
    for img, data in zip(images, parts):
        out += struct.pack('<BBBBHHII', img.width % 256, img.height % 256, 0, 0, 1, 32, len(data), offset)
        offset += len(data)
    Path(name).write_bytes(out + b''.join(parts))


def main():
    images = {s: render(s) for s in SIZES}
    images[256].save(HERE / 'icon.png')
    write_ico(HERE / 'TrackMender.ico', [images[s] for s in SIZES])
    # a sheet of every size, to check them by eye
    sheet = Image.new('RGBA', (sum(SIZES) + 12 * (len(SIZES) + 1), 280), (240, 240, 240, 255))
    x = 12
    for s in SIZES:
        sheet.alpha_composite(images[s], (x, 12))
        x += s + 12
    return sheet


if __name__ == '__main__':
    sheet = main()
    import sys
    if len(sys.argv) > 1:
        sheet.save(sys.argv[1])
    print('wrote', HERE / 'TrackMender.ico')
