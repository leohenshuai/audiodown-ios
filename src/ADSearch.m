#import "AD.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import "ADInternal.h"

// ───────────── 搜索结果行 ─────────────
@interface ADSearchCell : UICollectionViewCell
- (void)fill:(ADAlbum *)a keyword:(NSString *)kw;
@end
@implementation ADSearchCell {
    UIView *_card;
    UIImageView *_cover, *_chev;
    UILabel *_title, *_sub, *_meta;
    UILabel *_p[3];
}
- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        _card = [UIView new];
        [ADLiquid glassLite:_card radius:20];
        [self.contentView addSubview:_card];
        _cover = [UIImageView new];
        _cover.layer.cornerRadius = 12; _cover.clipsToBounds = YES;
        _cover.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
        _title = [ADUtil label:nil size:16 color:UIColor.whiteColor]; _title.numberOfLines = 1;
        _sub = [ADUtil label:nil size:12.5 color:[UIColor colorWithWhite:1 alpha:0.7]]; _sub.numberOfLines = 1;
        _meta = [ADUtil label:nil size:11.5 color:[UIColor colorWithWhite:1 alpha:0.45]]; _meta.numberOfLines = 1;
        _chev = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightSemibold]]];
        _chev.tintColor = [UIColor colorWithWhite:1 alpha:0.28];
        for (UIView *v in @[_cover, _title, _sub, _meta, _chev]) [_card addSubview:v];
        for (int i = 0; i < 3; i++) {
            UILabel *l = [ADUtil label:nil size:10.5 color:UIColor.whiteColor];
            l.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightSemibold];
            l.numberOfLines = 1; l.textAlignment = NSTextAlignmentCenter;
            l.layer.cornerRadius = 9; l.clipsToBounds = YES; l.hidden = YES;
            [_card addSubview:l]; _p[i] = l;
        }
    }
    return self;
}
- (void)setHighlighted:(BOOL)h {
    [super setHighlighted:h];
    [UIView animateWithDuration:h ? 0.12 : 0.38 delay:0 usingSpringWithDamping:h ? 1 : 0.6 initialSpringVelocity:0
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ self.transform = h ? CGAffineTransformMakeScale(0.975, 0.975) : CGAffineTransformIdentity; } completion:nil];
}
- (void)fill:(ADAlbum *)a keyword:(NSString *)kw {
    [ADUtil cover:_cover url:a.cover];
    NSDictionary *base = @{NSFontAttributeName: [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold], NSForegroundColorAttributeName: UIColor.whiteColor};
    NSMutableAttributedString *as = [[NSMutableAttributedString alloc] initWithString:a.title ?: @"" attributes:base];
    if (kw.length && a.title.length) {
        NSRange r = [a.title rangeOfString:kw options:NSCaseInsensitiveSearch];
        if (r.location != NSNotFound) [as addAttribute:NSForegroundColorAttributeName value:[ADUtil brand] range:r];
    }
    _title.attributedText = as;
    NSString *who = a.anchor.length ? a.anchor : (a.author.length ? a.author : @"");
    _sub.text = who.length ? who : @"有声书";
    NSMutableArray *bits = [NSMutableArray array];
    if (a.trackCount > 0) [bits addObject:[NSString stringWithFormat:@"%ld 集", (long)a.trackCount]];
    if (a.playCount > 0) [bits addObject:[NSString stringWithFormat:@"%@播放", [ADUtil count:a.playCount]]];
    if (a.provider.length) [bits addObject:a.provider];
    _meta.text = [bits componentsJoinedByString:@" · "];
    ADStore *st = [ADStore shared];
    NSMutableArray *tags = [NSMutableArray array];   // @[文字, 是否强调]
    if ([st isAlbumDone:a.albumId]) [tags addObject:@[@"已听完", @YES]];
    if (a.isPaid) [tags addObject:@[@"VIP", @YES]];
    if ([st isFavorite:a.albumId]) [tags addObject:@[@"已收藏", @NO]];
    ADTask *tk = [[ADDownloader shared] taskForAlbum:a.albumId];
    if (tk && tk.done > 0) [tags addObject:@[@"已缓存", @NO]];
    for (int i = 0; i < 3; i++) {
        UILabel *l = _p[i];
        if (i < (NSInteger)tags.count) {
            BOOL hot = [tags[i][1] boolValue];
            l.text = tags[i][0]; l.hidden = NO;
            l.backgroundColor = hot ? [ADUtil brand] : [UIColor colorWithWhite:1 alpha:0.12];
            l.textColor = hot ? UIColor.whiteColor : [UIColor colorWithWhite:1 alpha:0.78];
        } else l.hidden = YES;
    }
    [self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat W = self.contentView.bounds.size.width, H = self.contentView.bounds.size.height;
    _card.frame = CGRectMake(12, 4, W - 24, H - 8);
    CGFloat cw = _card.bounds.size.width, ch = _card.bounds.size.height;
    _cover.frame = CGRectMake(12, (ch - 76) / 2, 76, 76);
    CGFloat x = 102, tw = cw - x - 30;
    _title.frame = CGRectMake(x, 12, tw, 20);
    _sub.frame = CGRectMake(x, 34, tw, 16);
    _meta.frame = CGRectMake(x, 52, tw, 16);
    _chev.frame = CGRectMake(cw - 26, (ch - 14) / 2, 14, 14);
    CGFloat px = x;
    for (int i = 0; i < 3; i++) {
        UILabel *l = _p[i]; if (l.hidden) continue;
        CGSize sz = [l.text sizeWithAttributes:@{NSFontAttributeName: l.font}];
        l.frame = CGRectMake(px, ch - 12 - 18, sz.width + 16, 18);
        px += sz.width + 16 + 6;
    }
}
@end

// ───────────── 搜索 ─────────────
@interface ADSearchController () <UICollectionViewDataSource, UICollectionViewDelegate, UISearchBarDelegate, UIScrollViewDelegate>
@property (nonatomic, strong) UISearchBar *bar;
@property (nonatomic, strong) UICollectionView *cv;
@property (nonatomic, strong) NSMutableArray<ADAlbum *> *list;
@property (nonatomic, assign) NSInteger page;
@property (nonatomic, assign) BOOL loading, more;
@property (nonatomic, copy) NSString *keyword;
@property (nonatomic, strong) UILabel *hint;
@property (nonatomic, strong) UIScrollView *cats;
@property (nonatomic, strong) UISegmentedControl *seg;
@property (nonatomic, assign) BOOL localMode;
@property (nonatomic, assign) NSInteger catIndex;
@property (nonatomic, assign) NSInteger autoPages;
@property (nonatomic, strong) NSMutableArray *chips;
@property (nonatomic, strong) UIScrollView *panel;
@property (nonatomic, strong) NSArray<ADAlbum *> *recs;
@property (nonatomic, strong) NSMutableArray<NSString *> *history;
@end

@implementation ADSearchController
- (void)viewDidLoad {
    [super viewDidLoad];
    [ADLiquid canvas:self.view];
    self.navigationController.navigationBar.hidden = YES;
    UILabel *stitle = [ADUtil label:@"PingFangSC-Semibold" size:34 color:UIColor.whiteColor];
    stitle.text = @"搜索"; stitle.tag = 76; stitle.numberOfLines = 1;
    [self.view addSubview:stitle];
    UIView *spill = [UIView new];
    spill.tag = 77; spill.userInteractionEnabled = NO;
    [ADLiquid glassLite:spill radius:22];
    [self.view addSubview:spill];
    self.bar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
    self.bar.placeholder = @"书名 / 作者 / 主播";
    self.bar.searchBarStyle = UISearchBarStyleMinimal;
    self.bar.delegate = self;
    self.bar.tintColor = [ADUtil brand];
    self.bar.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [self.bar setSearchFieldBackgroundImage:[UIImage new] forState:UIControlStateNormal];
    self.bar.backgroundImage = [UIImage new];
    self.bar.searchTextField.textColor = UIColor.whiteColor;
    self.bar.searchTextField.backgroundColor = UIColor.clearColor;
    [self.view addSubview:self.bar];
    [self layoutChrome];
    CGFloat w = (self.view.bounds.size.width - 16 * 2 - 12 * 2) / 3;
    (void)w;
    UICollectionViewFlowLayout *lo = [UICollectionViewFlowLayout new];
    lo.itemSize = CGSizeMake(self.view.bounds.size.width, 108);
    lo.minimumInteritemSpacing = 0;
    lo.minimumLineSpacing = 0;
    self.cv = [[UICollectionView alloc] initWithFrame:CGRectMake(0, 108, self.view.bounds.size.width, self.view.bounds.size.height - 108) collectionViewLayout:lo];
    self.cv.backgroundColor = UIColor.clearColor;
    self.cv.contentInset = UIEdgeInsetsMake(4, 0, 140, 0);
    self.cv.dataSource = self; self.cv.delegate = self;
    [self.cv registerClass:ADSearchCell.class forCellWithReuseIdentifier:@"c"];
    self.cv.refreshControl = [[UIRefreshControl alloc] init];
    self.cv.refreshControl.tintColor = [UIColor colorWithWhite:1 alpha:0.5];
    [self.cv.refreshControl addTarget:self action:@selector(refreshSearch) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.cv];
    self.hint = [ADUtil label:nil size:14 color:[UIColor colorWithWhite:1 alpha:0.5]];
    self.hint.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.hint];
    self.list = [NSMutableArray array];
    self.seg = [[UISegmentedControl alloc] initWithItems:@[@"在线", @"本地"]];
    self.seg.selectedSegmentIndex = 0;
    self.seg.frame = CGRectMake(16, 0, 130, 32);
    if (@available(iOS 13.0, *)) {
        self.seg.selectedSegmentTintColor = [ADUtil brand];
        self.seg.backgroundColor = [UIColor colorWithWhite:1 alpha:0.1];
    }
    [self.seg setTitleTextAttributes:@{NSForegroundColorAttributeName: UIColor.whiteColor} forState:UIControlStateSelected];
    [self.seg setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:0.7]} forState:UIControlStateNormal];
    [self.seg addTarget:self action:@selector(switchMode) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.seg];

    self.cats = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 40)];
    self.cats.showsHorizontalScrollIndicator = NO;
    self.cats.contentInset = UIEdgeInsetsMake(0, 12, 0, 12);
    [self.view addSubview:self.cats];
    [self buildChips];

    self.panel = [[UIScrollView alloc] initWithFrame:CGRectZero];
    self.panel.backgroundColor = UIColor.clearColor;
    self.panel.showsVerticalScrollIndicator = NO;
    self.panel.contentInset = UIEdgeInsetsMake(0, 0, 140, 0);
    [self.view addSubview:self.panel];
    [self rebuildPanel];
    [self loadRecs];
    [self updatePanel];
}

- (void)switchMode {
    self.localMode = (self.seg.selectedSegmentIndex == 1);
    [self layoutChrome];
    [self updatePanel];
    self.page = 1;
    self.autoPages = 0;
    if (self.localMode) {
        [self.bar resignFirstResponder];
        self.bar.placeholder = @"搜索本机下载、书架、历史";
        [self.cv reloadData];
        self.hint.text = [self visible].count ? @"" : @"本机还没有内容，先在专辑页「缓存到本机」或收藏";
    } else {
        self.bar.placeholder = @"书名 / 作者 / 主播";
        if (self.keyword.length) { [self.list removeAllObjects]; self.more = YES; [self loadPage]; }
        else { [self.cv reloadData]; self.hint.text = @""; }
    }
    [self paintChips];
}

- (NSArray<ADAlbum *> *)localAlbums {
    NSMutableArray *arr = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (ADTask *t in [ADDownloader shared].tasks) {
        if (!t.albumId.length || [seen containsObject:t.albumId]) continue;
        ADAlbum *a = [ADAlbum new];
        a.albumId = t.albumId;
        a.title = t.title.length ? t.title : t.albumId;
        a.cover = t.cover;
        [arr addObject:a];
        [seen addObject:t.albumId];
    }
    for (ADAlbum *a in [ADStore shared].favorites)
        if (![seen containsObject:a.albumId]) { [arr addObject:a]; [seen addObject:a.albumId]; }
    for (ADAlbum *a in [ADStore shared].history)
        if (![seen containsObject:a.albumId]) { [arr addObject:a]; [seen addObject:a.albumId]; }
    return arr;
}

- (void)searchBar:(UISearchBar *)b textDidChange:(NSString *)t {
    NSString *q = [t stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (self.localMode) {
        [self.cv reloadData];
        self.hint.text = [self visible].count ? @"" : (q.length ? @"本机没有匹配的内容" : @"本机还没有内容，先在专辑页「缓存到本机」或收藏");
        self.hint.hidden = self.hint.text.length == 0;
        return;
    }
    if (!q.length) {
        // 清空搜索词：结果要跟着清掉，回到「历史/热词/推荐」面板
        self.keyword = @"";
        [self.list removeAllObjects];
        self.page = 1;
        self.more = NO;
        self.autoPages = 0;
        self.hint.text = @"";
        [self.cv reloadData];
        [self updatePanel];
    }
}


- (NSCharacterSet *)noiseChars {
    static NSCharacterSet *cs; static dispatch_once_t once;
    dispatch_once(&once, ^{
        cs = [NSCharacterSet characterSetWithCharactersInString:@" ，,、|｜·•:：;；!！?？.。《》<>「」【】()（）[]-—_/\\\"'’“”\n\t"];
    });
    return cs;
}

- (NSString *)normText:(NSString *)s {
    if (!s.length) return @"";
    NSArray *parts = [s componentsSeparatedByCharactersInSet:[self noiseChars]];
    return [[parts componentsJoinedByString:@""] lowercaseString];
}

- (NSInteger)relevanceOf:(ADAlbum *)a {
    NSString *kw = self.keyword ?: @"";
    NSString *nk = [self normText:kw];
    if (!nk.length) return 0;
    NSString *nt = [self normText:a.title ?: @""];
    if ([nt containsString:nk]) return 0;               // 完整关键词命中（忽略空格标点）
    NSMutableArray *tokens = [NSMutableArray array];
    for (NSString *t in [kw componentsSeparatedByCharactersInSet:[self noiseChars]]) {
        NSString *n = [self normText:t];
        if (n.length) [tokens addObject:n];
    }
    NSInteger miss = 0;
    for (NSString *t in tokens) if (![nt containsString:t]) miss += 1;
    return 1 + miss;                                    // 命中词越多越靠前
}

- (NSArray *)catTitles {
    return @[@"全部", @"有声书", @"相声评书", @"音乐", @"儿童", @"历史", @"外语", @"个人成长"];
}

- (NSArray *)catWords:(NSInteger)i {
    NSArray *map = @[@[], @[],
                     @[@"相声", @"评书", @"单口", @"德云", @"郭德纲", @"小品", @"段子", @"说书"],
                     @[@"音乐", @"钢琴", @"古筝", @"纯音乐", @"轻音乐", @"歌曲", @"助眠", @"白噪音", @"吉他", @"睡眠"],
                     @[@"儿童", @"宝宝", @"睡前", @"童话", @"儿歌", @"绘本", @"成语", @"幼儿"],
                     @[@"历史", @"史", @"三国", @"明", @"清", @"唐", @"宋", @"通史", @"春秋", @"帝王"],
                     @[@"英语", @"日语", @"韩语", @"口语", @"单词", @"雅思", @"托福", @"听力", @"法语"],
                     @[@"成长", @"职场", @"情商", @"自律", @"思维", @"沟通", @"心理", @"认知"]];
    return (i >= 0 && i < (NSInteger)map.count) ? map[i] : @[];
}

- (void)buildChips {
    for (UIView *v in self.cats.subviews) [v removeFromSuperview];
    NSArray *titles = [self catTitles];
    CGFloat x = 12;
    for (NSInteger i = 0; i < (NSInteger)titles.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.tag = 100 + i;
        b.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        [b setTitle:titles[i] forState:UIControlStateNormal];
        CGSize sz = [titles[i] sizeWithAttributes:@{NSFontAttributeName: b.titleLabel.font}];
        CGFloat w = sz.width + 26;
        b.frame = CGRectMake(x, 6, w, 30);
        b.layer.cornerRadius = 15;
        [b addTarget:self action:@selector(tapChip:) forControlEvents:UIControlEventTouchUpInside];
        [self.cats addSubview:b];
        x += w + 8;
    }
    self.cats.contentSize = CGSizeMake(x + 4, 40);
    [self paintChips];
}

- (void)paintChips {
    NSArray *titles = [self catTitles];
    for (NSInteger i = 0; i < (NSInteger)titles.count; i++) {
        UIButton *b = (UIButton *)[self.cats viewWithTag:100 + i];
        BOOL on = (i == self.catIndex);
        b.backgroundColor = on ? [ADUtil brand] : [UIColor colorWithWhite:1 alpha:0.1];
        [b setTitleColor:(on ? UIColor.whiteColor : [UIColor colorWithWhite:1 alpha:0.72]) forState:UIControlStateNormal];
    }
}

- (void)tapChip:(UIButton *)b {
    [ADHaptic select];
    self.catIndex = b.tag - 100;
    [self paintChips];
    [self.cv reloadData];
    if (self.catIndex != 0 && self.list.count && [self visible].count < 6 && self.more) {
        self.autoPages = 0;
        [self loadPage];
    }
}

- (NSString *)hayOf:(ADAlbum *)a {
    return [NSString stringWithFormat:@"%@ %@ %@ %@", a.title ?: @"", a.anchor ?: @"", a.author ?: @"", a.intro ?: @""];
}

- (BOOL)titleMatches:(ADAlbum *)a category:(NSInteger)idx {
    NSArray *words = [self catWords:idx];
    if (!words.count) return NO;
    NSString *hay = [self hayOf:a];
    for (NSString *w in words) if ([hay rangeOfString:w].location != NSNotFound) return YES;
    return NO;
}

- (BOOL)catMatch:(ADAlbum *)a {
    if (self.catIndex == 0) return YES;
    if (self.catIndex == 1) {
        // 这个服务本身就是有声书库，「有声书」= 不属于其他分类的全部内容
        for (NSInteger i = 2; i < (NSInteger)[self catTitles].count; i++) {
            if ([self titleMatches:a category:i]) return NO;
        }
        return YES;
    }
    return [self titleMatches:a category:self.catIndex];
}

- (NSArray<ADAlbum *> *)visible {
    if (self.localMode) {
        NSString *q = [[self.bar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] lowercaseString];
        NSArray *all = [self localAlbums];
        if (!q.length) return all;
        NSMutableArray *arr = [NSMutableArray array];
        for (ADAlbum *a in all) {
            NSString *hay = [[NSString stringWithFormat:@"%@ %@ %@", a.title ?: @"", a.anchor ?: @"", a.author ?: @""] lowercaseString];
            if ([hay rangeOfString:q].location != NSNotFound) [arr addObject:a];
        }
        return arr;
    }
    if (self.catIndex == 0) return self.list;
    NSMutableArray *arr = [NSMutableArray array];
    for (ADAlbum *a in self.list) {
        // 关键词完全命中的结果永远保留，避免切分类后把要的书过滤掉
        if ([self catMatch:a] || [self relevanceOf:a] == 0) [arr addObject:a];
    }
    return arr;
}
// ── 空状态面板：搜索历史 / 热门搜索 / 推荐收听 ──
- (NSMutableArray<NSString *> *)history {
    if (!_history) {
        NSArray *a = [NSUserDefaults.standardUserDefaults arrayForKey:@"ad_search_history"];
        _history = a ? [a mutableCopy] : [NSMutableArray array];
    }
    return _history;
}

- (void)rememberKeyword:(NSString *)k {
    if (!k.length) return;
    [self.history removeObject:k];
    [self.history insertObject:k atIndex:0];
    while (self.history.count > 12) [self.history removeLastObject];
    [NSUserDefaults.standardUserDefaults setObject:self.history forKey:@"ad_search_history"];
    [self rebuildPanel];
}

- (NSArray<NSString *> *)hotWords {
    return @[@"郭德纲", @"三国演义", @"睡前故事", @"白噪音", @"英语听力",
             @"鬼吹灯", @"明朝那些事", @"儿童成语", @"盗墓笔记", @"助眠轻音乐"];
}

- (CGFloat)addChips:(NSArray<NSString *> *)words atY:(CGFloat)y tagBase:(NSInteger)base {
    UIFont *f = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    CGFloat x = 16, maxX = self.view.bounds.size.width - 16;
    for (NSInteger i = 0; i < (NSInteger)words.count; i++) {
        NSString *w = words[i];
        CGSize sz = [w sizeWithAttributes:@{NSFontAttributeName: f}];
        CGFloat bw = sz.width + 26;
        if (x + bw > maxX) { x = 16; y += 38; }
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(x, y, bw, 30);
        b.tag = base + i;
        b.titleLabel.font = f;
        [b setTitle:w forState:UIControlStateNormal];
        [b setTitleColor:[UIColor colorWithWhite:1 alpha:0.85] forState:UIControlStateNormal];
        b.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
        b.layer.cornerRadius = 15;
        b.layer.borderWidth = 0.6; b.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.12].CGColor;
        [b addTarget:self action:@selector(tapWord:) forControlEvents:UIControlEventTouchUpInside];
        [self.panel addSubview:b];
        x += bw + 8;
    }
    return y + 30;
}

- (void)rebuildPanel {
    for (UIView *v in self.panel.subviews) [v removeFromSuperview];
    CGFloat W = self.view.bounds.size.width;
    CGFloat y = 6;

    if (self.history.count) {
        UILabel *t = [ADUtil label:@"PingFangSC-Semibold" size:15 color:UIColor.whiteColor];
        t.text = @"搜索历史";
        t.frame = CGRectMake(16, y, 160, 22);
        [self.panel addSubview:t];

        UIButton *clr = [UIButton buttonWithType:UIButtonTypeSystem];
        clr.frame = CGRectMake(W - 72, y - 4, 56, 30);
        clr.titleLabel.font = [UIFont systemFontOfSize:13];
        [clr setTitle:@"清空" forState:UIControlStateNormal];
        [clr setTitleColor:[ADUtil dim] forState:UIControlStateNormal];
        [clr addTarget:self action:@selector(clearHistory) forControlEvents:UIControlEventTouchUpInside];
        [self.panel addSubview:clr];
        y += 30;
        y = [self addChips:self.history atY:y tagBase:1000];
        y += 16;
    }

    UILabel *h = [ADUtil label:@"PingFangSC-Semibold" size:15 color:UIColor.whiteColor];
    h.text = @"大家都在搜";
    h.frame = CGRectMake(16, y, 200, 22);
    [self.panel addSubview:h];
    y += 30;
    y = [self addChips:self.hotWords atY:y tagBase:2000];
    y += 22;

    if (self.recs.count) {
        UILabel *r = [ADUtil label:@"PingFangSC-Semibold" size:15 color:UIColor.whiteColor];
        r.text = @"推荐收听";
        r.frame = CGRectMake(16, y, 200, 22);
        [self.panel addSubview:r];
        y += 32;
        for (NSInteger i = 0; i < (NSInteger)self.recs.count; i++) {
            ADAlbum *a = self.recs[i];
            UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom];
            row.frame = CGRectMake(16, y, W - 32, 62);
            [ADLiquid glassLite:row radius:16];
            row.tag = 3000 + i;
            [row addTarget:self action:@selector(tapRec:) forControlEvents:UIControlEventTouchUpInside];

            UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(8, 7, 48, 48)];
            iv.layer.cornerRadius = 9;
            iv.clipsToBounds = YES;
            iv.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
            [ADUtil cover:iv url:a.cover];
            [row addSubview:iv];

            UILabel *t = [ADUtil label:nil size:14 color:UIColor.whiteColor];
            t.frame = CGRectMake(66, 9, W - 32 - 66 - 34, 20);
            t.numberOfLines = 1;
            t.text = a.title;
            [row addSubview:t];

            UILabel *sub = [ADUtil label:nil size:11 color:[ADUtil dim]];
            sub.frame = CGRectMake(66, 31, W - 32 - 66 - 34, 18);
            sub.text = [NSString stringWithFormat:@"%@%@", a.anchor.length ? a.anchor : @"有声书",
                        a.trackCount > 0 ? [NSString stringWithFormat:@" · %ld 集", (long)a.trackCount] : @""];
            [row addSubview:sub];

            UIImageView *chev = [[UIImageView alloc] initWithFrame:CGRectMake(W - 32 - 28, 23, 16, 16)];
            chev.image = [UIImage systemImageNamed:@"chevron.right" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightSemibold]];
            chev.tintColor = [UIColor colorWithWhite:1 alpha:0.3];
            [row addSubview:chev];

            [self.panel addSubview:row];
            y += 70;
        }
    }

    self.panel.contentSize = CGSizeMake(W, y + 20);
}

- (void)loadRecs {
    __weak typeof(self) w = self;
    [[ADApi shared] discover:^(NSArray<NSDictionary *> *sections, BOOL cached, NSString *err) {
        __strong typeof(w) self = w; if (!self) return;
        NSMutableArray *arr = [NSMutableArray array];
        NSMutableSet *seen = [NSMutableSet set];
        for (NSDictionary *sec in sections) {
            NSArray *its = sec[@"items"];
            if (![its isKindOfClass:NSArray.class]) continue;
            for (id o in its) {
                ADAlbum *a = [ADAlbum fromJSON:o];
                if (!a || [seen containsObject:a.albumId]) continue;
                [seen addObject:a.albumId];
                [arr addObject:a];
                if (arr.count >= 6) break;
            }
            if (arr.count >= 6) break;
        }
        self.recs = arr;
        [self rebuildPanel];
    }];
}

- (void)clearHistory {
    [self.history removeAllObjects];
    [NSUserDefaults.standardUserDefaults setObject:@[] forKey:@"ad_search_history"];
    [self rebuildPanel];
}

- (void)tapWord:(UIButton *)b {
    [ADHaptic tap];
    NSInteger tag = b.tag;
    NSString *word = nil;
    if (tag >= 2000 && tag < 3000) {
        NSArray *hw = [self hotWords];
        NSInteger i = tag - 2000;
        if (i < (NSInteger)hw.count) word = hw[i];
    } else if (tag >= 1000 && tag < 2000) {
        NSInteger i = tag - 1000;
        if (i < (NSInteger)self.history.count) word = self.history[i];
    }
    if (word.length) [self startSearch:word];
}

- (void)tapRec:(UIButton *)b {
    [ADHaptic tap];
    NSInteger i = b.tag - 3000;
    if (i < 0 || i >= (NSInteger)self.recs.count) return;
    ADAlbumController *vc = [ADAlbumController new];
    vc.album = self.recs[i];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)startSearch:(NSString *)q {
    [ADHaptic heavy];
    q = [q stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (!q.length) return;
    self.localMode = NO;
    self.seg.selectedSegmentIndex = 0;
    self.bar.text = q;
    [self.bar resignFirstResponder];
    self.keyword = q;
    self.page = 1;
    self.more = YES;
    self.autoPages = 0;
    self.list = [NSMutableArray array];
    if (self.catIndex != 0) { self.catIndex = 0; [self paintChips]; }
    [self.cv reloadData];
    self.hint.text = @"搜索中…";
    self.hint.hidden = NO;
    [self rememberKeyword:q];
    [self updatePanel];
    [self loadPage];
}

- (void)updatePanel {
    BOOL show = (!self.localMode && self.keyword.length == 0);
    self.panel.hidden = !show;
    self.cv.hidden = show;
    if (show) self.hint.hidden = YES;
}

- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; self.navigationController.navigationBar.hidden = YES; [self layoutChrome]; }
- (void)layoutChrome {
    CGFloat top = MAX(self.view.safeAreaInsets.top, 47);
    CGFloat W = self.view.bounds.size.width;
    [self.view viewWithTag:76].frame = CGRectMake(16, top - 4, 120, 42);
    self.seg.frame = CGRectMake(W - 16 - 130, top + 2, 130, 32);
    [self.view viewWithTag:77].frame = CGRectMake(16, top + 46, W - 32, 44);
    self.bar.frame = CGRectMake(10, top + 46, W - 20, 44);
    self.cats.frame = CGRectMake(0, top + 98, W, 40);
    self.cats.hidden = self.localMode;
    CGFloat gridTop = self.localMode ? top + 98 : top + 138;
    self.cv.frame = CGRectMake(0, gridTop, W, self.view.bounds.size.height - gridTop);
    UICollectionViewFlowLayout *lo = (UICollectionViewFlowLayout *)self.cv.collectionViewLayout;
    if ([lo isKindOfClass:UICollectionViewFlowLayout.class] && lo.itemSize.width != W) { lo.itemSize = CGSizeMake(W, 108); [lo invalidateLayout]; }
    self.panel.frame = self.cv.frame;
}
- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    self.hint.frame = CGRectMake(30, self.view.bounds.size.height / 2, self.view.bounds.size.width - 60, 40);
    [ADMiniBar.shared refresh];
}
- (void)searchBarSearchButtonClicked:(UISearchBar *)b {
    [b resignFirstResponder];
    if (self.localMode) { [self.cv reloadData]; return; }
    [self startSearch:b.text];
}
- (void)refreshSearch {
    [self.cv.refreshControl endRefreshing];
    if (!self.keyword.length) return;
    self.page = 1;
    [self.list removeAllObjects];
    [self loadPage];
}

- (void)loadPage {
    if (self.loading || !self.more) return;
    self.loading = YES;
    __weak typeof(self) w = self;
    [[ADApi shared] search:self.keyword page:self.page done:^(NSArray<ADAlbum *> *list, BOOL more, BOOL cached, NSString *err) {
        __strong typeof(w) self = w; if (!self) return;
        self.loading = NO;
        self.more = list.count > 0;
        if (list.count) {
            if (self.page == 1) [self.list removeAllObjects];
            [self.list addObjectsFromArray:list];
            self.page += 1;
        }
        NSInteger hits = 0;
        for (ADAlbum *a in self.list) if ([self relevanceOf:a] == 0) hits += 1;
        if (hits == 0 && self.more && self.autoPages < 2) {
            // 第一屏没有标题含关键词的，自动再翻两页
            self.autoPages += 1;
            [self loadPage];
        }
        if (self.keyword.length) {
            [self.list sortUsingComparator:^NSComparisonResult(ADAlbum *x, ADAlbum *y) {
                NSInteger sx = [self relevanceOf:x], sy = [self relevanceOf:y];
                if (sx == sy) return NSOrderedSame;
                return sx < sy ? NSOrderedAscending : NSOrderedDescending;
            }];
        }
        NSArray *shown = [self visible];
        if (self.catIndex != 0 && shown.count < 6 && self.more && self.autoPages < 6) {
            self.autoPages += 1;
            [self loadPage];
        }
        self.hint.text = (self.list.count ? (shown.count ? @"" : @"这个分类里没有结果，换个分类或关键词") : (err ?: @"没有找到"));
        [self.cv reloadData];
    }];
}
- (void)scrollViewDidScroll:(UIScrollView *)s {
    if (s.contentOffset.y + s.bounds.size.height > s.contentSize.height - 300) [self loadPage];
    static CGFloat lastY = 0;
    [ADLiquid followScroll:s lastY:&lastY];
}
- (void)scrollViewDidEndDecelerating:(UIScrollView *)s {
    [UIView animateWithDuration:0.3 animations:^{ ADNavDock.shared.transform = CGAffineTransformIdentity; ADNavDock.shared.alpha = 1; }];
}
- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)s { return [self visible].count; }
- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    ADSearchCell *cell = [cv dequeueReusableCellWithReuseIdentifier:@"c" forIndexPath:ip];
    NSArray *vis = [self visible];
    if (ip.item >= (NSInteger)vis.count) return cell;
    NSString *kw = self.localMode ? [self.bar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] : self.keyword;
    [cell fill:vis[ip.item] keyword:kw];
    return cell;
}
- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    [ADHaptic tap];
    ADAlbumController *vc = [ADAlbumController new];
    vc.album = [self visible][ip.item];
    [self.navigationController pushViewController:vc animated:YES];
}
@end
