#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class AVPlayer;
NS_ASSUME_NONNULL_BEGIN

// ───────────────── 配置 ─────────────────
@interface ADConfig : NSObject
@property (nonatomic, copy) NSString *baseURL;
@property (nonatomic, copy) NSString *token;
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
- (void)touchHistory:(ADAlbum *)a;
- (double)positionFor:(NSString *)trackId;
- (void)setPosition:(double)sec for:(NSString *)trackId;
- (NSString *)lastTrackOf:(NSString *)albumId;
- (void)setLastTrack:(NSString *)trackId album:(NSString *)albumId;
- (void)save;
@end

// ───────────────── 网络 ─────────────────
typedef void (^ADErr)(NSString * _Nullable err);
@interface ADApi : NSObject
+ (instancetype)shared;
- (void)discover:(void (^)(NSArray<NSDictionary *> *sections, NSString * _Nullable err))cb;
- (void)search:(NSString *)q page:(NSInteger)page done:(void (^)(NSArray<ADAlbum *> *list, BOOL more, NSString * _Nullable err))cb;
- (void)albumDetail:(NSString *)albumId done:(void (^)(ADAlbum * _Nullable a, NSString * _Nullable err))cb;
- (void)tracksOf:(NSString *)albumId page:(NSInteger)page done:(void (^)(NSArray<ADTrack *> *list, NSInteger total, NSString * _Nullable err))cb;
- (void)playURLOf:(ADTrack *)t done:(void (^)(NSString * _Nullable url, NSDictionary * _Nullable headers, NSString * _Nullable err))cb;
- (void)downloads:(void (^)(NSArray<NSDictionary *> *items, NSString * _Nullable err))cb;
@end

// ───────────────── 播放器 ─────────────────
@interface ADPlayer : NSObject
@property (nonatomic, strong, nullable) ADAlbum *album;
@property (nonatomic, strong) NSArray<ADTrack *> *tracks;
@property (nonatomic, assign) NSInteger index;
@property (nonatomic, assign) float rate;
@property (nonatomic, assign) double sleepDeadline;   // 0 关闭
@property (nonatomic, copy, nullable) NSString *statusText;
+ (instancetype)shared;
- (AVPlayer *)player;
- (nullable ADTrack *)current;
- (BOOL)isPlaying;
- (void)playAlbum:(ADAlbum *)album tracks:(NSArray<ADTrack *> *)tracks at:(NSInteger)index;
- (void)playAt:(NSInteger)index;
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
