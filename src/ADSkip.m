#import "AD.h"
#import <CoreImage/CoreImage.h>
#import <objc/runtime.h>
#import <MediaPlayer/MediaPlayer.h>
#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>
#import "ADInternal.h"

// ───────────── 跳过片头片尾（设置入口） ─────────────
// 真正的跳播在播放器里做；这里只负责：给菜单一行摘要文案、给用户一个能改的地方。
// 每本书可以单独设，没单独设过就落回全局默认值（ad_skip_head / ad_skip_tail）。

double ADSkipClamp(double v) {
    if (isnan(v) || v < 0) v = 0;
    if (v > 600) v = 600;
    return v;
}

NSString *ADSkipSummary(ADAlbum *album) {
    double h = 0, t = 0;
    if (album.albumId.length) {
        h = [[ADStore shared] skipHeadOf:album.albumId];
        t = [[ADStore shared] skipTailOf:album.albumId];
    } else {
        NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
        h = [ud doubleForKey:@"ad_skip_head"];
        t = [ud doubleForKey:@"ad_skip_tail"];
    }
    h = ADSkipClamp(h); t = ADSkipClamp(t);
    if (h <= 0 && t <= 0) return (album.albumId.length && [[ADStore shared] hasSkipOf:album.albumId]) ? @"不跳（已单独设置）" : @"未设置";
    if (h <= 0) return [NSString stringWithFormat:@"片尾 %.0f 秒", t];
    if (t <= 0) return [NSString stringWithFormat:@"片头 %.0f 秒", h];
    return [NSString stringWithFormat:@"片头 %.0f 秒 · 片尾 %.0f 秒", h, t];
}

// album 非空 → 默认只存这本书，可选"同时设为所有书的默认"；album 为空 → 只改全局默认。
void ADEditSkip(UIViewController *host, ADAlbum *album) {
    if (!host) return;
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    NSString *aid = album.albumId.length ? album.albumId : nil;
    double head = aid ? [[ADStore shared] skipHeadOf:aid] : [ud doubleForKey:@"ad_skip_head"];
    double tail = aid ? [[ADStore shared] skipTailOf:aid] : [ud doubleForKey:@"ad_skip_tail"];
    head = ADSkipClamp(head); tail = ADSkipClamp(tail);

    NSString *msg = aid
        ? [NSString stringWithFormat:@"每集开始自动跳过片头、结尾提前进入下一集；填 0 表示不跳。当前仅对《%@》生效", album.title.length ? album.title : @"这本书"]
        : @"每集开始自动跳过片头、结尾提前进入下一集；填 0 表示不跳。设置全局默认值，对没有单独设置过的书生效";
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"跳过片头片尾" message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"片头(秒)";
        tf.keyboardType = UIKeyboardTypeDecimalPad;
        tf.text = head > 0 ? [NSString stringWithFormat:@"%.0f", head] : @"";
    }];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"片尾(秒)";
        tf.keyboardType = UIKeyboardTypeDecimalPad;
        tf.text = tail > 0 ? [NSString stringWithFormat:@"%.0f", tail] : @"";
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    if (aid && [[ADStore shared] hasSkipOf:aid]) {
        [a addAction:[UIAlertAction actionWithTitle:@"恢复默认" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
            [[ADStore shared] clearSkipOfAlbum:aid];
            [ADHaptic warning];
            if ([host respondsToSelector:@selector(reloadSkipRows)]) [(id<ADSkipReloader>)host reloadSkipRows];
        }]];
    }
    __weak UIAlertController *wa = a;          // 弱引用:alert 持有 action → handler,handler 不能反过来强持有 alert
    void (^doSave)(BOOL) = ^(BOOL asDefault) {
        UIAlertController *ac = wa; if (!ac) return;
        double h = ADSkipClamp([[ac.textFields[0] text] doubleValue]);
        double t = ADSkipClamp([[ac.textFields[1] text] doubleValue]);
        if (aid) [[ADStore shared] setSkipHead:h tail:t forAlbum:aid];
        if (asDefault || !aid) { [ud setDouble:h forKey:@"ad_skip_head"]; [ud setDouble:t forKey:@"ad_skip_tail"]; }
        [ADHaptic success];
        if ([host respondsToSelector:@selector(reloadSkipRows)]) [(id<ADSkipReloader>)host reloadSkipRows];
    };
    if (aid) {
        [a addAction:[UIAlertAction actionWithTitle:@"保存并设为所有书的默认" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { doSave(YES); }]];
        [a addAction:[UIAlertAction actionWithTitle:@"只保存这本书" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { doSave(NO); }]];
    } else {
        [a addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { doSave(YES); }]];
    }
    [host presentViewController:a animated:YES completion:nil];
}

// ───────────── 专辑详情 ─────────────
