# Makes the map picture for the About box.
#
#   python make_about_map.py      reads map.png and "MAP REF.png" in resources,
#                                 writes about-map.png
#                                 and about-map-faded.png (the one the About box shows)
#
# map.png      the map as cropped from the CyclOSM layer (1280 x 960)
# MAP REF.png  the same picture with a red line drawn where the track goes
#
# What it does: takes the creek names, "ECG" and the upper "Ridge Road" off the
# map, then draws the track along the red line the way the program draws one:
# a thin line with a dot at every point.  The red line only has to be near the
# road; the track is pulled onto the middle of the road.
# Needs Pillow and numpy.
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent.parent      # the resources folder

WATER = (173, 222, 255)
TRACK = (20, 48, 138)
CASING = (255, 255, 255)
END = (217, 48, 37)

# Sizes in map pixels.  The About box shows the map at half size, so these are
# twice what the program uses on its own map.
LINE_WIDTH = 5.5
CASING_WIDTH = 11
POINT_RADIUS = 6.5
POINT_EDGE = 3
POINT_SPACING = 26        # distance between the dots
END_RADIUS = 9
END_RING = 3.5

FADE = 0.62               # how far the faded picture goes towards white (0 = not at all)

SNAP_RADIUS = 10          # how far the track may move to reach the road

# "Ridge Road" is on the map twice. This box holds the upper one, which goes.
RIDGE_UPPER = (176, 36, 240, 100)   # left, top, right, bottom
ROAD_DIRECTION = (-0.87, 1.0)       # the way Ridge Road runs there (x, y)


def grow(mask, times):
    """Widen a mask by one pixel in every direction, 'times' times."""
    for _ in range(times):
        m = mask.copy()
        m[1:, :] |= mask[:-1, :]
        m[:-1, :] |= mask[1:, :]
        m[:, 1:] |= mask[:, :-1]
        m[:, :-1] |= mask[:, 1:]
        m[1:, 1:] |= mask[:-1, :-1]
        m[:-1, :-1] |= mask[1:, 1:]
        m[1:, :-1] |= mask[:-1, 1:]
        m[:-1, 1:] |= mask[1:, :-1]
        mask = m
    return mask


def fill_along(img, mask, direction):
    """Paint over the masked pixels from the nearest clear pixels up and down
    the road, so the road's edges and centre line carry straight through."""
    dx, dy = direction
    length = (dx * dx + dy * dy) ** 0.5
    dx, dy = dx / length, dy / length
    h, w = mask.shape
    out = img.copy()

    def reach(x, y, sign):
        for step in range(1, 120):
            sx = int(round(x + sign * dx * step))
            sy = int(round(y + sign * dy * step))
            if not (0 <= sx < w and 0 <= sy < h):
                return None
            if not mask[sy, sx]:
                return step, img[sy, sx].astype(float)
        return None

    for y, x in zip(*np.nonzero(mask)):
        a = reach(x, y, 1)
        b = reach(x, y, -1)
        if a and b:
            out[y, x] = (a[1] * b[0] + b[1] * a[0]) / (a[0] + b[0]) + 0.5
        elif a or b:
            out[y, x] = (a or b)[1]
    return out


def clean(img):
    r = img[..., 0].astype(int)
    g = img[..., 1].astype(int)
    b = img[..., 2].astype(int)

    # creek names: blue letters with a pale edge, lying in the water
    letters = (r < 140) & (g > r + 40) & (b > 190)
    area = grow(letters, 4)
    dashes = grow((g < r + 25) & (b > 180) & (r < 170), 1)   # the purple dashed line stays
    img[area & ~dashes] = WATER

    # "ECG": red letters beside the road
    red = (r > 190) & (g < 120) & (b < 120)
    img = fill_along(img, grow(red, 2), ROAD_DIRECTION)

    # the upper "Ridge Road": dark letters on the road
    x0, y0, x1, y1 = RIDGE_UPPER
    dark = np.zeros(r.shape, bool)
    lum = (r + g + b) // 3
    dark[y0:y1, x0:x1] = lum[y0:y1, x0:x1] < 150
    img = fill_along(img, grow(dark, 1), ROAD_DIRECTION)
    return img


def red_line(plain, marked):
    """The red line of MAP REF.png as points in order, from the left edge on."""
    diff = np.abs(marked.astype(int) - plain.astype(int)).sum(axis=2) > 120
    line = grow(diff, 2)
    ys, xs = np.nonzero(diff)
    start = (int(ys[np.argmin(xs)]), int(xs.min()))
    h, w = line.shape
    dist = np.full(line.shape, -1, int)
    dist[start] = 0
    queue = deque([start])
    last = start
    while queue:
        y, x = queue.popleft()
        last = (y, x)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                ny, nx = y + dy, x + dx
                if 0 <= ny < h and 0 <= nx < w and line[ny, nx] and dist[ny, nx] < 0:
                    dist[ny, nx] = dist[y, x] + 1
                    queue.append((ny, nx))
    # walk back from the far end
    path = [last]
    y, x = last
    while dist[y, x] > 0:
        best = None
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                ny, nx = y + dy, x + dx
                if 0 <= ny < h and 0 <= nx < w and dist[ny, nx] == dist[y, x] - 1:
                    best = (ny, nx)
        y, x = best
        path.append(best)
    path.reverse()
    return np.array([(x, y) for y, x in path], float)


def smooth(pts, win):
    pad = np.concatenate([np.repeat(pts[:1], win, 0), pts, np.repeat(pts[-1:], win, 0)])
    kernel = np.ones(2 * win + 1) / (2 * win + 1)
    return np.stack([np.convolve(pad[:, i], kernel, 'valid') for i in (0, 1)], axis=1)


def snap_to_road(pts, plain):
    """Move each point to the middle of the white road next to it."""
    road = (plain.min(axis=2) >= 250)
    h, w = road.shape
    n = len(pts)
    steps = np.arange(-SNAP_RADIUS, SNAP_RADIUS + 0.25, 0.5)
    normals = np.zeros_like(pts)
    shift = np.full(n, np.nan)
    last = 0.0
    for i in range(n):
        a, b = pts[max(i - 4, 0)], pts[min(i + 4, n - 1)]
        t = (b - a) / max(np.hypot(*(b - a)), 1e-6)
        normals[i] = (-t[1], t[0])
        # look sideways for the nearest stretch of road and take its middle
        on = []
        for s in steps:
            x, y = pts[i] + normals[i] * s
            xi, yi = int(round(x)), int(round(y))
            on.append(0 <= xi < w and 0 <= yi < h and bool(road[yi, xi]))
        runs, start = [], None
        for k, v in enumerate(on + [False]):
            if v and start is None:
                start = k
            elif not v and start is not None:
                runs.append((steps[start] + steps[k - 1]) / 2)
                start = None
        if runs:
            # stay with the road the track is already on
            shift[i] = min(runs, key=lambda r: abs(r - last))
            last = shift[i]
    # no road beside a point: go by its neighbours; then even out any jumps
    known = ~np.isnan(shift)
    if not known.any():
        return pts
    shift = np.interp(np.arange(n), np.nonzero(known)[0], shift[known])
    pad = np.concatenate([np.repeat(shift[:1], 6), shift, np.repeat(shift[-1:], 6)])
    shift = np.array([np.median(pad[i:i + 13]) for i in range(n)])
    shift = np.convolve(np.concatenate([np.repeat(shift[:1], 5), shift, np.repeat(shift[-1:], 5)]),
                        np.ones(11) / 11, 'valid')
    return pts + normals * shift[:, None]


def evenly(pts, spacing):
    """Points 'spacing' apart along the line, counted back from its end."""
    seg = np.hypot(*np.diff(pts, axis=0).T)
    along = np.concatenate([[0], np.cumsum(seg)])
    marks = np.arange(along[-1], 0, -spacing)[::-1]
    return np.stack([np.interp(marks, along, pts[:, i]) for i in (0, 1)], axis=1)


def track_points(plain, marked):
    pts = smooth(red_line(plain, marked), 5)
    pts = smooth(snap_to_road(pts, plain), 7)
    # the track comes in from off the picture
    lead = pts[0] + (pts[0] - pts[12]) / np.hypot(*(pts[0] - pts[12])) * 60
    return np.concatenate([[lead], pts])


def draw_track(img, line):
    z = 3                                        # drawn large, then scaled down for smooth edges
    base = Image.fromarray(img).convert('RGBA')
    layer = Image.new('RGBA', (base.width * z, base.height * z), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    thin = list(line[:-1:4]) + [line[-1]]          # fewer joints draw a cleaner line
    pts = [(x * z, y * z) for x, y in thin]

    def stroke(color, width):
        d.line(pts, fill=color, width=int(round(width * z)), joint='curve')

    def disc(p, radius, color):
        x, y = p[0] * z, p[1] * z
        r = radius * z
        d.ellipse((x - r, y - r, x + r, y + r), fill=color)

    stroke(CASING, CASING_WIDTH)
    stroke(TRACK, LINE_WIDTH)
    dots = evenly(line, POINT_SPACING)
    for p in dots[:-1]:
        disc(p, POINT_RADIUS + POINT_EDGE / 2, TRACK)
        disc(p, POINT_RADIUS - POINT_EDGE / 2, CASING)
    disc(line[-1], END_RADIUS + END_RING, CASING)
    disc(line[-1], END_RADIUS, END)
    layer = layer.resize(base.size, Image.LANCZOS)
    return Image.alpha_composite(base, layer).convert('RGB')


def main():
    for name in ('map.png', 'MAP REF.png'):
        if not (HERE / name).exists():
            raise SystemExit('Put %s in the resources folder first.' % name)
    plain = np.array(Image.open(HERE / 'map.png').convert('RGB'))
    marked = np.array(Image.open(HERE / 'MAP REF.png').convert('RGB'))
    line = track_points(plain, marked)
    result = draw_track(clean(plain.copy()), line)
    result.save(HERE / 'about-map.png')
    faded = Image.blend(result, Image.new('RGB', result.size, 'white'), FADE)
    faded.save(HERE / 'about-map-faded.png', optimize=True)
    print('wrote', HERE / 'about-map.png', 'and about-map-faded.png')


if __name__ == '__main__':
    main()
