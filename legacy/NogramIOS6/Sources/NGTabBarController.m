#import "NGTabBarController.h"
#import "NGTheme.h"
#import "NGOriginal.h"

const CGFloat NGTabBarHeight = 49.0f;

@implementation NGTabBarItem

+ (instancetype)itemWithTitle:(NSString *)title imageName:(NSString *)imageName animationName:(NSString *)animationName {
    NGTabBarItem *item = [self new];
    item.title = title;
    item.imageName = imageName;
    item.animationName = animationName;
    return item;
}

@end

// tabBarItemImage(_:title:backgroundColor:tintColor:horizontal: false, imageMode:)
// imageMode draws only the icon, otherwise only the title; the node stacks both.
static UIImage *NGTabBarItemImage(UIImage *image, NSString *title, UIColor *tintColor, BOOL imageMode, CGFloat *contentWidth) {
    UIFont *font = [NGTheme mediumFont:10.0f];
    CGSize titleSize = [title sizeWithFont:font];
    CGSize imageSize = image ? image.size : CGSizeZero;
    CGSize size = CGSizeMake(MAX(1.0f, MAX(ceilf(titleSize.width), imageSize.width)), 45.0f);
    if (contentWidth) *contentWidth = imageSize.width;

    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0f);
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (image && imageMode) {
        CGFloat px = 1.0f / [UIScreen mainScreen].scale;
        CGFloat x = floorf((size.width - imageSize.width) / 2.0f / px) * px;
        CGRect imageRect = CGRectMake(x, 0.0f, imageSize.width, imageSize.height);
        CGContextSaveGState(context);
        CGContextTranslateCTM(context, CGRectGetMidX(imageRect), CGRectGetMidY(imageRect));
        CGContextScaleCTM(context, 1.0f, -1.0f);
        CGContextTranslateCTM(context, -CGRectGetMidX(imageRect), -CGRectGetMidY(imageRect));
        CGContextClipToMask(context, imageRect, image.CGImage);
        CGContextSetFillColorWithColor(context, tintColor.CGColor);
        CGContextFillRect(context, imageRect);
        CGContextRestoreGState(context);
    }
    if (!imageMode) {
        CGFloat px = 1.0f / [UIScreen mainScreen].scale;
        [tintColor setFill];
        [title drawAtPoint:CGPointMake(floorf((size.width - titleSize.width) / 2.0f / px) * px, size.height - titleSize.height - 1.0f) withFont:font];
    }
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

@interface NGTabBarItemView : UIView
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIImageView *textImageView;
@property (nonatomic, strong) UIImageView *animationView;
@property (nonatomic, strong) UIImageView *badgeBackground;
@property (nonatomic, strong) UILabel *badgeLabel;
@property (nonatomic, strong) NSArray *animationFrames;
@end

@implementation NGTabBarItemView
@end

@interface NGTabBarController ()
@end

@implementation NGTabBarController {
    UIView *_contentView;
    UIView *_bar;
    UIView *_separator;
    NSMutableArray *_itemViews;
    BOOL _barHidden;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    _contentView = [[UIView alloc] initWithFrame:self.view.bounds];
    _contentView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_contentView];

    // rootController.tabBar: backgroundColor 0xf7f7f7 (opaque form), separatorColor 0xb2b2b2.
    _bar = [[UIView alloc] initWithFrame:CGRectZero];
    _bar.backgroundColor = NGHex(0xf7f7f7);
    _separator = [[UIView alloc] initWithFrame:CGRectZero];
    _separator.backgroundColor = NGHex(0xb2b2b2);
    [_bar addSubview:_separator];
    [_bar addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(barTapped:)]];
    [self.view addSubview:_bar];

    [self rebuildItems];
    [self showSelectedController];
}

- (void)setViewControllers:(NSArray *)viewControllers {
    _viewControllers = [viewControllers copy];
    for (UINavigationController *nav in _viewControllers) {
        if ([nav isKindOfClass:[UINavigationController class]]) nav.delegate = self;
    }
    if (self.isViewLoaded) [self showSelectedController];
}

- (void)setItems:(NSArray *)items {
    _items = [items copy];
    if (self.isViewLoaded) [self rebuildItems];
}

- (void)rebuildItems {
    for (UIView *v in _itemViews) [v removeFromSuperview];
    _itemViews = [NSMutableArray array];
    for (NSUInteger i = 0; i < _items.count; i++) {
        NGTabBarItem *item = _items[i];
        NGTabBarItemView *view = [[NGTabBarItemView alloc] initWithFrame:CGRectZero];
        view.userInteractionEnabled = NO;
        view.imageView = [[UIImageView alloc] initWithFrame:CGRectZero];
        view.textImageView = [[UIImageView alloc] initWithFrame:CGRectZero];
        view.animationView = [[UIImageView alloc] initWithFrame:CGRectZero];
        view.animationFrames = [self framesForAnimation:item.animationName];
        // badgeBackgroundColor 0xff3b30, generateStretchableFilledCircleImage(diameter: 18)
        view.badgeBackground = [[UIImageView alloc] initWithImage:NGBadgeBackgroundImage(NGHex(0xff3b30), 18.0f)];
        view.badgeLabel = [NGTheme labelWithFont:[NGTheme regularFont:13.0f] color:[UIColor whiteColor]];
        view.badgeLabel.textAlignment = NSTextAlignmentCenter;
        [view addSubview:view.imageView];
        [view addSubview:view.animationView];
        [view addSubview:view.textImageView];
        [view addSubview:view.badgeBackground];
        [view.badgeBackground addSubview:view.badgeLabel];
        [_bar addSubview:view];
        [_itemViews addObject:view];
        [self updateItemImageAtIndex:i];
    }
    [self.view setNeedsLayout];
}

- (NSArray *)framesForAnimation:(NSString *)name {
    if (!name.length) return nil;
    NSMutableArray *frames = [NSMutableArray array];
    for (int i = 0;; i++) {
        UIImage *frame = [UIImage imageNamed:[NSString stringWithFormat:@"%@_%d", name, i]];
        if (!frame) break;
        [frames addObject:frame];
    }
    return frames.count ? frames : nil;
}

- (void)updateItemImageAtIndex:(NSUInteger)index {
    NGTabBarItem *item = _items[index];
    NGTabBarItemView *view = _itemViews[index];
    BOOL selected = index == _selectedIndex;
    // rootController.tabBar: iconColor / textColor 0x959595, selected = accent.
    UIColor *tint = selected ? [NGTheme accentColor] : NGHex(0x959595);
    UIImage *icon = [UIImage imageNamed:item.imageName];
    view.imageView.image = NGTabBarItemImage(icon, item.title, tint, YES, NULL);
    view.textImageView.image = NGTabBarItemImage(icon, item.title, tint, NO, NULL);
    view.badgeLabel.text = item.badgeValue;
    view.badgeBackground.hidden = item.badgeValue.length == 0;

    if (view.animationFrames) {
        // The animated icon replaces the static one; it rests on its first
        // frame (tinted grey) and plays once when selected.
        view.imageView.hidden = YES;
        view.animationView.hidden = NO;
        NSMutableArray *tinted = [NSMutableArray arrayWithCapacity:view.animationFrames.count];
        for (UIImage *frame in view.animationFrames) [tinted addObject:NGTintedImage(frame, tint)];
        view.animationView.image = selected ? [tinted lastObject] : tinted[0];
        view.animationView.animationImages = tinted;
    } else {
        view.imageView.hidden = NO;
        view.animationView.hidden = YES;
    }
    [view setNeedsLayout];
    [self.view setNeedsLayout];
}

- (void)setBadgeValue:(NSString *)value atIndex:(NSUInteger)index {
    if (index >= _items.count) return;
    NGTabBarItem *item = _items[index];
    if ((value.length == 0 && item.badgeValue.length == 0) || [value isEqualToString:item.badgeValue]) return;
    item.badgeValue = value;
    if (self.isViewLoaded) [self updateItemImageAtIndex:index];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width, h = self.view.bounds.size.height;
    _bar.frame = CGRectMake(_barHidden ? -w : 0, h - NGTabBarHeight, w, NGTabBarHeight);
    _separator.frame = CGRectMake(0, 0, w, [NGTheme pixel]);

    // TabBarNode.updateLayout (vertical layout, no side insets)
    NSUInteger count = _itemViews.count;
    if (count == 0) return;
    CGFloat distanceBetweenNodes = w / (CGFloat)count;
    CGFloat internalWidth = distanceBetweenNodes * (CGFloat)(count - 1);
    CGFloat leftNodeOriginX = (w - internalWidth) / 2.0f;
    CGFloat px = [NGTheme pixel];
    for (NSUInteger i = 0; i < count; i++) {
        NGTabBarItemView *node = _itemViews[i];
        CGSize nodeSize = node.textImageView.image.size;
        CGFloat originX = floorf(leftNodeOriginX + (CGFloat)i * distanceBetweenNodes - nodeSize.width / 2.0f);
        node.frame = CGRectMake(originX, 3.0f, nodeSize.width, nodeSize.height);
        node.imageView.frame = node.bounds;
        node.textImageView.frame = node.bounds;
        node.animationView.frame = CGRectMake(floorf((nodeSize.width - 51.0f) / 2.0f / px) * px, -10.0f - px, 51.0f, 51.0f);

        if (!node.badgeBackground.hidden) {
            NSString *badge = node.badgeLabel.text;
            CGSize badgeSize = [badge sizeWithFont:node.badgeLabel.font];
            badgeSize = CGSizeMake(ceilf(badgeSize.width), ceilf(badgeSize.height));
            BOOL single = badge.length == 1;
            CGSize backgroundSize = CGSizeMake(single ? 18.0f : MAX(18.0f, badgeSize.width + 10.0f + 1.0f), 18.0f);
            CGFloat contentWidth = 25.0f;
            node.badgeBackground.frame = CGRectMake(floorf(nodeSize.width / 2.0f) + contentWidth - backgroundSize.width - 5.0f, -1.0f, backgroundSize.width, backgroundSize.height);
            node.badgeLabel.frame = CGRectMake(floorf((backgroundSize.width - badgeSize.width) / 2.0f / px) * px, 1.0f, badgeSize.width, badgeSize.height);
        }
    }
    [self layoutSelectedController];
}

- (void)barTapped:(UITapGestureRecognizer *)tap {
    // TabBarNode.tapped(at:): the closest item by x.
    CGPoint location = [tap locationInView:_bar];
    NSInteger closest = -1;
    CGFloat best = CGFLOAT_MAX;
    for (NSUInteger i = 0; i < _itemViews.count; i++) {
        CGFloat distance = fabsf((float)(location.x - [_itemViews[i] center].x));
        if (distance < best) { best = distance; closest = (NSInteger)i; }
    }
    if (closest < 0) return;
    if ((NSUInteger)closest == _selectedIndex) {
        UINavigationController *nav = _viewControllers[_selectedIndex];
        if (nav.viewControllers.count > 1) [nav popToRootViewControllerAnimated:YES];
        return;
    }
    self.selectedIndex = (NSUInteger)closest;
    NGTabBarItemView *view = _itemViews[(NSUInteger)closest];
    if (view.animationFrames) {
        // playbackMode: .once
        view.animationView.animationDuration = view.animationFrames.count / 60.0;
        view.animationView.animationRepeatCount = 1;
        [view.animationView startAnimating];
    }
}

- (void)setSelectedIndex:(NSUInteger)selectedIndex {
    NSUInteger previous = _selectedIndex;
    _selectedIndex = selectedIndex;
    if (!self.isViewLoaded) return;
    if (previous < _itemViews.count) [self updateItemImageAtIndex:previous];
    if (selectedIndex < _itemViews.count) [self updateItemImageAtIndex:selectedIndex];
    [self showSelectedController];
}

- (UIViewController *)selectedController {
    return _selectedIndex < _viewControllers.count ? _viewControllers[_selectedIndex] : nil;
}

- (void)showSelectedController {
    UIViewController *selected = [self selectedController];
    for (UIViewController *vc in _viewControllers) {
        if (vc == selected || !vc.parentViewController) continue;
        [vc willMoveToParentViewController:nil];
        [vc.view removeFromSuperview];
        [vc removeFromParentViewController];
    }
    if (selected && selected.parentViewController != self) {
        [self addChildViewController:selected];
        [_contentView addSubview:selected.view];
        [selected didMoveToParentViewController:self];
    }
    if ([selected isKindOfClass:[UINavigationController class]]) {
        UIViewController *top = ((UINavigationController *)selected).topViewController;
        _barHidden = top.hidesBottomBarWhenPushed;
    }
    [self.view setNeedsLayout];
    [self layoutSelectedController];
}

- (void)layoutSelectedController {
    UIViewController *selected = [self selectedController];
    selected.view.frame = _contentView.bounds;
}

#pragma mark - Hiding with pushes

- (void)navigationController:(UINavigationController *)navigationController willShowViewController:(UIViewController *)viewController animated:(BOOL)animated {
    if (navigationController != [self selectedController]) return;
    BOOL hide = viewController.hidesBottomBarWhenPushed;
    if (hide == _barHidden) return;
    _barHidden = hide;
    CGFloat w = self.view.bounds.size.width;
    // The bar travels with the root controller, as UIKit's does on a push.
    void (^move)(void) = ^{
        CGRect f = self->_bar.frame;
        f.origin.x = hide ? -w : 0;
        self->_bar.frame = f;
    };
    if (animated) {
        [UIView animateWithDuration:0.35 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:move completion:nil];
    } else {
        move();
    }
}

@end

@implementation UIViewController (NGTabBar)

- (NGTabBarController *)ng_tabBarController {
    UIViewController *vc = self.parentViewController;
    while (vc && ![vc isKindOfClass:[NGTabBarController class]]) vc = vc.parentViewController;
    return (NGTabBarController *)vc;
}

@end
