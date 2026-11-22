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

    # 用琴颈区域的重心确定方向，保证琴颈竖直
    min_y_all = min(p[1] for p in points)
    max_y_all = max(p[1] for p in points)
    neck_pts = [p for p in points if p[1] <= min_y_all + (max_y_all - min_y_all) * 0.35]
    nx, ny = centroid(neck_pts)
    angle = math.atan2(ny - by, nx - bx)
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
    shape, _ = load_shape()

    # 橙底（左上亮、右下深）
    img = Image.new("RGB", (W, W), ACCENT)
    d = ImageDraw.Draw(img)
    for y in range(W):
        t = y / W
        d.line([(0, y), (W, y)], fill=(int(255 - 30 * t), int(150 - 70 * t), int(72 - 38 * t)))

    # 白色剪影：只保留轮廓，不画音孔/琴弦等细节
    fg = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    fd = ImageDraw.Draw(fg)
    for sub in shape:
        fd.polygon([(x * S, y * S) for x, y in sub], fill=WHITE + (255,))

    # 仿 GarageBand 的斜向构图：琴颈朝左上
    fg = fg.rotate(45, expand=True, resample=Image.BICUBIC)
    fg = fg.crop(fg.getbbox())
    fg.thumbnail((int(W * 0.9), int(W * 0.9)), Image.LANCZOS)

    canvas = img.convert("RGBA")
    canvas.alpha_composite(fg, ((W - fg.width) // 2, (W - fg.height) // 2))
    canvas.convert("RGB").resize((UNIT, UNIT), Image.LANCZOS).save("AppIcon.png")
    print("saved")


if __name__ == "__main__":
    main()
