#import <UIKit/UIKit.h>

// Line-for-line Objective-C ports of Telegram's image generators. Each
// function names the Swift function it reproduces; constants and path
// geometry are copied unchanged so the output is the same artwork.

// Display/Source/GenerateImage.swift: generateTintedImage(image:color:)
UIImage *NGTintedImage(UIImage *image, UIColor *color);
UIImage *NGTintedAsset(NSString *name, UIColor *color);

// TelegramPresentationData/Sources/ChatMessageBubbleImages.swift
typedef NS_ENUM(NSInteger, NGBubbleNeighbors) {
    NGBubbleNeighborsNone,      // .none
    NGBubbleNeighborsTop,       // .top(side: false)
    NGBubbleNeighborsBottom,    // .bottom
    NGBubbleNeighborsBoth,      // .both
};
// messageBubbleImage(maxCornerRadius:minCornerRadius:incoming:fillColor:...neighbors:...)
// with knockout = false, mask = false, onlyOutline = false, onlyShadow = false:
// the fill image the day-classic theme draws on a wallpaper.
UIImage *NGMessageBubbleImage(CGFloat maxCornerRadius, CGFloat minCornerRadius, BOOL incoming, UIColor *fillColor, NGBubbleNeighbors neighbors);

// PresentationThemeEssentialGraphics.swift: generateCheckImage(partial:color:width:)
UIImage *NGCheckImage(BOOL partial, UIColor *color, CGFloat width);
// PresentationThemeEssentialGraphics.swift: generateClockFrameImage / generateClockMinImage
UIImage *NGClockFrameImage(UIColor *color);
UIImage *NGClockMinImage(UIColor *color);

// PresentationResourcesChatList.swift: generateStatusCheckImage(theme:single:)
UIImage *NGStatusCheckImage(UIColor *color, BOOL single);
// PresentationResourcesChatList.swift: generateBadgeBackgroundImage(theme:diameter:active:...)
UIImage *NGBadgeBackgroundImage(UIColor *color, CGFloat diameter);

// PresentationResourcesSettings.swift: renderSettingsIcon(name:backgroundColors:)
UIImage *NGSettingsIcon(NSString *assetName, NSArray *backgroundColors);
