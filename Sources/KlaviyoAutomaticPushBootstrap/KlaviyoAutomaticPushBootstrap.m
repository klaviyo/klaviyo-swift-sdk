#import "KlaviyoAutomaticPushBootstrap.h"

#import <objc/runtime.h>
#import <UIKit/UIKit.h>

static NSString *const KlaviyoAutomaticPushTokenForwardingKey =
    @"klaviyo_automatic_push_token_forwarding";
static NSString *const KlaviyoAutomaticPushOpenTrackingKey =
    @"klaviyo_automatic_push_open_tracking";

typedef void (*KlaviyoApplicationDelegateSetterIMP)(
    UIApplication *,
    SEL,
    id<UIApplicationDelegate> _Nullable
);

static KlaviyoApplicationDelegateSetterIMP KlaviyoPriorApplicationDelegateSetter;

void KlaviyoAutomaticPushBootstrapLinkerAnchor(void) {}

// Matches Swift's `as? Bool` bridging for `NSNumber`/`CFBoolean`, which the Swift-side gate
// (KlaviyoSwiftEnvironment.production) uses: any NSNumber whose value is exactly 0 or 1 bridges
// to a Bool, in addition to true CFBoolean values. A stricter CFBoolean-only check here would
// let an integer-valued plist flag enable the feature at initialize(with:) while this pre-main
// hook skips installing it — an inconsistency depending on which path evaluates the flag first.
static BOOL KlaviyoIsTrueBoolean(id _Nullable value) {
    if (![value isKindOfClass:[NSNumber class]]) {
        return NO;
    }

    NSNumber *number = (NSNumber *)value;
    if (CFGetTypeID((__bridge CFTypeRef)number) == CFBooleanGetTypeID()) {
        return number.boolValue;
    }
    return [number isEqualToNumber:@1];
}

BOOL KlaviyoAutomaticPushBootstrapShouldInstall(
    NSDictionary<NSString *, id> *infoDictionary
) {
    return KlaviyoIsTrueBoolean(infoDictionary[KlaviyoAutomaticPushTokenForwardingKey]) ||
        KlaviyoIsTrueBoolean(infoDictionary[KlaviyoAutomaticPushOpenTrackingKey]);
}

static void KlaviyoInvokeAutomaticPushInstaller(
    id<UIApplicationDelegate> _Nullable applicationDelegate
) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            KlaviyoInvokeAutomaticPushInstaller(applicationDelegate);
        });
        return;
    }

    Class installerClass = NSClassFromString(@"KlaviyoAutomaticPushInstaller");
    SEL installerSelector = NSSelectorFromString(@"installForApplicationDelegate:");
    Method installerMethod = class_getClassMethod(installerClass, installerSelector);
    if (installerMethod == NULL) {
        return;
    }

    typedef void (*KlaviyoAutomaticPushInstallerIMP)(id, SEL, id _Nullable);
    KlaviyoAutomaticPushInstallerIMP installer =
        (KlaviyoAutomaticPushInstallerIMP)method_getImplementation(installerMethod);
    installer(installerClass, installerSelector, applicationDelegate);
}

static void KlaviyoSetApplicationDelegate(
    UIApplication *application,
    SEL selector,
    id<UIApplicationDelegate> _Nullable assignedDelegate
) {
    KlaviyoPriorApplicationDelegateSetter(application, selector, assignedDelegate);

    KlaviyoInvokeAutomaticPushInstaller(assignedDelegate);
    id<UIApplicationDelegate> effectiveDelegate = application.delegate;
    if (effectiveDelegate != assignedDelegate) {
        KlaviyoInvokeAutomaticPushInstaller(effectiveDelegate);
    }
}

static void KlaviyoInstallApplicationDelegateSetterHook(void) {
    Method setter = class_getInstanceMethod(UIApplication.class, @selector(setDelegate:));
    if (setter == NULL) {
        return;
    }

    IMP currentIMP = method_getImplementation(setter);
    // Never record this hook's own IMP as the "prior" setter; if the hook is ever installed
    // twice in one process, that would make KlaviyoSetApplicationDelegate call itself and
    // recurse without bound.
    if (currentIMP == (IMP)KlaviyoSetApplicationDelegate) {
        return;
    }

    KlaviyoPriorApplicationDelegateSetter =
        (KlaviyoApplicationDelegateSetterIMP)currentIMP;
    method_setImplementation(setter, (IMP)KlaviyoSetApplicationDelegate);
}

@interface KlaviyoAutomaticPushBootstrapLoader : NSObject
@end

@implementation KlaviyoAutomaticPushBootstrapLoader

+ (void)load {
    NSDictionary<NSString *, id> *infoDictionary = NSBundle.mainBundle.infoDictionary ?: @{};
    if (KlaviyoAutomaticPushBootstrapShouldInstall(infoDictionary)) {
        KlaviyoInstallApplicationDelegateSetterHook();
    }
}

@end
