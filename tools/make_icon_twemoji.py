"""图标：左半橙底、竖直的半个吉他（Twemoji 剪影），右半黑底、竖向键盘。"""
import math
import re
import urllib.request
from PIL import Image, ImageDraw

import make_icon_svg as svg

S = 4
UNIT = 1024
W = UNIT * S
SPLIT = (UNIT // 2) * S
BG = (13, 13, 15)
WHITE = (250, 248, 244)
ACCENT = (240, 100, 45)

SVG_URL = "https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/svg/1f3b8.svg"


def centroid(points):
    return (sum(p[0] for p in points) / len(points),
            sum(p[1] for p in points) / len(points))


def load_shape():
    data = urllib.request.urlopen(SVG_URL, timeout=20).read().decode("utf-8")
    subs = []
    for d in re.findall(r'd="([^"]+)"', data):
        subs += svg.parse_subpaths(d)

    points = [p for s in subs for p in s]
    min_x = min(p[0] for p in points)
    max_x = max(p[0] for p in points)
    min_y = min(p[1] for p in points)
    max_y = max(p[1] for p in points)

    # 镜像：琴颈朝左上
    subs = [[((min_x + max_x) - x, y) for x, y in s] for s in subs]
    points = [p for s in subs for p in s]

    # 琴身质心（下半部）
    mid_y = (min(p[1] for p in points) + max(p[1] for p in points)) / 2
    body_pts = [p for p in points if p[1] > mid_y]
    bx, by = centroid(body_pts)

    # 最远点 = 琴头，旋转到正上方
    head = max(points, key=lambda p: (p[0] - bx) ** 2 + (p[1] - by) ** 2)
    angle = math.atan2(head[1] - by, head[0] - bx)
    rot = -math.pi / 2 - angle
    cos_r, sin_r = math.cos(rot), math.sin(rot)

    def turn(p):
        x, y = p[0] - bx, p[1] - by
        return (x * cos_r - y * sin_r, x * sin_r + y * cos_r)

    subs = [[turn(p) for p in s] for s in subs]
    points = [turn(p) for p in body_pts] + [turn(p) for p in points]
    ys = [p[1] for p in points]
    xs = [p[0] for p in points]
    height = max(ys) - min(ys)
    scale = 900 / height
    tx = UNIT / 2
    ty = 950 - max(ys) * scale

    def place(p):
        return (p[0] * scale + tx, p[1] * scale + ty)

    shape = [[place(p) for p in s] for s in subs]

    # 音孔：取面积最小的子路径质心
    def area(s):
        a = 0.0
        for i in range(len(s)):
            x1, y1 = s[i]
            x2, y2 = s[(i + 1) % len(s)]
            a += x1 * y2 - x2 * y1
        return abs(a / 2)

    hole_sub = min(subs, key=area)
    hx, hy = place(centroid(hole_sub))
    return shape, (hx, hy)


def main():
    shape, hole = load_shape()
    img = Image.new("RGB", (W, W), BG)
    d = ImageDraw.Draw(img)

    for x in range(SPLIT):
        t = x / SPLIT
        d.line([(x, 0), (x, W)], fill=(int(255 - 22 * t), int(140 - 58 * t), int(64 - 30 * t)))

    for sub in shape:
        d.polygon([(x * S, y * S) for x, y in sub], fill=WHITE)

    hx, hy = hole
    r = 44
    d.ellipse([(hx - r) * S, (hy - r) * S, (hx + r) * S, (hy + r) * S], fill=ACCENT)

    d.rectangle([SPLIT, 0, W, W], fill=BG)

    # 键盘：8 个白键（C 起），黑键只在 C-D / D-E / F-G / G-A / A-B 之间
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
    for i in [0, 1, 3, 4, 5]:
        x = 8 + wkw * (i + 1) - bkw / 2
        kd.rectangle([x, 8, x + bkw, 8 + bkh], fill=(18, 18, 20))

    kb = kb.rotate(90, expand=True).resize((512 * S, 1024 * S), Image.LANCZOS)
    img.paste(kb, (SPLIT, 0))

    img.resize((UNIT, UNIT), Image.LANCZOS).save("AppIcon.png")
    print("saved")


if __name__ == "__main__":
    main()
