#!/usr/bin/env python3
"""
生成 MacCleaner 应用图标 —— 扫帚 + 磁盘
macOS Big Sur 之后的图标规范：
  - 圆角矩形，圆角半径约为边长的 22.37%（squircle 近似）
  - 图标内容不铺满画布，四周留出约 10% 边距
  - 光源在上方，底部有轻微投影
"""
from PIL import Image, ImageDraw, ImageFilter
import math, os, sys

S = 1024                      # 主画布
MARGIN = int(S * 0.098)       # 四周留白
BOX = (MARGIN, MARGIN, S - MARGIN, S - MARGIN)
BW = BOX[2] - BOX[0]          # 圆角矩形边长
RADIUS = int(BW * 0.2237)     # squircle 近似半径


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def rounded_mask(size, box, radius, supersample=4):
    """高质量圆角矩形遮罩（4x 超采样后缩小，边缘更平滑）"""
    w, h = size
    m = Image.new("L", (w * supersample, h * supersample), 0)
    d = ImageDraw.Draw(m)
    x0, y0, x1, y1 = [v * supersample for v in box]
    d.rounded_rectangle([x0, y0, x1, y1], radius=radius * supersample, fill=255)
    return m.resize((w, h), Image.LANCZOS)


def vertical_gradient(size, top, bottom):
    """垂直线性渐变"""
    w, h = size
    g = Image.new("RGB", (1, h))
    px = g.load()
    for y in range(h):
        t = y / max(h - 1, 1)
        px[0, y] = lerp(top, bottom, t)
    return g.resize((w, h), Image.BILINEAR)


def draw_glow(img, bbox, color, blur, alpha):
    """在指定区域画一层柔光"""
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.ellipse(bbox, fill=color + (alpha,))
    layer = layer.filter(ImageFilter.GaussianBlur(blur))
    return Image.alpha_composite(img, layer)


def make_icon(size=S, bg_top=(58, 62, 92), bg_bottom=(28, 30, 48)):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    # ---------- 1. 底色圆角矩形 + 渐变 ----------
    grad = vertical_gradient((size, size), bg_top, bg_bottom).convert("RGBA")
    mask = rounded_mask((size, size), BOX, RADIUS)
    img.paste(grad, (0, 0), mask)

    # 顶部高光（模拟光源在上方）
    hl = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    hd = ImageDraw.Draw(hl)
    hd.ellipse([BOX[0] - BW * 0.15, BOX[1] - BW * 0.42,
                BOX[2] + BW * 0.15, BOX[1] + BW * 0.30],
               fill=(255, 255, 255, 26))
    hl = hl.filter(ImageFilter.GaussianBlur(BW * 0.09))
    hl.putalpha(Image.composite(hl.getchannel("A"), Image.new("L", (size, size), 0), mask))
    img = Image.alpha_composite(img, hl)

    # ---------- 2. 磁盘（底部，带透视感的扁圆柱）----------
    cx = size / 2
    disk_cy = BOX[1] + BW * 0.665
    disk_rx = BW * 0.295
    disk_ry = BW * 0.108
    disk_h = BW * 0.085          # 圆柱高度

    disk = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    dd = ImageDraw.Draw(disk)

    # 侧面（柱体）
    side = [cx - disk_rx, disk_cy - disk_h, cx + disk_rx, disk_cy + disk_ry]
    dd.rounded_rectangle(
        [cx - disk_rx, disk_cy - disk_h - disk_ry * 0.2,
         cx + disk_rx, disk_cy + disk_ry * 0.85],
        radius=disk_rx * 0.92, fill=(122, 132, 168, 255))

    # 顶面
    dd.ellipse([cx - disk_rx, disk_cy - disk_ry - disk_h,
                cx + disk_rx, disk_cy + disk_ry - disk_h],
               fill=(168, 178, 210, 255))
    # 顶面内圈（金属质感）
    inner = disk_rx * 0.55
    inner_y = disk_ry * 0.55
    dd.ellipse([cx - inner, disk_cy - inner_y - disk_h,
                cx + inner, disk_cy + inner_y - disk_h],
               fill=(196, 205, 232, 255))
    # 中心轴
    hub = disk_rx * 0.17
    hub_y = disk_ry * 0.17
    dd.ellipse([cx - hub, disk_cy - hub_y - disk_h,
                cx + hub, disk_cy + hub_y - disk_h],
               fill=(120, 130, 165, 255))

    # 磁盘顶面高光
    disk = draw_glow(disk, [cx - disk_rx * 0.8, disk_cy - disk_ry - disk_h - disk_ry * 0.3,
                            cx + disk_rx * 0.1, disk_cy - disk_h + disk_ry * 0.2],
                     (255, 255, 255), BW * 0.03, 60)

    # ---------- 3. 扫帚 ----------
    broom = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    bd = ImageDraw.Draw(broom)

    # 手柄：从左下到右上的倾斜木杆
    handle_w = BW * 0.052
    x1, y1 = cx - BW * 0.155, disk_cy - disk_h - disk_ry * 0.05   # 底部（靠近磁盘）
    x2, y2 = cx + BW * 0.175, BOX[1] + BW * 0.175                  # 顶部
    bd.line([x1, y1, x2, y2], fill=(214, 168, 108, 255), width=int(handle_w))
    # 手柄高光
    bd.line([x1 - handle_w * 0.22, y1, x2 - handle_w * 0.22, y2],
            fill=(238, 200, 148, 255), width=int(handle_w * 0.34))

    # 扫帚头（刷毛）：在底端，做成梯形束
    head_cx, head_cy = x1, y1
    head_w = BW * 0.232
    head_h = BW * 0.150

    # 刷毛束：多条竖直的毛，底部略散开
    n = 13
    for i in range(n):
        t = i / (n - 1)
        # 从左到右，底部呈扇形展开
        xa = head_cx - head_w / 2 + head_w * t
        xb = head_cx - head_w / 2 + head_w * t
        spread = (t - 0.5) * head_w * 0.30
        yb = head_cy + head_h * (1 - 0.16 * abs(t - 0.5) * 2)
        # 颜色渐变：中间亮，两侧暗
        shade = 1 - abs(t - 0.5) * 0.55
        col = (int(238 * shade + 30), int(196 * shade + 26), int(96 * shade + 20), 255)
        bd.line([xa, head_cy - head_h * 0.12, xb + spread, yb],
                fill=col, width=int(head_w / n * 1.25))

    # 束带（把刷毛扎起来的箍）
    band_y = head_cy - head_h * 0.06
    band_w = head_w * 0.86
    bd.rounded_rectangle([head_cx - band_w / 2, band_y - BW * 0.019,
                          head_cx + band_w / 2, band_y + BW * 0.019],
                         radius=BW * 0.019, fill=(196, 148, 92, 255))
    bd.rounded_rectangle([head_cx - band_w / 2, band_y - BW * 0.019,
                          head_cx + band_w / 2, band_y - BW * 0.004],
                         radius=BW * 0.008, fill=(228, 184, 128, 255))

    img = Image.alpha_composite(img, broom)

    # ---------- 4. 清理效果：几粒发光的小星 ----------
    for (sx, sy, sr, al) in [
        (cx + BW * 0.245, disk_cy - disk_h - disk_ry * 1.75, BW * 0.026, 210),
        (cx + BW * 0.315, disk_cy - disk_h - disk_ry * 1.05, BW * 0.017, 160),
        (cx - BW * 0.245, disk_cy - disk_h - disk_ry * 1.45, BW * 0.020, 150),
    ]:
        img = draw_glow(img, [sx - sr * 2.6, sy - sr * 2.6, sx + sr * 2.6, sy + sr * 2.6],
                        (255, 236, 170), sr * 1.7, al // 2)
        star = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        sd = ImageDraw.Draw(star)
        # 四角星
        sd.polygon([(sx, sy - sr * 2.0), (sx + sr * 0.46, sy - sr * 0.46),
                    (sx + sr * 2.0, sy), (sx + sr * 0.46, sy + sr * 0.46),
                    (sx, sy + sr * 2.0), (sx - sr * 0.46, sy + sr * 0.46),
                    (sx - sr * 2.0, sy), (sx - sr * 0.46, sy - sr * 0.46)],
                   fill=(255, 244, 200, al))
        img = Image.alpha_composite(img, star)

    # ---------- 5. 裁回圆角 + 内描边 ----------
    final = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    final.paste(img, (0, 0), mask)

    stroke = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sd2 = ImageDraw.Draw(stroke)
    sd2.rounded_rectangle(BOX, radius=RADIUS, outline=(255, 255, 255, 30),
                          width=max(2, int(BW * 0.006)))
    final = Image.alpha_composite(final, stroke)

    return final


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out_dir, exist_ok=True)

    base = make_icon(S)

    # 生成 iconset 所需的全部尺寸
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

    # 预览图（也是给用户看的那个）
    base.resize((512, 512), Image.LANCZOS).save(os.path.join(out_dir, "icon-preview.png"))
    print(f"✅ 生成 {len(specs)} 个尺寸 → {iconset}")
    print(f"✅ 预览图 → {os.path.join(out_dir, 'icon-preview.png')}")


if __name__ == "__main__":
    main()
