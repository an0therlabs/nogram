#import <UIKit/UIKit.h>

// The default chat wallpaper: the four-colour gradient of
// GradientBackground/Sources/SoftwareGradientBackground.swift with
// Telegram's built-in doodle pattern (fqv01SQemVIBAAAApND8LDRUhRU.tgv)
// laid over it in soft light at 50% opacity, as WallpaperBackgroundNode does.
//
// iOS 6 has no layer compositing filters, so the soft-light blend is
// composed into each frame with Core Graphics instead of between layers.
@interface NGWallpaperView : UIView
// GradientBackgroundNode.animateEvent(transition:extendAnimation: false):
// steps the phase back by one and morphs the gradient to it.
- (void)animateEventWithDuration:(NSTimeInterval)duration;
@end
