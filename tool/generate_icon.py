"""Генератор иконки приложения MemoryFly.
Запуск: python tool/generate_icon.py
Создаёт assets/icon/app_icon.png (1024x1024) и app_icon_foreground.png.
"""
import os
from PIL import Image, ImageDraw

W = 1024
TEAL = (20, 184, 166)     # #14B8A6
INDIGO = (99, 102, 241)   # #6366F1


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def gradient_bg():
    img = Image.new("RGB", (W, W))
    d = ImageDraw.Draw(img)
    for y in range(W):
        # лёгкая диагональ: смешиваем по y с небольшим вкладом — мягкий переход
        t = y / (W - 1)
        d.line([(0, y), (W, y)], fill=lerp(TEAL, INDIGO, t))
    return img.convert("RGBA")


def rounded(draw, box, radius, **kw):
    draw.rounded_rectangle(box, radius=radius, **kw)


def draw_board(img, inset=0):
    d = ImageDraw.Draw(img, "RGBA")
    white = (255, 255, 255, 255)

    # Сетка 3x3 — «поле памяти»
    total = 560
    gap = 46
    cell = (total - 2 * gap) // 3
    x0 = (W - total) // 2
    y0 = (W - total) // 2 + 8

    centers = {}
    for r in range(3):
        for c in range(3):
            cx = x0 + c * (cell + gap)
            cy = y0 + r * (cell + gap)
            box = [cx, cy, cx + cell, cy + cell]
            centers[(r, c)] = (cx + cell // 2, cy + cell // 2)
            # фоновые ячейки — полупрозрачный контур
            rounded(d, box, radius=34, outline=(255, 255, 255, 150), width=10)

    # Стартовая «фишка» — яркая залитая ячейка (верх-лево)
    r, c = 0, 0
    cx = x0 + c * (cell + gap)
    cy = y0 + r * (cell + gap)
    rounded(d, [cx, cy, cx + cell, cy + cell], radius=34, fill=white)

    # Цель — кольцо (низ-право)
    r, c = 2, 2
    cx = x0 + c * (cell + gap)
    cy = y0 + r * (cell + gap)
    rounded(d, [cx, cy, cx + cell, cy + cell], radius=34,
            outline=white, width=22)

    # Стрелка движения по диагонали из старта в цель
    p_start = centers[(0, 0)]
    p_end = centers[(2, 2)]
    # немного укоротим, чтобы не лезть в ячейки
    sx = p_start[0] + 70
    sy = p_start[1] + 70
    ex = p_end[0] - 70
    ey = p_end[1] - 70
    d.line([(sx, sy), (ex, ey)], fill=white, width=26)
    # наконечник
    head = 64
    d.polygon([(ex + 18, ey + 18),
               (ex - head, ey - 6),
               (ex - 6, ey - head)], fill=white)
    return img


def main():
    os.makedirs("assets/icon", exist_ok=True)

    base = gradient_bg()
    draw_board(base)
    base.convert("RGB").save("assets/icon/app_icon.png")

    # Foreground для Android adaptive: прозрачный фон + сетка с отступом (safe zone)
    fg = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    draw_board(fg)
    fg.save("assets/icon/app_icon_foreground.png")

    print("Готово: assets/icon/app_icon.png, app_icon_foreground.png")


if __name__ == "__main__":
    main()
