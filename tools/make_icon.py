"""生成 App 图标（吉他 + 键盘），1024x1024 RGB，无透明通道。"""
from PIL import Image, ImageDraw

W = 1024
BG = (13, 13, 15)
ORANGE = (255, 122, 40)
WHITE = (245, 245, 245)
BLACK = (20, 20, 22)
DARK = (30, 30, 32)

img = Image.new("RGB", (W, W), BG)
d = ImageDraw.Draw(img)

# 吉他：琴身
d.ellipse([150, 520, 560, 790], fill=ORANGE)
d.ellipse([190, 390, 540, 640], fill=ORANGE)
d.ellipse([320, 545, 400, 625], fill=BG)
# 琴颈
d.polygon([(430, 430), (520, 470), (770, 210), (710, 150)], fill=ORANGE)
# 琴头
d.polygon([(748, 222), (806, 150), (872, 192), (812, 264)], fill=ORANGE)
# 琴弦
for i in range(3):
    off = i * 20
    d.line([(445 + off, 445 - off * 0.2), (742 - off, 218 + off * 0.55)], fill=BG, width=5)

# 键盘
kx0, ky0, kx1, ky1 = 585, 630, 940, 905
d.rounded_rectangle([kx0, ky0, kx1, ky1], radius=20, fill=WHITE)
keys = 7
kw = (kx1 - kx0) / keys
for i in range(1, keys):
    x = kx0 + kw * i
    d.line([(x, ky0), (x, ky1)], fill=DARK, width=6)
bw = kw * 0.58
bh = (ky1 - ky0) * 0.56
for i in [0, 1, 3, 4, 5]:
    x = kx0 + kw * (i + 1) - bw / 2
    d.rectangle([x, ky0, x + bw, ky0 + bh], fill=BLACK)

img.save("AppIcon.png")
print("saved AppIcon.png", img.size)
