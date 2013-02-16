#import <SpringBoard/SpringBoard.h>
#import <QuartzCore/QuartzCore.h>
#import <notify.h>
#import <CaptainHook/CaptainHook.h>

static CFMutableSetRef icons;
static CATransform3D currentTransform;
static CGFloat reflectionOpacity;
static int notify_token;
static UIInterfaceOrientation lastOrientation;

@interface SBIconView : UIView
@end

@interface SBNowPlayingBarView : UIView
@property (readonly, nonatomic) UIButton *toggleButton;
@property (readonly, nonatomic) UIButton *airPlayButton;
@end

@interface SBNowPlayingBarMediaControlsView : UIView
@property (readonly, nonatomic) UIButton *prevButton;
@property (readonly, nonatomic) UIButton *playButton;
@property (readonly, nonatomic) UIButton *nextButton;
@property (readonly, nonatomic) UIButton *airPlayButton;
@end

@interface UIView (Springtomize)
- (CGFloat)springtomizeScaleFactor;
@end

@interface SBOrientationLockManager : NSObject {
	NSMutableSet *_lockOverrideReasons;
	UIInterfaceOrientation _userLockedOrientation;
}
+ (SBOrientationLockManager *)sharedInstance;
- (void)restoreStateFromPrefs;
- (id)init;
- (void)dealloc;
- (void)lock;
- (void)lock:(UIInterfaceOrientation)lock;
- (void)unlock;
- (BOOL)isLocked;
- (UIInterfaceOrientation)userLockOrientation;
- (void)setLockOverrideEnabled:(BOOL)enabled forReason:(id)reason;
- (void)enableLockOverrideForReason:(id)reason suggestOrientation:(UIInterfaceOrientation)orientation;
- (void)enableLockOverrideForReason:(id)reason forceOrientation:(UIInterfaceOrientation)orientation;
- (BOOL)lockOverrideEnabled;
- (void)updateLockOverrideForCurrentDeviceOrientation;
- (void)_updateLockStateWithChanges:(id)changes;
- (void)_updateLockStateWithOrientation:(int)orientation changes:(id)changes;
- (void)_updateLockStateWithOrientation:(int)orientation forceUpdateHID:(BOOL)forceHID changes:(id)changes;
- (BOOL)_effectivelyLocked;
@end

@interface SpringBoard (iOS6)
- (void)setWantsOrientationEvents:(BOOL)wantsEvents;
- (void)updateOrientationAndAccelerometerSettings;
@end

static CATransform3D (*ScaledTransform)(UIView *, CATransform3D);

static CATransform3D ScaledTransformSpringtomize(UIView *iconView, CATransform3D transform)
{
	CGFloat scale = [iconView springtomizeScaleFactor];
	return CATransform3DScale(transform, scale, scale, 1.0f);
}

static CATransform3D ScaledTransformDefault(UIView *iconView, CATransform3D transform)
{
	return transform;
}

%hook UIView 

- (void)didMoveToWindow
{
	if (!self.window)
		CFSetRemoveValue(icons, self);
	%orig;
}

- (void)dealloc
{
	CFSetRemoveValue(icons, self);
	%orig;
}

%end

typedef void (^RotatedViewUpdateBlock)(id view, UIInterfaceOrientation orientation, CATransform3D transform, NSTimeInterval duration);
static RotatedViewUpdateBlock standardUpdateBlock = ^(id view, UIInterfaceOrientation orientation, CATransform3D transform, NSTimeInterval duration) {
	CALayer *layer = [view layer];
	if (duration) {
		CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"transform"];
		animation.toValue = [NSValue valueWithCATransform3D:transform];
		animation.duration = duration;
		animation.removedOnCompletion = YES;
		animation.fromValue = [layer.presentationLayer valueForKeyPath:@"transform"];
		[layer addAnimation:animation forKey:@"IconRotator"];
	}
	layer.transform = transform;
};

static RotatedViewUpdateBlock iconViewUpdateBlock = ^(id view, UIInterfaceOrientation orientation, CATransform3D transform, NSTimeInterval duration) {
	transform = ScaledTransform(view, transform);
	CALayer *layer = [view layer];
	if (duration) {
		CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"sublayerTransform"];
		animation.toValue = [NSValue valueWithCATransform3D:transform];
		animation.duration = duration;
		animation.removedOnCompletion = YES;
		animation.fromValue = [layer.presentationLayer valueForKeyPath:@"sublayerTransform"];
		[layer addAnimation:animation forKey:@"IconRotator"];
	}
	layer.sublayerTransform = transform;
	UIImageView **imageView = CHIvarRef(view, _reflection, UIImageView *);
	if (imageView)
		(*imageView).alpha = reflectionOpacity;
};

static void ApplyRotatedViewTransform(UIView *view, RotatedViewUpdateBlock updateBlock)
{
	if (view && updateBlock) {
		[view.layer setValue:[[updateBlock copy] autorelease] forKey:@"IconRotatorBlock"];
		CFSetSetValue(icons, view);
		updateBlock(view, lastOrientation, currentTransform, 0.0);
	}
}

%hook SBIconView

- (void)didMoveToWindow
{
	%orig;
	if (self.window) {
		ApplyRotatedViewTransform(self, iconViewUpdateBlock);
	}
}

- (void)didMoveToSuperview
{
	%orig;
	if (self.window) {
		ApplyRotatedViewTransform(self, iconViewUpdateBlock);
	}
}

%end


%hook SBNowPlayingBarView

- (void)didMoveToWindow
{
	%orig;
	if (self.window) {
		ApplyRotatedViewTransform(self.toggleButton, standardUpdateBlock);
		ApplyRotatedViewTransform(self.airPlayButton, standardUpdateBlock);
	}
}

%end

%hook SBNowPlayingBarMediaControlsView

- (void)didMoveToWindow
{
	%orig;
	if (self.window) {
		ApplyRotatedViewTransform(self.prevButton, standardUpdateBlock);
		ApplyRotatedViewTransform(self.playButton, standardUpdateBlock);
		ApplyRotatedViewTransform(self.nextButton, standardUpdateBlock);
		ApplyRotatedViewTransform(self.airPlayButton, standardUpdateBlock);
	}
}

%end

%hook SBSearchController

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
	UIView *result = %orig;
	if (result) {
		NSArray *subviews = result.subviews;
		if ([subviews count]) {
			ApplyRotatedViewTransform([subviews objectAtIndex:0], standardUpdateBlock);
		}
	}
	return result;
}

%end

static void SetAccelerometerEnabled(BOOL enabled)
{
	if ([UIApp respondsToSelector:@selector(setWantsOrientationEvents:)] && [UIApp respondsToSelector:@selector(updateOrientationAndAccelerometerSettings)]) {
		[(SpringBoard *)UIApp setWantsOrientationEvents:enabled];
		[(SpringBoard *)UIApp updateOrientationAndAccelerometerSettings];
		return;
	}
	// This code is quite evil
	SBAccelerometerInterface *accelerometer = [%c(SBAccelerometerInterface) sharedInstance];
	NSMutableArray **_clients = CHIvarRef(accelerometer, _clients, NSMutableArray *);
	if (_clients) {
		NSMutableArray *clients = *_clients;
		if (!clients)
			*_clients = clients = [[NSMutableArray alloc] init];
		static SBAccelerometerClient *client;
		if (!client) {
			client = [[%c(SBAccelerometerClient) alloc] init];
			[client setUpdateInterval:0.1];
		}
		if (client) {
			if (enabled) {
				if ([clients indexOfObjectIdenticalTo:client] == NSNotFound)
					[clients addObject:client];
			} else {
				[clients removeObjectIdenticalTo:client];
			}
		}
	}
	[accelerometer updateSettings];
}

%hook SpringBoard

- (void)applicationDidFinishLaunching:(UIApplication *)application
{
	%orig;
	if ([UIView instancesRespondToSelector:@selector(springtomizeScaleFactor)])
		ScaledTransform = ScaledTransformSpringtomize;
	SetAccelerometerEnabled(YES);
	[[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
}

%end

%hook SBAwayController

- (void)dimScreen:(BOOL)animated
{
	%orig;
	SetAccelerometerEnabled(NO);
}

- (void)undimScreen
{
	%orig;
	SBOrientationLockManager *olm = [%c(SBOrientationLockManager) sharedInstance];
	if (![olm _effectivelyLocked])
		SetAccelerometerEnabled(YES);
}

- (void)updateOrientationForUndim
{
	%orig();
	SetAccelerometerEnabled(YES);
}

%end;

%hook SBOrientationLockManager

- (void)setLockOverrideEnabled:(BOOL)enabled forReason:(NSString *)reason
{
	if ([reason isEqualToString:@"SBOrientationLockForSwitcher"])
		enabled = NO;
	%orig();
}

%end

static void UpdateWithOrientation(UIInterfaceOrientation orientation)
{
	switch (orientation) {
		case UIInterfaceOrientationPortrait:
			currentTransform = CATransform3DIdentity;
			reflectionOpacity = 1.0f;
			break;
		case UIInterfaceOrientationPortraitUpsideDown:
			currentTransform = CATransform3DMakeRotation(M_PI, 0.0f, 0.0f, 1.0f);
			reflectionOpacity = 0.0f;
			break;
		case UIInterfaceOrientationLandscapeRight:
			currentTransform = CATransform3DMakeRotation(0.5f * M_PI, 0.0f, 0.0f, 1.0f);
			reflectionOpacity = 0.0f;
			break;
		case UIInterfaceOrientationLandscapeLeft:
			currentTransform = CATransform3DMakeRotation(-0.5f * M_PI, 0.0f, 0.0f, 1.0f);
			reflectionOpacity = 0.0f;
			break;
		default:
			return;
	}
	[UIView animateWithDuration:0.2 animations:^{
		for (UIView *view in (id)icons) {
			RotatedViewUpdateBlock updateBlock = [view.layer valueForKey:@"IconRotatorBlock"];
			updateBlock(view, orientation, currentTransform, 0.2);
		}
	}];
}

%hook SBOrientationLockManager

- (void)_updateLockStateWithChanges:(id)changes
{
	%orig;
	if ([self _effectivelyLocked]) {
		SetAccelerometerEnabled(NO);
		UpdateWithOrientation([self userLockOrientation]);
	} else {
		SetAccelerometerEnabled(YES);
	}
}

- (void)_updateLockStateWithOrientation:(UIInterfaceOrientation)orientation forceUpdateHID:(BOOL)updateHID changes:(id)changes
{
	%orig;
	if ([self _effectivelyLocked]) {
		SetAccelerometerEnabled(NO);
		UpdateWithOrientation([self userLockOrientation]);
	} else {
		SetAccelerometerEnabled(YES);
	}
}

- (void)_updateLockStateWithOrientation:(UIInterfaceOrientation)orientation changes:(id)changes
{
	%orig;
	if ([self _effectivelyLocked]) {
		SetAccelerometerEnabled(NO);
		UpdateWithOrientation([self userLockOrientation]);
	} else {
		SetAccelerometerEnabled(YES);
	}
}

%end

static inline void UpdateWithDeviceOrientation(UIDeviceOrientation orientation)
{
	if (UIDeviceOrientationIsValidInterfaceOrientation(orientation)) {
		if (orientation != lastOrientation) {
			lastOrientation = orientation;
			switch (orientation) {
				case UIDeviceOrientationPortrait:
					UpdateWithOrientation(UIInterfaceOrientationPortrait);
					break;
				case UIDeviceOrientationPortraitUpsideDown:
					UpdateWithOrientation(UIInterfaceOrientationPortraitUpsideDown);
					break;
				case UIDeviceOrientationLandscapeLeft:
					UpdateWithOrientation(UIInterfaceOrientationLandscapeRight);
					break;
				case UIDeviceOrientationLandscapeRight:
					UpdateWithOrientation(UIInterfaceOrientationLandscapeLeft);
					break;
			}
		}
	}
}

static void LegacyOrientationChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo)
{
	SBOrientationLockManager *olm = [%c(SBOrientationLockManager) sharedInstance];
	if ([olm _effectivelyLocked])
		return;
	uint64_t orientation = 0;
	notify_get_state(notify_token, &orientation);
	UpdateWithDeviceOrientation((UIDeviceOrientation)orientation);
}

static void UIDeviceOrientationChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo)
{
	SBOrientationLockManager *olm = [%c(SBOrientationLockManager) sharedInstance];
	if ([olm _effectivelyLocked])
		return;
	UpdateWithDeviceOrientation([UIDevice currentDevice].orientation);
}

%ctor
{
	%init;
	ScaledTransform = ScaledTransformDefault;
	currentTransform = CATransform3DIdentity;
	icons = CFSetCreateMutable(kCFAllocatorDefault, 0, NULL);
	if (kCFCoreFoundationVersionNumber < 783.0) {
		notify_register_check("com.apple.springboard.rawOrientation", &notify_token);
		CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, LegacyOrientationChangedCallback, CFSTR("com.apple.springboard.rawOrientation"), NULL, CFNotificationSuspensionBehaviorCoalesce);
	} else {
		CFNotificationCenterAddObserver(CFNotificationCenterGetLocalCenter(), NULL, UIDeviceOrientationChangedCallback, (CFStringRef)UIDeviceOrientationDidChangeNotification, NULL, CFNotificationSuspensionBehaviorCoalesce);
	}
}
