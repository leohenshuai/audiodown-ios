#import "AD.h"

@implementation ADUtil

+ (UIColor *)brand { return [UIColor colorWithRed:0.973 green:0.392 blue:0.26 alpha:1]; }   // #F86442
+ (UIColor *)bg { return [UIColor colorWithRed:0.086 green:0.055 blue:0.039 alpha:1]; }      // 深棕
+ (UIColor *)card { return [UIColor colorWithWhite:1 alpha:0.07]; }
+ (UIColor *)dim { return [UIColor colorWithWhite:1 alpha:0.55]; }

+ (UILabel *)label:(NSString *)font size:(CGFloat)size color:(UIColor *)c {
    UILabel *l = [UILabel new];
    l.font = [UIFont fontWithName:font size:size] ?: [UIFont systemFontOfSize:size];
    l.textColor = c; l.numberOfLines = 0;
    return l;
}

+ (NSString *)timeString:(double)sec {
    if (isnan(sec) || sec < 0) sec = 0;
    int s = (int)sec;
    int h = s / 3600, m = (s % 3600) / 60, ss = s % 60;
    if (h > 0) return [NSString stringWithFormat:@"%d:%02d:%02d", h, m, ss];
    return [NSString stringWithFormat:@"%02d:%02d", m, ss];
}

+ (void)coverInto:(UIImageView *)iv url:(NSString *)url {
    iv.contentMode = UIViewContentModeScaleAspectFill;
    iv.clipsToBounds = YES;
    iv.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
    iv.image = nil;
    if (!url.length) return;
    NSURL *u = [url hasPrefix:@"http"] ? [NSURL URLWithString:url] : [NSURL URLWithString:[[ADConfig shared] urlFor:url args:@{}]];
    if (!u) return;
    [[[NSURLSession sharedSession] dataTaskWithURL:u completionHandler:^(NSData *data, NSURLResponse *r, NSError *e) {
        if (!data.length) return;
        UIImage *img = [UIImage imageWithData:data];
        if (!img) return;
        dispatch_async(dispatch_get_main_queue(), ^{ if (iv.image == nil) iv.image = img; });
    }] resume];
}

@end
