"""TalkBridge 四葉幸運草圖示產生器（PIL 繪製，4 倍超取樣後縮小）。
用法: python make_icon.py <A|B|C> <out.png> [size]"""
import math, sys
from PIL import Image, ImageDraw

S = 4

def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

def gradient(W, top, bottom):
    img = Image.new("RGB", (W, W))
    d = ImageDraw.Draw(img)
    for y in range(W):
        d.line([(0, y), (W, y)], fill=lerp(top, bottom, y / (W - 1)))
    return img

def heart_poly(cx, cy, r, angle, steps=120):
    """心形葉片：尖端在 (cx,cy)，往 angle 方向長出去，大小 r。"""
    pts = []
    for k in range(steps):
        t = 2 * math.pi * k / steps
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        # 經典心形尖端在 (0,-17)，讓尖端對齊原點、往 +y 延伸
        x, y = x / 17 * r * 0.58, (y + 17) / 22 * r   # 長 r、寬約 1.1r，尖端在原點
        a = angle - math.pi / 2
        rx = x * math.cos(a) - y * math.sin(a)
        ry = x * math.sin(a) + y * math.cos(a)
        pts.append((cx + rx, cy + ry))
    return pts

def clover(d, cx, cy, r, leaf, vein, stem, stem_width):
    # 莖：從中心往右下彎
    pts = [(cx + (180 * t) * r / 260 + 40 * math.sin(t * 2.2) * r / 260, cy + 380 * t * r / 260) for t in [i / 30 for i in range(31)]]
    d.line(pts, fill=stem, width=stem_width, joint="curve")
    for i in range(4):
        ang = math.radians(45 + 90 * i)
        poly = heart_poly(cx, cy, r, ang)
        d.polygon(poly, fill=leaf)
    # 葉脈：每片中線
    for i in range(4):
        ang = math.radians(45 + 90 * i)
        ex = cx + math.cos(ang) * r * 0.62; ey = cy + math.sin(ang) * r * 0.62
        d.line([(cx, cy), (ex, ey)], fill=vein, width=max(2, stem_width // 3))
    d.ellipse([cx - r * 0.07, cy - r * 0.07, cx + r * 0.07, cy + r * 0.07], fill=vein)

def bubble(d, box, col, tail_left=True):
    x0, y0, x1, y1 = box
    h = y1 - y0
    d.rounded_rectangle(box, radius=int(h * 0.45), fill=col)
    if tail_left:
        d.polygon([(x0 + h * 0.4, y1 - 4), (x0 + h * 0.15, y1 + h * 0.35), (x0 + h * 0.85, y1 - 4)], fill=col)
    else:
        d.polygon([(x1 - h * 0.4, y1 - 4), (x1 - h * 0.15, y1 + h * 0.35), (x1 - h * 0.85, y1 - 4)], fill=col)

def make(variant, size=1024):
    W = size * S
    u = W / 1024
    if variant == "A":    # 奶油白底＋綠色幸運草
        img = gradient(W, (252, 251, 240), (236, 244, 224))
        d = ImageDraw.Draw(img)
        clover(d, 500 * u, 470 * u, 300 * u, (76, 170, 92), (196, 232, 190), (76, 150, 84), int(34 * u))
    elif variant == "B":  # 綠色漸層底＋白色幸運草
        img = gradient(W, (120, 200, 120), (40, 140, 80))
        d = ImageDraw.Draw(img)
        clover(d, 500 * u, 470 * u, 300 * u, (255, 255, 255), (150, 210, 150), (240, 250, 238), int(34 * u))
    else:                 # C：淺綠底＋幸運草＋兩個對話泡泡（翻譯）
        img = gradient(W, (240, 249, 236), (214, 238, 206))
        d = ImageDraw.Draw(img)
        bubble(d, [110 * u, 110 * u, 430 * u, 300 * u], (255, 255, 255), True)
        bubble(d, [594 * u, 110 * u, 914 * u, 300 * u], (60, 150, 84), False)
        for x in (195, 270, 345):
            d.ellipse([(x - 20) * u, 185 * u, (x + 20) * u, 225 * u], fill=(60, 150, 84))
        for x in (679, 754, 829):
            d.ellipse([(x - 20) * u, 185 * u, (x + 20) * u, 225 * u], fill=(255, 255, 255))
        clover(d, 500 * u, 590 * u, 230 * u, (76, 170, 92), (196, 232, 190), (76, 150, 84), int(28 * u))
    return img.resize((size, size), Image.LANCZOS)

if __name__ == "__main__":
    make(sys.argv[1], int(sys.argv[3]) if len(sys.argv) > 3 else 1024).save(sys.argv[2])
