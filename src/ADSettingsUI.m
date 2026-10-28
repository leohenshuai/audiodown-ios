#import "AD.h"
#import <CoreImage/CoreImage.h>
#import <objc/runtime.h>
#import <MediaPlayer/MediaPlayer.h>
#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>
#import "ADInternal.h"

// ───────────── 设置 ─────────────
@interface ADSettingsController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UITextField *baseField;
@property (nonatomic, copy) NSString *token;
@property (nonatomic, strong) UILabel *status;
@property (nonatomic, assign) BOOL tokenShown;
@property (nonatomic, assign) BOOL checking, hasUpdate;
@property (nonatomic, copy) NSString *latestTag, *updateHint;
@end

@implementation ADSettingsController

- (void)viewDidLoad {
    [super viewDidLoad];
    [ADLiquid canvas:self.view];
    self.title = @"设置";
    self.navigationController.navigationBar.tintColor = UIColor.whiteColor;
    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
    self.token = [ADConfig shared].token ?: @"";
    self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.table.backgroundColor = UIColor.clearColor;
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:self.table];

    self.baseField = [self field:[ADConfig shared].baseURL placeholder:@"https://服务器地址:端口" keyboard:UIKeyboardTypeURL];

    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.navigationController.navigationBar.largeTitleTextAttributes = @{NSForegroundColorAttributeName: UIColor.whiteColor};
    self.navigationController.navigationBar.titleTextAttributes = @{NSForegroundColorAttributeName: UIColor.whiteColor};
    [self.navigationController.navigationBar setBackgroundImage:[UIImage new] forBarMetrics:UIBarMetricsDefault];
    self.navigationController.navigationBar.shadowImage = [UIImage new];
    NSString *cachedTag = [NSUserDefaults.standardUserDefaults stringForKey:@"ad_update_tag"];
    if (cachedTag.length) { self.latestTag = cachedTag; self.hasUpdate = [ADUpdater isNewer:cachedTag than:[self appVersion]]; }
    if (self.navigationController.presentingViewController) self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"关闭" style:UIBarButtonItemStylePlain target:self action:@selector(closeSelf)];
    self.table.contentInset = UIEdgeInsetsMake(0, 0, 110, 0);
    self.table.scrollIndicatorInsets = UIEdgeInsetsMake(0, 0, 100, 0);

    self.status = [ADUtil label:nil size:12 color:[UIColor colorWithWhite:1 alpha:0.5]];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:@"ADDownloadChanged" object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.navigationBar.hidden = NO;
    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
    self.navigationController.navigationBar.tintColor = UIColor.whiteColor;
    self.token = [ADConfig shared].token ?: self.token;
    self.baseField.text = [ADConfig shared].baseURL;
    [self.table reloadData];
}
- (void)closeSelf { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)reloadSkipRows { [self.table reloadData]; }   // 跳过片头片尾弹窗保存/恢复后刷新文案

- (void)prefetchSwitch:(UISwitch *)sw {
    [NSUserDefaults.standardUserDefaults setBool:sw.on forKey:@"ad_prefetch"];
    if (sw.on) [ADPlayer.shared prefetchAhead];
}

- (void)prefetchWifi:(UISwitch *)sw {
    [NSUserDefaults.standardUserDefaults setBool:sw.on forKey:@"ad_prefetch_wifi"];
}

- (void)hapticSwitch:(UISwitch *)sw {
    [NSUserDefaults.standardUserDefaults setBool:sw.on forKey:@"ad_haptic"];
    if (sw.on) [ADHaptic tap];
}

- (void)soundSwitch:(UISwitch *)sw {
    [NSUserDefaults.standardUserDefaults setBool:sw.on forKey:@"ad_sound"];
    if (sw.on) [ADHaptic tap];
}

- (void)prefetchStepper:(UIStepper *)st {
    [NSUserDefaults.standardUserDefaults setInteger:(NSInteger)st.value forKey:@"ad_prefetch_count"];
    [self.table reloadData];
}

- (void)refresh { [self.table reloadData]; }

- (UITextField *)field:(NSString *)text placeholder:(NSString *)ph keyboard:(UIKeyboardType)kb {
    UITextField *f = [UITextField new];
    f.text = text;
    f.placeholder = ph;
    f.textColor = UIColor.whiteColor;
    f.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    f.autocapitalizationType = UITextAutocapitalizationTypeNone;
    f.autocorrectionType = UITextAutocorrectionTypeNo;
    f.spellCheckingType = UITextSpellCheckingTypeNo;
    f.keyboardType = kb;
    f.clearButtonMode = UITextFieldViewModeWhileEditing;
    f.textAlignment = NSTextAlignmentRight;
    f.delegate = self;
    return f;
}

// token 显示：默认只露出前后各 3 位，其余用圆点
- (NSString *)tokenDisplay {
    if (!self.token.length) return @"未填写";
    if (self.tokenShown) return self.token;
    if (self.token.length <= 10) return @"••••••••";
    return [NSString stringWithFormat:@"%@••••••%@", [self.token substringToIndex:5], [self.token substringFromIndex:self.token.length - 4]];
}

- (void)toggleToken {
    self.tokenShown = !self.tokenShown;
    [self.table reloadData];
}

- (void)editToken {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Token" message:@"粘贴服务端给你的 token" preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = self.token;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
        tf.placeholder = @"xmd_…";
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        self.token = [a.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        [self save];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"从剪贴板粘贴" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *p = UIPasteboard.generalPasteboard.string;
        if (p.length) { self.token = [p stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; [self save]; }
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)editBaseURL {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"服务地址" message:@"例如 https://域名:端口" preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = self.baseField.text.length ? self.baseField.text : [ADConfig shared].baseURL;
        tf.placeholder = @"https://服务器地址:端口";
        tf.keyboardType = UIKeyboardTypeURL;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.clearButtonMode = UITextFieldViewModeWhileEditing;
        tf.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"保存并测试" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *v = [a.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        while ([v hasSuffix:@"/"]) v = [v substringToIndex:v.length - 1];
        if (!v.length) return;
        self.baseField.text = v;
        [self save];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)editAccount {
    ADConfig *cfg = [ADConfig shared];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"网页账号"
                                                               message:@"填服务端网页后台的账号密码。VIP/付费专辑的目录只有登录态才取得到。"
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = cfg.username;
        tf.placeholder = @"用户名";
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = cfg.password;
        tf.placeholder = @"密码";
        tf.secureTextEntry = YES;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"保存并登录" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        cfg.username = [a.textFields[0].text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
        cfg.password = a.textFields[1].text ?: @"";
        [cfg save];
        [[NSHTTPCookieStorage sharedHTTPCookieStorage] removeCookiesSinceDate:[NSDate dateWithTimeIntervalSince1970:0]];
        [[ADApi shared] panelLogin:^(BOOL ok, NSString *err) {
            UIAlertController *r = [UIAlertController alertControllerWithTitle:(ok ? @"登录成功" : @"登录失败")
                                                                      message:(ok ? @"现在可以读取 VIP 专辑的目录了" : (err ?: @"请检查账号密码"))
                                                               preferredStyle:UIAlertControllerStyleAlert];
            [r addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:r animated:YES completion:nil];
            [self.table reloadData];
        }];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)save {
    [ADHaptic success];
    [ADConfig shared].baseURL = self.baseField.text ?: @"";
    [ADConfig shared].token = self.token ?: @"";
    [[ADConfig shared] save];
    UIImpactFeedbackGenerator *g = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [g impactOccurred];
    [self.table reloadData];
    [self test];
}

- (void)test {
    self.status.text = @"正在测试连接…";
    [self.table reloadData];
    __weak typeof(self) w = self;
    [[ADApi shared] albumDetail:@"XMID59325711" done:^(ADAlbum *a, BOOL cached, NSString *err) {
        __strong typeof(w) self = w; if (!self) return;
        self.status.text = err ? [@"连接失败：" stringByAppendingString:err] : @"连接正常，可以搜索和播放";
        [self.table reloadData];
    }];
}

// ───────── 设置页：按用途分组 ─────────
// 0 服务  1 播放  2 下载与存储  3 体验  4 数据  5 关于
typedef NS_ENUM(NSInteger, ADSetSec) { ADSecServer, ADSecPlay, ADSecStorage, ADSecFeel, ADSecData, ADSecAbout, ADSecCount };

- (NSString *)appVersion {
    NSDictionary *i = NSBundle.mainBundle.infoDictionary;
    return [NSString stringWithFormat:@"%@", i[@"CFBundleShortVersionString"] ?: @"?"];
}
- (NSString *)buildNo { return NSBundle.mainBundle.infoDictionary[@"CFBundleVersion"] ?: @""; }

- (UISwitch *)sw:(NSString *)key def:(BOOL)def action:(SEL)a {
    UISwitch *sw = [UISwitch new];
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    sw.on = [ud objectForKey:key] ? [ud boolForKey:key] : def;
    sw.onTintColor = [ADUtil brand];
    [sw addTarget:self action:a forControlEvents:UIControlEventValueChanged];
    return sw;
}
- (UIImageView *)icon:(NSString *)name color:(UIColor *)c {
    UIImageView *v = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 30, 30)];
    v.backgroundColor = c; v.layer.cornerRadius = 8;
    if (@available(iOS 13.0, *)) v.layer.cornerCurve = kCACornerCurveContinuous;
    v.image = [UIImage systemImageNamed:name withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightSemibold]];
    v.tintColor = UIColor.whiteColor; v.contentMode = UIViewContentModeCenter;
    return v;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return ADSecCount; }
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s {
    return @[@"服务", @"播放", @"下载与存储", @"体验", @"数据", @"关于"][s];
}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s {
    if (s == ADSecServer) return self.status.text.length ? self.status.text : @"点 Token 那一行可以粘贴或修改";
    if (s == ADSecPlay) return @"智能预缓存会提前准备后面几集，弱网和地铁里更顺；片头片尾默认值只对没单独设置的书生效";
    if (s == ADSecData) return @"备份文件在「文件」App → 阅听 → backups，重装前先备份";
    if (s == ADSecAbout) return self.updateHint;
    return nil;
}
- (void)tableView:(UITableView *)t willDisplayHeaderView:(UIView *)v forSection:(NSInteger)s {
    if ([v isKindOfClass:UITableViewHeaderFooterView.class]) ((UITableViewHeaderFooterView *)v).textLabel.textColor = [UIColor colorWithWhite:1 alpha:0.5];
}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s {
    switch (s) {
        case ADSecServer: return 4;     // 地址 / Token / 网页账号 / 测试连接
        case ADSecPlay: return 5;       // 预缓存 / 仅 WiFi / 集数 / 自动清理 / 跳过片头片尾
        case ADSecStorage: return 3;    // 本机下载 / 离线存储 / 全部暂停继续
        case ADSecFeel: return 2;       // 触感 / 提示音
        case ADSecData: return 3;       // 书签 / 备份恢复 / 运行日志
        default: return 4;              // 版本 / 检查更新 / GitHub 令牌 / 项目主页
    }
}
- (CGFloat)tableView:(UITableView *)t heightForRowAtIndexPath:(NSIndexPath *)ip { return 56; }

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    c.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
    c.textLabel.textColor = UIColor.whiteColor;
    c.detailTextLabel.textColor = [UIColor colorWithWhite:1 alpha:0.5];
    c.textLabel.font = [UIFont systemFontOfSize:16];
    c.detailTextLabel.font = [UIFont systemFontOfSize:12];
    c.selectionStyle = UITableViewCellSelectionStyleNone;
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    UIColor *orange = [ADUtil brand], *blue = [UIColor systemBlueColor], *green = [UIColor systemGreenColor],
            *purple = [UIColor systemPurpleColor], *gray = [UIColor systemGrayColor], *teal = [UIColor systemTealColor],
            *pink = [UIColor systemPinkColor], *indigo = [UIColor systemIndigoColor];
    NSString *icon = nil; UIColor *ic = gray;

    switch (ip.section) {
    case ADSecServer: {
        if (ip.row == 0) {
            icon = @"server.rack"; ic = blue;
            c.textLabel.text = @"服务地址";
            NSString *u = self.baseField.text.length ? self.baseField.text : [ADConfig shared].baseURL;
            c.detailTextLabel.text = u.length ? u : @"未填写";
            c.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
            c.detailTextLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
            c.detailTextLabel.textColor = [UIColor colorWithWhite:1 alpha:0.65];
            c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            c.selectionStyle = UITableViewCellSelectionStyleDefault;
        } else if (ip.row == 1) {
            icon = @"key.fill"; ic = orange;
            c.textLabel.text = @"Token";
            UILabel *v = [ADUtil label:nil size:12 color:[UIColor colorWithWhite:1 alpha:0.75]];
            v.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
            v.textAlignment = NSTextAlignmentRight; v.numberOfLines = 1;
            v.lineBreakMode = NSLineBreakByTruncatingMiddle;
            v.text = [self tokenDisplay];
            v.frame = CGRectMake(0, 0, 170, 56);
            UIButton *eye = [UIButton buttonWithType:UIButtonTypeSystem];
            eye.frame = CGRectMake(172, 10, 34, 36);
            eye.tintColor = [UIColor colorWithWhite:1 alpha:0.55];
            [eye setImage:[UIImage systemImageNamed:self.tokenShown ? @"eye" : @"eye.slash"] forState:UIControlStateNormal];
            [eye addTarget:self action:@selector(toggleToken) forControlEvents:UIControlEventTouchUpInside];
            UIView *acc = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 206, 56)];
            [acc addSubview:v]; [acc addSubview:eye];
            c.accessoryView = acc;
            c.selectionStyle = UITableViewCellSelectionStyleDefault;
        } else if (ip.row == 2) {
            icon = @"person.crop.circle"; ic = gray;
            ADConfig *cfg = [ADConfig shared];
            c.textLabel.text = @"网页账号（可选）";
            c.detailTextLabel.text = cfg.username.length ? cfg.username : @"一般用不到，目录已不依赖登录";
            c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            c.selectionStyle = UITableViewCellSelectionStyleDefault;
        } else {
            icon = @"bolt.horizontal.circle"; ic = green;
            c.textLabel.text = @"保存并测试连接";
            c.textLabel.textColor = orange;
            c.selectionStyle = UITableViewCellSelectionStyleDefault;
        }
        break;
    }
    case ADSecPlay: {
        if (ip.row == 0) {
            icon = @"bolt.fill"; ic = orange;
            c.textLabel.text = @"智能预缓存";
            c.accessoryView = [self sw:@"ad_prefetch" def:NO action:@selector(prefetchSwitch:)];
        } else if (ip.row == 1) {
            icon = @"wifi"; ic = blue;
            c.textLabel.text = @"仅 Wi‑Fi 预缓存";
            c.accessoryView = [self sw:@"ad_prefetch_wifi" def:YES action:@selector(prefetchWifi:)];
        } else if (ip.row == 2) {
            icon = @"square.stack.3d.down.right"; ic = purple;
            NSInteger n = [ud integerForKey:@"ad_prefetch_count"]; if (n <= 0) n = 2;
            c.textLabel.text = @"提前准备";
            c.detailTextLabel.text = [NSString stringWithFormat:@"后面 %ld 集", (long)n];
            UIStepper *st = [UIStepper new];
            st.minimumValue = 1; st.maximumValue = 5; st.stepValue = 1; st.value = n;
            st.tintColor = orange;
            [st addTarget:self action:@selector(prefetchStepper:) forControlEvents:UIControlEventValueChanged];
            c.accessoryView = st;
        } else if (ip.row == 3) {
            icon = @"clock.arrow.circlepath"; ic = teal;
            NSInteger days = [ud integerForKey:@"ad_prefetch_days"];
            c.textLabel.text = @"自动清理预缓存";
            c.detailTextLabel.text = days == 0 ? @"不自动清理" : [NSString stringWithFormat:@"超过 %ld 天自动删除", (long)days];
            c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            c.selectionStyle = UITableViewCellSelectionStyleDefault;
        } else {
            icon = @"forward.end.fill"; ic = indigo;
            c.textLabel.text = @"跳过片头片尾(默认值)";
            c.detailTextLabel.text = ADSkipSummary(nil);
            c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            c.selectionStyle = UITableViewCellSelectionStyleDefault;
        }
        break;
    }
    case ADSecStorage: {
        NSArray<ADTask *> *tasks = [ADDownloader shared].tasks;
        if (ip.row == 0) {
            icon = @"arrow.down.circle.fill"; ic = green;
            c.textLabel.text = @"本机下载";
            NSInteger running = 0, done = 0;
            for (ADTask *x in tasks) { if (x.state == ADTaskStateRunning || x.state == ADTaskStateQueued) running++; if (x.state == ADTaskStateDone) done++; }
            c.detailTextLabel.text = tasks.count ? [NSString stringWithFormat:@"%ld 本 · 进行中 %ld · 已完成 %ld", (long)tasks.count, (long)running, (long)done] : @"还没有下载";
            c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else if (ip.row == 1) {
            icon = @"internaldrive.fill"; ic = indigo;
            c.textLabel.text = @"离线存储管理";
            c.detailTextLabel.text = @"查看占用、清理缓存、重试失败";
            c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else {
            BOOL anyRunning = NO;
            for (ADTask *x in tasks) if (x.state == ADTaskStateRunning || x.state == ADTaskStateQueued) anyRunning = YES;
            icon = anyRunning ? @"pause.circle.fill" : @"play.circle.fill"; ic = anyRunning ? gray : orange;
            c.textLabel.text = anyRunning ? @"全部暂停" : @"全部继续";
            c.textLabel.textColor = tasks.count ? orange : [UIColor colorWithWhite:1 alpha:0.35];
        }
        c.selectionStyle = UITableViewCellSelectionStyleDefault;
        break;
    }
    case ADSecFeel: {
        if (ip.row == 0) {
            icon = @"hand.tap.fill"; ic = pink;
            c.textLabel.text = @"触控反馈";
            c.accessoryView = [self sw:@"ad_haptic" def:YES action:@selector(hapticSwitch:)];
        } else {
            icon = @"speaker.wave.2.fill"; ic = teal;
            c.textLabel.text = @"提示音";
            c.accessoryView = [self sw:@"ad_sound" def:YES action:@selector(soundSwitch:)];
        }
        break;
    }
    case ADSecData: {
        if (ip.row == 0) { icon = @"bookmark.fill"; ic = orange; c.textLabel.text = @"书签"; c.detailTextLabel.text = [NSString stringWithFormat:@"%ld 条", (long)[ADStore shared].bookmarks.count]; }
        else if (ip.row == 1) { icon = @"externaldrive.badge.timemachine"; ic = blue; c.textLabel.text = @"备份与恢复"; c.detailTextLabel.text = @"收藏、进度、听完标记、书签"; }
        else { icon = @"doc.text.magnifyingglass"; ic = purple; c.textLabel.text = @"运行日志"; c.detailTextLabel.text = @"出问题时导出并分享,可筛选网络、播放、错误"; }
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        c.selectionStyle = UITableViewCellSelectionStyleDefault;
        break;
    }
    default: {
        if (ip.row == 0) {
            icon = @"info.circle.fill"; ic = gray;
            c.textLabel.text = @"版本";
            UILabel *v = [ADUtil label:nil size:15 color:[UIColor colorWithWhite:1 alpha:0.6]];
            v.numberOfLines = 1;
            v.text = [NSString stringWithFormat:@"%@ (%@)", [self appVersion], [self buildNo]];
            [v sizeToFit]; c.accessoryView = v;
        } else if (ip.row == 1) {
            icon = @"arrow.triangle.2.circlepath"; ic = green;
            c.textLabel.text = self.checking ? @"正在检查…" : @"检查更新";
            c.detailTextLabel.text = self.latestTag.length ? [NSString stringWithFormat:@"GitHub 最新：%@", self.latestTag] : @"从 GitHub Release 获取最新版本";
            if (self.hasUpdate) {
                UILabel *b = [ADUtil label:nil size:11 color:UIColor.whiteColor];
                b.text = @"有新版本"; b.textAlignment = NSTextAlignmentCenter; b.numberOfLines = 1;
                b.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
                b.backgroundColor = orange; b.layer.cornerRadius = 10; b.clipsToBounds = YES;
                b.frame = CGRectMake(0, 0, 64, 20); c.accessoryView = b;
            } else if (self.checking) {
                UIActivityIndicatorView *sp = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
                sp.color = UIColor.whiteColor; [sp startAnimating]; c.accessoryView = sp;
            } else c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            c.selectionStyle = UITableViewCellSelectionStyleDefault;
        } else if (ip.row == 2) {
            icon = @"lock.fill"; ic = indigo;
            c.textLabel.text = @"GitHub 令牌";
            NSString *gt = [ADUpdater token];
            c.detailTextLabel.text = gt.length ? [NSString stringWithFormat:@"已设置 · %@…%@", [gt substringToIndex:MIN(4, gt.length)], gt.length > 8 ? [gt substringFromIndex:gt.length - 4] : @""] : @"私有仓库检查更新需要只读令牌";
            c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            c.selectionStyle = UITableViewCellSelectionStyleDefault;
        } else {
            icon = @"chevron.left.forwardslash.chevron.right"; ic = UIColor.darkGrayColor;
            c.textLabel.text = @"项目主页";
            c.detailTextLabel.text = [ADUpdater repo];
            c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            c.selectionStyle = UITableViewCellSelectionStyleDefault;
        }
        break;
    }
    }
    if (icon) {
        UIImageView *iv = [self icon:icon color:ic];
        UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(30, 30)];
        c.imageView.image = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) { [iv.layer renderInContext:ctx.CGContext]; }];
    }
    return c;
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    switch (ip.section) {
    case ADSecServer:
        if (ip.row == 0) [self editBaseURL];
        else if (ip.row == 1) [self editToken];
        else if (ip.row == 2) [self editAccount];
        else [self save];
        return;
    case ADSecPlay:
        if (ip.row == 3) {
            [ADOptionSheet showIn:self title:@"自动清理预缓存" options:@[@"不清理", @"3 天", @"7 天", @"30 天"] destructive:-1 choose:^(NSInteger i2) {
                NSArray *v = @[@0, @3, @7, @30];
                [NSUserDefaults.standardUserDefaults setInteger:[v[i2] integerValue] forKey:@"ad_prefetch_days"];
                [ADPlayer.shared cleanPrefetch];
                [self.table reloadData];
            }];
        } else if (ip.row == 4) {
            ADEditSkip(self, nil);      // 只改全局默认值；保存后弹窗回调会调 reloadSkipRows 刷新这一行
        }
        return;
    case ADSecStorage: {
        [ADHaptic tap];
        if (ip.row == 0) { [self.navigationController pushViewController:[ADDownloadsController new] animated:YES]; return; }
        if (ip.row == 1) { [self.navigationController pushViewController:[ADStorageController new] animated:YES]; return; }
        NSArray<ADTask *> *tasks = [ADDownloader shared].tasks;
        if (!tasks.count) return;
        BOOL anyRunning = NO;
        for (ADTask *x in tasks) if (x.state == ADTaskStateRunning || x.state == ADTaskStateQueued) anyRunning = YES;
        if (anyRunning) [[ADDownloader shared] pauseAll]; else [[ADDownloader shared] resumeAll];
        [t reloadData];
        return;
    }
    case ADSecData:
        [ADHaptic tap];
        if (ip.row == 2) [self.navigationController pushViewController:[ADLogController new] animated:YES];
        else [self.navigationController pushViewController:(ip.row == 0 ? [ADBookmarksController new] : [ADBackupController new]) animated:YES];
        return;
    case ADSecAbout:
        if (ip.row == 1) [self checkUpdate:YES];
        else if (ip.row == 2) [self editGitToken];
        else if (ip.row == 3) [UIApplication.sharedApplication openURL:[NSURL URLWithString:[@"https://github.com/" stringByAppendingString:[ADUpdater repo]]] options:@{} completionHandler:nil];
        return;
    default: return;
    }
}

// ── 检查更新 ──
- (void)checkUpdate:(BOOL)manual {
    if (self.checking) return;
    if (![ADUpdater token].length) {
        self.updateHint = @"仓库是私有的，先在「GitHub 令牌」里填一个只读令牌";
        [self.table reloadData];
        if (manual) [self editGitToken];
        return;
    }
    if (manual) [ADHaptic tap];
    self.checking = YES; [self.table reloadData];
    [ADUpdater fetchLatest:^(NSDictionary *rel, NSString *err) {
        self.checking = NO;
        if (!rel) {
            self.updateHint = err ?: @"检查失败";
            [self.table reloadData];
            if (manual) [self alert:@"检查失败" msg:self.updateHint];
            return;
        }
        NSString *tag = rel[@"tag"];
        self.latestTag = tag;
        self.hasUpdate = [ADUpdater isNewer:tag than:[self appVersion]];
        self.updateHint = self.hasUpdate ? [NSString stringWithFormat:@"发现新版本 %@，点「检查更新」查看", tag]
                                         : [NSString stringWithFormat:@"已是最新版本（%@）", [self appVersion]];
        [self.table reloadData];
        if (!manual) return;
        if (!self.hasUpdate) { [ADHaptic success]; [self alert:@"已是最新" msg:[NSString stringWithFormat:@"当前 %@，GitHub 最新 %@", [self appVersion], tag]]; return; }
        [ADHaptic success];
        NSString *body = [rel[@"notes"] length] ? rel[@"notes"] : @"";
        if (body.length > 600) body = [[body substringToIndex:600] stringByAppendingString:@"…"];
        UIAlertController *a = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"新版本 %@", tag]
                                                                   message:[NSString stringWithFormat:@"当前 %@\n\n%@", [self appVersion], body]
                                                            preferredStyle:UIAlertControllerStyleAlert];
        if ([rel[@"ipa"] length]) {
            [a addAction:[UIAlertAction actionWithTitle:@"下载安装包" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { [self downloadIPA:rel]; }]];
        }
        [a addAction:[UIAlertAction actionWithTitle:@"在 GitHub 查看" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            [UIApplication.sharedApplication openURL:[NSURL URLWithString:rel[@"page"]] options:@{} completionHandler:nil];
        }]];
        [a addAction:[UIAlertAction actionWithTitle:@"稍后" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
    }];
}

- (void)downloadIPA:(NSDictionary *)rel {
    self.updateHint = @"正在下载安装包…";
    [self.table reloadData];
    [ADUpdater downloadAsset:rel progress:^(double p) {
        self.updateHint = [NSString stringWithFormat:@"正在下载安装包… %ld%%", (long)lround(p * 100)];
        [self.table reloadData];
    } done:^(NSURL *file, NSString *err) {
        if (!file) { self.updateHint = err ?: @"下载失败"; [self.table reloadData]; [self alert:@"下载失败" msg:self.updateHint]; return; }
        self.updateHint = @"已下载，用 TrollStore 或签名工具打开安装";
        [self.table reloadData];
        [ADHaptic success];
        UIActivityViewController *av = [[UIActivityViewController alloc] initWithActivityItems:@[file] applicationActivities:nil];
        av.popoverPresentationController.sourceView = self.view;
        [self presentViewController:av animated:YES completion:nil];
    }];
}

- (void)editGitToken {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"GitHub 令牌"
                                                               message:@"仓库是私有的，检查更新需要一个只读令牌。\n建议：GitHub → Settings → Developer settings → Fine-grained token，只给这个仓库的 Contents: Read-only。"
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = [ADUpdater token];
        tf.placeholder = @"github_pat_… / ghp_…";
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.secureTextEntry = YES;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"清除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        [ADUpdater setToken:@""]; self.latestTag = nil; self.hasUpdate = NO; self.updateHint = nil; [self.table reloadData];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"从剪贴板粘贴" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *p = [UIPasteboard.generalPasteboard.string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (p.length) { [ADUpdater setToken:p]; [self.table reloadData]; [self checkUpdate:YES]; }
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"保存并检查" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [ADUpdater setToken:[a.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]];
        [self.table reloadData];
        [self checkUpdate:YES];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)alert:(NSString *)t msg:(NSString *)m {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:t message:m preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf { [tf resignFirstResponder]; [self save]; return YES; }
@end
