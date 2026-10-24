#import "AD.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import "ADInternal.h"

@interface ADBookController () <UITableViewDataSource, UITableViewDelegate>
@end

@implementation ADBookController {
    UITableView *_tv;
    UIView *_header;
    UIImageView *_cover;
    UILabel *_title, *_meta, *_summary;
    UIButton *_playBtn;
    NSMutableArray<ADChapter *> *_chapters;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ADUtil bg];
    self.navigationItem.title = self.book.title;
    self.navigationController.navigationBar.tintColor = UIColor.whiteColor;
    _chapters = [self.book.chapters mutableCopy] ?: [NSMutableArray array];

    _tv = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    _tv.backgroundColor = UIColor.clearColor;
    _tv.separatorColor = [UIColor colorWithWhite:1 alpha:0.08];
    _tv.dataSource = self; _tv.delegate = self;
    _tv.contentInset = UIEdgeInsetsMake(0, 0, 90, 0);
    [self.view addSubview:_tv];

    _header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 210)];
    _cover = [[UIImageView alloc] initWithFrame:CGRectMake(18, 16, 120, 170)];
    _cover.layer.cornerRadius = 10; _cover.clipsToBounds = YES;
    [ADUtil coverInto:_cover url:self.book.cover];
    _title = [ADUtil label:@"PingFangSC-Semibold" size:18 color:UIColor.whiteColor];
    _title.frame = CGRectMake(152, 18, self.view.bounds.size.width - 170, 50);
    _meta = [ADUtil label:nil size:12 color:[ADUtil dim]];
    _meta.frame = CGRectMake(152, 70, self.view.bounds.size.width - 170, 30);
    _meta.text = [NSString stringWithFormat:@"%@  %@", self.book.author ?: @"", self.book.narrator.length ? [@"· " stringByAppendingString:self.book.narrator] : @""];
    _playBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _playBtn.frame = CGRectMake(152, 108, 110, 36);
    _playBtn.backgroundColor = [ADUtil brand];
    _playBtn.layer.cornerRadius = 18;
    [_playBtn setTitle:@"开始收听" forState:UIControlStateNormal];
    [_playBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    _playBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [_playBtn addTarget:self action:@selector(playFirst) forControlEvents:UIControlEventTouchUpInside];
    _summary = [ADUtil label:nil size:12 color:[ADUtil dim]];
    _summary.frame = CGRectMake(18, 194, self.view.bounds.size.width - 36, 0);
    [_header addSubview:_cover]; [_header addSubview:_title]; [_header addSubview:_meta];
    [_header addSubview:_playBtn]; [_header addSubview:_summary];
    _tv.tableHeaderView = _header;

    if (!_chapters.count && self.book.bid.length) [self loadDetail];
}

- (void)loadDetail {
    __weak typeof(self) w = self;
    [[ADAPI shared] fetchBook:self.book.bid completion:^(id json, NSError *err, NSInteger code) {
        __strong typeof(w) self = w; if (!self) return;
        NSDictionary *d = ADUnwrapBook(json);
        ADBook *b = [ADBook fromJSON:d];
        if (b) {
            if (b.title.length) self.book.title = b.title;
            if (b.summary.length) self.book.summary = b.summary;
            if (b.cover.length) self.book.cover = b.cover;
            if (b.author.length) self.book.author = b.author;
            if (b.chapters.count) { self.book.chapters = b.chapters; self->_chapters = [b.chapters mutableCopy]; }
        }
        [self->_tv reloadData];
        [ADUtil coverInto:self->_cover url:self.book.cover];
        self->_summary.text = self.book.summary;
        if (self.book.summary.length) {
            CGSize sz = [self.book.summary boundingRectWithSize:CGSizeMake(self.view.bounds.size.width - 36, 400)
                                                        options:NSStringDrawingUsesLineFragmentOrigin
                                                     attributes:@{NSFontAttributeName: self->_summary.font} context:nil].size;
            CGRect f = self->_header.frame;
            f.size.height = 200 + sz.height + 20;
            self->_header.frame = f;
            self->_tv.tableHeaderView = self->_header;
            self->_summary.frame = CGRectMake(18, 194, self.view.bounds.size.width - 36, sz.height);
        }
    }];
}

- (void)playFirst {
    if (!self.book.chapters.count) return;
    [[ADPlayer shared] playBook:self.book at:0];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ADPlayerChanged" object:nil];
    [self presentViewController:[ADPlayerController new] animated:YES completion:nil];
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return self.book.chapters.count; }
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return self.book.chapters.count ? [NSString stringWithFormat:@"共 %lu 章", (unsigned long)self.book.chapters.count] : nil;
}
- (void)tableView:(UITableView *)tv willDisplayHeaderView:(UIView *)v forSection:(NSInteger)s {
    if ([v isKindOfClass:[UITableViewHeaderFooterView class]]) {
        UITableViewHeaderFooterView *h = (id)v;
        h.textLabel.textColor = [ADUtil dim];
    }
}
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"ch";
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:cid];
    if (!c) { c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid]; }
    ADChapter *ch = self.book.chapters[ip.row];
    c.backgroundColor = UIColor.clearColor;
    c.textLabel.textColor = UIColor.whiteColor;
    c.detailTextLabel.textColor = [ADUtil dim];
    c.textLabel.font = [UIFont systemFontOfSize:15];
    c.textLabel.text = [NSString stringWithFormat:@"%ld. %@", (long)ip.row + 1, ch.title];
    double p = [[ADStore shared] progressForChapter:ch.fid];
    c.detailTextLabel.text = p > 0 ? [NSString stringWithFormat:@"上次听到 %@", [ADUtil timeString:p]] : (ch.duration > 0 ? [ADUtil timeString:ch.duration] : @"");
    c.tintColor = [ADUtil brand];
    BOOL playing = [[ADPlayer shared] currentChapter] && [[ADPlayer shared].currentChapter.fid isEqualToString:ch.fid];
    c.accessoryType = playing ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return c;
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    [[ADPlayer shared] playBook:self.book at:ip.row];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ADPlayerChanged" object:nil];
    [tv reloadData];
    [self presentViewController:[ADPlayerController new] animated:YES completion:nil];
}
@end

// ───────────────────────── 全屏播放器 ─────────────────────────
@implementation ADPlayerController {
    UIImageView *_cover;
    UILabel *_title, *_chapter, *_elapsed, *_remain;
    UISlider *_slider;
    UIButton *_play, *_prev, *_next, *_back15, *_fwd30, *_list;
    UILabel *_rate, *_sleep;
    NSTimer *_timer;
    BOOL _dragging;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.07 green:0.045 blue:0.03 alpha:1];
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    UIVisualEffectView *bg = [[UIVisualEffectView alloc] initWithEffect:blur];
    bg.frame = self.view.bounds; bg.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:bg];

    CGFloat w = self.view.bounds.size.width;
    _cover = [[UIImageView alloc] initWithFrame:CGRectMake(w / 2 - 120, 90, 240, 240)];
    _cover.layer.cornerRadius = 18; _cover.clipsToBounds = YES;
    _cover.layer.shadowColor = UIColor.blackColor.CGColor; _cover.layer.shadowRadius = 24; _cover.layer.shadowOpacity = 0.5;
    _title = [ADUtil label:@"PingFangSC-Semibold" size:19 color:UIColor.whiteColor];
    _title.textAlignment = NSTextAlignmentCenter;
    _title.frame = CGRectMake(24, 350, w - 48, 26);
    _chapter = [ADUtil label:nil size:13 color:[ADUtil dim]];
    _chapter.textAlignment = NSTextAlignmentCenter;
    _chapter.frame = CGRectMake(24, 380, w - 48, 20);

    _slider = [UISlider new];
    _slider.frame = CGRectMake(24, 420, w - 48, 30);
    _slider.tintColor = [ADUtil brand];
    [_slider addTarget:self action:@selector(sliderDown) forControlEvents:UIControlEventTouchDown];
    [_slider addTarget:self action:@selector(sliderUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [_slider addTarget:self action:@selector(sliderMove) forControlEvents:UIControlEventValueChanged];

    _elapsed = [ADUtil label:nil size:11 color:[ADUtil dim]];
    _elapsed.frame = CGRectMake(24, 450, 100, 16);
    _remain = [ADUtil label:nil size:11 color:[ADUtil dim]];
    _remain.textAlignment = NSTextAlignmentRight;
    _remain.frame = CGRectMake(w - 124, 450, 100, 16);

    _play = [self bigButton:@"play.fill" size:64 action:@selector(togglePlay)];
    _play.frame = CGRectMake(w / 2 - 32, 490, 64, 64);
    _prev = [self iconButton:@"backward.end.fill" action:@selector(prev) size:34];
    _prev.frame = CGRectMake(w / 2 - 120, 505, 40, 34);
    _next = [self iconButton:@"forward.end.fill" action:@selector(next) size:34];
    _next.frame = CGRectMake(w / 2 + 80, 505, 40, 34);
    _back15 = [self iconButton:@"gobackward.15" action:@selector(back) size:26];
    _back15.frame = CGRectMake(w / 2 - 190, 510, 34, 26);
    _fwd30 = [self iconButton:@"goforward.30" action:@selector(fwd) size:26];
    _fwd30.frame = CGRectMake(w / 2 + 156, 510, 34, 26);

    _rate = [ADUtil label:nil size:14 color:UIColor.whiteColor];
    _rate.textAlignment = NSTextAlignmentCenter;
    _rate.userInteractionEnabled = YES;
    _rate.frame = CGRectMake(w / 2 - 140, 590, 90, 34);
    _rate.text = [NSString stringWithFormat:@"%@x", [self rateLabel]];
    _rate.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.25].CGColor;
    _rate.layer.borderWidth = 1; _rate.layer.cornerRadius = 17;
    [_rate addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(cycleRate)]];

    _sleep = [ADUtil label:nil size:14 color:UIColor.whiteColor];
    _sleep.textAlignment = NSTextAlignmentCenter;
    _sleep.userInteractionEnabled = YES;
    _sleep.frame = CGRectMake(w / 2 + 50, 590, 90, 34);
    _sleep.text = @"定时";
    _sleep.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.25].CGColor;
    _sleep.layer.borderWidth = 1; _sleep.layer.cornerRadius = 17;
    [_sleep addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(cycleSleep)]];

    _list = [self iconButton:@"list.bullet" action:@selector(showList) size:24];
    _list.frame = CGRectMake(w - 54, 56, 34, 34);

    UIButton *close = [self iconButton:@"chevron.down" action:@selector(close) size:22];
    close.frame = CGRectMake(20, 56, 34, 34);

    for (UIView *v in @[_title, _chapter, _slider, _elapsed, _remain, _play, _prev, _next, _back15, _fwd30, _rate, _sleep, _list, close]) [self.view addSubview:v];
    [self.view addSubview:_cover];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sync) name:@"ADPlayerTick" object:nil];
    [self sync];
}

- (NSString *)rateLabel {
    float r = [ADPlayer shared].rate;
    return r == (int)r ? [NSString stringWithFormat:@"%d", (int)r] : [NSString stringWithFormat:@"%.1f", r];
}

- (UIButton *)bigButton:(NSString *)icon size:(CGFloat)sz action:(SEL)a {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setImage:[UIImage systemImageNamed:icon withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:sz weight:UIImageSymbolWeightMedium]] forState:UIControlStateNormal];
    b.tintColor = UIColor.whiteColor;
    [b addTarget:self action:a forControlEvents:UIControlEventTouchUpInside];
    return b;
}
- (UIButton *)iconButton:(NSString *)icon action:(SEL)a size:(CGFloat)sz {
    return [self bigButton:icon size:sz action:a];
}

- (void)sync {
    ADPlayer *p = [ADPlayer shared];
    ADChapter *ch = [p currentChapter];
    if (!ch) return;
    _title.text = p.book.title;
    _chapter.text = ch.title;
    [ADUtil coverInto:_cover url:p.book.cover];
    double dur = CMTimeGetSeconds(p.player.currentItem.duration);
    double cur = CMTimeGetSeconds(p.player.currentTime);
    if (!_dragging && dur > 0 && !isnan(dur)) {
        _slider.maximumValue = dur; _slider.value = cur;
    }
    _elapsed.text = [ADUtil timeString:cur];
    _remain.text = dur > 0 && !isnan(dur) ? [NSString stringWithFormat:@"-%@", [ADUtil timeString:dur - cur]] : @"";
    [_play setImage:[UIImage systemImageNamed:p.player.rate > 0 ? @"pause.fill" : @"play.fill"
                                withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:64 weight:UIImageSymbolWeightMedium]]
           forState:UIControlStateNormal];
    if (p.sleepTimerDeadline > 0) {
        double left = p.sleepTimerDeadline - [NSDate date].timeIntervalSince1970;
        _sleep.text = [NSString stringWithFormat:@"%@后停", [ADUtil timeString:MAX(0, left)]];
    } else _sleep.text = @"定时";
}

- (void)sliderDown { _dragging = YES; }
- (void)sliderMove { _elapsed.text = [ADUtil timeString:_slider.value]; }
- (void)sliderUp { _dragging = NO; [[ADPlayer shared] seekTo:_slider.value]; }

- (void)togglePlay { [[ADPlayer shared] toggle]; [self sync]; }
- (void)prev { [[ADPlayer shared] prev]; [self sync]; }
- (void)next { [[ADPlayer shared] next]; [self sync]; }
- (void)back { [[ADPlayer shared] seekBy:-15]; }
- (void)fwd { [[ADPlayer shared] seekBy:30]; }

- (void)cycleRate {
    NSArray *rates = @[@0.75, @1.0, @1.25, @1.5, @1.75, @2.0, @2.5, @3.0];
    float r = [ADPlayer shared].rate;
    NSUInteger i = 0;
    for (NSUInteger k = 0; k < rates.count; k++) if (fabs([rates[k] floatValue] - r) < 0.01) { i = k; break; }
    i = (i + 1) % rates.count;
    [ADPlayer shared].rate = [rates[i] floatValue];
    _rate.text = [NSString stringWithFormat:@"%@x", [self rateLabel]];
}

- (void)cycleSleep {
    NSArray *mins = @[@0, @15, @30, @45, @60, @90];
    double now = [NSDate date].timeIntervalSince1970;
    double cur = [ADPlayer shared].sleepTimerDeadline;
    NSInteger idx = 0;
    if (cur > 0) {
        double left = (cur - now) / 60.0;
        for (NSUInteger k = 0; k < mins.count; k++) if (fabs([mins[k] doubleValue] - left) < 1.5) { idx = k; break; }
    }
    idx = (idx + 1) % mins.count;
    double m = [mins[idx] doubleValue];
    [ADPlayer shared].sleepTimerDeadline = m > 0 ? now + m * 60 : 0;
    [self sync];
}

- (void)showList {
    ADPlayer *p = [ADPlayer shared];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"章节" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSInteger i = 0; i < (NSInteger)p.book.chapters.count && i < 60; i++) {
        ADChapter *ch = p.book.chapters[i];
        [a addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%ld. %@", (long)i + 1, ch.title] style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            [p playIndex:i]; [self sync];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = _list;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
@end
