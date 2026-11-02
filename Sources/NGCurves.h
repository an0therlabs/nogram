#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

// Timing curves used by Telegram's send transition
// (ChatMessageTransitionNodeImpl.AnimationParameters.bezier).
typedef NS_ENUM(NSInteger, NGCurve) {
    // verticalCurve: .custom(0.19919472913616398, 0.010644531250000006, 0.27920937042459737, 0.91025390625)
    NGCurveSendVertical,
    // horizontalCurve: .custom(0.23, 1.0, 0.32, 1.0)
    NGCurveSendHorizontal,
};

// The send transition's duration: chatMessageTransitionAnimationDuration(0.3).
extern const NSTimeInterval NGSendTransitionDuration;

// Display/Source/Spring.swift: bezierPoint(x1, y1, x2, y2, x)
CGFloat NGCurveSolve(NGCurve curve, CGFloat x);
CAMediaTimingFunction *NGCurveTimingFunction(NGCurve curve);
