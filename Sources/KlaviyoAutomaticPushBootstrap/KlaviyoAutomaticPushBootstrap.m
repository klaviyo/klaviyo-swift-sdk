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

static BOOL KlaviyoIsTrueBoolean(id _Nullable value) {
    if (value == nil) {
        return NO;
    }

    CFTypeRef bridgedValue = (__bridge CFTypeRef)value;
    return CFGetTypeID(bridgedValue) == CFBooleanGetTypeID() && [value boolValue];
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

    KlaviyoPriorApplicationDelegateSetter =
        (KlaviyoApplicationDelegateSetterIMP)method_getImplementation(setter);
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
