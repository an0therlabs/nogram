#import "NGOriginal.h"

#pragma mark - DrawingContext

// Display's DrawingContext: an ARGB bitmap in Core Graphics' native y-up
// coordinates, scaled to the screen. withFlippedContext hands the context out
// as is; generateImage(_:rotatedContext:) flips it to UIKit's y-down first.
typedef void (^NGDrawBlock)(CGSize size, CGContextRef context);

static CGFloat NGScreenScale(void) {
    return [UIScreen mainScreen].scale;
}


static UIImage *NGDrawingContextImage(CGSize size, BOOL flipped, NGDrawBlock draw) {
    CGFloat scale = NGScreenScale();
    size_t w = (size_t)ceil(size.width * scale), h = (size_t)ceil(size.height * scale);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, w, h, 8, w * 4, space, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(space);
    CGContextClearRect(context, CGRectMake(0, 0, w, h));
    CGContextScaleCTM(context, scale, scale);
    if (flipped) {
        CGContextTranslateCTM(context, size.width / 2.0f, size.height / 2.0f);
        CGContextScaleCTM(context, 1.0f, -1.0f);
        CGContextTranslateCTM(context, -size.width / 2.0f, -size.height / 2.0f);
    }
    draw(size, context);
    CGImageRef cgImage = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    UIImage *image = [UIImage imageWithCGImage:cgImage scale:scale orientation:UIImageOrientationUp];
    CGImageRelease(cgImage);
    return image;
}

// generateImage(_:contextGenerator:) — raw y-up context.
static UIImage *NGGenerateImage(CGSize size, NGDrawBlock draw) {
    return NGDrawingContextImage(size, NO, draw);
}

// generateImage(_:rotatedContext:) — UIKit y-down context.
static UIImage *NGGenerateRotatedImage(CGSize size, NGDrawBlock draw) {
    return NGDrawingContextImage(size, YES, draw);
}

static void NGAddArcToPoint(CGContextRef c, CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2, CGFloat r) {
    CGContextAddArcToPoint(c, x1, y1, x2, y2, r);
}


#pragma mark - Tint

UIImage *NGTintedImage(UIImage *image, UIColor *color) {
    if (!image) return nil;
    CGSize imageSize = image.size;
    UIGraphicsBeginImageContextWithOptions(imageSize, NO, image.scale);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGRect imageRect = CGRectMake(0, 0, imageSize.width, imageSize.height);
    CGContextSaveGState(context);
    CGContextTranslateCTM(context, CGRectGetMidX(imageRect), CGRectGetMidY(imageRect));
    CGContextScaleCTM(context, 1.0f, -1.0f);
    CGContextTranslateCTM(context, -CGRectGetMidX(imageRect), -CGRectGetMidY(imageRect));
    CGContextClipToMask(context, imageRect, image.CGImage);
    CGContextSetFillColorWithColor(context, color.CGColor);
    CGContextFillRect(context, imageRect);
    CGContextRestoreGState(context);
    UIImage *tinted = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return tinted;
}

UIImage *NGTintedAsset(NSString *name, UIColor *color) {
    return NGTintedImage([UIImage imageNamed:name], color);
}

#pragma mark - Bubbles

static const CGFloat minRadiusForFullTailCorner = 14.0f;

UIImage *NGMessageBubbleImage(CGFloat maxCornerRadius, CGFloat minCornerRadius, BOOL incoming, UIColor *fillColor, NGBubbleNeighbors neighbors) {
    CGFloat topLeftRadius, topRightRadius, bottomLeftRadius, bottomRightRadius;
    BOOL drawTail;

    switch (neighbors) {
        case NGBubbleNeighborsNone:
            topLeftRadius = maxCornerRadius;
            topRightRadius = maxCornerRadius;
            bottomLeftRadius = maxCornerRadius;
            bottomRightRadius = maxCornerRadius;
            drawTail = YES;
            break;
        case NGBubbleNeighborsBoth:
            topLeftRadius = maxCornerRadius;
            topRightRadius = minCornerRadius;
            bottomLeftRadius = maxCornerRadius;
            bottomRightRadius = minCornerRadius;
            drawTail = NO;
            break;
        case NGBubbleNeighborsBottom:
            topLeftRadius = maxCornerRadius;
            topRightRadius = minCornerRadius;
            bottomLeftRadius = maxCornerRadius;
            bottomRightRadius = maxCornerRadius;
            drawTail = YES;
            break;
        case NGBubbleNeighborsTop:
        default:
            topLeftRadius = maxCornerRadius;
            topRightRadius = maxCornerRadius;
            bottomLeftRadius = maxCornerRadius;
            bottomRightRadius = minCornerRadius;
            drawTail = NO;
            break;
    }

    const CGFloat fixedMainDiameter = 33.0f;
    CGSize innerSize = CGSizeMake(fixedMainDiameter + 6.0f, fixedMainDiameter);
    const CGFloat strokeInset = 1.0f;
    CGSize sourceRawSize = CGSizeMake(innerSize.width + strokeInset * 2.0f, innerSize.height + strokeInset * 2.0f);
    const CGFloat additionalInset = 1.0f;
    CGSize imageSize = CGSizeMake(sourceRawSize.width + additionalInset * 2.0f, sourceRawSize.height + additionalInset * 2.0f);
    int outgoingStretchX = (int)(additionalInset + strokeInset + roundf(fixedMainDiameter / 2.0f)) - 1;
    int outgoingStretchY = (int)(additionalInset + strokeInset + roundf(fixedMainDiameter / 2.0f));
    int incomingStretchX = (int)sourceRawSize.width - outgoingStretchX + (int)additionalInset;
    int incomingStretchY = outgoingStretchY;

    CGSize rawSize = imageSize;
    CGRect bottomEllipse = CGRectMake(24.0f, 16.0f, 27.0f, 17.0f);
    CGRect topEllipse = CGRectMake(33.0f, 14.0f, 23.0f, 21.0f);

    UIImage *formImage = NGGenerateImage(imageSize, ^(CGSize size, CGContextRef context) {
        CGContextClearRect(context, CGRectMake(0, 0, rawSize.width, rawSize.height));
        CGContextTranslateCTM(context, additionalInset + strokeInset, additionalInset + strokeInset);

        CGContextSetFillColorWithColor(context, [UIColor blackColor].CGColor);

        CGContextMoveToPoint(context, 0.0f, topLeftRadius);
        NGAddArcToPoint(context, 0.0f, 0.0f, topLeftRadius, 0.0f, topLeftRadius);
        CGContextAddLineToPoint(context, fixedMainDiameter - topRightRadius, 0.0f);
        NGAddArcToPoint(context, fixedMainDiameter, 0.0f, fixedMainDiameter, topRightRadius, topRightRadius);
        CGContextAddLineToPoint(context, fixedMainDiameter, fixedMainDiameter - bottomRightRadius);
        NGAddArcToPoint(context, fixedMainDiameter, fixedMainDiameter, fixedMainDiameter - bottomRightRadius, fixedMainDiameter, bottomRightRadius);
        CGContextAddLineToPoint(context, bottomLeftRadius, fixedMainDiameter);
        NGAddArcToPoint(context, 0.0f, fixedMainDiameter, 0.0f, fixedMainDiameter - bottomLeftRadius, bottomLeftRadius);
        CGContextAddLineToPoint(context, 0.0f, topLeftRadius);
        CGContextFillPath(context);

        if (drawTail) {
            if (maxCornerRadius >= minRadiusForFullTailCorner) {
                CGContextMoveToPoint(context, CGRectGetMinX(bottomEllipse), CGRectGetMidY(bottomEllipse));
                CGContextAddQuadCurveToPoint(context, CGRectGetMinX(bottomEllipse), CGRectGetMaxY(bottomEllipse), CGRectGetMidX(bottomEllipse), CGRectGetMaxY(bottomEllipse));
                CGContextAddQuadCurveToPoint(context, CGRectGetMaxX(bottomEllipse), CGRectGetMaxY(bottomEllipse), CGRectGetMaxX(bottomEllipse), CGRectGetMidY(bottomEllipse));
                CGContextFillPath(context);
            } else {
                CGContextFillRect(context, CGRectMake(CGRectGetMinX(bottomEllipse) - 2.0f, CGRectGetMidY(bottomEllipse), bottomEllipse.size.width + 2.0f, bottomEllipse.size.height / 2.0f));
            }
            CGContextFillRect(context, CGRectMake(fixedMainDiameter / 2.0f, floorf(fixedMainDiameter / 2.0f), fixedMainDiameter / 2.0f, ceilf(CGRectGetMidY(bottomEllipse)) - floorf(fixedMainDiameter / 2.0f)));
            CGContextSetFillColorWithColor(context, [UIColor clearColor].CGColor);
            CGContextSetBlendMode(context, kCGBlendModeCopy);
            CGContextFillEllipseInRect(context, topEllipse);
        }
    });

    UIImage *image = NGGenerateImage(imageSize, ^(CGSize size, CGContextRef context) {
        CGContextClearRect(context, CGRectMake(0, 0, rawSize.width, rawSize.height));
        CGContextSetBlendMode(context, kCGBlendModeNormal);
        CGContextSetFillColorWithColor(context, fillColor.CGColor);

        CGContextSaveGState(context);
        CGContextTranslateCTM(context, rawSize.width / 2.0f, rawSize.height / 2.0f);
        CGContextScaleCTM(context, incoming ? -1.0f : 1.0f, -1.0f);
        CGContextTranslateCTM(context, -rawSize.width / 2.0f, -rawSize.height / 2.0f);
        CGContextClipToMask(context, CGRectMake(0, 0, rawSize.width, rawSize.height), formImage.CGImage);
        CGContextFillRect(context, CGRectMake(0, 0, rawSize.width, rawSize.height));
        CGContextRestoreGState(context);
    });

    return [image stretchableImageWithLeftCapWidth:(incoming ? incomingStretchX : outgoingStretchX)
                                      topCapHeight:(incoming ? incomingStretchY : outgoingStretchY)];
}

#pragma mark - Checks and clock

// drawSvgPath(context, path: "...S ") strokes the path at the trailing S.
UIImage *NGCheckImage(BOOL partial, UIColor *color, CGFloat width) {
    return NGGenerateRotatedImage(CGSizeMake(width, floorf(width * 9.0f / 11.0f)), ^(CGSize size, CGContextRef context) {
        CGContextClearRect(context, CGRectMake(0, 0, size.width, size.height));
        CGContextScaleCTM(context, width / 11.0f, width / 11.0f);
        CGContextTranslateCTM(context, 1.0f, 1.0f);
        CGContextSetStrokeColorWithColor(context, color.CGColor);
        CGContextSetLineWidth(context, 0.99f);
        CGContextSetLineCap(context, kCGLineCapRound);
        CGContextSetLineJoin(context, kCGLineJoinRound);
        if (partial) {
            // "M0.5,7 L7,0 S "
            CGContextMoveToPoint(context, 0.5f, 7.0f);
            CGContextAddLineToPoint(context, 7.0f, 0.0f);
        } else {
            // "M0,4 L2.95157047,6.95157047 L2.95157047,6.95157047 C2.97734507,6.97734507 3.01913396,6.97734507
            //  3.04490857,6.95157047 C3.04548448,6.95099456 3.04604969,6.95040803 3.04660389,6.9498112 L9.5,0 S "
            CGContextMoveToPoint(context, 0.0f, 4.0f);
            CGContextAddLineToPoint(context, 2.95157047f, 6.95157047f);
            CGContextAddLineToPoint(context, 2.95157047f, 6.95157047f);
            CGContextAddCurveToPoint(context, 2.97734507f, 6.97734507f, 3.01913396f, 6.97734507f, 3.04490857f, 6.95157047f);
            CGContextAddCurveToPoint(context, 3.04548448f, 6.95099456f, 3.04604969f, 6.95040803f, 3.04660389f, 6.9498112f);
            CGContextAddLineToPoint(context, 9.5f, 0.0f);
        }
        CGContextStrokePath(context);
    });
}

UIImage *NGClockFrameImage(UIColor *color) {
    return NGGenerateImage(CGSizeMake(11.0f, 11.0f), ^(CGSize size, CGContextRef context) {
        CGContextClearRect(context, CGRectMake(0, 0, size.width, size.height));
        CGContextSetStrokeColorWithColor(context, color.CGColor);
        CGContextSetFillColorWithColor(context, color.CGColor);
        CGFloat strokeWidth = 1.0f;
        CGContextSetLineWidth(context, strokeWidth);
        CGContextStrokeEllipseInRect(context, CGRectMake(strokeWidth / 2.0f, strokeWidth / 2.0f, size.width - strokeWidth, size.height - strokeWidth));
        CGContextFillRect(context, CGRectMake((11.0f - strokeWidth) / 2.0f, strokeWidth * 3.0f, strokeWidth, 11.0f / 2.0f - strokeWidth * 3.0f));
    });
}

UIImage *NGClockMinImage(UIColor *color) {
    return NGGenerateImage(CGSizeMake(11.0f, 11.0f), ^(CGSize size, CGContextRef context) {
        CGContextClearRect(context, CGRectMake(0, 0, size.width, size.height));
        CGContextSetFillColorWithColor(context, color.CGColor);
        CGFloat strokeWidth = 1.0f;
        CGContextFillRect(context, CGRectMake((11.0f - strokeWidth) / 2.0f, (11.0f - strokeWidth) / 2.0f, 11.0f / 2.0f - strokeWidth, strokeWidth));
    });
}

UIImage *NGStatusCheckImage(UIColor *color, BOOL single) {
    return NGGenerateRotatedImage(CGSizeMake(single ? 13.0f : 18.0f, 13.0f), ^(CGSize size, CGContextRef context) {
        CGContextClearRect(context, CGRectMake(0, 0, size.width, size.height));
        CGContextTranslateCTM(context, 1.0f, 2.0f);
        CGContextSetStrokeColorWithColor(context, color.CGColor);
        CGContextSetLineWidth(context, 1.32f);
        CGContextSetLineCap(context, kCGLineCapRound);
        CGContextSetLineJoin(context, kCGLineJoinRound);
        // "M0,4.48 L3.59439858,7.93062264 L3.59439858,7.93062264 C3.63384129,7.96848764 3.69651158,7.96720866
        //  3.73437658,7.92776595 C3.7346472,7.92748405 3.73491615,7.92720055 3.73518342,7.92691547 L11.1666667,0 S "
        CGContextMoveToPoint(context, 0.0f, 4.48f);
        CGContextAddLineToPoint(context, 3.59439858f, 7.93062264f);
        CGContextAddLineToPoint(context, 3.59439858f, 7.93062264f);
        CGContextAddCurveToPoint(context, 3.63384129f, 7.96848764f, 3.69651158f, 7.96720866f, 3.73437658f, 7.92776595f);
        CGContextAddCurveToPoint(context, 3.7346472f, 7.92748405f, 3.73491615f, 7.92720055f, 3.73518342f, 7.92691547f);
        CGContextAddLineToPoint(context, 11.1666667f, 0.0f);
        CGContextStrokePath(context);
        if (!single) {
            // "M7.33333333,8 L14.8333333,0 S "
            CGContextMoveToPoint(context, 7.33333333f, 8.0f);
            CGContextAddLineToPoint(context, 14.8333333f, 0.0f);
            CGContextStrokePath(context);
        }
    });
}

UIImage *NGBadgeBackgroundImage(UIColor *color, CGFloat diameter) {
    UIImage *image = NGGenerateImage(CGSizeMake(diameter, diameter), ^(CGSize size, CGContextRef context) {
        CGContextClearRect(context, CGRectMake(0, 0, size.width, size.height));
        CGContextSetFillColorWithColor(context, color.CGColor);
        CGContextFillEllipseInRect(context, CGRectMake(0, 0, size.width, size.height));
    });
    return [image stretchableImageWithLeftCapWidth:(NSInteger)(diameter / 2.0f) topCapHeight:(NSInteger)(diameter / 2.0f)];
}

#pragma mark - Settings icons

UIImage *NGSettingsIcon(NSString *assetName, NSArray *backgroundColors) {
    UIImage *gradientImage = [UIImage imageNamed:@"settings_gradient"];
    UIImage *backdropImage = [UIImage imageNamed:@"settings_backdrop"];
    UIImage *image = [UIImage imageNamed:assetName];
    return NGGenerateImage(CGSizeMake(30.0f, 30.0f), ^(CGSize size, CGContextRef context) {
        CGRect bounds = CGRectMake(0, 0, size.width, size.height);
        CGContextClearRect(context, bounds);

        CGFloat locations[2] = { 0.0f, 1.0f };
        NSMutableArray *colors = [NSMutableArray array];
        for (UIColor *c in backgroundColors) [colors addObject:(__bridge id)c.CGColor];
        if (colors.count == 1) [colors addObject:colors[0]];
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        CGGradientRef gradient = CGGradientCreateWithColors(colorSpace, (__bridge CFArrayRef)colors, locations);
        CGContextDrawLinearGradient(context, gradient, CGPointMake(size.width, size.height), CGPointMake(0.0f, 0.0f), 0);
        CGGradientRelease(gradient);
        CGColorSpaceRelease(colorSpace);

        if (gradientImage.CGImage) {
            CGContextSetBlendMode(context, kCGBlendModePlusLighter);
            CGContextDrawImage(context, bounds, gradientImage.CGImage);
        }
        if (backdropImage.CGImage) {
            CGContextSetBlendMode(context, kCGBlendModeOverlay);
            CGContextDrawImage(context, bounds, backdropImage.CGImage);
        }
        CGContextSetBlendMode(context, kCGBlendModeNormal);

        if (image.CGImage) {
            CGSize imageSize = image.size;
            CGRect imageRect = CGRectMake((bounds.size.width - imageSize.width) * 0.5f, (bounds.size.height - imageSize.height) * 0.5f, imageSize.width, imageSize.height);
            CGContextSaveGState(context);
            CGContextClipToMask(context, imageRect, image.CGImage);
            CGContextSetFillColorWithColor(context, [UIColor whiteColor].CGColor);
            CGContextFillRect(context, imageRect);
            CGContextRestoreGState(context);
        }

        UIBezierPath *outerPath = [UIBezierPath bezierPathWithRect:bounds];
        UIBezierPath *innerPath = [UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:8.0f];
        [outerPath appendPath:innerPath];
        CGContextSaveGState(context);
        CGContextAddPath(context, outerPath.CGPath);
        CGContextEOClip(context);
        CGContextSetBlendMode(context, kCGBlendModeClear);
        CGContextFillRect(context, bounds);
        CGContextRestoreGState(context);
    });
}

