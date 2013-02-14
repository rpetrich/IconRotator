#import <SpringBoard/SpringBoard.h>
#import <QuartzCore/QuartzCore.h>
#import <notify.h>
#import <CaptainHook/CaptainHook.h>

static CFMutableSetRef icons;
static CATransform3D currentTransform;
static CGFloat reflectionOpacity;
static int notify_token;
static uint64_t lastOrientation;

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

static CATransform3D (*ScaledTransform)(UIView *);

static CATransform3D ScaledTransformSpringtomize(UIView *iconView)
{
	CGFloat scale = [iconView springtomizeScaleFactor];
	return CATransform3DScale(currentTransform, scale, scale, 1.0f);
}

static CATransform3D ScaledTransformDefault(UIView *iconView)
{
	return currentTransform;
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

%hook SBIconView

- (void)didMoveToWindow
{
	%orig;
	if (self.window) {
		CFSetSetValue(icons, self);
		CALayer *layer = self.layer;
		layer.sublayerTransform = ScaledTransform(self);
		[layer setValue:@"sublayerTransform" forKey:@"IconRotatorKeyPath"];
		CHIvar(self, _reflection, UIImageView *).alpha = reflectionOpacity;
	}
}

- (void)didMoveToSuperview
{
	%orig;
	if (self.superview) {
		self.layer.sublayerTransform = ScaledTransform(self);
	}
}

%end

static void ApplyRotatedViewTransform(UIView *view)
{
	if (view) {
		CALayer *layer = view.layer;
		layer.transform = ScaledTransform(view);
		[layer setValue:@"transform" forKey:@"IconRotatorKeyPath"];
		CFSetSetValue(icons, view);
	}
}


%hook SBNowPlayingBarView

- (void)didMoveToWindow
{
	%orig;
	if (self.window) {
		ApplyRotatedViewTransform(self.toggleButton);
		ApplyRotatedViewTransform(self.airPlayButton);
	}
}

%end

%hook SBNowPlayingBarMediaControlsView

- (void)didMoveToWindow
{
	%orig;
	if (self.window) {
		ApplyRotatedViewTransform(self.prevButton);
		ApplyRotatedViewTransform(self.playButton);
		ApplyRotatedViewTransform(self.nextButton);
		ApplyRotatedViewTransform(self.airPlayButton);
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
			ApplyRotatedViewTransform([subviews objectAtIndex:0]);
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
	for (UIView *view in (id)icons) {
		CALayer *layer = view.layer;
		NSString *keyPath = [layer valueForKey:@"IconRotatorKeyPath"];
		CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:keyPath];
		NSValue *toValue = [NSValue valueWithCATransform3D:ScaledTransform(view)];
		animation.toValue = toValue;
		animation.duration = 0.2;
		animation.removedOnCompletion = YES;
		animation.fromValue = [layer.presentationLayer valueForKeyPath:keyPath];
		[layer setValue:toValue forKeyPath:keyPath];
		[layer addAnimation:animation forKey:@"IconRotator"];
		UIImageView **imageView = CHIvarRef(view, _reflection, UIImageView *);
		if (imageView)
			(*imageView).alpha = reflectionOpacity;
	}
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
