from PIL import Image, ImageDraw, ImageFont, ImageFilter
S = 2
W, H = 390, 844
FB = '/usr/share/fonts/noto/NotoSansCJK-Bold.ttc'
import os
FR = '/usr/share/fonts/noto/NotoSansCJK-Regular.ttc'
if not os.path.exists(FR): FR = FB
def f(sz, b=False): return ImageFont.truetype(FB if b else FR, int(sz * S), index=2)
D = os.path.dirname(os.path.abspath(__file__))
covers = [Image.open(f'{D}/c{i}.jpg').convert('RGB') for i in range(6)]

def canvas():
    im = Image.new('RGB', (W * S, H * S), (18, 14, 12))
    g = Image.new('RGB', (W * S, H * S))
    gd = ImageDraw.Draw(g)
    for y in range(H * S):
        t = y / (H * S)
        gd.line([(0, y), (W * S, y)], fill=(int(30 - 14 * t), int(22 - 10 * t), int(18 - 8 * t)))
    glow = Image.new('L', (W * S, H * S), 0)
    ImageDraw.Draw(glow).ellipse([-120 * S, -160 * S, 260 * S, 220 * S], fill=90)
    glow = glow.filter(ImageFilter.GaussianBlur(70 * S))
    g.paste(Image.new('RGB', g.size, (190, 100, 40)), (0, 0), glow)
    return g

def rr(d, box, r, fill, outline=None):
    x0, y0, x1, y1 = [v * S for v in box]
    d.rounded_rectangle([x0, y0, x1, y1], r * S, fill=fill, outline=outline, width=max(1, int(0.7 * S)))

def text(d, xy, s, sz, col, b=False, anchor='la'):
    d.text((xy[0] * S, xy[1] * S), s, font=f(sz, b), fill=col, anchor=anchor)

def cover(im, c, box, r=12):
    x0, y0, x1, y1 = box
    w, h = int((x1 - x0) * S), int((y1 - y0) * S)
    cw, ch = c.size; side = min(cw, ch)
    c = c.crop(((cw - side) // 2, (ch - side) // 2, (cw + side) // 2, (ch + side) // 2)).resize((w, h))
    m = Image.new('L', (w, h), 0); ImageDraw.Draw(m).rounded_rectangle([0, 0, w, h], r * S, fill=255)
    im.paste(c, (int(x0 * S), int(y0 * S)), m)

# 简单矢量图标(代替 SF Symbols)
def icon(d, kind, cx, cy, col):
    s = S
    X = lambda v: (cx + v[0]) * s
    Y = lambda v: (cy + v[1]) * s
    def P(pts): return [((cx + a) * s, (cy + b) * s) for a, b in pts]
    if kind == 'book': d.rounded_rectangle(P([(-7, -8), (7, 8)])[0] + P([(7, 8)])[0], 2 * s, fill=col); d.line(P([(0, -8), (0, 8)]), fill=(0, 0, 0, 90), width=s)
    elif kind == 'bear': d.ellipse(P([(-7, -5), (7, 9)])[0] + P([(7, 9)])[0], fill=col); d.ellipse(P([(-8, -9), (-3, -4)])[0] + P([(-3, -4)])[0], fill=col); d.ellipse(P([(3, -9), (8, -4)])[0] + P([(8, -4)])[0], fill=col)
    elif kind == 'mic': d.rounded_rectangle(P([(-4, -9), (4, 3)])[0] + P([(4, 3)])[0], 4 * s, fill=col); d.arc(P([(-7, -4), (7, 7)])[0] + P([(7, 7)])[0], 0, 180, fill=col, width=2 * s); d.line(P([(0, 7), (0, 10)]), fill=col, width=2 * s)
    elif kind == 'note': d.ellipse(P([(-8, 3), (-1, 9)])[0] + P([(-1, 9)])[0], fill=col); d.line(P([(-1, 6), (-1, -9)]), fill=col, width=2 * s); d.line(P([(-1, -9), (7, -6)]), fill=col, width=3 * s)
    elif kind == 'col': d.polygon(P([(-9, -4), (0, -10), (9, -4)]), fill=col); [d.rectangle(P([(x, -3), (x + 2, 6)])[0] + P([(x + 2, 6)])[0], fill=col) for x in (-7, -1, 5)]; d.rectangle(P([(-9, 7), (9, 9)])[0] + P([(9, 9)])[0], fill=col)
    elif kind == 'eye': d.ellipse(P([(-10, -6), (10, 6)])[0] + P([(10, 6)])[0], fill=col); d.ellipse(P([(-3, -3), (3, 3)])[0] + P([(3, 3)])[0], fill=(30, 30, 50))
    elif kind == 'globe': d.ellipse(P([(-8, -8), (8, 8)])[0] + P([(8, 8)])[0], outline=col, width=2 * s); d.ellipse(P([(-3, -8), (3, 8)])[0] + P([(3, 8)])[0], outline=col, width=s); d.line(P([(-8, 0), (8, 0)]), fill=col, width=s)
    elif kind == 'leaf': d.ellipse(P([(-8, -8), (8, 4)])[0] + P([(8, 4)])[0], fill=col); d.line(P([(-6, 8), (5, -4)]), fill=(20, 40, 20), width=s)

def glass_btn(im, box, r):
    ov = Image.new('RGBA', im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    rr(d, box, r, (255, 255, 255, 22), (255, 255, 255, 40))
    im.paste(ov, (0, 0), ov)

def status(d):
    text(d, (34, 14), '19:00', 15, 'white', True)
    rr(d, (330, 18, 354, 29), 3, None, (255, 255, 255, 200)); rr(d, (332, 20, 348, 27), 2, 'white')

def dock(im, sel):
    ov = Image.new('RGBA', im.size, (0, 0, 0, 0)); d = ImageDraw.Draw(ov)
    rr(d, (16, 770, 374, 830), 30, (40, 34, 30, 235), (255, 255, 255, 40))
    names = ['发现', '搜索', '书架', '设置']
    for i, n in enumerate(names):
        cx = 16 + 358 / 4 * (i + .5)
        if i == sel: rr(d, (cx - 40, 776, cx + 40, 824), 24, (255, 255, 255, 30))
        col = (242, 140, 56) if i == sel else (255, 255, 255, 150)
        d.ellipse([(cx - 9) * S, 784 * S, (cx + 9) * S, 802 * S], outline=col, width=2 * S)
        text(d, (cx, 808), n, 10.5, col, anchor='ma')
    im.paste(ov, (0, 0), ov)

CATS = [('有声书', 'book', (242, 140, 56)), ('儿童', 'bear', (255, 181, 71)), ('相声评书', 'mic', (226, 87, 76)), ('音乐', 'note', (90, 169, 230)),
        ('历史', 'col', (176, 137, 84)), ('悬疑', 'eye', (108, 123, 217)), ('外语', 'globe', (79, 182, 168)), ('个人成长', 'leaf', (124, 193, 107))]

def home():
    im = canvas().convert('RGBA'); d = ImageDraw.Draw(im)
    status(d)
    y = 47
    text(d, (16, y + 4), '阅听', 34, 'white', True)
    glass_btn(im, (330, y + 4, 374, y + 48), 22); d = ImageDraw.Draw(im)
    d.arc([343 * S, (y + 17) * S, 361 * S, (y + 35) * S], 40, 340, fill='white', width=2 * S)
    y += 62
    glass_btn(im, (16, y, 374, y + 44), 22); d = ImageDraw.Draw(im)
    d.ellipse([32 * S, (y + 14) * S, 46 * S, (y + 28) * S], outline=(255, 255, 255, 140), width=2 * S)
    text(d, (56, y + 12), '搜书名、作者或主播', 14, (255, 255, 255, 110))
    y += 62
    text(d, (16, y), '分类', 24, 'white', True)
    text(d, (360, y + 6), '全部 18', 14, (255, 255, 255, 150), anchor='ra'); d.polygon([(364*S,(y+13)*S),(374*S,(y+13)*S),(369*S,(y+19)*S)], fill=(255,255,255,150))
    y += 42
    gap = 10; cw = (W - 32 - gap * 3) / 4; ch = 78
    for i, (n, k, col) in enumerate(CATS):
        r, c = divmod(i, 4)
        x0 = 16 + c * (cw + gap); y0 = y + r * (ch + gap)
        glass_btn(im, (x0, y0, x0 + cw, y0 + ch), 16); d = ImageDraw.Draw(im)
        bx = x0 + (cw - 34) / 2
        ov = Image.new('RGBA', im.size, (0, 0, 0, 0)); od = ImageDraw.Draw(ov)
        rr(od, (bx, y0 + 11, bx + 34, y0 + 45), 10, col + (60,)); im.paste(ov, (0, 0), ov); d = ImageDraw.Draw(im)
        icon(d, k, bx + 17, y0 + 28, col)
        text(d, (x0 + cw / 2, y0 + 53), n, 12.5, (255, 255, 255, 220), anchor='ma')
    y += 2 * ch + gap + 24
    text(d, (16, y), '继续收听', 24, 'white', True)
    y += 40
    cwid = W * 0.5
    for i in range(2):
        x0 = 16 + i * (cwid + 14)
        glass_btn(im, (x0, y, x0 + cwid, y + 258), 22); d = ImageDraw.Draw(im)
        cover(im, covers[i], (x0 + 12, y + 12, x0 + cwid - 12, y + cwid - 12), 14); d = ImageDraw.Draw(im)
        text(d, (x0 + 12, y + cwid - 2), ['深度睡眠轻音乐', '三国演义'][i], 14, 'white', True)
        text(d, (x0 + 12, y + cwid + 20), ['第 12 集 · 听到 08:21', '第 37 集 · 听到 21:05'][i], 11.5, (255, 255, 255, 130))
        rr(d, (x0 + 12, y + cwid + 42, x0 + cwid - 12, y + cwid + 45), 2, (255, 255, 255, 40))
        rr(d, (x0 + 12, y + cwid + 42, x0 + 12 + (cwid - 24) * (.35 + .3 * i), y + cwid + 45), 2, (242, 140, 56))
    dock(im, 0)
    return im

def catpage():
    im = canvas().convert('RGBA'); d = ImageDraw.Draw(im)
    status(d)
    top = 47
    glass_btn(im, (16, top + 2, 60, top + 46), 22); d = ImageDraw.Draw(im)
    d.line([(41 * S, (top + 15) * S), (34 * S, (top + 24) * S), (41 * S, (top + 33) * S)], fill='white', width=int(2.4 * S))
    text(d, (72, top + 4), '相声评书', 30, 'white', True)
    text(d, (20, top + 54), '按「相声」「评书」「郭德纲」整理', 12.5, (255, 255, 255, 128))
    y = top + 84
    titles = ['德云社侯震相声精选', '单田芳评书·隋唐演义', '郭德纲于谦相声集', '刘兰芳·岳飞传', '袁阔成评书三国', '岳云鹏相声合集',
              '田连元·杨家将', '马三立相声精选', '郭德纲单口相声', '连丽如·东汉演义', '侯宝林相声选', '王玥波评书']
    subs = ['侯震', '单田芳', '郭德纲', '刘兰芳', '袁阔成', '岳云鹏', '田连元', '马三立', '郭德纲', '连丽如', '侯宝林', '王玥波']
    cw = (W - 32 - 24) / 3
    for i in range(12):
        r, c = divmod(i, 3)
        x0 = 16 + c * (cw + 12); y0 = y + r * (cw + 58 + 18)
        if y0 > 770: break
        cover(im, covers[(i + 2) % 6], (x0, y0, x0 + cw, y0 + cw)); d = ImageDraw.Draw(im)
        t = titles[i]
        l1, l2 = t[:7], t[7:]
        text(d, (x0, y0 + cw + 6), l1, 13, (255, 255, 255, 230))
        if l2: text(d, (x0, y0 + cw + 23), l2, 13, (255, 255, 255, 230))
        text(d, (x0, y0 + cw + (42 if l2 else 25)), subs[i], 11, (255, 255, 255, 115))
    return im

a, b = home(), catpage()
pad = 30 * S
out = Image.new('RGB', (W * S * 2 + pad * 3, H * S + pad * 2 + 40 * S), (235, 235, 238))
od = ImageDraw.Draw(out)
for i, (im, cap) in enumerate([(a, '首页 · 分类'), (b, '点进「相声评书」')]):
    x = pad + i * (W * S + pad)
    m = Image.new('L', im.size, 0); ImageDraw.Draw(m).rounded_rectangle([0, 0, W * S, H * S], 44 * S, fill=255)
    out.paste(im.convert('RGB'), (x, pad), m)
    od.text((x + W * S / 2, pad + H * S + 10 * S), cap, font=f(15, True), fill=(40, 40, 40), anchor='ma')
out = out.resize((out.width // 2, out.height // 2), Image.LANCZOS)
out.save(f'{D}/cats.png')
print(out.size)
