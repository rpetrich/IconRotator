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

@interface UIView (Springtomize)
- (CGFloat)springtomizeScaleFactor;
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

%hook SBSearchController

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
	UIView *result = %orig;
	if (result) {
		NSArray *subviews = result.subviews;
		if ([subviews count]) {
			UIView *icon = [subviews objectAtIndex:0];
			CALayer *layer = icon.layer;
			layer.transform = ScaledTransform(result);
			[layer setValue:@"transform" forKey:@"IconRotatorKeyPath"];
			CFSetSetValue(icons, icon);
		}
	}
	return result;
}

%end

%hook SpringBoard

- (void)applicationDidFinishLaunching:(UIApplication *)application
{
	%orig;
	if ([UIView instancesRespondToSelector:@selector(springtomizeScaleFactor)])
		ScaledTransform = ScaledTransformSpringtomize;
	// This code is quite evil
	SBAccelerometerInterface *accelerometer = [%c(SBAccelerometerInterface) sharedInstance];
	NSMutableArray **_clients = CHIvarRef(accelerometer, _clients, NSMutableArray *);
	if (_clients) {
		NSMutableArray *clients = *_clients;
		if (!clients)
			*_clients = clients = [[NSMutableArray alloc] init];
		SBAccelerometerClient *client = [[%c(SBAccelerometerClient) alloc] init];
		if (client) {
			[client setUpdateInterval:0.1];
			[clients addObject:client];
		}
		[client release];
	}
}

%end

static void OrientationChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo)
{
	uint64_t orientation = 0;
	notify_get_state(notify_token, &orientation);
	if (orientation == lastOrientation)
		return;
	switch (orientation) {
		case UIDeviceOrientationPortrait:
			currentTransform = CATransform3DIdentity;
			reflectionOpacity = 1.0f;
			break;
		case UIDeviceOrientationPortraitUpsideDown:
			currentTransform = CATransform3DMakeRotation(M_PI, 0.0f, 0.0f, 1.0f);
			reflectionOpacity = 0.0f;
			break;
		case UIDeviceOrientationLandscapeLeft:
			currentTransform = CATransform3DMakeRotation(0.5f * M_PI, 0.0f, 0.0f, 1.0f);
			reflectionOpacity = 0.0f;
			break;
		case UIDeviceOrientationLandscapeRight:
			currentTransform = CATransform3DMakeRotation(-0.5f * M_PI, 0.0f, 0.0f, 1.0f);
			reflectionOpacity = 0.0f;
			break;
		default:
			return;
	}
	lastOrientation = orientation;
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

%ctor
{
	%init;
	ScaledTransform = ScaledTransformDefault;
	currentTransform = CATransform3DIdentity;
	icons = CFSetCreateMutable(kCFAllocatorDefault, 0, NULL);
	notify_register_check("com.apple.springboard.rawOrientation", &notify_token);
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, OrientationChangedCallback, CFSTR("com.apple.springboard.rawOrientation"), NULL, CFNotificationSuspensionBehaviorCoalesce);
}
