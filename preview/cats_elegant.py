import os
D = os.path.dirname(os.path.abspath(__file__))
src = open(f'{D}/cats4.py').read()
exec(src[:src.index('# A 横滑胶囊')])

def blurbg(im, k, box, r, dark=110):
    x0, y0, x1, y1 = box
    w, h = int((x1 - x0) * S), int((y1 - y0) * S)
    c = covers[k % 6]; cw, ch = c.size; side = min(cw, ch)
    c = c.crop(((cw - side) // 2, (ch - side) // 2, (cw + side) // 2, (ch + side) // 2)).resize((max(w, h), max(w, h))).crop((0, 0, w, h))
    c = c.filter(ImageFilter.GaussianBlur(28 * S))
    c = Image.blend(c, Image.new('RGB', c.size, (0, 0, 0)), dark / 255)
    m = Image.new('L', (w, h), 0); ImageDraw.Draw(m).rounded_rectangle([0, 0, w, h], r * S, fill=255)
    im.paste(c, (int(x0 * S), int(y0 * S)), m)

def shadow_cover(im, k, box, r=10):
    x0, y0, x1, y1 = box
    sh = Image.new('RGBA', im.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle([(x0 + 2) * S, (y0 + 6) * S, (x1 + 2) * S, (y1 + 8) * S], r * S, fill=(0, 0, 0, 150))
    sh = sh.filter(ImageFilter.GaussianBlur(8 * S)); im.alpha_composite(sh)
    cover(im, covers[k % 6], box, r)

# E 文字页签 + 精选 + 榜单
def E():
    im = canvas().convert('RGBA'); y = head(im); d = ImageDraw.Draw(im)
    x = 16; sel = 1
    for i, (n, col, _) in enumerate(SECS):
        on = i == sel
        tw = d.textlength(n, font=f(17 if on else 15, on)) / S
        text(d, (x, y + (0 if on else 2)), n, 17 if on else 15, 'white' if on else (255, 255, 255, 110), on)
        if on: rr(d, (x + tw / 2 - 10, y + 30, x + tw / 2 + 10, y + 33), 2, (242, 140, 56))
        x += tw + 22
    y += 50
    blurbg(im, 2, (16, y, 374, y + 200), 24, 90)
    shadow_cover(im, 2, (32, y + 24, 164, y + 156), 14); d = ImageDraw.Draw(im)
    text(d, (182, y + 26), '本周精选', 11.5, (242, 140, 56), True)
    text(d, (182, y + 46), '苗阜王声', 20, 'white', True)
    text(d, (182, y + 74), '青曲社相声全国巡演', 13, (255, 255, 255, 190))
    text(d, (182, y + 94), '第五季 · 现场版', 13, (255, 255, 255, 190))
    text(d, (182, y + 126), '86 集 · 1.2 亿次播放', 11.5, (255, 255, 255, 130))
    rr(d, (32, y + 166, 128, y + 190), 12, (255, 255, 255, 235))
    d.polygon([(46 * S, (y + 172) * S), (46 * S, (y + 184) * S), (55 * S, (y + 178) * S)], fill=(20, 20, 20))
    text(d, (62, y + 170), '立即收听', 12, (20, 20, 20), True)
    y += 222
    text(d, (16, y), '热门榜', 19, 'white', True); text(d, (374, y + 5), '全部 28 ›', 13, (255, 255, 255, 120), anchor='ra')
    y += 36
    names = ['苗阜王声 第六季', '击鼓骂曹 · 武宗亮', '收官福袋', '传统单口相声精选', '评书三国演义']
    for i, n in enumerate(names):
        yy = y + i * 70
        if yy > 740: break
        text(d, (24, yy + 18), str(i + 1), 22, (242, 140, 56) if i < 3 else (255, 255, 255, 90), True, anchor='ma')
        cover(im, covers[(i + 3) % 6], (44, yy, 100, yy + 56), 10); d = ImageDraw.Draw(im)
        text(d, (112, yy + 8), n, 15, 'white', True)
        text(d, (112, yy + 32), f'{[64, 12, 30, 120, 240][i]} 集 · {["8.6", "5.1", "3.3", "2.9", "2.2"][i]} 千万次', 11.5, (255, 255, 255, 120))
        if i < 4: d = overlay(im, lambda od: od.line([(112 * S, (yy + 63) * S), (374 * S, (yy + 63) * S)], fill=(255, 255, 255, 22), width=S))
    dock(im, 0); return im

# F 横向翻页大卡:每类一页,封面虚化做底
def F():
    im = canvas().convert('RGBA'); y = head(im); d = ImageDraw.Draw(im)
    text(d, (16, y), '探索', 24, 'white', True); y += 42
    cw = 300
    for i, k in enumerate([1, 0]):
        x = 16 + i * (cw + 14)
        n, col, books = SECS[[1, 0][i]]
        blurbg(im, k * 2 + 1, (x, y, x + cw, y + 380), 28, 120)
        d = overlay(im, lambda od: rr(od, (x, y, x + cw, y + 380), 28, None, (255, 255, 255, 40)))
        text(d, (x + 22, y + 22), ['CROSSTALK', 'AUDIOBOOK'][i], 11, col, True)
        text(d, (x + 22, y + 40), n, 28, 'white', True)
        text(d, (x + 22, y + 80), ['德云社 · 青曲社 · 传统评书', '言情 · 悬疑 · 都市长篇'][i], 13, (255, 255, 255, 160))
        for j in range(3):
            bx = x + 22 + j * 70; by = y + 128 + (j % 2) * 18
            shadow_cover(im, k * 2 + j + 1, (bx, by, bx + 116, by + 116), 12)
        d = ImageDraw.Draw(im)
        text(d, (x + 22, y + 300), books[0], 15, 'white', True)
        text(d, (x + 22, y + 324), f'等 {[28, 21][i]} 部作品', 12.5, (255, 255, 255, 140))
        d.ellipse([(x + cw - 62) * S, (y + 304) * S, (x + cw - 22) * S, (y + 344) * S], fill=(255, 255, 255, 235))
        d.line([((x + cw - 46) * S, (y + 316) * S), ((x + cw - 38) * S, (y + 324) * S), ((x + cw - 46) * S, (y + 332) * S)], fill=(20, 20, 20), width=int(2.4 * S))
    y += 396
    for i in range(5):
        cx = W / 2 - 32 + i * 16
        rr(d, (cx - (9 if i == 0 else 3), y, cx + (9 if i == 0 else 3), y + 6), 3, 'white' if i == 0 else (255, 255, 255, 70))
    dock(im, 0); return im

# G 书店式目录:每类一行,右侧扇形叠封面,细分隔线
def G():
    im = canvas().convert('RGBA'); y = head(im); d = ImageDraw.Draw(im)
    text(d, (16, y), '分类', 24, 'white', True); y += 46
    subs = ['言情 · 悬疑 · 都市长篇', '德云社 · 青曲社 · 评书', '睡前故事 · 童话 · 儿歌', '科技 · 财经 · 资讯', '怪谈 · 奇闻 · 脱口秀']
    cnt = [21, 28, 31, 29, 30]
    for i, (n, col, _) in enumerate(SECS):
        yy = y + i * 104
        text(d, (16, yy + 22), n, 21, 'white', True)
        text(d, (16, yy + 54), subs[i], 12.5, (255, 255, 255, 125))
        text(d, (16, yy + 74), f'{cnt[i]} 部', 11.5, col, True)
        for j in range(3):
            bx = 238 + j * 34; by = yy + 12 + (2 - j) * 0
            sz = 72 - (2 - j) * 0
            shadow_cover(im, i + j, (bx, yy + 14 + j * 2, bx + 72, yy + 86 + j * 2), 8)
        d = ImageDraw.Draw(im)
        if i < 4: d = overlay(im, lambda od: od.line([(16 * S, (yy + 102) * S), (374 * S, (yy + 102) * S)], fill=(255, 255, 255, 24), width=S))
    dock(im, 0); return im

ims = [(E(), 'E 文字页签 + 精选 + 榜单'), (F(), 'F 翻页大卡'), (G(), 'G 书店目录')]
pad = 30 * S
out = Image.new('RGB', (W * S * 3 + pad * 4, H * S + pad * 2 + 40 * S), (235, 235, 238))
od = ImageDraw.Draw(out)
for i, (im, cap) in enumerate(ims):
    x = pad + i * (W * S + pad)
    m = Image.new('L', im.size, 0); ImageDraw.Draw(m).rounded_rectangle([0, 0, W * S, H * S], 44 * S, fill=255)
    out.paste(im.convert('RGB'), (x, pad), m)
    od.text((x + W * S / 2, pad + H * S + 10 * S), cap, font=f(16, True), fill=(30, 30, 30), anchor='ma')
out = out.resize((out.width // 2, out.height // 2), Image.LANCZOS)
out.save(f'{D}/cats_elegant.png'); print(out.size)
