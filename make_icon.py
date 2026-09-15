#!/usr/bin/env python3
"""
生成 MacCleaner 应用图标 —— 磁盘仪表环（抽象图形）

设计取舍
--------
旧版用「扫帚 + 磁盘」，实测有三个硬伤：
  1. 扫帚头盖住磁盘 39% 的宽度，磁盘等于白画；
  2. 13 条刷毛按 line width=1.25×间距 画，底部留出黑缝，像坏梳子；
  3. 扫帚是细长斜线图形，缩到 32px 后完全糊掉，只剩一团金色。

新版改用「开口环 + 指针」的仪表盘符号：
  - 主体是一个粗环，小尺寸下仍是一个结实的实心形状，不会散架；
  - 环的开口用进度语义（已用/可用），配合指针指向，一眼看懂"空间占用"；
  - 只用 2 个色相，靠明度分层，避免旧版「深蓝紫 + 土黄」的脏感。

macOS 图标规范
--------------
  - 圆角矩形，圆角半径约为边长的 22.37%（Big Sur squircle 近似）
  - 内容不铺满画布，四周留出约 10% 边距
  - 光源在上方，底部有投影；图形带轻微内阴影/高光
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
    g = Image.new("RGB", (w, h))
    px = g.load()
    denom = max(w + h - 2, 1)
    for y in range(h):
        for x in range(w):
            # 只按行采样再拉伸会丢对角信息，这里逐像素算但限制在低分辨率
            pass
    # 逐像素太慢，改用 256x256 计算后放大
    n = 256
    small = Image.new("RGB", (n, n))
    sp = small.load()
    for y in range(n):
        for x in range(n):
            t = (x + y) / (2 * (n - 1))
            sp[x, y] = lerp(top_left, bottom_right, t)
    return small.resize((w, h), Image.BICUBIC)


def glow(img, bbox, color, blur, alpha):
    """柔光层"""
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).ellipse(bbox, fill=color + (alpha,))
    return Image.alpha_composite(img, layer.filter(ImageFilter.GaussianBlur(blur)))


def ring_arc(draw, cx, cy, r_out, r_in, start_deg, end_deg, fill, ss=SS):
    """
    画一段圆环（带超采样）。
    PIL 没有环形图元，用「外圆减去内圆」的 pieslice 组合实现。
    """
    if end_deg <= start_deg:
        return
    box = [cx - r_out, cy - r_out, cx + r_out, cy + r_out]
    draw.pieslice(box, start=start_deg, end=end_deg, fill=fill)
    inner = [cx - r_in, cy - r_in, cx + r_in, cy + r_in]
    # 内圈用透明「挖洞」不可行（同一张图上），所以由调用方分层处理
    return box, inner


def make_icon(size=S):
    cx = cy = size / 2

    # ---------- 配色：蓝青渐变 ----------
    # 取自 macOS 磁盘工具一类的系统蓝青，比旧版的深蓝紫更干净
    BG_TL = (94, 186, 250)      # 左上：亮天蓝
    BG_BR = (28, 108, 210)      # 右下：深蓝
    RING_DONE = (255, 255, 255)  # 已用部分：纯白
    RING_TODO = (255, 255, 255, 92)  # 剩余部分：半透明白

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
        fill=(255, 255, 255, 40))
    hl = hl.filter(ImageFilter.GaussianBlur(BW * 0.10))
    hl.putalpha(Image.composite(hl.getchannel("A"),
                                Image.new("L", (size, size), 0), mask))
    img = Image.alpha_composite(img, hl)

    # 内描边：让圆角矩形边缘有一圈细腻的亮边（macOS 图标的关键质感）
    edge = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(edge).rounded_rectangle(
        [BOX[0] + BW * 0.004, BOX[1] + BW * 0.004,
         BOX[2] - BW * 0.004, BOX[3] - BW * 0.004],
        radius=RADIUS - BW * 0.004, outline=(255, 255, 255, 58),
        width=int(BW * 0.008))
    img = Image.alpha_composite(img, edge)

    # ---------- 2. 仪表环 ----------
    # 尺寸：外径取边长的 0.30，环厚 0.088 —— 够粗，32px 下仍结实
    r_out = BW * 0.300
    r_in = BW * 0.212
    r_mid = (r_out + r_in) / 2
    thickness = r_out - r_in

    # 圆环用「外圈实心圆 - 内圈挖空」实现：
    # 先在独立图层上画整环，再用 alpha 挖洞。
    def arc_layer(r_o, r_i, a0, a1, color, round_caps=True):
        """
        返回一个只含该段圆环的 RGBA 图层（已挖好内洞）。

        round_caps=True 时在两端补上半圆端帽 —— 否则 pieslice 会沿半径方向
        平切出一个斜角断面，放大看像被切断，是旧版没有的细节。
        """
        ss = SS
        W = size * ss
        layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        c = W / 2
        ro, ri = r_o * ss, r_i * ss
        d.pieslice([c - ro, c - ro, c + ro, c + ro], start=a0, end=a1, fill=color)

        if round_caps and (a1 - a0) < 359.9:
            # 两端各画一个直径为环厚的实心圆，圆心落在中径上
            rm = (ro + ri) / 2
            cap_r = (ro - ri) / 2
            for a in (a0, a1):
                rad = math.radians(a)
                px_, py_ = c + rm * math.cos(rad), c + rm * math.sin(rad)
                d.ellipse([px_ - cap_r, py_ - cap_r, px_ + cap_r, py_ + cap_r], fill=color)

        # 挖掉内圈：用 dst-out 效果靠 alpha 合成实现
        hole = Image.new("L", (W, W), 0)
        ImageDraw.Draw(hole).ellipse([c - ri, c - ri, c + ri, c + ri], fill=255)
        a = layer.getchannel("A")
        layer.putalpha(Image.composite(Image.new("L", (W, W), 0), a, hole))
        return layer.resize((size, size), Image.LANCZOS)

    # 角度约定：PIL 的 0° 在 3 点钟方向，顺时针为正。
    # 仪表盘习惯：起点在左下（约 135°），顺时针扫过 270° 到右下（约 45°）。
    START = 135
    TOTAL = 270
    USED = 0.78          # 「已用 78%」—— 与旧版 99% 的焦虑感相比更中性

    # 底环（剩余部分，半透明）
    img = Image.alpha_composite(
        img, arc_layer(r_out, r_in, START, START + TOTAL, RING_TODO))
    # 进度环（已用部分，纯白）
    img = Image.alpha_composite(
        img, arc_layer(r_out, r_in, START, START + TOTAL * USED, RING_DONE))

    # ---------- 3. 指针 ----------
    # 指针必须
    #   (a) 与「已用」段的端点角度严格一致，否则视觉上对不上；
    #   (b) 末端停在内径以内，绝不能戳进环里（旧版戳穿了，很穿帮）。
    ang = math.radians(START + TOTAL * USED)
    tip_r = r_in * 0.80          # 停在内径以内，留出余量
    tip = (cx + tip_r * math.cos(ang), cy + tip_r * math.sin(ang))

    hand = Image.new("RGBA", (size * SS, size * SS), (0, 0, 0, 0))
    hd = ImageDraw.Draw(hand)
    c = size * SS / 2
    hw = BW * 0.030 * SS
    hd.line([c, c, tip[0] * SS, tip[1] * SS], fill=RING_DONE + (255,), width=int(hw))
    # 指针两端都补圆头，避免出现方头断面
    for (ex, ey) in [(c, c), (tip[0] * SS, tip[1] * SS)]:
        rr = hw / 2
        hd.ellipse([ex - rr, ey - rr, ex + rr, ey + rr], fill=RING_DONE + (255,))
    # 轴心圆点
    hr = BW * 0.042 * SS
    hd.ellipse([c - hr, c - hr, c + hr, c + hr], fill=RING_DONE + (255,))
    img = Image.alpha_composite(img, hand.resize((size, size), Image.LANCZOS))

    # ---------- 4. 整体投影（让图形从底板上浮起来）----------
    # 关键：投影必须是有颜色的半透明黑，不能是 (0,0,0,0) —— 旧写法建了一张
    # 全透明图层，叠上去等于什么都没画，投影完全没生效。
    shape_alpha = img.getchannel("A")
    px_data = img.load()
    sa = Image.new("L", (size, size), 0)
    sap = sa.load()
    for y in range(size):
        for x in range(size):
            r, g, b, a = px_data[x, y]
            # 只给「白色图形」部分做投影，底板本身不投
            if a > 200 and r > 200 and g > 200 and b > 200:
                sap[x, y] = 150

    shadow = Image.new("RGBA", (size, size), (12, 40, 90, 0))
    shadow.putalpha(sa)
    shadow = shadow.filter(ImageFilter.GaussianBlur(BW * 0.018))

    # 下移一点，投影才自然
    shifted = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shifted.paste(shadow, (0, int(BW * 0.014)), shadow)
    # 投影不能溢出圆角矩形
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
