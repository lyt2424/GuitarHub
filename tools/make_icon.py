"""生成 App 图标：左橙右黑，白色吉他 + 钢琴键（原创，不复制任何厂商商标）。"""
from PIL import Image, ImageDraw

S = 4                 # 超采样倍数
W = 1024 * S

img = Image.new("RGB", (W, W), (10, 10, 12))
d = ImageDraw.Draw(img)

left_w = int(W * 0.56)
for x in range(left_w):
    t = x / left_w
    d.line([(x, 0), (x, W)], fill=(int(255 - 20 * t), int(138 - 60 * t), int(61 - 30 * t)))

for x in range(left_w, W):
    t = (x - left_w) / (W - left_w)
    v = int(16 + 8 * (1 - t))
    d.line([(x, 0), (x, W)], fill=(v, v, v + 2))

WHITE = (250, 248, 244)
ACCENT = (240, 100, 45)


def box(values):
    return [v * S for v in values]


def pts(values):
    return [(x * S, y * S) for x, y in values]


# 吉他
d.ellipse(box([170, 560, 545, 900]), fill=WHITE)
d.ellipse(box([205, 395, 565, 675]), fill=WHITE)
d.polygon(pts([(460, 470), (545, 512), (760, 255), (700, 200)]), fill=WHITE)
d.polygon(pts([(742, 266), (802, 196), (858, 238), (798, 308)]), fill=WHITE)

# 音孔与琴弦
d.ellipse(box([300, 600, 390, 690]), fill=ACCENT)
for i in range(4):
    off = i * 16
    d.line(pts([(480 + off, 500 - off * 0.4), (735 - off, 255 + off * 0.6)]),
           fill=ACCENT, width=int(5 * S))

# 钢琴键
kx0, ky0, kx1, ky1 = box([600, 650, 955, 905])
d.rounded_rectangle([kx0, ky0, kx1, ky1], radius=18 * S, fill=WHITE)
keys = 8
kw = (kx1 - kx0) / keys
for i in range(1, keys):
    x = kx0 + kw * i
    d.line([(x, ky0), (x, ky1)], fill=(28, 28, 30), width=int(4 * S))
bw = kw * 0.6
bh = (ky1 - ky0) * 0.58
for i in [0, 1, 3, 4, 5, 6]:
    x = kx0 + kw * (i + 1) - bw / 2
    d.rectangle([x, ky0, x + bw, ky0 + bh], fill=(18, 18, 20))

img.resize((1024, 1024), Image.LANCZOS).save("AppIcon.png")
print("saved")
