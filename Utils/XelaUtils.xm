#import "XelaUtils.h"
#import "UIKit/UIKit.h"
#include <string.h>
#include <inttypes.h>
#include <stdbool.h>
#import <objc/runtime.h>

static bool showPopups = true;
static NSMutableArray *alertsQueue = [NSMutableArray new];
static UIWindow *topAlertWindow;
NSString *const springboardBundleId = @"com.apple.springboard";
NSString *const preferencesPlistsFolder = @"/var/mobile/Library/Preferences";
NSString *const applicationSupport = @"/Library/Application Support";

@interface NSDistributedNotificationCenter : NSNotificationCenter
@end

@interface LSResourceProxy : NSObject
@end

@interface LSBundleProxy : LSResourceProxy <NSSecureCoding>
- (NSString *)bundleIdentifier;
@end

@interface LSApplicationProxy : LSBundleProxy <NSSecureCoding>
- (id)applicationIdentifier;
- (id)itemName;
@end

@interface LSApplicationWorkspace : NSObject
+ (id)defaultWorkspace;
- (id)allApplications;
@end

@interface FBSystemService : NSObject
+ (id)sharedInstance;
- (void)exitAndRelaunch:(BOOL)arg1;
@end

UIImage *rotatedImage(UIImage *image, CGFloat rotation) {
    CGFloat radian = rotation * M_PI / 180;
    CGAffineTransform t = CGAffineTransformMakeRotation(radian);
    CGRect sizeRect = (CGRect){.size = image.size};
    CGRect destRect = CGRectApplyAffineTransform(sizeRect, t);
    CGSize destinationSize = destRect.size;
    UIGraphicsBeginImageContext(destinationSize);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextTranslateCTM(context, destinationSize.width / 2.0f, destinationSize.height / 2.0f);
    CGContextRotateCTM(context, radian);
    [image drawInRect:CGRectMake(-image.size.width / 2.0f, -image.size.height / 2.0f, image.size.width, image.size.height)];
    UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return newImage;
}

void copyLibraryBundleToAppDataDirectory() {
    NSArray *directoriesOfCurrentApp = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *appDataOfCurrentApp = [directoriesOfCurrentApp objectAtIndex:0];
    NSString *libXelahotBundle = @"/libXelahot.bundle";
    
    if ([[NSFileManager defaultManager] isReadableFileAtPath:appDataOfCurrentApp]) {
        NSString *desiredPath = [appDataOfCurrentApp stringByAppendingPathComponent:libXelahotBundle];
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:desiredPath]) {
            NSError *deleteError;
            
            if ([[NSFileManager defaultManager] isDeletableFileAtPath:desiredPath]) {
                [[NSFileManager defaultManager] removeItemAtPath:desiredPath error:&deleteError];
            }
        }
        
        if ([[NSFileManager defaultManager] isReadableFileAtPath:applicationSupport]) {
            if ([[NSFileManager defaultManager] isWritableFileAtPath:appDataOfCurrentApp]) {
                NSString *libraryBundlePath = [applicationSupport stringByAppendingPathComponent:libXelahotBundle];
                NSError *copyError = nil;
                [[NSFileManager defaultManager] copyItemAtPath:libraryBundlePath toPath:desiredPath error:&copyError];
            }
        }
    }
}

bool determineIfCustomIpa(NSString *dylibName) {
    NSFileManager *defaultFileManager = [NSFileManager defaultManager];
    BOOL isDir = YES;
    NSString *appBundlePath = [[NSBundle mainBundle] bundlePath]; // /var/containers/Bundle/Application/XXXXXXXXXXXX/something.app
    NSString *frameworksFolderPath = [appBundlePath stringByAppendingPathComponent:@"/Frameworks"];
    BOOL frameworksFolderExists = [defaultFileManager fileExistsAtPath:frameworksFolderPath isDirectory:&isDir];
    isDir = NO;
    NSString *customIpaMessage = @"The tweak seems to be embedded in a custom IPA. Despite this, the tweak initialization will continue. If the app's bundle directory contains the resources required by the library, those resources will be used (Payload/xxxxxxx.app/libXelahot.bundle/images/...). Otherwise, default resources will be used.";
    
    // Embedded libraries in custom IPA files are usually in "something.app/Frameworks" or "something.app"
    if (frameworksFolderExists) {
        NSString *frameworksFolderLibraryPath = [frameworksFolderPath stringByAppendingFormat:@"/%@", dylibName];
        
        if ([defaultFileManager fileExistsAtPath:frameworksFolderLibraryPath isDirectory:&isDir]) {
            showPopup(dylibName, customIpaMessage);
            return true;
        }
    }
    
    NSString *appBundleAndDylibPath = [appBundlePath stringByAppendingFormat:@"/%@", dylibName];
    
    if ([defaultFileManager fileExistsAtPath:appBundleAndDylibPath isDirectory:&isDir]) {
        showPopup(dylibName, customIpaMessage);
        return true;
    }
    
    return false;
}

void updateSwitchValue(NSNotification *notifContent) {
    if (![[[NSBundle mainBundle] bundleIdentifier] isEqual:springboardBundleId]) {
        return;
    }
    
    NSDictionary *dict = notifContent.userInfo;
    NSString *bundleId = [dict objectForKey:@"bundleId"];
    NSNumber *newSwitchValue = [dict objectForKey:@"newSwitchValue"];
    NSString *tweakPrefPlistFile = [dict objectForKey:@"tweakPrefPlistFile"];
    NSString *tweakPrefPlistPath = [preferencesPlistsFolder stringByAppendingPathComponent:tweakPrefPlistFile];
    NSMutableDictionary *tweakPrefFileDict = getPlistFileAtFullPath(tweakPrefPlistPath);
    
    if (tweakPrefFileDict != nil) {
        [tweakPrefFileDict setValue:newSwitchValue forKey:bundleId];
        [tweakPrefFileDict writeToFile:tweakPrefPlistPath atomically:YES];
    }
}

NSMutableDictionary *getInstalledApps() {
    // [
    //    "com.miniclip.agario" --> "Agar.io",
    //    "com.trucMac.spotify" --> "Spotify",
    // ]
    
    NSArray<LSApplicationProxy *> *sbAppsArray = [[%c(LSApplicationWorkspace) defaultWorkspace] allApplications];
    NSMutableDictionary *installedAppsDict = [[NSMutableDictionary alloc] init];

    for(LSApplicationProxy *currentSbApp in sbAppsArray){
        NSString *bundleIdentifier = [currentSbApp bundleIdentifier];
        NSString *localizedShortName = [currentSbApp itemName];
        
        [installedAppsDict setValue:localizedShortName forKey:bundleIdentifier];
    }
    
    return installedAppsDict;
}

bool createTweakPrefPlistFileIfNeeded(NSString *tweakPrefPlistFile) {
    BOOL isDir = NO;
    NSString *tweakPrefPlistPath = [preferencesPlistsFolder stringByAppendingPathComponent:tweakPrefPlistFile];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:tweakPrefPlistPath isDirectory:&isDir]) {
        if ([[NSFileManager defaultManager] isWritableFileAtPath:preferencesPlistsFolder]) {
            if ([[NSFileManager defaultManager] createFileAtPath:tweakPrefPlistPath contents:nil attributes:nil]) {
                NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
                [dict writeToFile:tweakPrefPlistPath atomically:YES];
            }
        }
        
        return false;
    }
    
    return true;
}

NSMutableDictionary *getPlistFileAtFullPath(NSString *plistFileFullPath) {
    // [
    //    "com.miniclip.agario" --> NSNumber (BOOL),
    //    "com.somethg.spotify" --> NSNumber (BOOL),
    // ]
    
    BOOL isDir = NO;
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:plistFileFullPath isDirectory:&isDir]) {
        return [[[NSMutableDictionary alloc] initWithContentsOfFile:plistFileFullPath] mutableCopy];
    }
    
    return nil;
}

NSMutableDictionary *createNewPrefDictWithAllApps(NSMutableDictionary *installedAppsDict) {
    NSMutableArray *noValuesArray = [NSMutableArray array];
    
    for (NSInteger i = 0; i < installedAppsDict.count; i++) {
        [noValuesArray addObject:[NSNumber numberWithBool:NO]];
    }
    
    return [NSMutableDictionary dictionaryWithObjects:noValuesArray forKeys:[installedAppsDict allKeys]];
}

NSMutableDictionary *addNewAppsAndRemoveDeleteOnes(NSMutableDictionary *tweakPrefFileDict, NSMutableDictionary *installedAppsDict) {
    NSArray *installedAppsDictKeys = [installedAppsDict allKeys];
    NSArray *tweakPrefFileDictKeys = [tweakPrefFileDict allKeys];
    NSSet *installedAppsDictKeysSet = [NSSet setWithArray:installedAppsDictKeys];
    NSSet *tweakPrefFileDictKeysSet = [NSSet setWithArray:tweakPrefFileDictKeys];
    NSMutableArray *newApps = [[NSMutableArray alloc] init];
    NSMutableArray *deletedApps = [[NSMutableArray alloc] init];
    
    for (NSString *key in [installedAppsDictKeysSet setByAddingObjectsFromArray:tweakPrefFileDictKeys]) {
        if (![tweakPrefFileDictKeysSet containsObject:key]) {
            [newApps addObject:key];
        }
        if (![installedAppsDictKeysSet containsObject:key]) {
            [deletedApps addObject:key];
        }
    }

    // Add new apps
    for (NSString *currentNewApp in newApps) {
        if (tweakPrefFileDict[currentNewApp] == nil) {
            [tweakPrefFileDict setObject:[NSNumber numberWithBool:NO] forKey:currentNewApp];
        }
    }
    
    // Remove deleted apps
    for (NSString *currentAppToDelete in deletedApps) {
        [tweakPrefFileDict removeObjectForKey:currentAppToDelete];
    }
    
    return tweakPrefFileDict;
}

void getInstalledAppsAndAppsToInject(NSNotification *notifContent) {
    if (![[[NSBundle mainBundle] bundleIdentifier] isEqual:springboardBundleId]) {
        return;
    }
    
    NSDictionary *dict = notifContent.userInfo;
    NSString *tweakPrefPlistFile = [dict objectForKey:@"tweakPrefPlistFile"];
    NSString *tweakName = [dict objectForKey:@"tweakName"];
    NSMutableDictionary *installedAppsDict = getInstalledApps();
    NSMutableDictionary *userInfos = [[NSMutableDictionary alloc] init];
    [userInfos setObject:installedAppsDict forKey:@"installedAppsDict"];
    bool tweakPrefPlistFileExisted = createTweakPrefPlistFileIfNeeded(tweakPrefPlistFile);
    NSMutableDictionary *tweakPrefFileDict = nil;
    
    if (tweakPrefPlistFileExisted) {
        NSString *tweakPrefPlistPath = [preferencesPlistsFolder stringByAppendingPathComponent:tweakPrefPlistFile];
        tweakPrefFileDict = getPlistFileAtFullPath(tweakPrefPlistPath);

        if (tweakPrefFileDict != nil) {
            tweakPrefFileDict = addNewAppsAndRemoveDeleteOnes(tweakPrefFileDict, installedAppsDict);
            [userInfos setObject:tweakPrefFileDict forKey:@"appsToInjectDict"];
        }
    } else {
        tweakPrefFileDict = createNewPrefDictWithAllApps(installedAppsDict);
    }
    
    NSString *tweakPrefPlistPath = [preferencesPlistsFolder stringByAppendingPathComponent:tweakPrefPlistFile];
    [tweakPrefFileDict writeToFile:tweakPrefPlistPath atomically:YES];
    NSString *notifAppsObtainedFormatted = [NSString stringWithFormat:notifAppsObtained, tweakName];
    [[NSDistributedNotificationCenter defaultCenter] postNotificationName:notifAppsObtainedFormatted object:nil userInfo:userInfos];
}

void getTweakPrefFileForTweakInjectionDecision(NSNotification *notifContent) {
    if ([[[NSBundle mainBundle] bundleIdentifier] isEqual:springboardBundleId]) {
        NSDictionary *dict = notifContent.userInfo;
        NSString *tweakPrefPlistFile = [dict objectForKey:@"tweakPrefPlistFile"];
        NSString *tweakName = [dict objectForKey:@"tweakName"];
        NSString *tweakPrefPlistPath = [preferencesPlistsFolder stringByAppendingPathComponent:tweakPrefPlistFile];
        NSMutableDictionary *tweakPrefFileDict = getPlistFileAtFullPath(tweakPrefPlistPath);
        
        if (tweakPrefFileDict == nil) {
            tweakPrefFileDict = [[NSMutableDictionary alloc] init];
        }
        
        NSMutableDictionary *userInfos = [[NSMutableDictionary alloc] init];
        [userInfos setObject:tweakPrefFileDict forKey:@"tweakPrefFileDict"];
        NSString *notifReceiveTweakPrefFileForTweakInjectionDecisionFormatted = [NSString stringWithFormat:notifReceiveTweakPrefFileForTweakInjectionDecision, tweakName];
        
        [[NSDistributedNotificationCenter defaultCenter] postNotificationName:notifReceiveTweakPrefFileForTweakInjectionDecisionFormatted object:nil userInfo:userInfos];
    }
}

void respring(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    if ([[[NSBundle mainBundle] bundleIdentifier] isEqual:springboardBundleId]) {
        [[%c(FBSystemService) sharedInstance] exitAndRelaunch:YES];
    }
}

UIWindow *findCurrentProcessMainWindow(bool shouldThrowException) {
    UIApplication *uiApp = [UIApplication sharedApplication];
    id uiAppDelegate = (id)[uiApp delegate];
    SEL appWindowSelector = NSSelectorFromString(@"appWindow");
    
    if ([uiApp respondsToSelector:@selector(keyWindow)]) {
        // Most AppStore/Sideloaded apps
        return uiApp.keyWindow;
    } else if ([[uiApp delegate] respondsToSelector:@selector(window)]) {
        // Other way for some AppStore/Sideloaded apps
        return [uiApp delegate].window;
    } else if ([uiAppDelegate respondsToSelector:appWindowSelector]) {
        // Some stock apps (tested with the Settings app)
        return ((UIWindow *(*)(id, SEL))[uiAppDelegate methodForSelector:appWindowSelector])(uiAppDelegate, appWindowSelector);
    } else {
        // This shows the available methods for the object (requires #import <objc/runtime.h>)
        /*int i = 0;
        unsigned int mc = 0;
        Method *mlist = class_copyMethodList(object_getClass([uiApp delegate]), &mc);

        for (i = 0; i < mc; i++) {
            writeLog("Method num. #%d: %s", i, sel_getName(method_getName(mlist[i])));
        }*/
        
        if (shouldThrowException) {
            NSString *exceptionMessage = [@"Unable to find a UIWindow for this process. This is necessary in order to show the tweak's UI. The UIApplication delegate is this class: " stringByAppendingString:NSStringFromClass([[uiApp delegate] class])];
            [NSException raise:NSInternalInconsistencyException format:@"%@", exceptionMessage];
            __builtin_unreachable();
        }
        
        // You can catch exceptions this way
        /*@try {

        }
        @catch (NSException *exception) {
            consoleLog(@"Error: ", [NSString stringWithFormat:@"%@", exception]);
        }*/
        
        return nil;
    }
}

//C style
void showPopup(const char *title, const char *description, bool wasWaitingToShowNextAlert) {
	NSString *myTitle = [NSString stringWithUTF8String:title];
	NSString *myMessage = [NSString stringWithUTF8String:description];
	showPopup(myTitle, myMessage, wasWaitingToShowNextAlert);
}

//Objective-c style (will crash if not executing from main thread)
void showPopup(NSString *title, NSString *description, bool wasWaitingToShowNextAlert) {
    if (!showPopups) {
        return;
    }
    
    if (!wasWaitingToShowNextAlert) {
        NSArray *newAlertStrings = @[title, description];
        [alertsQueue addObject:newAlertStrings];
    }
    
    UIWindow *mainWindow = findCurrentProcessMainWindow(false);
    topAlertWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    topAlertWindow.rootViewController = [UIViewController new];
    
    NSArray *firstAlert = [alertsQueue objectAtIndex:0];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[firstAlert objectAtIndex:0] message:[firstAlert objectAtIndex:1] preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Ok", @"confirm") style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        topAlertWindow.hidden = YES;
        topAlertWindow = nil;
        [alertsQueue removeObjectAtIndex:0];
        
        if ((int)[alertsQueue count] > 0) {
            showPopup(@"",@"",true);
        }
    }]];
    
	topAlertWindow.windowScene = mainWindow.windowScene;
    topAlertWindow.hidden = NO;
	[topAlertWindow.rootViewController presentViewController:alert animated:YES completion:nil];
	topAlertWindow.windowLevel = UIWindowLevelAlert + 1;
}
