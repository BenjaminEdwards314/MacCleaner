#!/usr/bin/env python3
"""
生成 MacCleaner 应用图标 —— 闪电扫帚

设计思路
--------
把「扫帚」和「闪电」合成一个符号：闪电充当扫帚的柄，扫帚头在下方。
这样一眼能读出「快速清理」，而不是单纯的扫帚或单纯的闪电。

小尺寸可读性是本设计的核心约束。闪电和扫帚都是**细长斜线图形**，
实测闪电在 64/32/16px 下都只占约 9% 的像素 —— 天然容易糊。
因此这里的做法是：

  1. 放大主体：闪电+扫帚头合起来占满内容区，不做成小点缀；
  2. 加粗线条：柄宽取边长的 0.075，远粗于正常笔画；
  3. 靠底板对比：图形用纯白，压在高饱和橙红渐变上，边界锐利；
  4. 去掉所有小装饰：旧版那三颗星星在 32px 下就是三个脏点。

配色
----
橙红渐变（闪电/能量）+ 纯白图形。与之前的蓝青仪表环明显区分，
且在浅色和深色 Dock 背景上都跳得出来。

macOS 图标规范
--------------
  - 圆角矩形，圆角半径约为边长的 22.37%（Big Sur squircle 近似）
  - 内容不铺满画布，四周留出约 10% 边距
  - 光源在上方，底部有投影
"""
from PIL import Image, ImageDraw, ImageFilter
import math, os, sys

S = 1024                        # 主画布
MARGIN = int(S * 0.098)         # 四周留白
BOX = (MARGIN, MARGIN, S - MARGIN, S - MARGIN)
BW = BOX[2] - BOX[0]            # 圆角矩形边长
RADIUS = int(BW * 0.2237)       # squircle 近似半径
SS = 4                          # 超采样倍率


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def rounded_mask(size, box, radius, supersample=SS):
    """高质量圆角矩形遮罩（超采样后缩小，边缘更平滑）"""
    w, h = size
    m = Image.new("L", (w * supersample, h * supersample), 0)
    d = ImageDraw.Draw(m)
    x0, y0, x1, y1 = [v * supersample for v in box]
    d.rounded_rectangle([x0, y0, x1, y1], radius=radius * supersample, fill=255)
    return m.resize((w, h), Image.LANCZOS)


def diagonal_gradient(size, top_left, bottom_right):
    """对角线性渐变 —— 比纯垂直渐变更有体积感"""
    w, h = size
    n = 256
    small = Image.new("RGB", (n, n))
    sp = small.load()
    for y in range(n):
        for x in range(n):
            t = (x + y) / (2 * (n - 1))
            sp[x, y] = lerp(top_left, bottom_right, t)
    return small.resize((w, h), Image.BICUBIC)


def make_icon(size=S):
    cx = cy = size / 2

    # ---------- 配色：橙红渐变底 + 纯白图形 ----------
    BG_TL = (255, 168, 74)      # 左上：亮橙
    BG_BR = (222, 58, 62)       # 右下：深红
    FG = (255, 255, 255)        # 图形：纯白

    # ---------- 1. 底色圆角矩形 + 对角渐变 ----------
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    grad = diagonal_gradient((size, size), BG_TL, BG_BR).convert("RGBA")
    mask = rounded_mask((size, size), BOX, RADIUS)
    img.paste(grad, (0, 0), mask)

    # 顶部高光（光源在上方）
    hl = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(hl).ellipse(
        [BOX[0] - BW * 0.15, BOX[1] - BW * 0.46,
         BOX[2] + BW * 0.15, BOX[1] + BW * 0.26],
        fill=(255, 255, 255, 46))
    hl = hl.filter(ImageFilter.GaussianBlur(BW * 0.10))
    hl.putalpha(Image.composite(hl.getchannel("A"),
                                Image.new("L", (size, size), 0), mask))
    img = Image.alpha_composite(img, hl)

    # 内描边：边缘一圈细腻亮边，macOS 图标的关键质感
    edge = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(edge).rounded_rectangle(
        [BOX[0] + BW * 0.004, BOX[1] + BW * 0.004,
         BOX[2] - BW * 0.004, BOX[3] - BW * 0.004],
        radius=RADIUS - BW * 0.004, outline=(255, 255, 255, 64),
        width=int(BW * 0.008))
    img = Image.alpha_composite(img, edge)

    # ---------- 2. 闪电（充当扫帚的柄）----------
    # 所有坐标都用 BW 的比例表示，便于整体缩放调形。
    # 坐标原点在内容区左上角，取值 0..1 会被映射到内容区。
    def P(fx, fy):
        """比例坐标 → 画布坐标"""
        return (BOX[0] + BW * fx, BOX[1] + BW * fy)

    # 闪电外轮廓：经典七点折线，上宽下尖。
    # 下尖必须伸到扫帚头内部（y≈0.80），否则柄和头会断开，
    # 读起来像「闪电 + 一把刷子」两个独立物体，而不是「闪电柄的扫帚」。
    LIGHTNING = [
        (0.560, 0.070),   # 右上起点
        (0.335, 0.452),   # 向左下斜切
        (0.468, 0.452),   # 内侧台阶
        (0.330, 0.815),   # 下尖端 —— 插进扫帚头里
        (0.660, 0.352),   # 向右上回折
        (0.512, 0.352),   # 内侧台阶
        (0.672, 0.070),   # 回到右上
    ]
    bolt = Image.new("RGBA", (size * SS, size * SS), (0, 0, 0, 0))
    bd = ImageDraw.Draw(bolt)
    bd.polygon([(x * SS, y * SS) for (x, y) in
                [P(fx, fy) for (fx, fy) in LIGHTNING]], fill=FG + (255,))

    # ---------- 3. 扫帚头 ----------
    # 位置紧接闪电下尖，形成「闪电是柄、扫帚头在底」的完整读法
    head_cy = BOX[1] + BW * 0.785     # 扫帚头中心 y
    head_half = BW * 0.212            # 半宽
    bristle_h = BW * 0.130            # 刷毛高度

    # 3a. 刷毛：整体画成一个梯形，再在上面压「缝」。
    #     旧版是把 13 条毛当独立直线画，线宽 1.25×间距，底部留黑缝像坏梳子。
    #     正确做法是先画实心梯形保证底部连贯，再用细缝做纹理。
    brush = Image.new("RGBA", (size * SS, size * SS), (0, 0, 0, 0))
    brd = ImageDraw.Draw(brush)

    top_y = head_cy - bristle_h * 0.5
    bot_y = head_cy + bristle_h * 0.5
    top_half = head_half * 0.92       # 上沿略窄
    bot_half = head_half * 1.00       # 下沿略宽（扇形张开）

    # 底部做成参差：每根毛长度略有不同，像真的扫帚，而不是一块板子
    n_bristles = 7
    bot_ys = []
    for i in range(n_bristles):
        t = i / (n_bristles - 1)
        # 中间短、两侧长，形成自然的下缘弧线
        dip = math.sin(t * math.pi) * bristle_h * 0.085
        bot_ys.append(bot_y - dip)

    # 逐根画刷毛：每根之间留窄缝，缝宽恒定，整体随梯形张开
    slot_w = BW * 0.0135
    for i in range(n_bristles):
        t0 = i / n_bristles
        t1 = (i + 1) / n_bristles
        xa_t = cx - top_half + 2 * top_half * t0
        xb_t = cx - top_half + 2 * top_half * t1
        xa_b = cx - bot_half + 2 * bot_half * t0
        xb_b = cx - bot_half + 2 * bot_half * t1
        # 每根毛是一个四边形，两侧各让出半个缝宽
        inset = slot_w * 0.5
        brd.polygon([
            ((xa_t + inset) * SS, top_y * SS),
            ((xb_t - inset) * SS, top_y * SS),
            ((xb_b - inset) * SS, bot_ys[i] * SS),
            ((xa_b + inset) * SS, bot_ys[i] * SS),
        ], fill=FG + (255,))

    # 3b. 束带（把刷毛扎起来的箍）：横跨扫帚头上沿
    band_h = BW * 0.052
    band_y = top_y - band_h * 0.10
    brd.rounded_rectangle(
        [(cx - head_half * 1.02) * SS, (band_y - band_h * 0.5) * SS,
         (cx + head_half * 1.02) * SS, (band_y + band_h * 0.5) * SS],
        radius=band_h * 0.34 * SS, fill=FG + (255,))

    img = Image.alpha_composite(img, brush.resize((size, size), Image.LANCZOS))

    # 闪电叠在扫帚头之上（柄插进箍里，遮挡关系自然）
    img = Image.alpha_composite(img, bolt.resize((size, size), Image.LANCZOS))

    # ---------- 4. 整体投影（让图形从底板上浮起来）----------
    # 投影必须是有颜色的半透明黑，不能是 (0,0,0,0) —— 全透明叠上去等于没画。
    px_data = img.load()
    sa = Image.new("L", (size, size), 0)
    sap = sa.load()
    for y in range(size):
        for x in range(size):
            r, g, b, a = px_data[x, y]
            # 只给白色图形做投影，底板本身不投
            if a > 200 and r > 230 and g > 230 and b > 230:
                sap[x, y] = 140

    shadow = Image.new("RGBA", (size, size), (120, 20, 24, 0))
    shadow.putalpha(sa)
    shadow = shadow.filter(ImageFilter.GaussianBlur(BW * 0.017))

    shifted = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shifted.paste(shadow, (0, int(BW * 0.013)), shadow)
    clipped = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    clipped.paste(shifted, (0, 0), rounded_mask((size, size), BOX, RADIUS))
    img = Image.alpha_composite(clipped, img)

    return img


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "Resources"
    os.makedirs(out_dir, exist_ok=True)

    base = make_icon(S)

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
