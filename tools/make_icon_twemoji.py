"""图标：左半橙底、半个吉他（Twemoji 剪影，CC-BY 4.0），右半黑底、逆时针旋转 90° 的键盘。"""
import re
import urllib.request
from PIL import Image, ImageDraw

import make_icon_svg as svg  # 复用路径解析

S = 4
UNIT = 1024
W = UNIT * S
SPLIT = (UNIT // 2) * S
BG = (13, 13, 15)
WHITE = (250, 248, 244)
ACCENT = (240, 100, 45)

SVG_URL = "https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/svg/1f3b8.svg"


def load_shape():
    data = urllib.request.urlopen(SVG_URL, timeout=20).read().decode("utf-8")
    subpaths = []
    for d in re.findall(r'd="([^"]+)"', data):
        subpaths += svg.parse_subpaths(d)

    points = [p for s in subpaths for p in s]
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    min_x, max_x = min(xs), max(xs)
    min_y, max_y = min(ys), max(ys)

    # 镜像：琴颈朝左上
    mirrored = [[(max_x - x + min_x, y) for x, y in s] for s in subpaths]
    points = [p for s in mirrored for p in s]
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    min_x, max_x = min(xs), max(xs)
    min_y, max_y = min(ys), max(ys)

    # 琴身中心（下半部分的质心）
    mid_y = (min_y + max_y) / 2
    body = [(x, y) for x, y in points if y > mid_y]
    body_cx = sum(p[0] for p in body) / len(body)
    body_cy = sum(p[1] for p in body) / len(body)

    anchor_y = max_y
    scale = 820 / (max_y - min_y)
    tx = UNIT / 2 - body_cx * scale + 26
    ty = 940 - anchor_y * scale
    shape = [[(x * scale + tx, y * scale + ty) for x, y in s] for s in mirrored]
    hole = (UNIT / 2 - 78, body_cy * scale + ty + 40)
    return shape, hole


def main():
    shape, hole = load_shape()
    img = Image.new("RGB", (W, W), BG)
    d = ImageDraw.Draw(img)

    for x in range(SPLIT):
        t = x / SPLIT
        d.line([(x, 0), (x, W)], fill=(int(255 - 22 * t), int(140 - 58 * t), int(64 - 30 * t)))

    for sub in shape:
        d.polygon([(x * S, y * S) for x, y in sub], fill=WHITE)

    # 音孔
    hx, hy = hole
    r = 46
    d.ellipse([(hx - r) * S, (hy - r) * S, (hx + r) * S, (hy + r) * S], fill=ACCENT)

    # 右半黑底（切掉吉他右半）
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
    print("saved")


if __name__ == "__main__":
    main()
