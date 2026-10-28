#import "AD.h"
#import <AVFoundation/AVFoundation.h>
#import <Network/Network.h>
#import <os/lock.h>
#import <os/proc.h>
#import <execinfo.h>
#import <signal.h>
#import <fcntl.h>
#import <unistd.h>
#import <sys/time.h>
#import <sys/sysctl.h>
#import <sys/stat.h>

// 运行日志:目标只有一个——出问题时能还原"那一刻经历了什么"。
// 行格式固定宽度: "MM-dd HH:mm:ss.SSS L TAG  消息"
//   L = I 信息 / W 警告 / E 错误;TAG = NET 网络 / PLAY 播放 / DL 下载 / UI 界面 / SYS 系统 / APP 其它
// 写入用 write(2) 直接落盘(同步、很快),所以崩溃前最后几行不会丢;文件 >1MB 轮转成 app.prev.log。

static const NSUInteger kMaxLines = 1500;
static const unsigned long long kMaxFileBytes = 1024 * 1024;

static os_unfair_lock gLock = OS_UNFAIR_LOCK_INIT;
static NSMutableArray<NSString *> *gLines;
static int gFD = -1;
static unsigned long long gSize;
static NSString *gDir, *gPath, *gPrevPath, *gMarker;
static uint64_t gVersion;
static BOOL gAbnormal;
static NSString *gNet = @"未知";
// 连续重复的同一条日志折叠成"↑ 上条重复 N 次"
static NSString *gRepKey, *gRepTag;
static NSUInteger gRepCount;
static char gRepLvl = 'I';
static double gRepLast;

static void ADLogOpenFD(void) {
    if (gFD >= 0) close(gFD);
    gFD = open(gPath.fileSystemRepresentation, O_WRONLY | O_APPEND | O_CREAT, 0644);
    struct stat st;
    gSize = (gFD >= 0 && fstat(gFD, &st) == 0) ? (unsigned long long)st.st_size : 0;
}

static void ADLogSetup(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSFileManager *fm = NSFileManager.defaultManager;
        gLines = [NSMutableArray array];
        gDir = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/logs"];
        [fm createDirectoryAtPath:gDir withIntermediateDirectories:YES attributes:nil error:nil];
        gPath = [gDir stringByAppendingPathComponent:@"app.log"];
        gPrevPath = [gDir stringByAppendingPathComponent:@"app.prev.log"];
        gMarker = [gDir stringByAppendingPathComponent:@".active"];
        gAbnormal = [fm fileExistsAtPath:gMarker];     // 上次是在前台活跃时中断的(崩溃 / 被系统杀)
        unsigned long long sz = [fm attributesOfItemAtPath:gPath error:nil].fileSize;
        if (sz > kMaxFileBytes) {
            [fm removeItemAtPath:gPrevPath error:nil];
            [fm moveItemAtPath:gPath toPath:gPrevPath error:nil];
        }
        ADLogOpenFD();
        // 只读文件尾部 400KB,从第一个换行之后开始(避免截断 UTF-8 多字节字符)
        NSData *d = [NSData dataWithContentsOfFile:gPath options:NSDataReadingMappedIfSafe error:nil];
        if (d.length) {
            NSUInteger off = d.length > 400 * 1024 ? d.length - 400 * 1024 : 0;
            const uint8_t *b = d.bytes;
            if (off > 0) { while (off < d.length && b[off] != 0x0A) off++; off++; }
            if (off < d.length) {
                NSString *all = [[NSString alloc] initWithData:[d subdataWithRange:NSMakeRange(off, d.length - off)] encoding:NSUTF8StringEncoding];
                for (NSString *l in [all componentsSeparatedByString:@"\n"]) if (l.length) [gLines addObject:l];
                while (gLines.count > kMaxLines) [gLines removeObjectAtIndex:0];
            }
        }
    });
}

// 密钥脱敏:xmd_ 开头的 token 和当前配置里的 token 一律打码
static NSString *ADRedact(NSString *s) {
    if (!s.length) return s;
    NSString *tk = [ADConfig shared].token;
    if (tk.length > 8 && [s containsString:tk]) s = [s stringByReplacingOccurrencesOfString:tk withString:@"xmd_***"];
    if ([s containsString:@"xmd_"]) {
        static NSRegularExpression *re; static dispatch_once_t o;
        dispatch_once(&o, ^{ re = [NSRegularExpression regularExpressionWithPattern:@"xmd_[A-Za-z0-9_]{6,}" options:0 error:nil]; });
        s = [re stringByReplacingMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@"xmd_***"];
    }
    return s;
}

static void ADLogWriteLocked(char lvl, NSString *tag, NSString *msg) {
    struct timeval tv; gettimeofday(&tv, NULL);
    struct tm tmv; localtime_r(&tv.tv_sec, &tmv);
    char ts[24];
    snprintf(ts, sizeof ts, "%02d-%02d %02d:%02d:%02d.%03d", tmv.tm_mon + 1, tmv.tm_mday, tmv.tm_hour, tmv.tm_min, tmv.tm_sec, (int)(tv.tv_usec / 1000));
    NSString *t4 = tag.length > 4 ? [tag substringToIndex:4] : tag;
    NSString *line = [NSString stringWithFormat:@"%s %c %-4s %@", ts, lvl, t4.UTF8String, msg];
    [gLines addObject:line];
    if (gLines.count > kMaxLines + 100) [gLines removeObjectsInRange:NSMakeRange(0, gLines.count - kMaxLines)];
    gVersion++;
    if (gFD < 0) return;
    if (gSize > kMaxFileBytes) {                      // 轮转:当前文件变上一份
        close(gFD); gFD = -1;
        NSFileManager *fm = NSFileManager.defaultManager;
        [fm removeItemAtPath:gPrevPath error:nil];
        [fm moveItemAtPath:gPath toPath:gPrevPath error:nil];
        ADLogOpenFD();
    }
    NSData *d = [[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
    ssize_t n = write(gFD, d.bytes, d.length);
    if (n > 0) gSize += (unsigned long long)n;
}

static void ADLogFlushRepeatLocked(void) {
    if (gRepCount == 0) return;
    NSString *m = [NSString stringWithFormat:@"↑ 上条重复 %lu 次", (unsigned long)gRepCount];
    gRepCount = 0;
    ADLogWriteLocked(gRepLvl, gRepTag ?: @"APP", m);
}

static void ADLogEmit(char lvl, NSString *tag, NSString *msg) {
    if (!msg) return;
    ADLogSetup();
    msg = ADRedact(msg);
    msg = [msg stringByReplacingOccurrencesOfString:@"\n" withString:@" ⏎ "];
    NSString *key = [NSString stringWithFormat:@"%c|%@|%@", lvl, tag, msg];
    double now = CFAbsoluteTimeGetCurrent();
    os_unfair_lock_lock(&gLock);
    if (gRepKey && [gRepKey isEqualToString:key] && now - gRepLast < 3.0) {
        gRepCount++; gRepLast = now; gVersion++;
        os_unfair_lock_unlock(&gLock);
        return;
    }
    ADLogFlushRepeatLocked();
    gRepKey = key; gRepLast = now; gRepLvl = lvl; gRepTag = tag;
    ADLogWriteLocked(lvl, tag, msg);
    os_unfair_lock_unlock(&gLock);
}

void ADLog(NSString *fmt, ...) {
    if (!fmt.length) return;
    va_list ap; va_start(ap, fmt);
    NSString *m = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    ADLogEmit([m hasPrefix:@"✗"] ? 'E' : 'I', @"APP", m);
}
void ADLogTag(NSString *tag, NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *m = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    ADLogEmit('I', tag, m);
}
void ADLogWarn(NSString *tag, NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *m = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    ADLogEmit('W', tag, m);
}
void ADLogError(NSString *tag, NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *m = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    ADLogEmit('E', tag, m);
}

NSArray<NSString *> *ADLogLines(void) {
    ADLogSetup();
    os_unfair_lock_lock(&gLock);
    ADLogFlushRepeatLocked();
    NSArray *out = [gLines copy];
    os_unfair_lock_unlock(&gLock);
    return out;
}

uint64_t ADLogVersion(void) {
    os_unfair_lock_lock(&gLock);
    uint64_t v = gVersion;
    os_unfair_lock_unlock(&gLock);
    return v;
}

NSString *ADLogTail(NSUInteger n) {
    NSArray *all = ADLogLines();
    NSUInteger cnt = MIN(n, all.count);
    return [[all subarrayWithRange:NSMakeRange(all.count - cnt, cnt)] componentsJoinedByString:@"\n"];
}

NSString *ADLogFilePath(void) { ADLogSetup(); return gPath; }
BOOL ADLogLastRunAbnormal(void) { ADLogSetup(); return gAbnormal; }

void ADLogSetNetState(NSString *st) {
    os_unfair_lock_lock(&gLock);
    gNet = [st copy] ?: @"未知";
    gVersion++;
    os_unfair_lock_unlock(&gLock);
}

NSString *ADLogNetState(void) {
    os_unfair_lock_lock(&gLock);
    NSString *s = gNet;
    os_unfair_lock_unlock(&gLock);
    return s;
}

void ADLogClear(void) {
    ADLogSetup();
    os_unfair_lock_lock(&gLock);
    gRepCount = 0; gRepKey = nil;
    [gLines removeAllObjects];
    if (gFD >= 0) { close(gFD); gFD = -1; }
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm removeItemAtPath:gPath error:nil];
    [fm removeItemAtPath:gPrevPath error:nil];
    ADLogOpenFD();
    gVersion++;
    os_unfair_lock_unlock(&gLock);
    ADLogTag(@"APP", @"日志已清空");
}

// ───────────── 设备信息 / 导出 ─────────────
static NSString *ADMachine(void) {
    size_t sz = 0;
    sysctlbyname("hw.machine", NULL, &sz, NULL, 0);
    if (sz == 0) return @"?";
    char *m = malloc(sz);
    sysctlbyname("hw.machine", m, &sz, NULL, 0);
    NSString *s = [NSString stringWithUTF8String:m] ?: @"?";
    free(m);
    return s;
}

static NSString *ADDeviceSummary(void) {
    NSProcessInfo *pi = NSProcessInfo.processInfo;
    double freeGB = [[NSFileManager.defaultManager attributesOfFileSystemForPath:NSHomeDirectory() error:nil][NSFileSystemFreeSize] doubleValue] / 1e9;
    return [NSString stringWithFormat:@"%@ · iOS %@ · 内存 %.0fGB · 可用 %luMB · 磁盘剩余 %.1fGB · 省电%@ · %@",
            ADMachine(), UIDevice.currentDevice.systemVersion, pi.physicalMemory / 1e9,
            (unsigned long)(os_proc_available_memory() / 1048576), freeGB,
            pi.lowPowerModeEnabled ? @"开" : @"关", NSLocale.preferredLanguages.firstObject ?: @"?"];
}

NSString *ADLogExportPath(void) {
    ADLogSetup();
    ADLogLines();    // 先把待折叠的重复计数落盘
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    NSDateFormatter *df = [NSDateFormatter new];
    df.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"阅听 运行日志\n版本 %@ (%@)\n设备 %@\n网络 %@\n导出 %@\n说明 行格式: 时间 级别(I信息/W警告/E错误) 标签(NET网络/PLAY播放/DL下载/UI界面/SYS系统) 内容\n",
        info[@"CFBundleShortVersionString"] ?: @"?", info[@"CFBundleVersion"] ?: @"?", ADDeviceSummary(), ADLogNetState(), [df stringFromDate:NSDate.date]];
    if (gAbnormal) [out appendString:@"注意 上一次运行是在前台中断的(崩溃 / 被系统杀掉 / 内存不足)\n"];
    NSString *prev = [NSString stringWithContentsOfFile:gPrevPath encoding:NSUTF8StringEncoding error:nil];
    if (prev.length) { [out appendString:@"\n==== 上一份 app.prev.log ====\n"]; [out appendString:prev]; }
    NSString *cur = [NSString stringWithContentsOfFile:gPath encoding:NSUTF8StringEncoding error:nil];
    [out appendString:@"\n==== 本次 app.log ====\n"];
    if (cur.length) [out appendString:cur];
    df.dateFormat = @"yyyyMMdd-HHmmss";
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"yueting-log-%@.txt", [df stringFromDate:NSDate.date]]];
    [out writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    return path;
}

// ───────────── 崩溃 ─────────────
// 信号处理函数里只能用 async-signal-safe 的调用:这里只有 write / backtrace_symbols_fd,不碰 ObjC。
static void ADFatalSignal(int sig) {
    if (gFD >= 0) {
        const char *nm = "?";
        switch (sig) {
            case SIGABRT: nm = "SIGABRT"; break; case SIGSEGV: nm = "SIGSEGV"; break;
            case SIGBUS: nm = "SIGBUS"; break;   case SIGILL: nm = "SIGILL"; break;
            case SIGFPE: nm = "SIGFPE"; break;   case SIGTRAP: nm = "SIGTRAP"; break;
        }
        const char *a = "\n!! 致命信号 ";
        write(gFD, a, strlen(a)); write(gFD, nm, strlen(nm)); write(gFD, "\n", 1);
        void *frames[48];
        int cnt = backtrace(frames, 48);
        backtrace_symbols_fd(frames, cnt, gFD);
        fsync(gFD);
    }
    signal(sig, SIG_DFL);
    raise(sig);
}

void ADLogExceptionHandler(NSException *e) {
    NSArray *st = e.callStackSymbols;
    NSString *s = [[st subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)25, st.count))] componentsJoinedByString:@" ⏎ "];
    ADLogError(@"APP", @"未捕获异常 %@: %@ ⏎ %@", e.name, e.reason, s);
}

void ADLogInstallCrashHandler(void) {
    ADLogSetup();
    NSSetUncaughtExceptionHandler(&ADLogExceptionHandler);
    int sigs[] = {SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP};
    for (size_t i = 0; i < sizeof(sigs) / sizeof(sigs[0]); i++) {
        struct sigaction sa; memset(&sa, 0, sizeof sa);
        sa.sa_handler = ADFatalSignal;
        sigemptyset(&sa.sa_mask);
        sa.sa_flags = SA_RESETHAND;
        sigaction(sigs[i], &sa, NULL);
    }
}
