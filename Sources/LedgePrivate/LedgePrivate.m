#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import "LedgePrivate.h"

// Selectors of the private classes, declared so the compiler knows their signatures.
@interface NSObject (LedgePrivateOSD)
+ (instancetype)sharedManager;
- (void)showImage:(long long)image
      onDisplayID:(unsigned int)display
         priority:(unsigned int)priority
    msecUntilFade:(unsigned int)msec
   filledChiclets:(unsigned int)filled
    totalChiclets:(unsigned int)total
           locked:(BOOL)locked;
@end

@interface NSObject (LedgePrivateKeyboard)
- (NSArray *)copyKeyboardBacklightIDs;
- (BOOL)isKeyboardBuiltIn:(unsigned long long)keyboardID;
- (float)brightnessForKeyboard:(unsigned long long)keyboardID;
- (BOOL)setBrightness:(float)brightness forKeyboard:(unsigned long long)keyboardID;
@end

static id LGOSDManager(void) {
    static id manager;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dlopen("/System/Library/PrivateFrameworks/OSD.framework/OSD", RTLD_LAZY);
        Class cls = NSClassFromString(@"OSDManager");
        SEL show = @selector(showImage:onDisplayID:priority:msecUntilFade:filledChiclets:totalChiclets:locked:);
        if (cls && [cls respondsToSelector:@selector(sharedManager)] && [cls instancesRespondToSelector:show]) {
            manager = [cls sharedManager];
        }
    });
    return manager;
}

bool LGShowSystemHUD(LGOSDImage image, CGDirectDisplayID display, unsigned int filled, unsigned int total) {
    id manager = LGOSDManager();
    if (!manager) return false;
    [manager showImage:image onDisplayID:display priority:0x1f4 msecUntilFade:1000 filledChiclets:filled totalChiclets:total locked:NO];
    return true;
}

static id LGKeyboardClient(void) {
    static id client;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY);
        Class cls = NSClassFromString(@"KeyboardBrightnessClient");
        if (cls && [cls instancesRespondToSelector:@selector(setBrightness:forKeyboard:)]) {
            client = [[cls alloc] init];
        }
    });
    return client;
}

static bool LGBuiltInKeyboardID(unsigned long long *outID) {
    id client = LGKeyboardClient();
    if (!client) return false;
    NSArray *ids = [client copyKeyboardBacklightIDs];
    for (NSNumber *number in ids) {
        if ([client isKeyboardBuiltIn:number.unsignedLongLongValue]) {
            *outID = number.unsignedLongLongValue;
            return true;
        }
    }
    return false;
}

bool LGKeyboardBacklightAvailable(void) {
    unsigned long long keyboardID;
    return LGBuiltInKeyboardID(&keyboardID);
}

bool LGGetKeyboardBacklight(float *value) {
    unsigned long long keyboardID;
    if (!LGBuiltInKeyboardID(&keyboardID)) return false;
    *value = [LGKeyboardClient() brightnessForKeyboard:keyboardID];
    return true;
}

bool LGSetKeyboardBacklight(float value) {
    unsigned long long keyboardID;
    if (!LGBuiltInKeyboardID(&keyboardID)) return false;
    return [LGKeyboardClient() setBrightness:value forKeyboard:keyboardID];
}
