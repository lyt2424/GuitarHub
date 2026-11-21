"""图标：左半橙底半个吉他，右半黑底竖向钢琴键（键盘逆时针旋转 90°）。"""
import math
from PIL import Image, ImageDraw

S = 4
W = 1024 * S
CX = 512            # 中线（1024 坐标）
SPLIT = 512 * S
UNIT = 1024

img = Image.new("RGB", (W, W), (13, 13, 15))
d = ImageDraw.Draw(img)

for x in range(SPLIT):
    t = x / SPLIT
    d.line([(x, 0), (x, W)], fill=(int(255 - 22 * t), int(140 - 58 * t), int(64 - 30 * t)))

WHITE = (250, 248, 244)
ACCENT = (240, 100, 45)
DARK = (13, 13, 15)


def sp(p):
    return (p[0] * S, p[1] * S)


def sb(v):
    return [n * S for n in v]


def spoly(points):
    return [sp(p) for p in points]


def half_width(t):
    return (98
            + 62 * math.exp(-((t - 0.16) / 0.14) ** 2)
            + 78 * math.exp(-((t - 0.80) / 0.19) ** 2)
            - 30 * math.exp(-((t - 0.50) / 0.11) ** 2))


top, bottom = 360, 930
left, right = [], []
steps = 120
for i in range(steps + 1):
    t = i / steps
    y = top + (bottom - top) * t
    left.append((CX - half_width(t), y))
for i in range(steps, -1, -1):
    t = i / steps
    y = top + (bottom - top) * t
    right.append((CX + half_width(t), y))
d.polygon(spoly(left + right), fill=WHITE)

# 音孔
d.ellipse(sb([CX - 62, 640, CX + 38, 740]), fill=ACCENT)
# 琴桥（左半）
d.rounded_rectangle(sb([CX - 118, 798, CX + 20, 834]), radius=8 * S, fill=ACCENT)

# 琴颈（左上）
ns = (CX - 22, 430)
ne = (CX - 292, 140)
dx, dy = ne[0] - ns[0], ne[1] - ns[1]
length = math.hypot(dx, dy)
ux, uy = dx / length, dy / length
px, py = -uy, ux
half = 27
d.polygon(spoly([
    (ns[0] + px * half, ns[1] + py * half),
    (ns[0] - px * half, ns[1] - py * half),
    (ne[0] - px * half, ne[1] - py * half),
    (ne[0] + px * half, ne[1] + py * half),
]), fill=WHITE)

# 琴头
head_len, head_half = 92, 48
hx, hy = ne[0] + ux * head_len, ne[1] + uy * head_len
d.polygon(spoly([
    (ne[0] + px * head_half, ne[1] + py * head_half),
    (ne[0] - px * head_half, ne[1] - py * head_half),
    (hx - px * head_half, hy - py * head_half),
    (hx + px * head_half, hy + py * head_half),
]), fill=WHITE)

# 品丝
for i in range(1, 7):
    t = i / 7
    fx, fy = ns[0] + dx * t, ns[1] + dy * t
    d.line(spoly([(fx + px * half, fy + py * half), (fx - px * half, fy - py * half)]),
           fill=(228, 228, 228), width=int(2.6 * S))

# 六根弦
for i in range(6):
    off = (i - 2.5) * 6
    d.line(spoly([
        (CX - 48 + off, 798),
        (ne[0] + px * off * 1.3, ne[1] + py * off * 1.3),
    ]), fill=ACCENT, width=int(2.2 * S))

# 右半黑底
d.rectangle([SPLIT, 0, W, W], fill=DARK)

# 键盘：横向画好，逆时针旋转 90°，铺满右半
kw, kh = 1024, 512
kb = Image.new("RGB", (kw, kh), DARK)
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

kb = kb.rotate(90, expand=True)
kb = kb.resize((512 * S, 1024 * S), Image.LANCZOS)
img.paste(kb, (SPLIT, 0))

img.resize((UNIT, UNIT), Image.LANCZOS).save("AppIcon.png")
print("saved")
