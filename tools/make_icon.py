"""图标：左半橙底半个吉他，右半黑底竖向钢琴键。"""
from PIL import Image, ImageDraw

S = 4
W = 1024 * S
SPLIT = W // 2

img = Image.new("RGB", (W, W), (13, 13, 15))
d = ImageDraw.Draw(img)

# 左半橙色渐变
for x in range(SPLIT):
    t = x / SPLIT
    d.line([(x, 0), (x, W)], fill=(int(255 - 25 * t), int(138 - 62 * t), int(58 - 30 * t)))

WHITE = (250, 248, 244)
ACCENT = (240, 100, 45)
DARK = (13, 13, 15)


def box(values):
    return [v * S for v in values]


def pts(values):
    return [(x * S, y * S) for x, y in values]


# 吉他（画全，右半随后被黑底盖掉，形成"半个吉他"）
d.ellipse(box([250, 620, 780, 940]), fill=WHITE)
d.ellipse(box([290, 480, 820, 760]), fill=WHITE)
d.polygon(pts([(500, 560), (430, 512), (196, 262), (262, 206)]), fill=WHITE)
d.polygon(pts([(222, 286), (160, 214), (100, 258), (164, 330)]), fill=WHITE)
d.ellipse(box([360, 660, 470, 770]), fill=ACCENT)
for i in range(4):
    off = i * 18
    d.line(pts([(470 - off, 555 - off * 0.4), (210 + off, 268 + off * 0.6)]),
           fill=ACCENT, width=int(5 * S))

# 右半黑底（覆盖吉他右半边）
d.rectangle([SPLIT, 0, W, W], fill=DARK)

# 右半：竖向钢琴键
margin = 24 * S
kx0, ky0, kx1, ky1 = SPLIT + margin, margin, W - margin, W - margin
d.rounded_rectangle([kx0, ky0, kx1, ky1], radius=14 * S, fill=WHITE)

keys = 7
kw = (kx1 - kx0) / keys
for i in range(1, keys):
    x = kx0 + kw * i
    d.line([(x, ky0), (x, ky1)], fill=(30, 30, 32), width=int(5 * S))

bw = kw * 0.6
bh = (ky1 - ky0) * 0.42
for i in [0, 1, 3, 4, 5]:
    x = kx0 + kw * (i + 1) - bw / 2
    d.rectangle([x, ky0, x + bw, ky0 + bh], fill=(18, 18, 20))

img.resize((1024, 1024), Image.LANCZOS).save("AppIcon.png")
print("saved")
