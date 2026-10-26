import os
D = os.path.dirname(os.path.abspath(__file__))
src = open(f'{D}/cats.py').read()
exec(src[:src.index('CATS = [')])

SECS = [('有声书', (242, 140, 56), ['爱你是我戒不掉的瘾', '情人劫', '凤囚凰', '永世沉沦']),
        ('相声评书', (226, 87, 76), ['苗阜王声 第五季', '苗阜王声 第六季', '击鼓骂曹', '收官福袋']),
        ('儿童', (255, 181, 71), ['骑士街9号', '小红帽童话', '小猪佩奇', '大灰狼睡前']),
        ('头条', (90, 169, 230), ['威锋网科技快讯', '每经热评', '财经快讯', '快听短资讯']),
        ('娱乐', (155, 123, 224), ['鬼叔怪谈', '怪哉', '奇谭', '明清异闻录'])]

def head(im, title='阅听'):
    d = ImageDraw.Draw(im); status(d)
    text(d, (16, 51), title, 34, 'white', True)
    glass_btn(im, (16, 109, 374, 153), 22); d = ImageDraw.Draw(im)
    d.ellipse([32 * S, 123 * S, 46 * S, 137 * S], outline=(255, 255, 255, 140), width=2 * S)
    text(d, (56, 121), '搜书名、作者或主播', 14, (255, 255, 255, 110))
    return 171

def book(im, x, y, w, t, k, sub=None):
    cover(im, covers[k % 6], (x, y, x + w, y + w)); d = ImageDraw.Draw(im)
    text(d, (x, y + w + 6), t[:8], 12.5, (255, 255, 255, 230))
    if sub: text(d, (x, y + w + 24), sub, 10.5, (255, 255, 255, 110))

def overlay(im, fn):
    ov = Image.new('RGBA', im.size, (0, 0, 0, 0)); fn(ImageDraw.Draw(ov)); im.paste(ov, (0, 0), ov)
    return ImageDraw.Draw(im)

# A 横滑胶囊:点哪个,下面网格就切到该类
def A():
    im = canvas().convert('RGBA'); y = head(im); d = ImageDraw.Draw(im)
    x = 16; sel = 1
    for i, (n, col, _) in enumerate(SECS):
        w = len(n) * 14 + 30
        if i == sel: rr(d, (x, y, x + w, y + 34), 17, col)
        else: d = overlay(im, lambda od: rr(od, (x, y, x + w, y + 34), 17, (255, 255, 255, 26), (255, 255, 255, 40)))
        text(d, (x + w / 2, y + 8), n, 14, 'white' if i == sel else (255, 255, 255, 180), i == sel, anchor='ma')
        x += w + 8
    y += 50
    text(d, (16, y), '相声评书', 22, 'white', True); text(d, (374, y + 6), '28 部', 13, (255, 255, 255, 120), anchor='ra')
    y += 40
    cw = (W - 32 - 24) / 3
    names = SECS[1][2] + ['武宗亮评书', '青曲社精选', '传统相声', '单口小段', '评书三国']
    for i in range(9):
        r, c = divmod(i, 3)
        book(im, 16 + c * (cw + 12), y + r * (cw + 44), cw, names[i], i + 2)
    dock(im, 0); return im

# B 封面卡片:每类一张大卡,三张封面叠放
def B():
    im = canvas().convert('RGBA'); y = head(im); d = ImageDraw.Draw(im)
    text(d, (16, y), '分类', 24, 'white', True); y += 42
    cw, ch = 220, 150
    for i, (n, col, books) in enumerate(SECS[:2]):
        x = 16 + i * (cw + 14)
        d = overlay(im, lambda od: rr(od, (x, y, x + cw, y + ch), 22, col + (70,), col + (120,)))
        for j in range(3):
            cover(im, covers[(i * 3 + j) % 6], (x + cw - 150 + j * 34, y + 30 - j * 6, x + cw - 150 + j * 34 + 80, y + 110 - j * 6), 10)
        d = ImageDraw.Draw(im)
        text(d, (x + 16, y + 16), n, 20, 'white', True)
        text(d, (x + 16, y + 118), f'{[21, 28][i]} 部 ›', 13, (255, 255, 255, 200))
    y += ch + 16
    sw = (W - 32 - 24) / 3
    for i, (n, col, _) in enumerate(SECS[2:]):
        x = 16 + i * (sw + 12)
        d = overlay(im, lambda od: rr(od, (x, y, x + sw, y + 96), 18, col + (60,), col + (110,)))
        cover(im, covers[(i + 3) % 6], (x + sw - 54, y + 36, x + sw - 10, y + 80), 8); d = ImageDraw.Draw(im)
        text(d, (x + 12, y + 12), n, 16, 'white', True)
    y += 96 + 28
    text(d, (16, y), '继续收听', 24, 'white', True); y += 40
    for i in range(2):
        x0 = 16 + i * (195 + 14)
        glass_btn(im, (x0, y, x0 + 195, y + 240), 22)
        cover(im, covers[i], (x0 + 12, y + 12, x0 + 183, y + 183), 14)
    dock(im, 0); return im

# C 频道页:首页一个入口,点进去左侧竖栏右侧书单
def C():
    im = canvas().convert('RGBA'); d = ImageDraw.Draw(im); status(d)
    top = 47
    glass_btn(im, (16, top + 2, 60, top + 46), 22); d = ImageDraw.Draw(im)
    d.line([(41 * S, (top + 15) * S), (34 * S, (top + 24) * S), (41 * S, (top + 33) * S)], fill='white', width=int(2.4 * S))
    text(d, (72, top + 4), '分类', 30, 'white', True)
    y0 = top + 66
    d = overlay(im, lambda od: rr(od, (0, y0, 92, H), 0, (255, 255, 255, 14)))
    sel = 2
    for i, (n, col, _) in enumerate(SECS):
        yy = y0 + 10 + i * 56
        if i == sel:
            d = overlay(im, lambda od: rr(od, (8, yy, 84, yy + 44), 12, (255, 255, 255, 30)))
            rr(d, (8, yy + 12, 11, yy + 32), 2, col)
        text(d, (46, yy + 12), n, 14, 'white' if i == sel else (255, 255, 255, 140), i == sel, anchor='ma')
    x = 104; y = y0 + 8
    text(d, (x, y), '儿童', 20, 'white', True); text(d, (374, y + 6), '31 部', 12, (255, 255, 255, 120), anchor='ra')
    y += 38
    names = SECS[2][2] + ['米小圈上学记', '凯叔讲故事', '十万个为什么', '睡前儿歌']
    for i in range(8):
        yy = y + i * 80
        if yy > 760: break
        d = overlay(im, lambda od: rr(od, (x, yy, 374, yy + 70), 14, (255, 255, 255, 16), (255, 255, 255, 30)))
        cover(im, covers[(i + 1) % 6], (x + 8, yy + 8, x + 62, yy + 62), 10); d = ImageDraw.Draw(im)
        text(d, (x + 72, yy + 14), names[i], 14, 'white', True)
        text(d, (x + 72, yy + 38), f'{[120, 46, 52, 300, 86, 210, 64, 98][i]} 集 · 儿童', 11.5, (255, 255, 255, 120))
    dock(im, 0); return im

# D 首页分区:没有格子,每类一行横滑
def Dd():
    im = canvas().convert('RGBA'); y = head(im); d = ImageDraw.Draw(im)
    for i, (n, col, books) in enumerate(SECS[:4]):
        rr(d, (16, y + 6, 20, y + 24), 2, col)
        text(d, (28, y), n, 20, 'white', True)
        text(d, (374, y + 5), '全部 ›', 13, (255, 255, 255, 130), anchor='ra')
        y += 34
        for j in range(4):
            book(im, 16 + j * 112, y, 100, books[j], i * 2 + j)
        d = ImageDraw.Draw(im)
        y += 100 + 46
        if y > 740: break
    dock(im, 0); return im

ims = [(A(), 'A 横滑胶囊'), (B(), 'B 封面卡片'), (C(), 'C 分类频道页'), (Dd(), 'D 首页分区')]
pad = 30 * S
out = Image.new('RGB', (W * S * 2 + pad * 3, (H * S + pad + 40 * S) * 2 + pad), (235, 235, 238))
od = ImageDraw.Draw(out)
for i, (im, cap) in enumerate(ims):
    r, c = divmod(i, 2)
    x = pad + c * (W * S + pad); y = pad + r * (H * S + pad + 40 * S)
    m = Image.new('L', im.size, 0); ImageDraw.Draw(m).rounded_rectangle([0, 0, W * S, H * S], 44 * S, fill=255)
    out.paste(im.convert('RGB'), (x, y), m)
    od.text((x + W * S / 2, y + H * S + 10 * S), cap, font=f(16, True), fill=(30, 30, 30), anchor='ma')
out = out.resize((out.width // 2, out.height // 2), Image.LANCZOS)
out.save(f'{D}/cats4.png'); print(out.size)
