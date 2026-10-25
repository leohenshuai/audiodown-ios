#import "AD.h"
#import <AudioToolbox/AudioToolbox.h>

@implementation ADHaptic

+ (BOOL)hapticOn {
    id v = [NSUserDefaults.standardUserDefaults objectForKey:@"ad_haptic"];
    return v ? [NSUserDefaults.standardUserDefaults boolForKey:@"ad_haptic"] : YES;
}

+ (BOOL)soundOn {
    id v = [NSUserDefaults.standardUserDefaults objectForKey:@"ad_sound"];
    return v ? [NSUserDefaults.standardUserDefaults boolForKey:@"ad_sound"] : YES;
}

+ (void)play:(SystemSoundID)sid {
    if (sid == 0 || ![self soundOn]) return;
    AudioServicesPlaySystemSound(sid);
}

+ (void)doImpact:(UIImpactFeedbackStyle)style sound:(SystemSoundID)sid {
    if ([self hapticOn]) {
        UIImpactFeedbackGenerator *g = [[UIImpactFeedbackGenerator alloc] initWithStyle:style];
        [g prepare];
        [g impactOccurred];
    }
    [self play:sid];
}

+ (void)doNotify:(UINotificationFeedbackType)type sound:(SystemSoundID)sid {
    if ([self hapticOn]) {
        UINotificationFeedbackGenerator *g = [UINotificationFeedbackGenerator new];
        [g prepare];
        [g notificationOccurred:type];
    }
    [self play:sid];
}

+ (void)tap { [self doImpact:UIImpactFeedbackStyleLight sound:1104]; }
+ (void)soft { [self doImpact:UIImpactFeedbackStyleSoft sound:0]; }
+ (void)heavy { [self doImpact:UIImpactFeedbackStyleMedium sound:1104]; }

+ (void)select {
    if ([self hapticOn]) {
        UISelectionFeedbackGenerator *g = [UISelectionFeedbackGenerator new];
        [g prepare];
        [g selectionChanged];
    }
    [self play:1105];
}

+ (void)success { [self doNotify:UINotificationFeedbackTypeSuccess sound:1001]; }
+ (void)warning { [self doNotify:UINotificationFeedbackTypeWarning sound:0]; }
+ (void)error { [self doNotify:UINotificationFeedbackTypeError sound:0]; }

@end
