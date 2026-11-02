#import "NGWallpaper.h"
#import "NGCurves.h"
#import <QuartzCore/QuartzCore.h>

// defaultBuiltinWallpaperGradientColors (DefaultDayPresentationTheme.swift)
static const unsigned int NGGradientColors[4] = { 0xdbddbb, 0x6ba587, 0xd5d88d, 0x88b884 };

// GradientBackgroundNode.basePositions
static const CGFloat NGBasePositions[8][2] = {
    { 0.80f, 0.10f },
    { 0.60f, 0.20f },
    { 0.35f, 0.25f },
    { 0.25f, 0.60f },
    { 0.20f, 0.90f },
    { 0.40f, 0.80f },
    { 0.65f, 0.75f },
    { 0.75f, 0.40f },
};

// gatherPositions(shiftArray(array: basePositions, offset: phase))
static void NGPositionsForPhase(NSInteger phase, CGPoint out[4]) {
    for (int i = 0; i < 4; i++) {
        NSInteger index = (i * 2 + phase) % 8;
        out[i] = CGPointMake(NGBasePositions[index][0], NGBasePositions[index][1]);
    }
}

// generateGradient(size:colors:positions:), including the swirl displacement
// that SwirlMap precomputes there.
static CGImageRef NGCreateGradientImage(int width, int height, const CGPoint positions[4]) {
    float rgb[4][3];
    for (int i = 0; i < 4; i++) {
        rgb[i][0] = ((NGGradientColors[i] >> 16) & 0xff) / 255.0f;
        rgb[i][1] = ((NGGradientColors[i] >> 8) & 0xff) / 255.0f;
        rgb[i][2] = (NGGradientColors[i] & 0xff) / 255.0f;
    }
    float positionFloats[4][2];
    for (int i = 0; i < 4; i++) {
        positionFloats[i][0] = (float)positions[i].x;
        positionFloats[i][1] = (float)(1.0 - positions[i].y);
    }

    size_t bytesPerRow = (size_t)width * 4;
    uint8_t *bytes = calloc((size_t)height, bytesPerRow);
    for (int y = 0; y < height; y++) {
        float directPixelY = (float)y / (float)height;
        float centerDistanceY = directPixelY - 0.5f;
        float centerDistanceY2 = centerDistanceY * centerDistanceY;
        uint8_t *line = bytes + bytesPerRow * (size_t)y;
        for (int x = 0; x < width; x++) {
            float directPixelX = (float)x / (float)width;
            float centerDistanceX = directPixelX - 0.5f;
            float centerDistance = sqrtf(centerDistanceX * centerDistanceX + centerDistanceY2);
            float swirlFactor = 0.35f * centerDistance;
            float theta = swirlFactor * swirlFactor * 0.8f * 8.0f;
            float sinTheta = sinf(theta), cosTheta = cosf(theta);
            float pixelX = fmaxf(0.0f, fminf(1.0f, 0.5f + centerDistanceX * cosTheta - centerDistanceY * sinTheta));
            float pixelY = fmaxf(0.0f, fminf(1.0f, 0.5f + centerDistanceX * sinTheta + centerDistanceY * cosTheta));

            float distanceSum = 0.0f, r = 0.0f, g = 0.0f, b = 0.0f;
            for (int i = 0; i < 4; i++) {
                float distanceX = pixelX - positionFloats[i][0];
                float distanceY = pixelY - positionFloats[i][1];
                float distance = fmaxf(0.0f, 0.92f - sqrtf(distanceX * distanceX + distanceY * distanceY));
                distance = distance * distance * distance;
                distanceSum += distance;
                r += distance * rgb[i][0];
                g += distance * rgb[i][1];
                b += distance * rgb[i][2];
            }
            float clampedSum = fmaxf(distanceSum, 0.00001f);
            uint8_t *pixel = line + x * 4;
            pixel[0] = (uint8_t)fminf(b / clampedSum * 255.0f, 255.0f);
            pixel[1] = (uint8_t)fminf(g / clampedSum * 255.0f, 255.0f);
            pixel[2] = (uint8_t)fminf(r / clampedSum * 255.0f, 255.0f);
            pixel[3] = 0xff;
        }
    }

    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(bytes, (size_t)width, (size_t)height, 8, bytesPerRow, space, kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    CGColorSpaceRelease(space);
    free(bytes);
    return image;
}

@implementation NGWallpaperView {
    UIImageView *_imageView;
    NSInteger _phase;
    CGSize _validSize;
    CGImageRef _pattern;
    BOOL _animating;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.clipsToBounds = YES;
        self.userInteractionEnabled = NO;
        _imageView = [[UIImageView alloc] initWithFrame:self.bounds];
        _imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:_imageView];
        _pattern = CGImageRetain([UIImage imageNamed:@"wallpaper_pattern"].CGImage);
    }
    return self;
}

- (void)dealloc {
    CGImageRelease(_pattern);
}

// size.fitted(CGSize(width: 80, height: 80)).integralFloor
static void NGGradientImageSize(CGSize size, int *w, int *h) {
    CGFloat scale = MIN(80.0f / size.width, 80.0f / size.height);
    *w = MAX(1, (int)floorf(size.width * scale));
    *h = MAX(1, (int)floorf(size.height * scale));
}

// The gradient stretched over the view, then the pattern (black, aspect fill)
// in soft light at 0.5.
- (UIImage *)composeWithPositions:(const CGPoint *)positions size:(CGSize)size scale:(CGFloat)scale {
    int gw, gh;
    NGGradientImageSize(size, &gw, &gh);
    CGImageRef gradient = NGCreateGradientImage(gw, gh, positions);

    UIGraphicsBeginImageContextWithOptions(size, YES, scale);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
    // UIKit's context is y-down; CGImages draw upright only in y-up.
    CGContextTranslateCTM(context, 0, size.height);
    CGContextScaleCTM(context, 1.0f, -1.0f);
    CGContextDrawImage(context, CGRectMake(0, 0, size.width, size.height), gradient);
    CGImageRelease(gradient);

    if (_pattern) {
        CGFloat pw = CGImageGetWidth(_pattern), ph = CGImageGetHeight(_pattern);
        CGFloat fill = MAX(size.width / pw, size.height / ph);
        CGRect rect = CGRectMake((size.width - pw * fill) / 2.0f, (size.height - ph * fill) / 2.0f, pw * fill, ph * fill);
        CGContextSaveGState(context);
        CGContextSetBlendMode(context, kCGBlendModeSoftLight);
        CGContextSetAlpha(context, 0.5f);
        CGContextClipToMask(context, rect, _pattern);
        CGContextSetFillColorWithColor(context, [UIColor blackColor].CGColor);
        CGContextFillRect(context, rect);
        CGContextRestoreGState(context);
    }

    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    if (size.width < 1 || size.height < 1 || CGSizeEqualToSize(size, _validSize)) return;
    _validSize = size;
    CGPoint positions[4];
    NGPositionsForPhase(_phase, positions);
    _imageView.image = [self composeWithPositions:positions size:size scale:0];
}

// updateLayout(size:transition:extendAnimation: false, backwards: false) for
// an animated transition: two steps (the old phase and the new one), 30 fps,
// frames sampled along the transition's curve, played with linear
// interpolation.
- (void)animateEventWithDuration:(NSTimeInterval)duration {
    if (_animating || _validSize.width < 1) return;
    NSInteger previousPhase = _phase;
    _phase = _phase == 0 ? 7 : _phase - 1;

    // Blocks cannot capture C arrays, so the positions travel in a struct.
    struct { CGPoint p[4]; } from, to;
    NGPositionsForPhase(previousPhase, from.p);
    NGPositionsForPhase(_phase, to.p);
    CGSize size = _validSize;
    int maxFrame = (int)(duration * 30.0);
    if (maxFrame < 2) return;
    _animating = YES;

    // The frames are composed at 1x off the main thread: a whole-screen
    // composite per frame is too much memory at @2x on a 512 MB device.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        NSMutableArray *frames = [NSMutableArray array];
        for (int frameIndex = 0; frameIndex < maxFrame; frameIndex++) {
            CGFloat t = NGCurveSolve(NGCurveSendVertical, (CGFloat)frameIndex / (CGFloat)(maxFrame - 1));
            t = MAX(0.0f, MIN(1.0f, t));
            // One step: stepIndex is 0, so the interpolation factor is the
            // sampled frame over the step's frame count.
            int globalStep = (int)(t * maxFrame);
            CGFloat stepT = (CGFloat)globalStep / (CGFloat)(maxFrame - 1);
            CGPoint morphed[4];
            for (int i = 0; i < 4; i++) {
                morphed[i] = CGPointMake(from.p[i].x * (1.0f - stepT) + to.p[i].x * stepT, from.p[i].y * (1.0f - stepT) + to.p[i].y * stepT);
            }
            [frames addObject:(__bridge id)[self composeWithPositions:morphed size:size scale:1].CGImage];
        }
        UIImage *final = [self composeWithPositions:to.p size:size scale:0];
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_imageView.image = final;
            CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:@"contents"];
            animation.values = frames;
            animation.duration = duration;
            animation.calculationMode = kCAAnimationLinear;
            animation.removedOnCompletion = YES;
            [self->_imageView.layer addAnimation:animation forKey:@"contents"];
            self->_animating = NO;
        });
    });
}

@end
