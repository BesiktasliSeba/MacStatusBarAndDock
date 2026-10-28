# Draws our Settings icons (29 pt) as vector shapes at 24x supersampling and writes @2x / @3x PNGs.
# Usage: python3 tools/settings-icons.py <repo root>
import sys, os
import numpy as np
from PIL import Image, ImageDraw, ImageFont

SS = 24                                   # supersampling per output pixel
PT = 29.0                                 # icon size in points

def hexc(h, a=255):
    h = h.lstrip('#'); return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)

class Canvas:
    def __init__(self, px):
        self.n = px * SS
        self.k = self.n / PT              # canvas pixels per point
        self.im = Image.new('RGBA', (self.n, self.n), (0, 0, 0, 0))
    def p(self, v): return v * self.k
    def box(self, x0, y0, x1, y1): return [self.p(x0), self.p(y0), self.p(x1) - 1, self.p(y1) - 1]
    def layer(self): return Image.new('RGBA', (self.n, self.n), (0, 0, 0, 0))
    def over(self, lay): self.im = Image.alpha_composite(self.im, lay)
    def rrect(self, x0, y0, x1, y1, r, fill):
        lay = self.layer(); ImageDraw.Draw(lay).rounded_rectangle(self.box(x0, y0, x1, y1), radius=self.p(r), fill=fill); self.over(lay)
    def rrect_top(self, x0, y0, x1, y1, r, fill):   # rounded at the top corners only (a title bar)
        lay = self.layer(); ImageDraw.Draw(lay).rounded_rectangle(self.box(x0, y0, x1, y1), radius=self.p(r), fill=fill, corners=(True, True, False, False)); self.over(lay)
    def ellipse(self, cx, cy, r, fill):
        lay = self.layer(); ImageDraw.Draw(lay).ellipse(self.box(cx - r, cy - r, cx + r, cy + r), fill=fill); self.over(lay)
    def font(self, size, weight):
        f = ImageFont.truetype('/System/Library/Fonts/SFNS.ttf', max(1, int(round(self.p(size)))))
        f.set_variation_by_axes([100, 17, 400, weight])   # width, optical size (small text), grade, weight
        return f
    def text(self, x, baseline, s, size, weight, fill):   # x and the baseline in points; returns the advance in points
        f = self.font(size, weight); lay = self.layer()
        ImageDraw.Draw(lay).text((self.p(x), self.p(baseline)), s, font=f, fill=fill, anchor='ls'); self.over(lay)
        return f.getlength(s) / self.k
    def wedge(self, cx, cy, r, a0, a1, fill):            # a pie slice (angles in degrees, 0 = right, clockwise)
        lay = self.layer(); ImageDraw.Draw(lay).pieslice(self.box(cx - r, cy - r, cx + r, cy + r), a0, a1, fill=fill); self.over(lay)
    def out(self, px): return self.im.resize((px, px), Image.BOX)

def squircle_mask(n):
    # Apple-like continuous corners: a superellipse (n = 5) filling the square
    t = (np.arange(n) + 0.5) / n * 2 - 1
    x, y = np.meshgrid(t, t)
    return Image.fromarray(((np.abs(x) ** 5 + np.abs(y) ** 5) <= 1).astype(np.uint8) * 255, 'L')

def gradient(n, top, bottom, split=None):
    # vertical gradient; split = (y in points, colour above it) for a flat band at the top
    ys = (np.arange(n) + 0.5) / n
    t, b = np.array(top[:3], float), np.array(bottom[:3], float)
    rows = t[None, :] + (b - t)[None, :] * ys[:, None]
    if split:
        y, c = split
        cut = ys < y / PT
        rows[cut] = np.array(c[:3], float)
        lo = ys[~cut]; lo = (lo - y / PT) / (1 - y / PT)
        rows[~cut] = t[None, :] + (b - t)[None, :] * lo[:, None]
    img = np.repeat(rows[:, None, :], n, axis=1).astype(np.uint8)
    return Image.fromarray(np.dstack([img, np.full((n, n), 255, np.uint8)]), 'RGBA')

def base(c, top, bottom, split=None):
    bg = gradient(c.n, top, bottom, split)
    c.im.paste(bg, (0, 0), squircle_mask(c.n))

def status_bar(px):
    c = Canvas(px)
    BAR = 8.0
    base(c, hexc('#626E8E'), hexc('#323A52'), split=(BAR, hexc('#E2E5EE')))
    ink = hexc('#1F2230'); base_y = 5.55
    x = 3.1
    x += c.text(x, base_y + 0.1, '\uf8ff', 3.5, 500, ink) + 0.9        # the Apple menu
    c.text(x, base_y, 'Finder', 2.75, 700, ink)                          # the app's menu
    # the status items on the right: Wi-Fi, then the battery
    bx1, by = 25.9, 4.2
    c.rrect(bx1 - 4.0, by - 1.15, bx1, by + 1.15, 0.6, ink)                # battery outline
    c.rrect(bx1 - 3.6, by - 0.75, bx1 - 0.4, by + 0.75, 0.3, hexc('#E2E5EE'))
    c.rrect(bx1 - 3.3, by - 0.45, bx1 - 1.2, by + 0.45, 0.2, ink)      # charge
    c.rrect(bx1 + 0.2, by - 0.45, bx1 + 0.65, by + 0.45, 0.2, ink)       # nub
    wx, wy = 19.6, 5.65                                                   # Wi-Fi: three rings and a dot
    for r in (2.4, 1.6, 0.85):
        c.wedge(wx, wy, r, 225, 315, ink)
        c.wedge(wx, wy, r - 0.42, 225, 315, hexc('#E2E5EE'))
    c.wedge(wx, wy, 0.45, 225, 315, ink)
    c.rrect(5.5, 11.0, 23.5, 24.3, 2.0, hexc('#A9B1C8', 120))           # a window
    c.rrect_top(5.5, 11.0, 23.5, 14.1, 2.0, hexc('#C9CEDD', 150))
    for i, col in enumerate(('#FF5F57', '#FEBC2E', '#28C840')):
        c.ellipse(7.7 + i * 2.1, 12.55, 0.8, hexc(col))
    return c.out(px)

def dock(px):
    c = Canvas(px)
    base(c, hexc('#5BC6FB'), hexc('#1D6FEF'))
    c.rrect(1.9, 14.6, 27.1, 21.6, 2.8, hexc('#FFFFFF', 95))       # the shelf
    sizes = (3.3, 4.3, 5.8, 4.3, 3.3); gap = 0.6
    x = 14.5 - (sum(sizes) + gap * (len(sizes) - 1)) / 2
    for s in sizes:                                                 # magnified icons, bottoms on one line
        c.rrect(x, 20.6 - s, x + s, 20.6, s * 0.24, hexc('#FFFFFF'))
        x += s + gap
    c.ellipse(14.5, 22.7, 0.5, hexc('#FFFFFF', 230))                # running dot under the middle app
    return c.out(px)

def ram_cpu(px):
    c = Canvas(px)
    base(c, hexc('#4FD868'), hexc('#25AE46'))
    w = hexc('#FFFFFF')
    for v in (11.6, 14.5, 17.4):                                    # pins
        c.rrect(v - 0.6, 5.6, v + 0.6, 9.6, 0.4, w); c.rrect(v - 0.6, 19.4, v + 0.6, 23.4, 0.4, w)
        c.rrect(5.6, v - 0.6, 9.6, v + 0.6, 0.4, w); c.rrect(19.4, v - 0.6, 23.4, v + 0.6, 0.4, w)
    c.rrect(8.4, 8.4, 20.6, 20.6, 2.0, w)                           # the chip, outlined
    c.rrect(9.8, 9.8, 19.2, 19.2, 1.1, hexc('#2FBE52'))
    c.rrect(11.6, 11.6, 17.4, 17.4, 0.9, w)                         # its die
    return c.out(px)

def windows(px):
    c = Canvas(px)
    base(c, hexc('#8E8BFF'), hexc('#5450D4'))
    c.rrect(4.2, 5.8, 19.2, 17.6, 1.8, hexc('#FFFFFF', 120))        # the window behind
    c.rrect(9.8, 11.2, 24.8, 23.4, 1.8, hexc('#FFFFFF'))            # the window in front
    c.rrect_top(9.8, 11.2, 24.8, 14.0, 1.8, hexc('#E4E4F2'))
    for i, col in enumerate(('#FF5F57', '#FEBC2E', '#28C840')):
        c.ellipse(12.0 + i * 2.1, 12.6, 0.8, hexc(col))
    return c.out(px)

ICONS = {
    'statusbar/macstatusbarprefs/Resources/icon': status_bar,
    'dock/dockmagnificationprefs/Resources/icon': dock,
    'ccmodule/Resources/SettingsIcon': ram_cpu,
    'statusbar/macstatusbarprefs/Resources/windows': windows,   # the Windows & Multitasking page (its row's icon, from the Status Bar page's bundle)
}

root = sys.argv[1]
for path, fn in ICONS.items():
    os.makedirs(os.path.dirname(os.path.join(root, path)), exist_ok=True)
    for scale in (2, 3):
        fn(int(PT * scale)).save(os.path.join(root, f'{path}@{scale}x.png'), optimize=True)
print('ok')
