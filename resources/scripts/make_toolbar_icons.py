# Draws the toolbar icons and puts them into the Delphi main form.
#
#   python make_toolbar_icons.py      rewrites the path data in D12/uMain.fmx
#   python export_graphics.py         then saves them to resources/toolbar as svg and png
#
# Every icon is built here from plain shapes (bars, rings, arcs, teeth) on a
# 24 x 24 grid; nothing is taken from an icon set.  To change an icon, change
# its function below and run both scripts.
#
# A shape is a list of outlines.  The first outline of a part is filled; a
# hole is an outline that runs the other way round inside it.  Parts never
# overlap, so the result is the same whichever way a program fills paths.
import math
import re
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
FORM = ROOT / 'D12' / 'uMain.fmx'


# ---- building blocks -----------------------------------------------------------

def area(pts):
    return sum(x0 * y1 - x1 * y0 for (x0, y0), (x1, y1) in zip(pts, pts[1:] + pts[:1])) / 2


def solid(pts):
    """An outline to fill."""
    return pts if area(pts) > 0 else pts[::-1]


def hole(pts):
    """An outline to cut out of the solid around it."""
    return pts if area(pts) < 0 else pts[::-1]


def rect(x0, y0, x1, y1):
    return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]


def circle(cx, cy, r, steps=48):
    return [(cx + r * math.cos(2 * math.pi * i / steps), cy + r * math.sin(2 * math.pi * i / steps))
            for i in range(steps)]


def polar(cx, cy, r, degrees):
    """A point on a circle; 0 is right, 90 is up."""
    a = math.radians(degrees)
    return (cx + r * math.cos(a), cy - r * math.sin(a))


def stroke(points, width):
    """A line of the given width through the points, as one outline (square ends, sharp corners)."""
    h = width / 2
    n = len(points)
    left, right = [], []
    for i, (x, y) in enumerate(points):
        def normal(a, b):
            dx, dy = b[0] - a[0], b[1] - a[1]
            d = math.hypot(dx, dy)
            return (-dy / d, dx / d)
        if i == 0:
            nx, ny = normal(points[0], points[1])
            k = 1.0
        elif i == n - 1:
            nx, ny = normal(points[-2], points[-1])
            k = 1.0
        else:
            n1 = normal(points[i - 1], points[i])
            n2 = normal(points[i], points[i + 1])
            nx, ny = n1[0] + n2[0], n1[1] + n2[1]
            d = math.hypot(nx, ny)
            nx, ny = nx / d, ny / d
            k = 1 / max(nx * n1[0] + ny * n1[1], 0.3)
        left.append((x + nx * h * k, y + ny * h * k))
        right.append((x - nx * h * k, y - ny * h * k))
    return left + right[::-1]


def mirror(shape):
    return [[(24 - x, y) for x, y in outline] for outline in shape]


# ---- the icons -----------------------------------------------------------------

def icon_open():
    # a folder: tab at the top left, open front
    body = [(2, 4.5), (9, 4.5), (11.2, 7.2), (22, 7.2), (22, 19.5), (2, 19.5)]
    return [solid(body), hole(rect(4.2, 9.6, 19.8, 17.3))]


def icon_save():
    # a disk: clipped corner, label at the top, window at the bottom
    body = [(3, 3), (17.2, 3), (21, 6.8), (21, 21), (3, 21)]
    return [solid(body), hole(rect(6.2, 5.2, 15.2, 9.6)), hole(rect(6.2, 12.8, 17.8, 18.8))]


def icon_undo():
    # an arrow that swings over the top and points back down to the left
    cx, cy, r_out, r_in = 12.6, 15.2, 8.2, 5.7
    start, end = -8, 152
    outer = [polar(cx, cy, r_out, a) for a in range(start, end + 1, 4)]
    inner = [polar(cx, cy, r_in, a) for a in range(end, start - 1, -4)]
    band = outer + inner
    # the head sits on the left end of the band and follows its curve
    mid = polar(cx, cy, (r_out + r_in) / 2, end)
    a = math.radians(end)
    along = (-math.sin(a), -math.cos(a))          # the way the arrow is travelling
    across = (math.cos(a), -math.sin(a))
    half, length = 3.9, 5.2
    head = [(mid[0] + across[0] * half, mid[1] + across[1] * half),
            (mid[0] + along[0] * length, mid[1] + along[1] * length),
            (mid[0] - across[0] * half, mid[1] - across[1] * half)]
    return [solid(band), solid(head)]


def icon_redo():
    return [solid(o) for o in mirror(icon_undo())]


def icon_zoom_in():
    a, b, h = 4.5, 19.5, 1.25
    c = 12
    plus = [(c - h, a), (c + h, a), (c + h, c - h), (b, c - h), (b, c + h), (c + h, c + h),
            (c + h, b), (c - h, b), (c - h, c + h), (a, c + h), (a, c - h), (c - h, c - h)]
    return [solid(plus)]


def icon_zoom_out():
    return [solid(rect(4.5, 10.75, 19.5, 13.25))]


def icon_zoom_fit():
    # four corner brackets around the whole track
    t, arm, a, b = 2.3, 6.4, 3, 21

    def corner(x, y, sx, sy):
        return [(x, y), (x + sx * arm, y), (x + sx * arm, y + sy * t), (x + sx * t, y + sy * t),
                (x + sx * t, y + sy * arm), (x, y + sy * arm)]

    return [solid(corner(a, a, 1, 1)), solid(corner(b, a, -1, 1)),
            solid(corner(b, b, -1, -1)), solid(corner(a, b, 1, -1))]


def icon_graph():
    # a rising line over a base line
    line = stroke([(3, 15.8), (8.6, 9.4), (13.2, 12.9), (21, 4.2)], 2.3)
    base = rect(3, 18.6, 21, 20.4)
    return [solid(line), solid(base)]


def icon_info():
    ring = [solid(circle(12, 12, 9.6)), hole(circle(12, 12, 7.5))]
    dot = solid(circle(12, 7.9, 1.35, 24))
    stem = solid(rect(10.85, 10.6, 13.15, 17))
    return ring + [dot, stem]


def icon_settings():
    # a gear: eight teeth around a ring
    teeth, tip, root, bore = 8, 9.8, 7.3, 3.5
    outline = []
    for i in range(teeth):
        mid = 360 / teeth * i
        for r, off in ((root, -13.5), (tip, -8.5), (tip, 8.5), (root, 13.5)):
            outline.append(polar(12, 12, r, mid + off))
    return [solid(outline), hole(circle(12, 12, bore, 32))]


def icon_warn_close():
    # a cross: a plus sign turned 45 degrees
    h, reach = 1.2, 8.6
    plus = [(-h, -reach), (h, -reach), (h, -h), (reach, -h), (reach, h), (h, h),
            (h, reach), (-h, reach), (-h, h), (-reach, h), (-reach, -h), (-h, -h)]
    c = math.sqrt(0.5)
    return [solid([(12 + (x - y) * c, 12 + (x + y) * c) for x, y in plus])]


def icon_more():
    # the small arrow beside Open and Save: a triangle pointing down
    return [solid([(5, 9), (19, 9), (12, 16.5)])]


ICONS = {
    'pathOpen': icon_open,
    'pathSave': icon_save,
    'pathUndo': icon_undo,
    'pathRedo': icon_redo,
    'pathZoomIn': icon_zoom_in,
    'pathZoomOut': icon_zoom_out,
    'pathZoomFit': icon_zoom_fit,
    'pathGraph': icon_graph,
    'pathInfo': icon_info,
    'pathSettings': icon_settings,
    'pathWarnClose': icon_warn_close,
    'pathOpenMore': icon_more,
    'pathSaveMore': icon_more,
}


# ---- into the form --------------------------------------------------------------

def path_bytes(shape):
    """FMX path data: a count, then (kind, x, y) per point.
    kind 0 = move, 1 = line, 3 = close (it repeats the first point)."""
    recs = []
    for outline in shape:
        recs.append((0,) + tuple(outline[0]))
        for p in outline[1:]:
            recs.append((1,) + tuple(p))
        recs.append((3,) + tuple(outline[0]))
    out = struct.pack('<i', len(recs))
    for kind, x, y in recs:
        out += struct.pack('<iff', kind, round(x, 3), round(y, 3))
    return out


def main():
    text = FORM.read_bytes().decode('utf-8')
    for control, make in ICONS.items():
        pattern = re.compile(r'(object ' + control + r': TPath\r\n(?:.*\r\n)*?\s*Data\.Path = \{\r\n)'
                             r'((?:\s*[0-9A-F]+\}?\r\n)+)')
        m = pattern.search(text)
        if not m:
            raise SystemExit('Cannot find the path data of %s in %s' % (control, FORM.name))
        indent = re.match(r'\s*', m.group(2)).group(0)
        data = path_bytes(make()).hex().upper()
        lines = [indent + data[i:i + 64] for i in range(0, len(data), 64)]
        lines[-1] += '}'
        text = text[:m.start(2)] + '\r\n'.join(lines) + '\r\n' + text[m.end(2):]
    FORM.write_bytes(text.encode('utf-8'))
    print('put', len(ICONS), 'icons into', FORM)


if __name__ == '__main__':
    main()
