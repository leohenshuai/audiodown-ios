#import "AD.h"
// 内部共享:只给 ADDetail / ADPlayerUI / ADSettingsUI / ADSkip 用
#define kSegLen 60
@protocol ADSkipReloader <NSObject>
- (void)reloadSkipRows;      // 设置页实现:改完弹窗让那一行文案刷新
@end
extern double ADSkipClamp(double v);
extern NSString *ADSkipSummary(ADAlbum *album);

// 迷你播放条(实现在 ADHome.m)
@interface ADMiniBar : UIView
+ (instancetype)shared;
- (void)refresh;
- (void)unfoldNow;
@end
