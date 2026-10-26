#import "AD.h"

// 分段式下载面板：按 20 集一段折叠，点开分段可选单集；可整段勾选，也可只选几集
#define kSeg 20

@interface ADDLSheet ()
@property (nonatomic, strong) ADAlbum *album;
@property (nonatomic, strong) NSArray<ADTrack *> *tracks;
@property (nonatomic, assign) NSInteger total;
@property (nonatomic, strong) NSMutableSet<NSString *> *picked;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *open;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UILabel *head, *src, *cur, *cnt, *hint;
@property (nonatomic, strong) UIButton *dlAll, *dlPick;
@property (nonatomic, assign) BOOL filling, closed;
@property (nonatomic, copy) NSString *currentTitle;
@end

@implementation ADDLSheet

+ (void)presentFrom:(UIViewController *)vc album:(ADAlbum *)a tracks:(NSArray<ADTrack *> *)tracks total:(NSInteger)total {
    ADDLSheet *s = [ADDLSheet new];
    s.album = a; s.tracks = tracks ?: @[]; s.total = MAX(total, (NSInteger)tracks.count);
    s.modalPresentationStyle = UIModalPresentationPageSheet;
    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sp = s.sheetPresentationController;
        sp.detents = @[UISheetPresentationControllerDetent.largeDetent];
        sp.prefersGrabberVisible = YES;
        sp.preferredCornerRadius = 28;
    }
    [vc presentViewController:s animated:YES completion:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.055 green:0.05 blue:0.06 alpha:1];
    self.picked = [NSMutableSet set];
    self.open = [NSMutableSet set];
    ADPlayer *p = ADPlayer.shared;
    BOOL same = p.album && [p.album.albumId isEqualToString:self.album.albumId];
    self.currentTitle = same ? p.current.title : [[ADStore shared] lastInfoOf:self.album.albumId][@"title"];

    self.head = [ADUtil label:@"PingFangSC-Semibold" size:24 color:UIColor.whiteColor];
    self.head.text = @"下载"; self.head.numberOfLines = 1;
    UIView *bar = [UIView new]; bar.tag = 5; bar.backgroundColor = UIColor.whiteColor; bar.layer.cornerRadius = 2;
    self.src = [ADUtil label:nil size:15 color:[UIColor colorWithWhite:1 alpha:0.55]]; self.src.numberOfLines = 1;
    self.cur = [ADUtil label:nil size:15 color:[UIColor colorWithWhite:1 alpha:0.55]]; self.cur.numberOfLines = 1;
    self.cnt = [ADUtil label:@"PingFangSC-Semibold" size:20 color:UIColor.whiteColor]; self.cnt.numberOfLines = 1;
    self.hint = [ADUtil label:nil size:13 color:[UIColor colorWithWhite:1 alpha:0.45]]; self.hint.numberOfLines = 1;
    for (UIView *v in @[self.head, bar, self.src, self.cur, self.cnt, self.hint]) [self.view addSubview:v];

    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.table.backgroundColor = UIColor.clearColor;
    self.table.separatorColor = [UIColor colorWithWhite:1 alpha:0.1];
    self.table.separatorInset = UIEdgeInsetsMake(0, 56, 0, 0);
    self.table.dataSource = self; self.table.delegate = self;
    self.table.contentInset = UIEdgeInsetsMake(0, 0, 100, 0);
    [self.view addSubview:self.table];

    self.dlAll = [self pill:@"下载本书" filled:NO action:@selector(downloadAll)];
    self.dlPick = [self pill:@"选集下载" filled:YES action:@selector(downloadPicked)];
    [self.view addSubview:self.dlAll]; [self.view addSubview:self.dlPick];

    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload) name:@"ADDownloadChanged" object:nil];
    [self refreshTexts];
    [self fillCatalog];
}

- (UIButton *)pill:(NSString *)t filled:(BOOL)f action:(SEL)a {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.layer.cornerRadius = 28; b.layer.borderWidth = 1.2;
    b.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
    [b setTitle:t forState:UIControlStateNormal];
    b.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.75].CGColor;
    [b addTarget:self action:a forControlEvents:UIControlEventTouchUpInside];
    [b addTarget:self action:@selector(down:) forControlEvents:UIControlEventTouchDown];
    [b addTarget:self action:@selector(up:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    return b;
}
- (void)down:(UIView *)b { [UIView animateWithDuration:0.12 animations:^{ b.transform = CGAffineTransformMakeScale(0.97, 0.97); }]; }
- (void)up:(UIView *)b { [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.55 initialSpringVelocity:0.8 options:0 animations:^{ b.transform = CGAffineTransformIdentity; } completion:nil]; }

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat W = self.view.bounds.size.width, H = self.view.bounds.size.height, m = 20;
    CGFloat sb = self.view.safeAreaInsets.bottom;
    self.head.frame = CGRectMake(m, 28, 120, 32);
    [self.view viewWithTag:5].frame = CGRectMake(m + 2, 66, 30, 4);
    self.src.frame = CGRectMake(m, 84, W - 2 * m, 22);
    self.cur.frame = CGRectMake(m, 110, W - 2 * m, 22);
    self.cnt.frame = CGRectMake(m, 148, W / 2, 28);
    self.hint.frame = CGRectMake(m, 182, W - 2 * m, 20);
    CGFloat by = H - sb - 14 - 56;
    CGFloat bw = (W - m * 2 - 14) / 2;
    self.dlAll.frame = CGRectMake(m, by, bw, 56);
    self.dlPick.frame = CGRectMake(m + bw + 14, by, bw, 56);
    self.table.frame = CGRectMake(0, 210, W, by - 210 - 6);
    self.table.contentInset = UIEdgeInsetsMake(0, 0, 8, 0);
    [self paintButtons];
}

- (void)paintButtons {
    NSInteger n = self.picked.count;
    BOOL on = n > 0;
    self.dlPick.backgroundColor = on ? UIColor.whiteColor : [UIColor colorWithWhite:1 alpha:0.1];
    self.dlPick.layer.borderColor = (on ? UIColor.clearColor : [UIColor colorWithWhite:1 alpha:0.0]).CGColor;
    [self.dlPick setTitleColor:(on ? UIColor.blackColor : [UIColor colorWithWhite:1 alpha:0.35]) forState:UIControlStateNormal];
    [self.dlPick setTitle:(on ? [NSString stringWithFormat:@"选集下载 (%ld)", (long)n] : @"选集下载") forState:UIControlStateNormal];
    self.dlPick.enabled = on;
    self.dlAll.backgroundColor = UIColor.clearColor;
    [self.dlAll setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
}

- (void)refreshTexts {
    self.src.attributedText = [self kv:@"来源 · 专辑 " v:self.album.title ?: @""];
    self.cur.attributedText = [self kv:@"当前 · " v:self.currentTitle.length ? self.currentTitle : @"尚未开始收听"];
    self.cnt.text = [NSString stringWithFormat:@"共 %ld 集", (long)self.total];
    BOOL full = (NSInteger)self.tracks.count >= self.total && self.total > 0;
    self.hint.text = full ? @"点分段展开，可勾选整段或单集" : [NSString stringWithFormat:@"正在补齐完整章节列表… %ld/%ld", (long)self.tracks.count, (long)self.total];
}
- (NSAttributedString *)kv:(NSString *)k v:(NSString *)v {
    NSMutableAttributedString *a = [[NSMutableAttributedString alloc] initWithString:k attributes:@{NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:0.5], NSFontAttributeName: [UIFont systemFontOfSize:15]}];
    [a appendAttributedString:[[NSAttributedString alloc] initWithString:v attributes:@{NSForegroundColorAttributeName: UIColor.whiteColor, NSFontAttributeName: [UIFont systemFontOfSize:15 weight:UIFontWeightMedium]}]];
    return a;
}

// 目录没拉全就自动补齐（只往后追加，不动已有顺序）
- (void)fillCatalog {
    if (self.filling || self.closed) return;
    if (self.total > 0 && (NSInteger)self.tracks.count >= self.total) return;
    if ((NSInteger)self.tracks.count % 50 != 0 && self.tracks.count > 0) return;
    self.filling = YES;
    [self fillPage:(NSInteger)self.tracks.count / 50 + 1 tries:0];
}
- (void)fillPage:(NSInteger)page tries:(NSInteger)tries {
    __block BOOL fired = NO;
    __weak typeof(self) w = self;
    [[ADApi shared] tracksOf:self.album.albumId page:page done:^(NSArray<ADTrack *> *list, NSInteger total, BOOL cached, NSString *err) {
        __strong typeof(w) self = w; if (!self || self.closed || fired) return;
        if (cached && !list.count) return;
        if (err.length && !list.count) {
            fired = YES;
            if (tries < 2) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [w fillPage:page tries:tries + 1]; });
            else { self.filling = NO; self.hint.text = @"目录没取全，已显示部分章节"; }
            return;
        }
        fired = YES;
        NSMutableArray *m = [self.tracks mutableCopy]; NSMutableSet *have = [NSMutableSet set];
        for (ADTrack *t in m) [have addObject:t.trackId];
        NSInteger add = 0;
        for (ADTrack *t in list) if (t.trackId.length && ![have containsObject:t.trackId]) { [m addObject:t]; [have addObject:t.trackId]; add++; }
        self.tracks = m;
        if (total > self.total) self.total = total;
        if ((NSInteger)m.count > self.total) self.total = m.count;
        [self refreshTexts]; [self.table reloadData];
        if (add == 0 || list.count < 50) { self.filling = NO; self.total = MAX((NSInteger)m.count, add == 0 ? (NSInteger)m.count : self.total); [self refreshTexts]; [self.table reloadData]; return; }
        [self fillPage:page + 1 tries:0];
    }];
}

- (void)reload { [self.table reloadData]; }
- (void)viewWillDisappear:(BOOL)a { [super viewWillDisappear:a]; if (self.isBeingDismissed) self.closed = YES; }

// ── 分段 ──
- (NSInteger)segCount { return (self.total + kSeg - 1) / kSeg; }
- (NSInteger)segStart:(NSInteger)s { return s * kSeg; }
- (NSInteger)segEnd:(NSInteger)s { return MIN((s + 1) * kSeg, MAX(self.total, (NSInteger)self.tracks.count)); }   // 不含
- (NSArray<ADTrack *> *)tracksInSeg:(NSInteger)s {
    NSInteger a = [self segStart:s], b = MIN([self segEnd:s], (NSInteger)self.tracks.count);
    if (a >= b) return @[];
    return [self.tracks subarrayWithRange:NSMakeRange(a, b - a)];
}
- (double)segBytes:(NSInteger)s { return 0; }

// section = 分段，第 0 行是分段头，展开后再跟单集行
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return [self segCount]; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s {
    if (![self.open containsObject:@(s)]) return 1;
    return 1 + [self segEnd:s] - [self segStart:s];
}
- (CGFloat)tableView:(UITableView *)t heightForRowAtIndexPath:(NSIndexPath *)ip { return ip.row == 0 ? 68 : 56; }

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    c.backgroundColor = UIColor.clearColor; c.selectionStyle = UITableViewCellSelectionStyleNone;
    for (UIView *v in [c.contentView.subviews copy]) [v removeFromSuperview];
    CGFloat W = t.bounds.size.width;
    NSInteger s = ip.section;
    UIImageSymbolConfiguration *cf = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightRegular];
    if (ip.row == 0) {
        BOOL open = [self.open containsObject:@(s)];
        UIImageView *chev = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightMedium]]];
        chev.tintColor = [UIColor colorWithWhite:1 alpha:0.85]; chev.frame = CGRectMake(24, 26, 16, 16); chev.contentMode = UIViewContentModeCenter;
        chev.transform = open ? CGAffineTransformMakeRotation(M_PI_2) : CGAffineTransformIdentity;
        [c.contentView addSubview:chev];
        NSInteger a = [self segStart:s] + 1, b = [self segEnd:s];
        UILabel *l = [ADUtil label:@"PingFangSC-Medium" size:20 color:UIColor.whiteColor]; l.numberOfLines = 1;
        l.text = [NSString stringWithFormat:@"第%ld集-第%ld集", (long)a, (long)b];
        l.frame = CGRectMake(56, 0, W - 56 - 150, 68); [c.contentView addSubview:l];
        // 已下载进度
        NSArray *seg = [self tracksInSeg:s]; NSInteger have = 0, pick = 0;
        for (ADTrack *x in seg) { if ([[ADDownloader shared] hasLocal:x.trackId]) have++; if ([self.picked containsObject:x.trackId]) pick++; }
        UILabel *st = [ADUtil label:nil size:14 color:have ? [ADUtil brand] : [UIColor colorWithWhite:1 alpha:0.45]]; st.numberOfLines = 1; st.textAlignment = NSTextAlignmentRight;
        st.text = have ? [NSString stringWithFormat:@"已存 %ld/%ld", (long)have, (long)(b - a + 1)] : @"未下载";
        st.frame = CGRectMake(W - 24 - 44 - 100, 0, 100, 68); [c.contentView addSubview:st];
        BOOL all = seg.count > 0 && pick == (NSInteger)seg.count;
        BOOL some = pick > 0 && !all;
        UIImageView *ck = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:all ? @"checkmark.circle.fill" : (some ? @"minus.circle.fill" : @"circle") withConfiguration:cf]];
        ck.tintColor = (all || some) ? [ADUtil brand] : [UIColor colorWithWhite:1 alpha:0.5]; ck.contentMode = UIViewContentModeCenter;
        ck.frame = CGRectMake(W - 24 - 36, 16, 36, 36); [c.contentView addSubview:ck];
        UIButton *hit = [UIButton buttonWithType:UIButtonTypeCustom]; hit.frame = CGRectMake(W - 80, 0, 80, 68); hit.tag = s;
        [hit addTarget:self action:@selector(tapSegCheck:) forControlEvents:UIControlEventTouchUpInside]; [c.contentView addSubview:hit];
        return c;
    }
    NSInteger idx = [self segStart:s] + ip.row - 1;
    ADTrack *tr = idx < (NSInteger)self.tracks.count ? self.tracks[idx] : nil;
    UILabel *n = [ADUtil label:nil size:13 color:[UIColor colorWithWhite:1 alpha:0.4]]; n.numberOfLines = 1; n.textAlignment = NSTextAlignmentCenter;
    n.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightMedium];
    n.text = [NSString stringWithFormat:@"%ld", (long)idx + 1]; n.frame = CGRectMake(14, 0, 44, 56); [c.contentView addSubview:n];
    UILabel *l = [ADUtil label:nil size:16 color:tr ? UIColor.whiteColor : [UIColor colorWithWhite:1 alpha:0.3]]; l.numberOfLines = 1;
    l.text = tr ? tr.title : @"加载中…"; l.frame = CGRectMake(66, 0, W - 66 - 130, 56); [c.contentView addSubview:l];
    if (tr) {
        BOOL local = [[ADDownloader shared] hasLocal:tr.trackId], pk = [self.picked containsObject:tr.trackId];
        if (local) {
            UILabel *st = [ADUtil label:nil size:12 color:[ADUtil brand]]; st.numberOfLines = 1; st.textAlignment = NSTextAlignmentRight; st.text = @"已缓存";
            st.frame = CGRectMake(W - 24 - 36 - 60, 0, 56, 56); [c.contentView addSubview:st];
        } else if (tr.duration > 0) {
            UILabel *st = [ADUtil label:nil size:12 color:[UIColor colorWithWhite:1 alpha:0.4]]; st.numberOfLines = 1; st.textAlignment = NSTextAlignmentRight; st.text = [ADUtil time:tr.duration];
            st.frame = CGRectMake(W - 24 - 36 - 66, 0, 62, 56); [c.contentView addSubview:st];
        }
        UIImageView *ck = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:local ? @"checkmark.circle.fill" : (pk ? @"checkmark.circle.fill" : @"circle") withConfiguration:cf]];
        ck.tintColor = local ? [UIColor colorWithWhite:1 alpha:0.25] : (pk ? [ADUtil brand] : [UIColor colorWithWhite:1 alpha:0.5]);
        ck.contentMode = UIViewContentModeCenter; ck.frame = CGRectMake(W - 24 - 36, 10, 36, 36); [c.contentView addSubview:ck];
    }
    return c;
}

- (void)tapSegCheck:(UIButton *)b {
    [ADHaptic select];
    NSArray *seg = [self tracksInSeg:b.tag];
    BOOL all = YES;
    for (ADTrack *x in seg) if (![[ADDownloader shared] hasLocal:x.trackId] && ![self.picked containsObject:x.trackId]) { all = NO; break; }
    for (ADTrack *x in seg) {
        if ([[ADDownloader shared] hasLocal:x.trackId]) continue;
        if (all) [self.picked removeObject:x.trackId]; else [self.picked addObject:x.trackId];
    }
    [self.table reloadSections:[NSIndexSet indexSetWithIndex:b.tag] withRowAnimation:UITableViewRowAnimationNone];
    [self paintButtons];
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:NO];
    NSInteger s = ip.section;
    if (ip.row == 0) {
        [ADHaptic tap];
        if ([self.open containsObject:@(s)]) [self.open removeObject:@(s)]; else [self.open addObject:@(s)];
        [t reloadSections:[NSIndexSet indexSetWithIndex:s] withRowAnimation:UITableViewRowAnimationFade];
        return;
    }
    NSInteger idx = [self segStart:s] + ip.row - 1;
    if (idx >= (NSInteger)self.tracks.count) return;
    ADTrack *tr = self.tracks[idx];
    if ([[ADDownloader shared] hasLocal:tr.trackId]) { [ADHaptic warning]; return; }
    [ADHaptic select];
    if ([self.picked containsObject:tr.trackId]) [self.picked removeObject:tr.trackId]; else [self.picked addObject:tr.trackId];
    [t reloadSections:[NSIndexSet indexSetWithIndex:s] withRowAnimation:UITableViewRowAnimationNone];
    [self paintButtons];
}

- (void)downloadAll {
    if (!self.tracks.count) return;
    [ADHaptic success];
    NSMutableArray *rest = [NSMutableArray array];
    for (ADTrack *t in self.tracks) [rest addObject:t];
    ADTask *tk = [[ADDownloader shared] taskForAlbum:self.album.albumId];
    if (tk) [[ADDownloader shared] addTracks:self.album tracks:rest]; else [[ADDownloader shared] addAlbum:self.album tracks:rest];
    [self toastAndClose:[NSString stringWithFormat:@"已加入下载队列 %ld 集", (long)rest.count]];
}
- (void)downloadPicked {
    if (!self.picked.count) return;
    NSMutableArray *arr = [NSMutableArray array];
    for (ADTrack *t in self.tracks) if ([self.picked containsObject:t.trackId]) [arr addObject:t];
    [ADHaptic success];
    [[ADDownloader shared] addTracks:self.album tracks:arr];
    [self toastAndClose:[NSString stringWithFormat:@"已加入下载队列 %ld 集", (long)arr.count]];
}
- (void)toastAndClose:(NSString *)msg {
    UILabel *l = [ADUtil label:nil size:15 color:UIColor.whiteColor]; l.text = msg; l.textAlignment = NSTextAlignmentCenter; l.numberOfLines = 1;
    l.backgroundColor = [UIColor colorWithWhite:1 alpha:0.16]; l.layer.cornerRadius = 20; l.clipsToBounds = YES;
    l.frame = CGRectMake((self.view.bounds.size.width - 240) / 2, self.view.bounds.size.height / 2 - 20, 240, 40);
    l.alpha = 0; [self.view addSubview:l];
    [UIView animateWithDuration:0.2 animations:^{ l.alpha = 1; }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self dismissViewControllerAnimated:YES completion:nil]; });
}
@end
