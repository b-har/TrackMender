# Saves the graphics that live inside the forms as ordinary files.
#
#   python export_graphics.py
#
# Toolbar icons: the Delphi main form (D12/uMain.fmx) holds each one as path
# data.  Every icon is written to resources/toolbar as an .svg (the exact
# shape) and a .png (a 96 x 96 picture of it).
#
# About box pictures: the map and Frankie are stored inside both About forms.
# They are compared with the files in resources/; a picture that has no
# matching file there is saved next to them.
#
# Needs Pillow.
import io
import re
import struct
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

RES = Path(__file__).resolve().parent.parent
ROOT = RES.parent
TOOLBAR = RES / 'toolbar'
PNG_SIZE = 96


def objects(text, class_name):
    """(name, body) of every object of one class in a form file."""
    out = []
    pattern = re.compile(r'^( *)object (\w+): ' + class_name + r'\r?\n', re.M)
    for m in pattern.finditer(text):
        indent = m.group(1)
        end = re.compile(r'^' + indent + r'end\r?$', re.M).search(text, m.end())
        out.append((m.group(2), text[m.end():end.start()]))
    return out


def hex_block(body, key):
    """The bytes of a  key = { hex ... }  property, None when it is not there."""
    m = re.search(re.escape(key) + r' = \{([0-9A-Fa-f\s]*)\}', body)
    return bytes.fromhex(re.sub(r'\s', '', m.group(1))) if m else None


# ---- toolbar icons ------------------------------------------------------------

def path_commands(data):
    """FMX path data: a count, then (kind, x, y) per point.
    kind 0 = move, 1 = line, 2 = curve (three points make one curve), 3 = close."""
    count = struct.unpack_from('<i', data, 0)[0]
    pts = [struct.unpack_from('<iff', data, 4 + 12 * i) for i in range(count)]
    cmds, i = [], 0
    while i < count:
        kind, x, y = pts[i]
        if kind == 0:
            cmds.append(('M', [(x, y)]))
        elif kind == 1:
            cmds.append(('L', [(x, y)]))
        elif kind == 2:
            cmds.append(('C', [(p[1], p[2]) for p in pts[i:i + 3]]))
            i += 2
        else:
            cmds.append(('Z', []))
        i += 1
    return cmds


def number(v):
    return ('%.3f' % v).rstrip('0').rstrip('.')


def outlines(cmds):
    """The shape as closed outlines of straight pieces (curves cut into 16)."""
    shapes, cur, last = [], [], (0.0, 0.0)
    for op, p in cmds:
        if op == 'M':
            if len(cur) > 2:
                shapes.append(cur)
            cur = [p[0]]
            last = p[0]
        elif op == 'L':
            cur.append(p[0])
            last = p[0]
        elif op == 'C':
            (x1, y1), (x2, y2), (x3, y3) = p
            x0, y0 = last
            for s in range(1, 17):
                t = s / 16
                a, b, c, d = (1 - t) ** 3, 3 * (1 - t) ** 2 * t, 3 * (1 - t) * t * t, t ** 3
                cur.append((a * x0 + b * x1 + c * x2 + d * x3, a * y0 + b * y1 + c * y2 + d * y3))
            last = p[2]
        else:
            if len(cur) > 2:
                shapes.append(cur)
            cur = []
    if len(cur) > 2:
        shapes.append(cur)
    return shapes


def file_name(control):
    """pathZoomIn -> zoom-in"""
    words = re.findall(r'[A-Z][a-z0-9]*', control[len('path'):])
    return '-'.join(w.lower() for w in words)


def export_toolbar():
    text = (ROOT / 'D12' / 'uMain.fmx').read_text(encoding='utf-8')
    TOOLBAR.mkdir(exist_ok=True)
    names = []
    for control, body in objects(text, 'TPath'):
        data = hex_block(body, 'Data.Path')
        if not data:
            continue
        cmds = path_commands(data)
        m = re.search(r'Fill\.Color = x([0-9A-Fa-f]{8})', body)
        color = '#' + (m.group(1)[2:] if m else '000000')
        shapes = outlines(cmds)
        xs = [x for s in shapes for x, _ in s]
        ys = [y for s in shapes for _, y in s]
        x0, y0, x1, y1 = min(xs), min(ys), max(xs), max(ys)
        name = file_name(control)

        d = ' '.join(op + ' '.join(number(x) + ',' + number(y) for x, y in p) for op, p in cmds)
        svg = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="%s %s %s %s">\n'
               '  <path fill="%s" fill-rule="evenodd" d="%s"/>\n</svg>\n'
               % (number(x0), number(y0), number(x1 - x0), number(y1 - y0), color, d))
        (TOOLBAR / (name + '.svg')).write_text(svg, encoding='utf-8', newline='\n')

        # the picture: drawn large and scaled down; overlapping outlines cut holes
        z = 4
        big = PNG_SIZE * z
        scale = big * 0.8 / max(x1 - x0, y1 - y0)
        ox = (big - (x1 - x0) * scale) / 2 - x0 * scale
        oy = (big - (y1 - y0) * scale) / 2 - y0 * scale
        mask = Image.new('L', (big, big), 0)
        for s in shapes:
            one = Image.new('L', (big, big), 0)
            ImageDraw.Draw(one).polygon([(x * scale + ox, y * scale + oy) for x, y in s], fill=255)
            mask = ImageChops.difference(mask, one)
        rgb = tuple(int(color[i:i + 2], 16) for i in (1, 3, 5))
        png = Image.new('RGBA', (big, big), rgb + (0,))
        png.putalpha(mask)
        png.resize((PNG_SIZE, PNG_SIZE), Image.LANCZOS).save(TOOLBAR / (name + '.png'))
        names.append(name)
    print('toolbar icons:', ', '.join(names))


# ---- About box pictures ---------------------------------------------------------

def form_images(form):
    """(control, PNG bytes) for every picture stored in a form file."""
    text = form.read_text(encoding='utf-8')
    out = []
    for control, body in objects(text, 'TImage'):
        data = hex_block(body, 'PNG') or hex_block(body, 'Picture.Data')
        if not data:
            continue
        start = data.find(b'\x89PNG')
        if start >= 0:
            out.append((control, data[start:]))
    return out


def same_picture(a, b):
    if a.size != b.size:
        return False
    a, b = a.convert('RGBA'), b.convert('RGBA')
    return ImageChops.difference(a, b).getbbox() is None


def check_about():
    files = {p: Image.open(p) for p in RES.glob('*.png')}
    for form in (ROOT / 'D12' / 'uAbout.fmx', ROOT / 'LAZ' / 'uAbout.lfm'):
        for control, data in form_images(form):
            img = Image.open(io.BytesIO(data))
            match = [p.name for p, f in files.items() if same_picture(img, f)]
            where = '%s %s (%d x %d)' % (form.name, control, img.width, img.height)
            if match:
                print(where, '= resources/' + match[0])
            else:
                target = RES / ('about-%s.png' % control.lower())
                target.write_bytes(data)
                files[target] = Image.open(target)
                print(where, 'had no file in resources: saved as', target.name)


if __name__ == '__main__':
    export_toolbar()
    check_about()
