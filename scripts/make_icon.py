# -*- coding: utf-8 -*-
"""توليد أيقونة تطبيق «المراسلات الرسمية»:
وثيقة بيضاء بأسطر عربية (يمين) وختم ذهبي، على أخضر رسمي #14532D.
- icon.png: خلفية خضراء كاملة (الأيقونة العادية)
- icon_foreground.png: الوثيقة وحدها بخلفية شفافة (التكيفية) بمقياس أصغر
"""
from PIL import Image, ImageDraw

SIZE = 1024
GREEN = (20, 83, 45, 255)        # #14532D
PAPER = (255, 255, 255, 255)
FOLD = (203, 213, 223, 255)      # #CBD5DF
BAR_TITLE = (20, 83, 45, 255)
BAR = (182, 196, 208, 255)       # #B6C4D0
GOLD = (180, 83, 9, 255)         # #B45309


def glyph_layer(s=1.0):
    """طبقة شفافة عليها الوثيقة مرسومة حول مركز الصورة بمقياس s."""
    layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    c = SIZE / 2

    def T(x, y):
        return (c + (x - c) * s, c + (y - c) * s)

    def box(x0, y0, x1, y1):
        return [T(x0, y0), T(x1, y1)]

    # الورقة
    d.rounded_rectangle(box(292, 200, 732, 824), radius=28 * s, fill=PAPER)

    # قصّ الزاوية العلوية اليسرى إلى شفاف ثم رسم طيّة الورقة
    mask = Image.new("L", (SIZE, SIZE), 0)
    dm = ImageDraw.Draw(mask)
    dm.polygon([T(292, 200), T(396, 200), T(292, 304)], fill=255)
    clear = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    layer = Image.composite(clear, layer, mask)
    d = ImageDraw.Draw(layer)
    d.polygon([T(396, 200), T(292, 304), T(396, 304)], fill=FOLD)

    # سطر الموضوع (عريض بلون المنشأة) ثم أسطر النص — كلها من اليمين
    def bar(y, w, h, color, r):
        d.rounded_rectangle(box(676 - w, y, 676, y + h), radius=r * s,
                            fill=color)

    bar(320, 300, 34, BAR_TITLE, 17)
    bar(404, 356, 22, BAR, 11)
    bar(458, 356, 22, BAR, 11)
    bar(512, 300, 22, BAR, 11)
    bar(566, 356, 22, BAR, 11)
    bar(620, 240, 22, BAR, 11)

    # الختم الذهبي أسفل يسار الورقة: حلقة + قرص داخلي
    ring_w = max(2, round(14 * s))
    d.ellipse(box(392 - 64, 720 - 64, 392 + 64, 720 + 64),
              outline=GOLD, width=ring_w)
    d.ellipse(box(392 - 26, 720 - 26, 392 + 26, 720 + 26), fill=GOLD)
    return layer


def main(out_dir):
    # الأيقونة العادية: خلفية خضراء كاملة
    icon = Image.new("RGBA", (SIZE, SIZE), GREEN)
    icon = Image.alpha_composite(icon, glyph_layer(1.0))
    icon.save(out_dir + "/icon.png")

    # الأمامية التكيفية: شفافة، والمجسّم داخل منطقة الأمان (~66%)
    glyph_layer(0.72).save(out_dir + "/icon_foreground.png")
    print("OK:", out_dir)


if __name__ == "__main__":
    import sys
    main(sys.argv[1])
