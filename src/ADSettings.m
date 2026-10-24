#import "AD.h"
#import "ADInternal.h"

@interface ADSettingsController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@property (nonatomic, strong) NSMutableArray<UITextField *> *fields;
@property (nonatomic, strong) UITableView *tv;
@property (nonatomic, strong) UILabel *status;
@property (nonatomic, strong) UIActivityIndicatorView *spin;
@end

@implementation ADSettingsController {
    NSArray *_sections;
    NSArray *_keys;
    NSArray *_titles;
    NSArray *_placeholders;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"设置";
    self.view.backgroundColor = [ADUtil bg];
    self.navigationController.navigationBar.tintColor = UIColor.whiteColor;

    _sections = @[@"服务", @"接口路径", @"调试"];
    _keys = @[
        @[@"baseURL", @"token", @"authHeader", @"authScheme"],
        @[@"pathList", @"pathSearch", @"pathBook", @"pathStream", @"pathProgress", @"pathMe", @"listPath"],
        @[]
    ];
    _titles = @[
        @[@"服务地址", @"Token", @"认证请求头", @"认证前缀"],
        @[@"书单接口", @"搜索接口", @"书籍详情", @"音频地址", @"进度上报", @"用户信息", @"书单字段路径"],
        @[]
    ];
    _placeholders = @[
        @[@"https://…", @"粘贴 token", @"Authorization", @"Bearer"],
        @[@"{q} 代表关键词", @"", @"{id} 代表书籍 ID", @"{id} 代表章节 ID", @"留空则不上报", @"", @"如 data.list，留空自动"],
        @[]
    ];
    self.fields = [NSMutableArray array];
    for (NSInteger i = 0; i < (NSInteger)_keys.count; i++)
        for (NSInteger j = 0; j < (NSInteger)[(NSArray *)_keys[i] count]; j++) [self.fields addObject:[UITextField new]];

    self.tv = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tv.backgroundColor = UIColor.clearColor;
    self.tv.dataSource = self; self.tv.delegate = self;
    self.tv.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:self.tv];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"保存" style:UIBarButtonItemStyleDone target:self action:@selector(save)];
    [self loadFields];
}

- (void)loadFields {
    ADConfig *c = [ADConfig shared];
    NSArray *vals = @[c.baseURL ?: @"", c.token ?: @"", c.authHeader ?: @"", c.authScheme ?: @"",
                      c.pathList ?: @"", c.pathSearch ?: @"", c.pathBook ?: @"", c.pathStream ?: @"",
                      c.pathProgress ?: @"", c.pathMe ?: @"", c.listPath ?: @""];
    for (NSUInteger i = 0; i < self.fields.count && i < vals.count; i++) {
        self.fields[i].placeholder = [self placeholderAt:i];
        self.fields[i].text = vals[i];
        self.fields[i].delegate = self;
        self.fields[i].textColor = UIColor.whiteColor;
        self.fields[i].autocapitalizationType = UITextAutocapitalizationTypeNone;
        self.fields[i].autocorrectionType = UITextAutocorrectionTypeNo;
        self.fields[i].clearButtonMode = UITextFieldViewModeWhileEditing;
        self.fields[i].font = [UIFont systemFontOfSize:14];
        self.fields[i].returnKeyType = UIReturnKeyDone;
    }
    self.fields[1].secureTextEntry = NO;
}

- (NSString *)placeholderAt:(NSInteger)i {
    NSInteger k = i;
    for (NSArray *arr in _placeholders) { if (k < (NSInteger)arr.count) return arr[k]; k -= arr.count; }
    return @"";
}

- (void)save {
    ADConfig *c = [ADConfig shared];
    NSArray *vals = [self.fields valueForKey:@"text"];
    c.baseURL = vals[0]; c.token = vals[1]; c.authHeader = vals[2]; c.authScheme = vals[3];
    c.pathList = vals[4]; c.pathSearch = vals[5]; c.pathBook = vals[6]; c.pathStream = vals[7];
    c.pathProgress = vals[8]; c.pathMe = vals[9]; c.listPath = vals[10];
    [c save];
    UIImpactFeedbackGenerator *h = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [h impactOccurred];
    [self showAlert:@"已保存" msg:@"回到书架下拉刷新即可生效"];
}

- (void)showAlert:(NSString *)t msg:(NSString *)m {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:t message:m preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

// ───── 表格 ─────
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return _sections.count; }
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s { return _sections[s]; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if (s == 0) return 4;
    if (s == 1) return 7;
    return 4;
}
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.backgroundColor = [ADUtil card];
    cell.textLabel.textColor = UIColor.whiteColor;
    cell.textLabel.font = [UIFont systemFontOfSize:14];
    if (ip.section == 2) {
        cell.textLabel.text = @[@"测试连接", @"自动探测认证方式", @"查看原始返回", @"恢复默认接口路径"][ip.row];
        cell.textLabel.textColor = [ADUtil brand];
        return cell;
    }
    cell.textLabel.text = _titles[ip.section][ip.row];
    UITextField *f = self.fields[[self fieldIndex:ip]];
    f.frame = CGRectMake(cell.contentView.bounds.size.width - 200 - 16, 6, 196, 32);
    f.textAlignment = NSTextAlignmentRight;
    f.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [cell.contentView addSubview:f];
    return cell;
}
- (NSInteger)fieldIndex:(NSIndexPath *)ip {
    NSInteger n = 0;
    for (NSInteger s = 0; s < ip.section; s++) n += [_keys[s] count];
    return n + ip.row;
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section != 2) {
        [[self.fields objectAtIndex:[self fieldIndex:ip]] becomeFirstResponder];
        return;
    }
    [self save];
    if (ip.row == 0) [self testConnection];
    else if (ip.row == 1) [self probe];
    else if (ip.row == 2) [self showRaw];
    else { [self resetPaths]; }
}

- (void)resetPaths {
    ADConfig *c = [ADConfig shared];
    c.pathMe = @"/api/me"; c.pathList = @"/api/books"; c.pathSearch = @"/api/search?q={q}";
    c.pathBook = @"/api/books/{id}"; c.pathStream = @"/api/books/{id}/stream"; c.pathProgress = @"/api/progress";
    c.listPath = @""; [c save]; [self loadFields]; [self.tv reloadData];
    [self showAlert:@"已恢复" msg:@"接口路径已重置为默认猜测值"];
}

- (void)testConnection {
    [self busy:@"正在请求…"];
    [[ADAPI shared] me:^(id json, NSError *err, NSInteger code) {
        [self doneBusy];
        NSString *body = [self preview:json];
        [self showAlert:[NSString stringWithFormat:@"HTTP %ld", (long)code]
                    msg:[NSString stringWithFormat:@"%@\n\n%@", err.localizedDescription ?: @"", body]];
    }];
}

- (void)probe {
    [self busy:@"逐个尝试认证方式…"];
    [[ADAPI shared] probeAuth:^(NSString *report) {
        [self doneBusy];
        [self showAlert:@"探测结果" msg:report];
        [self loadFields]; [self.tv reloadData];
    }];
}

- (NSString *)preview:(id)json {
    if (!json) return @"(空)";
    if ([json isKindOfClass:[NSString class]]) return [(NSString *)json substringToIndex:MIN(400, [(NSString *)json length])];
    NSData *d = [NSJSONSerialization dataWithJSONObject:json options:NSJSONWritingPrettyPrinted error:nil];
    NSString *s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    return s.length > 800 ? [[s substringToIndex:800] stringByAppendingString:@"…"] : s;
}

- (void)showRaw {
    [self busy:@"正在请求书单…"];
    [[ADAPI shared] fetchList:nil completion:^(id json, NSError *err, NSInteger code) {
        [self doneBusy];
        NSString *url = [[ADConfig shared] urlFor:[ADConfig shared].pathList args:@{}];
        NSMutableString *m = [NSMutableString stringWithFormat:@"GET %@\nHTTP %ld\n\n", url, (long)code];
        [m appendString:[self preview:json]];
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"原始返回" message:m preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
        [a addAction:[UIAlertAction actionWithTitle:@"复制" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            UIPasteboard.generalPasteboard.string = m;
        }]];
        [self presentViewController:a animated:YES completion:nil];
        NSLog(@"[AudioDown] raw: %@", m);
    }];
}

- (void)busy:(NSString *)msg {
    if (!self.spin) { self.spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium]; self.spin.color = UIColor.whiteColor; self.spin.center = self.view.center; [self.view addSubview:self.spin]; }
    [self.spin startAnimating];
    self.navigationItem.title = msg;
}
- (void)doneBusy { [self.spin stopAnimating]; self.navigationItem.title = @"设置"; }

- (BOOL)textFieldShouldReturn:(UITextField *)tf { [tf resignFirstResponder]; return YES; }
@end
