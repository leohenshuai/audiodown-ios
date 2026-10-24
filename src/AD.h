#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class AVPlayer;

NS_ASSUME_NONNULL_BEGIN

// ─────────────────────────── 配置 ───────────────────────────
@interface ADConfig : NSObject
@property (nonatomic, copy) NSString *baseURL;      // https://audio.959935291.xyz:899
@property (nonatomic, copy) NSString *token;
@property (nonatomic, copy) NSString *authHeader;   // 例如 Authorization / X-Token / X-Api-Key
@property (nonatomic, copy) NSString *authScheme;   // 例如 Bearer  / Token / (空)
// 接口路径，支持 {id} {q} 占位符
@property (nonatomic, copy) NSString *pathMe;
@property (nonatomic, copy) NSString *pathList;
@property (nonatomic, copy) NSString *pathSearch;
@property (nonatomic, copy) NSString *pathBook;
@property (nonatomic, copy) NSString *pathStream;
@property (nonatomic, copy) NSString *pathProgress;
// JSON 取字段路径，支持 a.b.c 与 a[0]
@property (nonatomic, copy) NSString *listPath;     // 书籍数组所在位置，空=自动
+ (instancetype)shared;
- (void)save;
- (NSDictionary *)headers;
- (NSString *)urlFor:(NSString *)tmpl args:(NSDictionary<NSString *, NSString *> *)args;
@end

// ─────────────────────────── 数据 ───────────────────────────
@interface ADChapter : NSObject <NSCoding>
@property (nonatomic, copy) NSString *fid;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *streamURL;
@property (nonatomic, assign) double duration;
+ (instancetype)fromJSON:(NSDictionary *)json;
@end

@interface ADBook : NSObject <NSCoding>
@property (nonatomic, copy) NSString *bid;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *author;
@property (nonatomic, copy) NSString *narrator;
@property (nonatomic, copy) NSString *cover;
@property (nonatomic, copy) NSString *summary;
@property (nonatomic, strong) NSArray<ADChapter *> *chapters;
+ (instancetype)fromJSON:(NSDictionary *)json;
@end

@interface ADStore : NSObject
+ (instancetype)shared;
@property (nonatomic, strong, readonly) NSMutableArray<ADBook *> *shelf;
- (void)save;
- (void)addBook:(ADBook *)b;
- (void)removeBook:(ADBook *)b;
- (double)progressForChapter:(NSString *)cid;
- (void)setProgress:(double)p forChapter:(NSString *)cid;
- (NSString *)lastChapterOfBook:(NSString *)bid;
- (void)setLastChapter:(NSString *)cid book:(NSString *)bid;
@end

// ─────────────────────────── 网络 ───────────────────────────
typedef void (^ADJSONBlock)(id _Nullable json, NSError *_Nullable err, NSInteger status);
@interface ADAPI : NSObject
+ (instancetype)shared;
- (void)request:(NSString *)pathOrURL method:(NSString *)method body:(nullable id)body completion:(ADJSONBlock)cb;
- (void)me:(ADJSONBlock)cb;
- (void)fetchList:(nullable NSString *)query completion:(ADJSONBlock)cb;
- (void)fetchBook:(NSString *)bid completion:(ADJSONBlock)cb;
- (void)reportProgress:(NSString *)bid chapter:(NSString *)cid seconds:(double)s chapterProgress:(double)p;
- (nullable NSURL *)streamURLFor:(ADChapter *)ch;
// 认证测试：逐个尝试常见方式，返回命中描述
- (void)probeAuth:(void (^)(NSString *report))cb;
+ (nullable id)valueAt:(NSString *)path in:(id)obj;
+ (NSString *)stringAt:(NSString *)path in:(id)obj;
+ (double)doubleAt:(NSString *)path in:(id)obj;
@end

// ─────────────────────────── 播放器 ───────────────────────────
@interface ADPlayer : NSObject
@property (nonatomic, strong, nullable) ADBook *book;
@property (nonatomic, assign) NSInteger index;
@property (nonatomic, assign) float rate;
@property (nonatomic, assign) double sleepTimerDeadline; // 0 = 关
+ (instancetype)shared;
- (void)playBook:(ADBook *)book at:(NSInteger)index;
- (void)playIndex:(NSInteger)index;
- (void)toggle;
- (void)pause;
- (void)next; - (void)prev;
- (void)seekTo:(double)sec;
- (void)seekBy:(double)delta;
- (AVPlayer *)player;
- (nullable ADChapter *)currentChapter;
- (void)setupRemoteCommands;
@end

// ─────────────────────────── 工具 ───────────────────────────
@interface ADUtil : NSObject
+ (NSString *)timeString:(double)sec;
+ (void)coverInto:(UIImageView *)iv url:(nullable NSString *)url;
+ (UILabel *)label:(NSString *)font size:(CGFloat)size color:(UIColor *)c;
+ (UIColor *)brand;
+ (UIColor *)bg;
+ (UIColor *)card;
+ (UIColor *)dim;
@end

NS_ASSUME_NONNULL_END
