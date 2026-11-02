#import "NGTheme.h"
#import <QuartzCore/QuartzCore.h>

@implementation NGTheme

#pragma mark - Colours

+ (UIColor *)accentColor { return NGHex(0x0088ff); }
+ (UIColor *)separatorColor { return NGHex(0xc8c7cc); }
+ (UIColor *)secondaryTextColor { return NGHex(0x8e8e93); }
+ (UIColor *)blocksBackgroundColor { return NGHex(0xefeff4); }

+ (NSArray *)avatarColorsAtIndex:(NSInteger)index {
    static const unsigned int table[7][2] = {
        { 0xff516a, 0xff885e },
        { 0xffa85c, 0xffcd6a },
        { 0x665fff, 0x82b1ff },
        { 0x54cb68, 0xa0de7e },
        { 0x4acccd, 0x00fcfd },
        { 0x2a9ef1, 0x72d5fd },
        { 0xd669ed, 0xe0a2f3 },
    };
    NSInteger i = ((index % 7) + 7) % 7;
    return @[ NGHex(table[i][0]), NGHex(table[i][1]) ];
}

+ (UIColor *)nameColorAtIndex:(NSInteger)index {
    static const unsigned int table[7] = { 0xcc5049, 0xd67722, 0x955cdb, 0x40a920, 0x309eba, 0x368ad1, 0xc7508b };
    return NGHex(table[((index % 7) + 7) % 7]);
}

#pragma mark - Fonts

+ (UIFont *)regularFont:(CGFloat)size { return [UIFont systemFontOfSize:size]; }

+ (UIFont *)mediumFont:(CGFloat)size {
    if ([UIFont respondsToSelector:@selector(systemFontOfSize:weight:)]) {
        return [UIFont systemFontOfSize:size weight:UIFontWeightMedium];
    }
    UIFont *font = [UIFont fontWithName:@"HelveticaNeue-Medium" size:size];
    return font ?: [UIFont boldSystemFontOfSize:size];
}

+ (UIFont *)boldFont:(CGFloat)size { return [UIFont boldSystemFontOfSize:size]; }

+ (CGFloat)pixel { return 1.0f / [UIScreen mainScreen].scale; }

#pragma mark - Images

+ (UIImage *)imageWithColor:(UIColor *)color size:(CGSize)size {
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    [color setFill];
    UIRectFill(CGRectMake(0, 0, size.width, size.height));
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

static void NGStroke(UIBezierPath *path, CGFloat width) {
    path.lineWidth = width;
    path.lineCapStyle = kCGLineCapRound;
    path.lineJoinStyle = kCGLineJoinRound;
    [path stroke];
}

static UIBezierPath *NGPoly(const CGFloat *xy, int count, BOOL close) {
    UIBezierPath *p = [UIBezierPath bezierPath];
    [p moveToPoint:CGPointMake(xy[0], xy[1])];
    for (int i = 1; i < count; i++) {
        [p addLineToPoint:CGPointMake(xy[i * 2], xy[i * 2 + 1])];
    }
    if (close) [p closePath];
    return p;
}

static void NGLine(CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2, CGFloat width) {
    UIBezierPath *p = [UIBezierPath bezierPath];
    [p moveToPoint:CGPointMake(x1, y1)];
    [p addLineToPoint:CGPointMake(x2, y2)];
    NGStroke(p, width);
}

// Every glyph is drawn on a 24x24 grid and scaled, so the app ships no image assets.
+ (UIImage *)icon:(NGIcon)icon size:(CGFloat)size color:(UIColor *)color {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextScaleCTM(ctx, size / 24.0f, size / 24.0f);
    [color setStroke];
    [color setFill];
    const CGFloat w = 1.7f;

    switch (icon) {
        case NGIconChats: {
            NGStroke([UIBezierPath bezierPathWithRoundedRect:CGRectMake(3, 4, 18, 13.5f) cornerRadius:6.5f], w);
            const CGFloat t[] = { 8, 17.4f, 6, 21, 12.5f, 17.6f };
            NGStroke(NGPoly(t, 3, NO), w);
            break;
        }
        case NGIconContacts: {
            NGStroke([UIBezierPath bezierPathWithOvalInRect:CGRectMake(8, 3.5f, 8, 8)], w);
            UIBezierPath *b = [UIBezierPath bezierPath];
            [b addArcWithCenter:CGPointMake(12, 20.5f) radius:7.5f startAngle:(CGFloat)M_PI endAngle:(CGFloat)(2 * M_PI) clockwise:YES];
            [b closePath];
            NGStroke(b, w);
            break;
        }
        case NGIconCalls: {
            CGPoint c = CGPointMake(18, 6);
            CGFloat r = 11.5f, a1 = (CGFloat)(M_PI * 0.53), a2 = (CGFloat)(M_PI * 0.97);
            NGStroke([UIBezierPath bezierPathWithArcCenter:c radius:r startAngle:a1 endAngle:a2 clockwise:YES], 3.0f);
            CGFloat pr = 3.1f;
            CGPoint e1 = CGPointMake(c.x + r * cosf(a1), c.y + r * sinf(a1));
            CGPoint e2 = CGPointMake(c.x + r * cosf(a2), c.y + r * sinf(a2));
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(e1.x - pr, e1.y - pr, pr * 2, pr * 2)] fill];
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(e2.x - pr, e2.y - pr, pr * 2, pr * 2)] fill];
            break;
        }
        case NGIconSettings: {
            CGContextSaveGState(ctx);
            CGContextTranslateCTM(ctx, 12, 12);
            for (int i = 0; i < 8; i++) {
                CGContextSaveGState(ctx);
                CGContextRotateCTM(ctx, (CGFloat)(i * M_PI / 4));
                [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(-1.9f, -10.6f, 3.8f, 4.5f) cornerRadius:1] fill];
                CGContextRestoreGState(ctx);
            }
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(-7.6f, -7.6f, 15.2f, 15.2f)] fill];
            CGContextSetBlendMode(ctx, kCGBlendModeClear);
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(-3.2f, -3.2f, 6.4f, 6.4f)] fill];
            CGContextRestoreGState(ctx);
            break;
        }
        case NGIconCompose: {
            NGStroke([UIBezierPath bezierPathWithRoundedRect:CGRectMake(3.5f, 5.5f, 14, 14) cornerRadius:3.5f], w);
            NGLine(10.5f, 13.5f, 20, 4, 2.0f);
            break;
        }
        case NGIconBack: {
            const CGFloat t[] = { 14.5f, 3.5f, 6, 12, 14.5f, 20.5f };
            NGStroke(NGPoly(t, 3, NO), 2.6f);
            break;
        }
        case NGIconSearch: {
            NGStroke([UIBezierPath bezierPathWithOvalInRect:CGRectMake(4, 4, 12, 12)], 2.0f);
            NGLine(14.8f, 14.8f, 20, 20, 2.2f);
            break;
        }
        case NGIconAttach: {
            CGContextSaveGState(ctx);
            CGContextTranslateCTM(ctx, 12, 12);
            CGContextRotateCTM(ctx, (CGFloat)(M_PI / 4));
            CGContextTranslateCTM(ctx, -12, -12);
            UIBezierPath *p = [UIBezierPath bezierPath];
            [p moveToPoint:CGPointMake(15, 7.5f)];
            [p addLineToPoint:CGPointMake(15, 17)];
            [p addArcWithCenter:CGPointMake(11.5f, 17) radius:3.5f startAngle:0 endAngle:(CGFloat)M_PI clockwise:YES];
            [p addLineToPoint:CGPointMake(8, 5.5f)];
            [p addArcWithCenter:CGPointMake(10.5f, 5.5f) radius:2.5f startAngle:(CGFloat)M_PI endAngle:(CGFloat)(2 * M_PI) clockwise:YES];
            [p addLineToPoint:CGPointMake(13, 16)];
            NGStroke(p, w);
            CGContextRestoreGState(ctx);
            break;
        }
        case NGIconMic: {
            NGStroke([UIBezierPath bezierPathWithRoundedRect:CGRectMake(9, 2.5f, 6, 12) cornerRadius:3], w);
            NGStroke([UIBezierPath bezierPathWithArcCenter:CGPointMake(12, 11) radius:6 startAngle:0 endAngle:(CGFloat)M_PI clockwise:YES], w);
            NGLine(12, 17, 12, 21, w);
            break;
        }
        case NGIconPin: {
            CGContextSaveGState(ctx);
            CGContextTranslateCTM(ctx, 12, 12);
            CGContextRotateCTM(ctx, (CGFloat)(M_PI / 4));
            CGContextTranslateCTM(ctx, -12, -12);
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(8.5f, 2.5f, 7, 2.5f) cornerRadius:1] fill];
            const CGFloat body[] = { 9.5f, 5, 14.5f, 5, 15.5f, 12.5f, 8.5f, 12.5f };
            [NGPoly(body, 4, YES) fill];
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(6, 12, 12, 2.4f) cornerRadius:1] fill];
            NGLine(12, 14, 12, 21, 1.8f);
            CGContextRestoreGState(ctx);
            break;
        }
        case NGIconMute: {
            const CGFloat s[] = { 3, 9, 7, 9, 12, 4.5f, 12, 19.5f, 7, 15, 3, 15 };
            [NGPoly(s, 6, YES) fill];
            NGLine(15.5f, 9.5f, 20.5f, 14.5f, 2);
            NGLine(20.5f, 9.5f, 15.5f, 14.5f, 2);
            break;
        }
        case NGIconSaved: {
            const CGFloat s[] = { 6.5f, 3.5f, 17.5f, 3.5f, 17.5f, 20.5f, 12, 16, 6.5f, 20.5f };
            UIBezierPath *p = NGPoly(s, 5, YES);
            p.lineJoinStyle = kCGLineJoinRound;
            [p fill];
            break;
        }
        case NGIconDevices: {
            NGStroke([UIBezierPath bezierPathWithRoundedRect:CGRectMake(4.5f, 5.5f, 15, 10.5f) cornerRadius:1.5f], w);
            NGLine(2.5f, 19, 21.5f, 19, 2);
            break;
        }
        case NGIconFolder: {
            const CGFloat s[] = { 3, 6, 9.5f, 6, 11.5f, 8, 21, 8, 21, 18.5f, 3, 18.5f };
            [NGPoly(s, 6, YES) fill];
            break;
        }
        case NGIconBell: {
            UIBezierPath *p = [UIBezierPath bezierPath];
            [p moveToPoint:CGPointMake(5.5f, 17)];
            [p addLineToPoint:CGPointMake(5.5f, 11)];
            [p addArcWithCenter:CGPointMake(12, 11) radius:6.5f startAngle:(CGFloat)M_PI endAngle:(CGFloat)(2 * M_PI) clockwise:YES];
            [p addLineToPoint:CGPointMake(18.5f, 17)];
            [p closePath];
            [p fill];
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(4, 16, 16, 2) cornerRadius:1] fill];
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(10, 18.5f, 4, 3.5f)] fill];
            break;
        }
        case NGIconLock: {
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(5.5f, 11, 13, 10) cornerRadius:2] fill];
            UIBezierPath *p = [UIBezierPath bezierPath];
            [p moveToPoint:CGPointMake(8.5f, 11)];
            [p addLineToPoint:CGPointMake(8.5f, 8)];
            [p addArcWithCenter:CGPointMake(12, 8) radius:3.5f startAngle:(CGFloat)M_PI endAngle:(CGFloat)(2 * M_PI) clockwise:YES];
            [p addLineToPoint:CGPointMake(15.5f, 11)];
            NGStroke(p, 2);
            break;
        }
        case NGIconData: {
            NGStroke([UIBezierPath bezierPathWithOvalInRect:CGRectMake(4, 4, 16, 16)], w);
            UIBezierPath *p = [UIBezierPath bezierPath];
            [p moveToPoint:CGPointMake(12, 12)];
            [p addLineToPoint:CGPointMake(12, 4)];
            [p addArcWithCenter:CGPointMake(12, 12) radius:8 startAngle:(CGFloat)(-M_PI / 2) endAngle:0 clockwise:YES];
            [p closePath];
            [p fill];
            break;
        }
        case NGIconBrush: {
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(3, 3, 18, 18)] fill];
            CGContextSetBlendMode(ctx, kCGBlendModeClear);
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(6.5f, 8.5f, 3.2f, 3.2f)] fill];
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(10.5f, 5.5f, 3.2f, 3.2f)] fill];
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(14.5f, 8.5f, 3.2f, 3.2f)] fill];
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(12.5f, 14, 4, 4)] fill];
            CGContextSetBlendMode(ctx, kCGBlendModeNormal);
            break;
        }
        case NGIconBattery: {
            NGStroke([UIBezierPath bezierPathWithRoundedRect:CGRectMake(2.5f, 7.5f, 17, 9) cornerRadius:2.5f], w);
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(20.5f, 10.5f, 1.8f, 3) cornerRadius:0.8f] fill];
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(4.6f, 9.6f, 7, 4.8f) cornerRadius:1] fill];
            break;
        }
        case NGIconGlobe: {
            NGStroke([UIBezierPath bezierPathWithOvalInRect:CGRectMake(4, 4, 16, 16)], w);
            NGStroke([UIBezierPath bezierPathWithOvalInRect:CGRectMake(8.5f, 4, 7, 16)], w);
            NGLine(4, 12, 20, 12, w);
            break;
        }
        case NGIconStar: {
            UIBezierPath *p = [UIBezierPath bezierPath];
            for (int i = 0; i < 10; i++) {
                CGFloat r = (i % 2 == 0) ? 9.5f : 4.2f;
                CGFloat a = (CGFloat)(-M_PI / 2 + i * M_PI / 5);
                CGPoint pt = CGPointMake(12 + r * cosf(a), 12.8f + r * sinf(a));
                if (i == 0) [p moveToPoint:pt]; else [p addLineToPoint:pt];
            }
            [p closePath];
            [p fill];
            break;
        }
        case NGIconQuestion: {
            [@"?" drawInRect:CGRectMake(0, 0.5f, 24, 24) withFont:[self boldFont:19] lineBreakMode:NSLineBreakByClipping alignment:NSTextAlignmentCenter];
            break;
        }
        case NGIconAddContact: {
            NGStroke([UIBezierPath bezierPathWithOvalInRect:CGRectMake(4.5f, 4, 7.5f, 7.5f)], w);
            UIBezierPath *b = [UIBezierPath bezierPath];
            [b addArcWithCenter:CGPointMake(8.25f, 20) radius:6.5f startAngle:(CGFloat)M_PI endAngle:(CGFloat)(2 * M_PI) clockwise:YES];
            [b closePath];
            NGStroke(b, w);
            NGLine(18.5f, 7, 18.5f, 15, w);
            NGLine(14.5f, 11, 22.5f, 11, w);
            break;
        }
        case NGIconPlus: {
            NGLine(12, 4, 12, 20, 2);
            NGLine(4, 12, 20, 12, 2);
            break;
        }
    }

    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

+ (UIImage *)settingsIcon:(NGIcon)icon background:(UIColor *)background {
    CGFloat size = 29;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0);
    [background setFill];
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, size, size) cornerRadius:7] fill];
    UIImage *glyph = [self icon:icon size:20 color:[UIColor whiteColor]];
    [glyph drawInRect:CGRectMake(4.5f, 4.5f, 20, 20)];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

+ (UIImage *)sendButtonImage {
    CGFloat size = 34;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0);
    [[self accentColor] setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, size, size)] fill];
    [[UIColor whiteColor] setStroke];
    NGLine(17, 25, 17, 10, 2.4f);
    const CGFloat arrow[] = { 11, 15.5f, 17, 9.5f, 23, 15.5f };
    NGStroke(NGPoly(arrow, 3, NO), 2.4f);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

+ (UIImage *)badgeImageWithColor:(UIColor *)color {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(21, 20), NO, 0);
    [color setFill];
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 21, 20) cornerRadius:10] fill];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [image resizableImageWithCapInsets:UIEdgeInsetsMake(0, 10, 0, 10)];
}

+ (UIImage *)disclosureImage {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(8, 13), NO, 0);
    [NGHex(0xbab9be) setStroke];
    const CGFloat p[] = { 1.5f, 1.5f, 6.5f, 6.5f, 1.5f, 11.5f };
    NGStroke(NGPoly(p, 3, NO), 2);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

// Telegram's default chat wallpaper is a four-colour gradient
// (0xdbddbb, 0x6ba587, 0xd5d88d, 0x88b884); approximated with radial blobs.
+ (UIImage *)wallpaperImageWithSize:(CGSize)size {
    UIGraphicsBeginImageContextWithOptions(size, YES, 0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    [NGHex(0xb4c99c) setFill];
    UIRectFill(CGRectMake(0, 0, size.width, size.height));

    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    const unsigned int colors[4] = { 0xdbddbb, 0xd5d88d, 0x88b884, 0x6ba587 };
    const CGFloat points[4][2] = { { 0.1f, 0.15f }, { 0.95f, 0.3f }, { 0.15f, 0.85f }, { 0.9f, 0.95f } };
    CGFloat radius = MAX(size.width, size.height) * 0.75f;
    for (int i = 0; i < 4; i++) {
        UIColor *c = NGHex(colors[i]);
        UIColor *clear = [c colorWithAlphaComponent:0];
        NSArray *stops = @[ (__bridge id)c.CGColor, (__bridge id)clear.CGColor ];
        CGGradientRef gradient = CGGradientCreateWithColors(space, (__bridge CFArrayRef)stops, NULL);
        CGPoint center = CGPointMake(points[i][0] * size.width, points[i][1] * size.height);
        CGContextDrawRadialGradient(ctx, gradient, center, 0, center, radius, 0);
        CGGradientRelease(gradient);
    }
    CGColorSpaceRelease(space);

    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

+ (UIImage *)barBackgroundWithHeight:(CGFloat)height lineAtTop:(BOOL)top {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(1, height), YES, 0);
    [NGHex(0xf7f7f7) setFill];
    UIRectFill(CGRectMake(0, 0, 1, height));
    [NGHex(0xb2b2b2) setFill];
    CGFloat px = [self pixel];
    UIRectFill(CGRectMake(0, top ? 0 : height - px, 1, px));
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

#pragma mark - Views

+ (UILabel *)labelWithFont:(UIFont *)font color:(UIColor *)color {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.backgroundColor = [UIColor clearColor];
    label.font = font;
    label.textColor = color;
    return label;
}

+ (UIView *)separatorView {
    UIView *view = [[UIView alloc] initWithFrame:CGRectZero];
    view.backgroundColor = [self separatorColor];
    return view;
}

+ (UIView *)highlightView {
    UIView *view = [[UIView alloc] initWithFrame:CGRectZero];
    view.backgroundColor = NGHex(0xe5e5ea);
    return view;
}

#pragma mark - Bars

+ (void)applyAppearance {
    NSValue *noOffset = [NSValue valueWithUIOffset:UIOffsetZero];

    UINavigationBar *nav = [UINavigationBar appearance];
    [nav setBackgroundImage:[self barBackgroundWithHeight:44 lineAtTop:NO] forBarMetrics:UIBarMetricsDefault];
    if ([nav respondsToSelector:@selector(setShadowImage:)]) {
        [nav setShadowImage:[UIImage new]];
    }
    [nav setTitleTextAttributes:@{
        UITextAttributeTextColor: [UIColor blackColor],
        UITextAttributeTextShadowColor: [UIColor clearColor],
        UITextAttributeTextShadowOffset: noOffset,
        UITextAttributeFont: [self mediumFont:17],
    }];

    UITabBar *tab = [UITabBar appearance];
    [tab setBackgroundImage:[self barBackgroundWithHeight:49 lineAtTop:YES]];
    [tab setSelectionIndicatorImage:[self imageWithColor:[UIColor clearColor] size:CGSizeMake(1, 1)]];
    if ([tab respondsToSelector:@selector(setShadowImage:)]) {
        [tab setShadowImage:[UIImage new]];
    }

    UITabBarItem *item = [UITabBarItem appearance];
    [item setTitleTextAttributes:@{
        UITextAttributeTextColor: NGHex(0x959595),
        UITextAttributeTextShadowColor: [UIColor clearColor],
        UITextAttributeTextShadowOffset: noOffset,
        UITextAttributeFont: [self mediumFont:10],
    } forState:UIControlStateNormal];
    [item setTitleTextAttributes:@{
        UITextAttributeTextColor: [self accentColor],
        UITextAttributeTextShadowColor: [UIColor clearColor],
        UITextAttributeTextShadowOffset: noOffset,
        UITextAttributeFont: [self mediumFont:10],
    } forState:UIControlStateSelected];
}

+ (UITabBarItem *)tabItemWithTitle:(NSString *)title icon:(NGIcon)icon {
    UIImage *selected = [self icon:icon size:28 color:[self accentColor]];
    UIImage *normal = [self icon:icon size:28 color:NGHex(0x959595)];
    if ([UIImage instancesRespondToSelector:@selector(imageWithRenderingMode:)]) {
        return [[UITabBarItem alloc] initWithTitle:title
                                             image:[normal imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal]
                                     selectedImage:[selected imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal]];
    }
    UITabBarItem *item = [[UITabBarItem alloc] initWithTitle:title image:nil tag:0];
    [item setFinishedSelectedImage:selected withFinishedUnselectedImage:normal];
    return item;
}

+ (UIButton *)barButtonBase {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    [button setTitleColor:[self accentColor] forState:UIControlStateNormal];
    [button setTitleColor:[[self accentColor] colorWithAlphaComponent:0.4f] forState:UIControlStateHighlighted];
    button.titleLabel.font = [self regularFont:17];
    button.showsTouchWhenHighlighted = NO;
    return button;
}

+ (UIBarButtonItem *)barButtonWithTitle:(NSString *)title bold:(BOOL)bold target:(id)target action:(SEL)action {
    UIButton *button = [self barButtonBase];
    if (bold) button.titleLabel.font = [self mediumFont:17];
    [button setTitle:title forState:UIControlStateNormal];
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithCustomView:button];
    [self setTitle:title ofBarButton:item];
    return item;
}

+ (void)setTitle:(NSString *)title ofBarButton:(UIBarButtonItem *)item {
    UIButton *button = (UIButton *)item.customView;
    [button setTitle:title forState:UIControlStateNormal];
    CGFloat width = [self widthOfText:title font:button.titleLabel.font];
    button.frame = CGRectMake(0, 0, MAX(44, width + 4), 44);
}

+ (UIBarButtonItem *)barButtonWithIcon:(NGIcon)icon target:(id)target action:(SEL)action {
    UIButton *button = [self barButtonBase];
    [button setImage:[self icon:icon size:26 color:[self accentColor]] forState:UIControlStateNormal];
    [button setImage:[self icon:icon size:26 color:[[self accentColor] colorWithAlphaComponent:0.4f]] forState:UIControlStateHighlighted];
    button.frame = CGRectMake(0, 0, 44, 44);
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return [[UIBarButtonItem alloc] initWithCustomView:button];
}

+ (UIBarButtonItem *)backButtonWithTitle:(NSString *)title target:(id)target action:(SEL)action {
    UIButton *button = [self barButtonBase];
    [button setImage:[self icon:NGIconBack size:22 color:[self accentColor]] forState:UIControlStateNormal];
    [button setImage:[self icon:NGIconBack size:22 color:[[self accentColor] colorWithAlphaComponent:0.4f]] forState:UIControlStateHighlighted];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleEdgeInsets = UIEdgeInsetsMake(0, 2, 0, -2);
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    button.contentEdgeInsets = UIEdgeInsetsMake(0, -6, 0, 0);
    CGFloat width = [self widthOfText:title font:button.titleLabel.font];
    button.frame = CGRectMake(0, 0, MIN(120, width + 22), 44);
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return [[UIBarButtonItem alloc] initWithCustomView:button];
}

+ (void)disableExtendedLayoutFor:(UIViewController *)controller {
    if ([controller respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        controller.edgesForExtendedLayout = UIRectEdgeNone;
    }
}

#pragma mark - Dates

static NSDateFormatter *NGFormatter(NSString *format) {
    static NSMutableDictionary *cache;
    if (!cache) cache = [NSMutableDictionary new];
    NSDateFormatter *formatter = cache[format];
    if (!formatter) {
        formatter = [NSDateFormatter new];
        formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"ru_RU"];
        formatter.dateFormat = format;
        cache[format] = formatter;
    }
    return formatter;
}

static NSDate *NGDayStart(NSDate *date) {
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *parts = [calendar components:(NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit) fromDate:date];
    return [calendar dateFromComponents:parts];
}

static NSInteger NGDaysAgo(NSDate *date) {
    NSTimeInterval delta = [NGDayStart([NSDate date]) timeIntervalSinceDate:NGDayStart(date)];
    return (NSInteger)floor(delta / 86400.0 + 0.5);
}

+ (BOOL)date:(NSDate *)a isSameDayAs:(NSDate *)b {
    return [NGDayStart(a) isEqualToDate:NGDayStart(b)];
}

+ (NSString *)timeString:(NSDate *)date {
    return [NGFormatter(@"HH:mm") stringFromDate:date];
}

+ (NSString *)listDateString:(NSDate *)date {
    NSInteger days = NGDaysAgo(date);
    if (days <= 0) return [self timeString:date];
    if (days < 7) return [NGFormatter(@"EE") stringFromDate:date];
    return [NGFormatter(@"dd.MM.yy") stringFromDate:date];
}

+ (NSString *)dayHeaderString:(NSDate *)date {
    NSInteger days = NGDaysAgo(date);
    if (days <= 0) return @"Сегодня";
    if (days == 1) return @"Вчера";
    return [NGFormatter(@"d MMMM") stringFromDate:date];
}

#pragma mark - Text

+ (CGSize)sizeOfText:(NSString *)text font:(UIFont *)font width:(CGFloat)width {
    CGSize size = [text sizeWithFont:font constrainedToSize:CGSizeMake(width, 100000) lineBreakMode:NSLineBreakByWordWrapping];
    return CGSizeMake(ceilf(size.width), ceilf(size.height));
}

+ (CGFloat)widthOfText:(NSString *)text font:(UIFont *)font {
    return ceilf([text sizeWithFont:font].width);
}

@end
