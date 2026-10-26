#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class AVPlayer;
NS_ASSUME_NONNULL_BEGIN

// ───────────────── 配置 ─────────────────
@interface ADConfig : NSObject
@property (nonatomic, copy) NSString *baseURL;
@property (nonatomic, copy) NSString *token;
@property (nonatomic, copy) NSString *username;   // 网页后台账号（可选，用来拿 VIP 专辑的目录）
@property (nonatomic, copy) NSString *password;
+ (instancetype)shared;
- (void)save;
- (NSDictionary *)headers;
- (NSString *)url:(NSString *)path;
@end

// ───────────────── 模型 ─────────────────
@interface ADAlbum : NSObject <NSCoding>
@property (nonatomic, copy) NSString *albumId, *title, *cover, *anchor, *author, *reader, *intro, *provider;
@property (nonatomic, assign) NSInteger trackCount;
@property (nonatomic, assign) double playCount;
@property (nonatomic, assign) BOOL isFinished, isPaid;
+ (instancetype)fromJSON:(NSDictionary *)j;
@end

@interface ADTrack : NSObject
@property (nonatomic, copy) NSString *trackId, *title, *albumId, *provider;
@property (nonatomic, assign) NSInteger index;
@property (nonatomic, assign) double duration;
+ (instancetype)fromJSON:(NSDictionary *)j album:(ADAlbum *)a;
@end

// ───────────────── 本地存储 ─────────────────
@interface ADStore : NSObject
+ (instancetype)shared;
- (NSArray<ADAlbum *> *)favorites;
- (BOOL)isFavorite:(NSString *)albumId;
- (void)toggleFavorite:(ADAlbum *)a;
- (NSArray<ADAlbum *> *)history;                    // 最近收听
- (NSArray<ADAlbum *> *)wants;                      // 想听
- (BOOL)isWanted:(nullable NSString *)albumId;
- (void)toggleWant:(ADAlbum *)a;
- (BOOL)isPinned:(nullable NSString *)albumId;
- (void)togglePin:(nullable NSString *)albumId;
- (void)removeHistory:(nullable NSString *)albumId;
- (void)touchHistory:(ADAlbum *)a;
- (double)positionFor:(NSString *)trackId;
- (BOOL)isDone:(nullable NSString *)trackId;
- (void)markDone:(nullable NSString *)trackId album:(nullable NSString *)albumId wholeBook:(BOOL)whole;
- (BOOL)isAlbumDone:(nullable NSString *)albumId;
- (void)setPosition:(double)sec for:(NSString *)trackId;
- (NSString *)lastTrackOf:(NSString *)albumId;
- (NSDictionary *)lastInfoOf:(NSString *)albumId;
- (void)setLastInfo:(NSDictionary *)info album:(NSString *)albumId;
- (void)setLastTrack:(NSString *)trackId album:(NSString *)albumId;
- (void)save;
@end

// ───────────────── iOS26 设计系统 ─────────────────
@interface ADLiquid : NSObject
+ (void)canvas:(UIView *)v;                                  // 背景：渐变 + 双光斑（带缓慢漂移）
+ (void)glass:(UIView *)v radius:(CGFloat)r;                 // 玻璃面
+ (void)glass:(UIView *)v radius:(CGFloat)r alpha:(CGFloat)alpha;
+ (void)corner:(CGFloat)r on:(UIView *)v;
+ (void)glassLite:(UIView *)v radius:(CGFloat)r;               // 轻量玻璃（无实时模糊，列表行用）
+ (void)glassButton:(UIButton *)b radius:(CGFloat)r;          // 按钮用的玻璃（不遮挡图标）
+ (nullable UIColor *)tintFromImage:(nullable UIImage *)img;    // 封面主色
+ (void)recolor:(UIView *)v with:(UIColor *)color;             // 光斑换成封面色（渐变过渡）
+ (void)followScroll:(UIScrollView *)sv lastY:(CGFloat *)lastY; // 导航随滚动呼吸
+ (void)float:(UIView *)v;                                   // 悬浮投影
+ (void)press:(UIView *)v;                                   // 按压缩放
+ (void)pulse:(UIView *)v;
+ (void)breathe:(UIView *)v on:(BOOL)on;                      // 播放中封面呼吸
+ (void)rise:(UIView *)v delay:(NSTimeInterval)delay;        // 入场
@end

@interface ADNavDock : UIView
+ (instancetype)shared;
@property (nonatomic, assign) NSInteger selectedIndex;
@property (nonatomic, assign) BOOL dockVisible;
@property (nonatomic, copy) void (^onSelect)(NSInteger index);
@property (nonatomic, weak, nullable) UIViewController *hostSelected;   // 当前页的根控制器（用来“再点回根”）
- (void)show:(BOOL)show animated:(BOOL)animated;
- (CGFloat)topY;
@end

// 自建容器：不再继承 UITabBarController，系统底栏不存在，也就不会重影
@interface ADDockController : UIViewController
@property (nonatomic, strong) NSArray<UIViewController *> *pages;
@property (nonatomic, assign) NSInteger selectedIndex;
@property (nonatomic, readonly, nullable) UIViewController *selectedViewController;
@property (nonatomic, copy, nullable) void (^onChange)(NSInteger idx);
@end

// ───────────────── 触感 / 提示音 ─────────────────
@interface ADHaptic : NSObject
+ (void)tap;        // 轻点：按钮、行、卡片
+ (void)select;     // 选择：分段、分类、菜单项
+ (void)soft;       // 滑动、拖动结束
+ (void)heavy;      // 长按、打开菜单
+ (void)success;    // 收藏、下载完成、保存成功
+ (void)warning;
+ (void)error;
@end

// ───────────────── 网络 ─────────────────
typedef void (^ADErr)(NSString * _Nullable err);
@interface ADApi : NSObject
+ (instancetype)shared;
- (void)discover:(void (^)(NSArray<NSDictionary *> *sections, BOOL cached, NSString * _Nullable err))cb;
- (void)search:(NSString *)q page:(NSInteger)page done:(void (^)(NSArray<ADAlbum *> *list, BOOL more, BOOL cached, NSString * _Nullable err))cb;
- (void)albumDetail:(NSString *)albumId done:(void (^)(ADAlbum * _Nullable a, BOOL cached, NSString * _Nullable err))cb;
- (void)tracksOf:(NSString *)albumId page:(NSInteger)page done:(void (^)(NSArray<ADTrack *> *list, NSInteger total, BOOL cached, NSString * _Nullable err))cb;
- (void)tracksOf:(NSString *)albumId page:(NSInteger)page pageSize:(NSInteger)size done:(void (^)(NSArray<ADTrack *> *list, NSInteger total, BOOL cached, NSString * _Nullable err))cb;
- (void)playURLOf:(ADTrack *)t done:(void (^)(NSString * _Nullable url, NSDictionary * _Nullable headers, NSString * _Nullable err))cb;
- (void)downloads:(void (^)(NSArray<NSDictionary *> *items, NSString * _Nullable err))cb;
- (void)rawGET:(NSString *)path timeout:(NSTimeInterval)timeout done:(void (^)(NSInteger code, NSString *body, NSString * _Nullable err))cb;
- (BOOL)hasAccount;
- (void)panelLogin:(void (^)(BOOL ok, NSString * _Nullable err))cb;
- (void)panelTracksOf:(NSString *)albumId page:(NSInteger)page size:(NSInteger)size done:(void (^)(NSArray<ADTrack *> *list, NSInteger total, NSString * _Nullable err))cb;
@end


// ───────────────── 下载任务 ─────────────────
typedef NS_ENUM(NSInteger, ADTaskState) {
    ADTaskStateQueued = 0,
    ADTaskStateRunning,
    ADTaskStatePaused,
    ADTaskStateDone,
    ADTaskStateFailed
};

@interface ADTask : NSObject <NSCoding>
@property (nonatomic, copy) NSString *albumId, *title, *cover, *anchor, *provider;
@property (nonatomic, strong) NSArray<ADTrack *> *tracks;
@property (nonatomic, assign) NSInteger done, failed, state, cursor;
@property (nonatomic, assign) double bytes;
@end

@interface ADDownloader : NSObject
+ (instancetype)shared;
- (NSArray<ADTask *> *)tasks;
- (nullable ADTask *)taskForAlbum:(NSString *)albumId;
- (void)addAlbum:(ADAlbum *)a tracks:(NSArray<ADTrack *> *)tracks;
- (void)addTracks:(ADAlbum *)a tracks:(NSArray<ADTrack *> *)tracks;
- (void)pauseTask:(ADTask *)t;
- (void)resumeTask:(ADTask *)t;
- (void)deleteTask:(ADTask *)t;
- (void)pauseAll;
- (void)resumeAll;
- (BOOL)hasLocal:(nullable NSString *)trackId;
- (void)removeLocal:(NSString *)trackId;
- (nullable NSURL *)localURL:(nullable NSString *)trackId;
@end

// ───────────────── 播放器 ─────────────────
@interface ADPlayer : NSObject
@property (nonatomic, strong, nullable) ADAlbum *album;
@property (nonatomic, strong) NSArray<ADTrack *> *tracks;
@property (nonatomic, assign) NSInteger index;
@property (nonatomic, assign) float rate;
@property (nonatomic, assign) double sleepDeadline;
@property (nonatomic, strong) NSMutableSet *prefetching;
+ (BOOL)isWiFi;
- (void)prefetchAhead;
- (void)cleanPrefetch;
- (NSString *)prefetchPath:(NSString *)trackId;
@property (nonatomic, assign) BOOL stopAfterChapter;   // 0 关闭
@property (nonatomic, copy, nullable) NSString *statusText;
+ (instancetype)shared;
- (AVPlayer *)player;
- (nullable ADTrack *)current;
- (BOOL)isPlaying;
- (void)playAlbum:(ADAlbum *)album tracks:(NSArray<ADTrack *> *)tracks at:(NSInteger)index;
- (void)playAt:(NSInteger)index;
- (void)ensureFullQueue;      // 队列被截断（只有前 50/100 集）时把后面的目录补齐
- (void)toggle;
- (void)pause;
- (void)next;
- (void)prev;
- (void)seekTo:(double)sec;
- (void)seekBy:(double)delta;
- (void)start;
@end

// ───────────────── 工具 ─────────────────
@interface ADUtil : NSObject
+ (UIColor *)brand;
+ (UIColor *)bg;
+ (UIColor *)card;
+ (UIColor *)dim;
+ (UILabel *)label:(nullable NSString *)font size:(CGFloat)size color:(UIColor *)c;
+ (NSString *)time:(double)sec;
+ (NSString *)count:(double)n;
+ (void)cover:(UIImageView *)iv url:(nullable NSString *)url;
+ (NSString *)coverDir;
+ (void)togglePlaceholder:(UIImageView *)iv hidden:(BOOL)hidden;
+ (double)parseDuration:(nullable NSString *)text;
@end

NS_ASSUME_NONNULL_END

// 跨文件
@interface ADDiscoverController : UIViewController @end
@interface ADSearchController : UIViewController @end
@interface ADShelfController : UIViewController @end
@interface ADSettingsController : UIViewController @end
@interface ADAlbumController : UIViewController
@property (nonatomic, strong) ADAlbum *album;
@end
@interface ADPlayerController : UIViewController @end
@interface ADOptionSheet : NSObject
+ (void)showIn:(UIViewController *)vc title:(NSString *)title options:(NSArray<NSString *> *)options destructive:(NSInteger)destructiveIndex choose:(void (^)(NSInteger index))choose;
@end

@interface ADHistoryController : UITableViewController @end
@interface ADDownloadsController : UITableViewController @end
