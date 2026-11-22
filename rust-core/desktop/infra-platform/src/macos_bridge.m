// macOS bridge: Sparkle (loaded at run time from the app bundle, so builds
// need no Sparkle headers) and the unified toolbar window chrome.
#import <AppKit/AppKit.h>
#include <stdbool.h>

@interface ProcessLamaSparkleDelegate : NSObject
@property(nonatomic, copy) NSString *feedURL;
@property(nonatomic, assign) BOOL beta;
@end

@implementation ProcessLamaSparkleDelegate
- (NSSet<NSString *> *)allowedChannelsForUpdater:(id)updater {
    return self.beta ? [NSSet setWithObject:@"beta"] : [NSSet set];
}
- (NSString *)feedURLStringForUpdater:(id)updater {
    return self.feedURL;
}
@end

static id gUpdater;
static id gUserDriver;
static ProcessLamaSparkleDelegate *gDelegate;

static BOOL loadSparkle(void) {
    if (NSClassFromString(@"SPUUpdater") != nil) {
        return YES;
    }
    NSString *path = [[[NSBundle mainBundle] privateFrameworksPath] stringByAppendingPathComponent:@"Sparkle.framework"];
    NSBundle *bundle = [NSBundle bundleWithPath:path];
    return bundle != nil && [bundle load] && NSClassFromString(@"SPUUpdater") != nil;
}

bool processlama_sparkle_available(void) {
    return loadSparkle();
}

static void ensureUpdater(void) {
    if (gUpdater != nil || !loadSparkle()) {
        return;
    }
    NSBundle *host = [NSBundle mainBundle];
    Class driverClass = NSClassFromString(@"SPUStandardUserDriver");
    Class updaterClass = NSClassFromString(@"SPUUpdater");
    id driver = [driverClass alloc];
    SEL initDriver = NSSelectorFromString(@"initWithHostBundle:delegate:");
    driver = ((id (*)(id, SEL, id, id))[driver methodForSelector:initDriver])(driver, initDriver, host, nil);
    id updater = [updaterClass alloc];
    SEL initUpdater = NSSelectorFromString(@"initWithHostBundle:applicationBundle:userDriver:delegate:");
    updater = ((id (*)(id, SEL, id, id, id, id))[updater methodForSelector:initUpdater])(
        updater, initUpdater, host, host, driver, gDelegate);
    SEL clear = NSSelectorFromString(@"clearFeedURLFromUserDefaults");
    if ([updater respondsToSelector:clear]) {
        ((void (*)(id, SEL))[updater methodForSelector:clear])(updater, clear);
    }
    SEL start = NSSelectorFromString(@"startUpdater:");
    NSError *error = nil;
    ((BOOL (*)(id, SEL, NSError **))[updater methodForSelector:start])(updater, start, &error);
    gUserDriver = driver;
    gUpdater = updater;
}

void processlama_sparkle_configure(const char *feedURL, bool beta, long long intervalSeconds) {
    NSString *feed = [NSString stringWithUTF8String:feedURL];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gDelegate == nil) {
            gDelegate = [ProcessLamaSparkleDelegate new];
        }
        gDelegate.feedURL = feed;
        gDelegate.beta = beta;
        ensureUpdater();
        if (gUpdater == nil) {
            return;
        }
        SEL setInterval = NSSelectorFromString(@"setUpdateCheckInterval:");
        ((void (*)(id, SEL, NSTimeInterval))[gUpdater methodForSelector:setInterval])(gUpdater, setInterval, (NSTimeInterval)intervalSeconds);
        SEL reset = NSSelectorFromString(@"resetUpdateCycle");
        if ([gUpdater respondsToSelector:reset]) {
            ((void (*)(id, SEL))[gUpdater methodForSelector:reset])(gUpdater, reset);
        }
    });
}

void processlama_sparkle_check(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        ensureUpdater();
        SEL check = NSSelectorFromString(@"checkForUpdates");
        if (gUpdater != nil) {
            ((void (*)(id, SEL))[gUpdater methodForSelector:check])(gUpdater, check);
        }
    });
}

void processlama_configure_windows(bool mouseTracking) {
    (void)mouseTracking;
    for (NSWindow *window in [NSApp windows]) {
        if (window.toolbar != nil || (window.styleMask & NSWindowStyleMaskTitled) == 0) {
            continue;
        }
        window.titleVisibility = NSWindowTitleHidden;
        window.titlebarAppearsTransparent = YES;
        window.styleMask |= NSWindowStyleMaskFullSizeContentView;
        NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"ProcessLamaWindowToolbar"];
        toolbar.showsBaselineSeparator = NO;
        window.toolbar = toolbar;
        if (@available(macOS 11.0, *)) {
            window.toolbarStyle = NSWindowToolbarStyleUnified;
            window.titlebarSeparatorStyle = NSTitlebarSeparatorStyleNone;
        }
    }
}

bool processlama_system_reduce_motion(void) {
    return [[NSWorkspace sharedWorkspace] accessibilityDisplayShouldReduceMotion];
}
