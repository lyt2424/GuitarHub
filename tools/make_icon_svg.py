"""用开源吉他矢量图（Font Awesome Free, CC BY 4.0）做半个吉他剪影，
右侧放逆时针旋转 90° 的钢琴键盘。

不复制任何商业 App 的图标；吉他路径来自 @fortawesome/fontawesome-free。
"""
import math
import re
import urllib.request
from PIL import Image, ImageDraw

S = 4
UNIT = 1024
W = UNIT * S
SPLIT = (UNIT // 2) * S
BG = (13, 13, 15)
WHITE = (250, 248, 244)
ACCENT = (240, 100, 45)

SVG_URL = ("https://cdn.jsdelivr.net/npm/@fortawesome/fontawesome-free@6.5.2/"
           "svgs/solid/guitar.svg")


def load_path():
    data = urllib.request.urlopen(SVG_URL, timeout=20).read().decode("utf-8")
    m = re.search(r'd="([^"]+)"', data)
    if not m:
        raise RuntimeError("no path")
    return m.group(1)


NUM = re.compile(r"[MmLlHhVvCcSsQqTtAaZz]|-?\d*\.?\d+(?:[eE][-+]?\d+)?")


def tokenize(d):
    return NUM.findall(d)


def cubic(p0, p1, p2, p3, steps=14):
    out = []
    for i in range(1, steps + 1):
        t = i / steps
        mt = 1 - t
        x = mt**3*p0[0] + 3*mt*mt*t*p1[0] + 3*mt*t*t*p2[0] + t**3*p3[0]
        y = mt**3*p0[1] + 3*mt*mt*t*p1[1] + 3*mt*t*t*p2[1] + t**3*p3[1]
        out.append((x, y))
    return out


def quad(p0, p1, p2, steps=14):
    out = []
    for i in range(1, steps + 1):
        t = i / steps
        mt = 1 - t
        out.append((mt*mt*p0[0] + 2*mt*t*p1[0] + t*t*p2[0],
                    mt*mt*p0[1] + 2*mt*t*p1[1] + t*t*p2[1]))
    return out


def arc_to(p0, rx, ry, phi, large, sweep, p1, steps=18):
    """SVG 端点式圆弧 -> 折线（足够画图标）。"""
    x1, y1 = p0
    x2, y2 = p1
    if rx == 0 or ry == 0:
        return [p1]
    phi = math.radians(phi)
    dx, dy = (x1 - x2) / 2, (y1 - y2) / 2
    x1p = math.cos(phi) * dx + math.sin(phi) * dy
    y1p = -math.sin(phi) * dx + math.cos(phi) * dy
    lam = (x1p**2) / (rx**2) + (y1p**2) / (ry**2)
    if lam > 1:
        rx *= math.sqrt(lam)
        ry *= math.sqrt(lam)
    num = rx*rx*ry*ry - rx*rx*y1p*y1p - ry*ry*x1p*x1p
    den = rx*rx*y1p*y1p + ry*ry*x1p*x1p
    coef = math.sqrt(max(0.0, num / den)) if den else 0.0
    if large == sweep:
        coef = -coef
    cxp = coef * rx * y1p / ry
    cyp = -coef * ry * x1p / rx
    cx = math.cos(phi) * cxp - math.sin(phi) * cyp + (x1 + x2) / 2
    cy = math.sin(phi) * cxp + math.cos(phi) * cyp + (y1 + y2) / 2

    def angle(ux, uy, vx, vy):
        dot = ux*vx + uy*vy
        length = math.hypot(ux, uy) * math.hypot(vx, vy)
        a = math.acos(max(-1.0, min(1.0, dot / length))) if length else 0.0
        return -a if ux*vy - uy*vx < 0 else a

    theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
    dtheta = angle((x1p - cxp) / rx, (y1p - cyp) / ry,
                   (-x1p - cxp) / rx, (-y1p - cyp) / ry)
    if not sweep and dtheta > 0:
        dtheta -= 2 * math.pi
    elif sweep and dtheta < 0:
        dtheta += 2 * math.pi

    out = []
    for i in range(1, steps + 1):
        t = theta1 + dtheta * i / steps
        x = cx + rx * math.cos(t) * math.cos(phi) - ry * math.sin(t) * math.sin(phi)
        y = cy + rx * math.cos(t) * math.sin(phi) + ry * math.sin(t) * math.cos(phi)
        out.append((x, y))
    return out


def parse_subpaths(d):
    tokens = tokenize(d)
    subpaths = []
    cur = []
    i = 0
    cmd = None
    x = y = 0.0
    sx = sy = 0.0
    last_c = None
    while i < len(tokens):
        t = tokens[i]
        if re.match(r"[A-Za-z]", t):
            cmd = t
            i += 1
            if cmd in "Zz":
                if cur:
                    cur.append((sx, sy))
                    subpaths.append(cur)
                    cur = []
                x, y = sx, sy
                continue
        rel = cmd.islower()
        c = cmd.upper()

        def take(n):
            nonlocal i
            vals = [float(v) for v in tokens[i:i+n]]
            i += n
            return vals

        if c == "M":
            nx, ny = take(2)
            if rel:
                nx += x
                ny += y
            if cur:
                subpaths.append(cur)
            cur = [(nx, ny)]
            x, y = nx, ny
            sx, sy = nx, ny
            cmd = "l" if rel else "L"
        elif c == "L":
            nx, ny = take(2)
            if rel:
                nx += x
                ny += y
            cur.append((nx, ny))
            x, y = nx, ny
        elif c == "H":
            nx = take(1)[0] + (x if rel else 0)
            cur.append((nx, y))
            x = nx
        elif c == "V":
            ny = take(1)[0] + (y if rel else 0)
            cur.append((x, ny))
            y = ny
        elif c == "C":
            x1, y1, x2, y2, nx, ny = take(6)
            if rel:
                x1 += x; y1 += y; x2 += x; y2 += y; nx += x; ny += y
            cur.extend(cubic((x, y), (x1, y1), (x2, y2), (nx, ny)))
            last_c = (x2, y2)
            x, y = nx, ny
        elif c == "S":
            x2, y2, nx, ny = take(4)
            if rel:
                x2 += x; y2 += y; nx += x; ny += y
            if last_c:
                x1, y1 = 2*x - last_c[0], 2*y - last_c[1]
            else:
                x1, y1 = x, y
            cur.extend(cubic((x, y), (x1, y1), (x2, y2), (nx, ny)))
            last_c = (x2, y2)
            x, y = nx, ny
        elif c == "Q":
            x1, y1, nx, ny = take(4)
            if rel:
                x1 += x; y1 += y; nx += x; ny += y
            cur.extend(quad((x, y), (x1, y1), (nx, ny)))
            last_c = (x1, y1)
            x, y = nx, ny
        elif c == "T":
            nx, ny = take(2)
            if rel:
                nx += x; ny += y
            x1, y1 = (2*x - last_c[0], 2*y - last_c[1]) if last_c else (x, y)
            cur.extend(quad((x, y), (x1, y1), (nx, ny)))
            last_c = (x1, y1)
            x, y = nx, ny
        elif c == "A":
            rx, ry, phi, large, sweep, nx, ny = take(7)
            if rel:
                nx += x; ny += y
            cur.extend(arc_to((x, y), rx, ry, phi, int(large), int(sweep), (nx, ny)))
            x, y = nx, ny
        else:
            i += 1

    if cur:
        subpaths.append(cur)
    return subpaths


def main():
    path = load_path()
    subs = parse_subpaths(path)
    body = max(subs, key=lambda p: abs(_area(p)))  # 面积最大的子路径 = 琴身+琴颈

    # 镜像（琴颈朝左上），再缩放、平移
    mirrored = [(UNIT - x, y) for x, y in body]
    xs = [p[0] for p in mirrored]
    ys = [p[1] for p in mirrored]
    bw, bh = max(xs) - min(xs), max(ys) - min(ys)
    scale = 780 / bh
    tx = UNIT / 2 - (min(xs) + max(xs)) / 2 * scale
    ty = 940 - max(ys) * scale
    shape = [(x * scale + tx, y * scale + ty) for x, y in mirrored]

    img = Image.new("RGB", (W, W), BG)
    d = ImageDraw.Draw(img)

    for x in range(SPLIT):
        t = x / SPLIT
        d.line([(x, 0), (x, W)], fill=(int(255 - 22 * t), int(140 - 58 * t), int(64 - 30 * t)))

    d.polygon([(x * S, y * S) for x, y in shape], fill=WHITE)

    # 音孔：取次大的圆形子路径中心
    holes = [p for p in subs if p is not body]
    if holes:
        hx = sum(p[0] for p in holes[0]) / len(holes[0])
        hy = sum(p[1] for p in holes[0]) / len(holes[0])
        mx, my = UNIT - hx, hy
        px, py = mx * scale + tx, my * scale + ty
        r = 52
        d.ellipse([(px - r) * S, (py - r) * S, (px + r) * S, (py + r) * S], fill=ACCENT)

    # 右半黑底
    d.rectangle([SPLIT, 0, W, W], fill=BG)

    # 键盘：水平画好，逆时针旋转 90°，铺满右半
    kw, kh = 1024, 512
    kb = Image.new("RGB", (kw, kh), BG)
    kd = ImageDraw.Draw(kb)
    kd.rounded_rectangle([8, 8, kw - 8, kh - 8], radius=16, fill=WHITE)
    keys = 8
    wkw = (kw - 16) / keys
    for i in range(1, keys):
        x = 8 + wkw * i
        kd.line([(x, 8), (x, kh - 8)], fill=(28, 28, 30), width=6)
    bkw = wkw * 0.6
    bkh = (kh - 16) * 0.58
    for i in [0, 1, 3, 4, 5, 6]:
        x = 8 + wkw * (i + 1) - bkw / 2
        kd.rectangle([x, 8, x + bkw, 8 + bkh], fill=(18, 18, 20))

    kb = kb.rotate(90, expand=True).resize((512 * S, 1024 * S), Image.LANCZOS)
    img.paste(kb, (SPLIT, 0))

    img.resize((UNIT, UNIT), Image.LANCZOS).save("AppIcon.png")
    print("saved", len(shape), "points")


def _area(points):
    a = 0.0
    for i in range(len(points)):
        x1, y1 = points[i]
        x2, y2 = points[(i + 1) % len(points)]
        a += x1 * y2 - x2 * y1
    return a / 2


if __name__ == "__main__":
    main()
