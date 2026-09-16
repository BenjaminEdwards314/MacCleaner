#!/usr/bin/env python3
"""
生成 MacCleaner 应用图标 —— 飞天小女警风格的闪电扫帚

设计思路
--------
应用界面已经整体改成 PPG 主题（粗黑描边 + 硬阴影 + 粉/蓝/绿三色）。
图标必须跟界面说同一种语言，否则 Dock 里那个图标和窗口里的样子是两套东西。

主体沿用「闪电充当扫帚柄 + 扫帚头在下方」的合成读法（一眼读出「快速清理」），
但外壳换成片头卡的爆发感：黄底 + 粉色放射光 + 奶油色主体 + 粗黑描边。

尺寸可读性
----------
这是本设计最核心的约束。细长斜线图形在 16/32px 下天然容易糊，
所以做了三件事：

  1. 放大主体：闪电+扫帚头占满内容区，不做成小点缀；
  2. 加粗描边：轮廓线取边长的 0.030，远粗于正常笔画；
  3. 靠底板对比：奶油色图形压在黄/粉高饱和底上，边界锐利。

关于扫帚头的一个坑
------------------
初版用 5 根刷毛、每根接近正方形（0.089 宽 × 0.112 高），
结果整排读起来像**电池电量格 / 均衡器**，完全不像扫帚。修正办法：
刷毛变窄变长（0.057 × 0.150）并加到 7 根，下缘做扇形张开 + 参差长短。

配色
----
全部取自应用主题层 PPGTheme.swift，与窗口内保持同一套色值。

macOS 图标规范
--------------
  - 圆角矩形，圆角半径约为边长的 22.37%（Big Sur squircle 近似）
  - 内容不铺满画布，四周留出约 10% 边距
"""
from PIL import Image, ImageDraw, ImageFilter
import math, os, sys

S = 2048                        # 工作分辨率（最后缩到各尺寸）
SS = 1                          # 直接在 2048 画，已足够精细

# ── 配色：直接抄 PPGTheme.swift，保证和窗口内一致 ──
INK       = (28, 26, 38)        # 0.11, 0.10, 0.15
CREAM     = (255, 250, 245)     # 1.00, 0.98, 0.96
BLOSSOM   = (255, 107, 158)     # 1.00, 0.42, 0.62  花花·粉
BUBBLES   = (84, 194, 250)      # 0.33, 0.76, 0.98  泡泡·蓝
BUTTERCUP = (133, 219, 82)      # 0.52, 0.86, 0.32  毛毛·绿
SUNNY     = (255, 214, 71)      # 1.00, 0.84, 0.28

MARGIN = S * 0.098              # 四周留白
BOX = (MARGIN, MARGIN, S - MARGIN, S - MARGIN)
BW = BOX[2] - BOX[0]            # 内容区边长
RADIUS = BW * 0.2237            # squircle 近似半径
C = S / 2

# 闪电外轮廓：经典七点折线，下尖伸进扫帚头内部（y≈0.79），
# 否则柄和头断开，读起来像「闪电 + 一把刷子」两个独立物体。
LIGHTNING = [
    (0.560, 0.062), (0.335, 0.444), (0.468, 0.444), (0.330, 0.792),
    (0.660, 0.344), (0.512, 0.344), (0.672, 0.062),
]

HEAD_TOP, HEAD_BOT = 0.690, 0.862   # 扫帚头（深色束带）上下沿
HEAD_HALF = 0.196                   # 扫帚头半宽
BR_TOP, BR_BOT = 0.742, 0.892       # 刷毛上下沿
OUTLINE_W = 0.030                   # 描边粗细（占内容区比例）


def flat(color):
    return Image.new("RGB", (S, S), color)


def rays(colors, n=12, base=SUNNY):
    """片头卡的放射光 —— 从中心向外的扇区交替配色"""
    img = Image.new("RGB", (S, S), base)
    d = ImageDraw.Draw(img)
    for i in range(n):
        a0 = i * 2 * math.pi / n
        a1 = a0 + math.pi / n
        pts = [(C, C)] + [(C + S * math.cos(a0 + t * (a1 - a0) / 8),
                           C + S * math.sin(a0 + t * (a1 - a0) / 8))
                          for t in range(9)]
        d.polygon(pts, fill=colors[i % len(colors)])
    return img


def squircle_with(bg_img, border_w=0.021):
    """圆角方底板 + 一圈 ink 描边（与界面里的卡片同款）"""
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    b = BW * border_w
    d.rounded_rectangle(BOX, radius=RADIUS, fill=INK + (255,))
    m = Image.new("L", (S, S), 0)
    ImageDraw.Draw(m).rounded_rectangle(
        [BOX[0] + b, BOX[1] + b, BOX[2] - b, BOX[3] - b],
        radius=RADIUS - b, fill=255)
    img.paste(bg_img, (0, 0), m)
    return img


def broom_layers(n_bristles=7):
    """返回 (描边层, 彩色层)。

    描边由形状遮罩经高斯模糊后取阈值得到 —— 等价于向外膨胀，
    得到的是圆角描边，比直接画 stroke 更接近卡通线条。
    """
    cx = C

    def Q(fx, fy):
        return (BOX[0] + BW * fx, BOX[1] + BW * fy)

    bolt = [Q(fx, fy) for fx, fy in LIGHTNING]
    hx0, hx1 = cx - BW * HEAD_HALF, cx + BW * HEAD_HALF
    hb = [hx0, BOX[1] + BW * HEAD_TOP, hx1, BOX[1] + BW * HEAD_BOT]

    # 刷毛：等分后每根之间留缝，缝里露出深色底 —— 才读得出是「一撮毛」
    inset = BW * 0.020
    top_half = (hx1 - hx0) / 2 - inset
    bot_half = top_half * 1.16          # 下缘外张，扇形
    slot_t = 2 * top_half / n_bristles
    slot_b = 2 * bot_half / n_bristles
    gap = slot_t * 0.20

    quads = []
    for i in range(n_bristles):
        a_t = cx - top_half + i * slot_t + gap / 2
        b_t = cx - top_half + (i + 1) * slot_t - gap / 2
        a_b = cx - bot_half + i * slot_b + gap / 2
        b_b = cx - bot_half + (i + 1) * slot_b - gap / 2
        # 下缘参差：中间略短，形成自然弧线，不是一块板
        t = (i + 0.5) / n_bristles
        y_bot = BOX[1] + BW * BR_BOT - math.sin(t * math.pi) * BW * 0.020
        quads.append([(a_t, BOX[1] + BW * BR_TOP), (b_t, BOX[1] + BW * BR_TOP),
                      (b_b, y_bot), (a_b, y_bot)])

    shape = Image.new("L", (S, S), 0)
    sd = ImageDraw.Draw(shape)
    sd.polygon(bolt, fill=255)
    sd.rounded_rectangle(hb, radius=BW * 0.038, fill=255)

    col = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    cd = ImageDraw.Draw(col)
    cd.polygon(bolt, fill=CREAM + (255,))                       # 闪电 = 柄
    cd.rounded_rectangle(hb, radius=BW * 0.038, fill=INK + (255,))  # 束带
    for q in quads:
        cd.polygon(q, fill=CREAM + (255,))                      # 刷毛

    r = BW * OUTLINE_W * 0.55
    m = shape.filter(ImageFilter.GaussianBlur(r)).point(lambda v: 255 if v > 8 else 0)
    ink = Image.new("RGBA", (S, S), INK + (0,))
    ink.putalpha(m)
    return ink, col


def make_icon(size=1024):
    bg = rays([BLOSSOM, SUNNY]).convert("RGBA")
    ink, col = broom_layers()
    out = squircle_with(bg)
    out = Image.alpha_composite(out, ink)
    out = Image.alpha_composite(out, col)
    return out.resize((size, size), Image.LANCZOS)


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "Resources"
    os.makedirs(out_dir, exist_ok=True)

    base = make_icon(1024)

    specs = [
        ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
    ]
    iconset = os.path.join(out_dir, "MacCleaner.iconset")
    os.makedirs(iconset, exist_ok=True)

    for name, px in specs:
        base.resize((px, px), Image.LANCZOS).save(os.path.join(iconset, name))

    base.resize((512, 512), Image.LANCZOS).save(os.path.join(out_dir, "icon-preview.png"))
    print(f"✅ 生成 {len(specs)} 个尺寸 → {iconset}")
    print(f"✅ 预览图 → {os.path.join(out_dir, 'icon-preview.png')}")


if __name__ == "__main__":
    main()
