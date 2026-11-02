#import "NGTabBarController.h"
#import "NGTheme.h"
#import "NGOriginal.h"
#import "NGGlass.h"

// TabBarComponent / TabBarItemsLayout / TabBarControllerNode, horizontal,
// regular (not compact), no search, on a phone without a home indicator.
static const CGFloat NGTabBarInnerInset = 4.0f;    // tabBarInnerInset
static const CGFloat NGTabBarItemLength = 56.0f;   // tabBarItemLength
static const CGFloat NGTabBarBottomInset = 8.0f;   // panelsBottomInset with no bottom safe area
static const CGFloat NGTabBarSideInset = 20.0f;    // tabBarBottomInset <= 28 → 20

// The space a root list must leave under its content.
const CGFloat NGTabBarHeight = 72.0f;   // item 56 + inner insets 2 x 4 + bottom inset 8

@implementation NGTabBarItem

+ (instancetype)itemWithTitle:(NSString *)title imageName:(NSString *)imageName animationName:(NSString *)animationName {
    NGTabBarItem *item = [self new];
    item.title = title;
    item.imageName = imageName;
    item.animationName = animationName;
    return item;
}

@end

static UIFont *NGTabTitleFont(void) { return [NGTheme semiboldFont:10.0f]; }
static UIColor *NGTabTextColor(void) { return NGHexA(0x000000, 0.8f); }   // rootController.tabBar.textColor

// TabBarComponent.ItemComponent: icon at y 3 (static image) or a 48pt
// animation at y -4, title 8pt above the bottom, badge right of centre.
@interface NGTabBarItemView : UIView
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UIImageView *animationView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIView *badgeView;
@property (nonatomic, strong) UILabel *badgeLabel;
@property (nonatomic, strong) NSArray *animationFrames;
@end

@implementation NGTabBarItemView

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    CGSize iconSize = self.iconView.image.size;
    self.iconView.frame = CGRectMake(floorf((size.width - iconSize.width) * 0.5f), 3.0f, iconSize.width, iconSize.height);
    self.animationView.frame = CGRectMake(floorf((size.width - 48.0f) * 0.5f), -4.0f, 48.0f, 48.0f);
    CGSize titleSize = [self.titleLabel.text sizeWithFont:self.titleLabel.font];
    titleSize = CGSizeMake(ceilf(titleSize.width), ceilf(titleSize.height));
    self.titleLabel.frame = CGRectMake(floorf((size.width - titleSize.width) * 0.5f), size.height - 8.0f - titleSize.height, titleSize.width, titleSize.height);

    if (!self.badgeView.hidden) {
        // TextBadgeComponent(font: regular 13, insets: (0, 5, 1, 5))
        CGSize textSize = [self.badgeLabel.text sizeWithFont:self.badgeLabel.font];
        textSize = CGSizeMake(ceilf(textSize.width), ceilf(textSize.height));
        CGFloat height = textSize.height + 1.0f;
        CGFloat width = MAX(height, textSize.width + 10.0f);
        CGFloat contentWidth = 25.0f;
        self.badgeView.frame = CGRectMake(floorf(size.width / 2.0f) + contentWidth - width - 1.0f, 5.0f, width, height);
        self.badgeView.layer.cornerRadius = height * 0.5f;
        self.badgeLabel.frame = CGRectMake(floorf((width - textSize.width) * 0.5f), 0.0f, textSize.width, textSize.height);
    }
}

@end

@implementation NGTabBarController {
    UIView *_contentView;
    UIView *_bar;
    NGGlassView *_background;
    UIView *_lens;
    NSMutableArray *_itemViews;
    BOOL _barHidden;
    BOOL _layoutDone;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    _contentView = [[UIView alloc] initWithFrame:self.view.bounds];
    _contentView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_contentView];

    _bar = [[UIView alloc] initWithFrame:CGRectZero];
    _background = [[NGGlassView alloc] initWithFrame:CGRectZero];
    _background.userInteractionEnabled = NO;
    [_bar addSubview:_background];
    // LiquidLensView, legacy: a capsule tinted black at 7.5% under the selected item.
    _lens = [[UIView alloc] initWithFrame:CGRectZero];
    _lens.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.075f];
    _lens.userInteractionEnabled = NO;
    [_background.contentView addSubview:_lens];
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
        view.iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
        view.animationView = [[UIImageView alloc] initWithFrame:CGRectZero];
        view.animationFrames = [self framesForAnimation:item.animationName];
        view.titleLabel = [NGTheme labelWithFont:NGTabTitleFont() color:NGTabTextColor()];
        view.titleLabel.text = item.title;
        view.badgeView = [[UIView alloc] initWithFrame:CGRectZero];
        view.badgeView.backgroundColor = NGHex(0xff3b30);   // badgeBackgroundColor
        view.badgeLabel = [NGTheme labelWithFont:[NGTheme regularFont:13.0f] color:[UIColor whiteColor]];
        [view.badgeView addSubview:view.badgeLabel];
        for (UIView *v in @[ view.iconView, view.animationView, view.titleLabel, view.badgeView ]) [view addSubview:v];
        [_background.contentView addSubview:view];
        [_itemViews addObject:view];
        [self updateItemAtIndex:i];
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

- (void)updateItemAtIndex:(NSUInteger)index {
    NGTabBarItem *item = _items[index];
    NGTabBarItemView *view = _itemViews[index];
    BOOL selected = index == _selectedIndex;
    // selectedTextColor = accent, textColor = black 0.8; the icon follows the text colour.
    UIColor *tint = selected ? [NGTheme accentColor] : NGTabTextColor();
    view.titleLabel.textColor = tint;
    view.iconView.image = NGTintedAsset(item.imageName, tint);
    view.badgeLabel.text = item.badgeValue;
    view.badgeView.hidden = item.badgeValue.length == 0;

    if (view.animationFrames) {
        view.iconView.hidden = YES;
        view.animationView.hidden = NO;
        NSMutableArray *tinted = [NSMutableArray arrayWithCapacity:view.animationFrames.count];
        for (UIImage *frame in view.animationFrames) [tinted addObject:NGTintedImage(frame, tint)];
        view.animationView.image = selected ? [tinted lastObject] : tinted[0];
        view.animationView.animationImages = tinted;
    } else {
        view.iconView.hidden = NO;
        view.animationView.hidden = YES;
    }
    [view setNeedsLayout];
}

- (void)setBadgeValue:(NSString *)value atIndex:(NSUInteger)index {
    if (index >= _items.count) return;
    NGTabBarItem *item = _items[index];
    if ((value.length == 0 && item.badgeValue.length == 0) || [value isEqualToString:item.badgeValue]) return;
    item.badgeValue = value;
    if (self.isViewLoaded) [self updateItemAtIndex:index];
}

// tabBarItemsLayout(axis: .horizontal, isCompact: false, ...)
- (NSArray *)itemFramesForAvailableLength:(CGFloat)availableLength {
    NSUInteger count = _itemViews.count;
    CGFloat px = [NGTheme pixel];
    CGFloat availableItemsLength = availableLength - NGTabBarInnerInset * 2.0f;
    CGFloat equalLength = floorf(availableItemsLength / (CGFloat)count / px) * px;
    NSMutableArray *unbound = [NSMutableArray array];
    CGFloat total = 0.0f;
    BOOL allFit = YES;
    for (NGTabBarItemView *view in _itemViews) {
        // ItemComponent, unconstrained: title width + 10 * 2
        CGFloat width = ceilf([view.titleLabel.text sizeWithFont:NGTabTitleFont()].width) + 20.0f;
        [unbound addObject:@(width)];
        total += width;
        if (width > equalLength) allFit = NO;
    }
    NSMutableArray *frames = [NSMutableArray array];
    CGFloat position = NGTabBarInnerInset;
    for (NSUInteger i = 0; i < count; i++) {
        CGFloat length = allFit ? equalLength : floorf([unbound[i] floatValue] * (availableItemsLength / total) / px) * px;
        [frames addObject:[NSValue valueWithCGRect:CGRectMake(position, NGTabBarInnerInset, length, NGTabBarItemLength)]];
        position += length;
    }
    return frames;
}

// tabBarLensSelectionFrame, then the lens's visible capsule (inset 4).
- (CGRect)lensFrameForItemFrame:(CGRect)itemFrame barSize:(CGSize)barSize {
    if (itemFrame.size.width < itemFrame.size.height) {
        itemFrame = CGRectInset(itemFrame, floorf((itemFrame.size.height * 1.2f - itemFrame.size.width) * -0.5f), 0.0f);
    }
    CGFloat length = itemFrame.size.width + NGTabBarInnerInset * 2.0f;
    CGFloat origin = MAX(0.0f, MIN(itemFrame.origin.x - NGTabBarInnerInset, barSize.width - length));
    return CGRectInset(CGRectMake(origin, 0.0f, length, barSize.height), 4.0f, 4.0f);
}

- (CGRect)barFrame {
    CGFloat w = self.view.bounds.size.width, h = self.view.bounds.size.height;
    CGFloat barWidth = MIN(500.0f, w - NGTabBarSideInset * 2.0f);
    CGFloat barHeight = NGTabBarItemLength + NGTabBarInnerInset * 2.0f;
    CGFloat y = _barHidden ? h : h - barHeight - NGTabBarBottomInset;
    return CGRectMake(floorf((w - barWidth) * 0.5f), y, barWidth, barHeight);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    _bar.frame = [self barFrame];
    _background.frame = _bar.bounds;
    [_background layoutIfNeeded];
    NSArray *frames = [self itemFramesForAvailableLength:_bar.bounds.size.width];
    for (NSUInteger i = 0; i < _itemViews.count; i++) {
        NGTabBarItemView *view = _itemViews[i];
        view.frame = [frames[i] CGRectValue];
        [view setNeedsLayout];
    }
    [self layoutLensAnimated:NO];
    [self layoutSelectedController];
    _layoutDone = YES;
}

- (void)layoutLensAnimated:(BOOL)animated {
    if (_selectedIndex >= _itemViews.count) return;
    CGRect lens = [self lensFrameForItemFrame:[_itemViews[_selectedIndex] frame] barSize:_bar.bounds.size];
    void (^apply)(void) = ^{
        self->_lens.frame = lens;
        self->_lens.layer.cornerRadius = lens.size.height * 0.5f;
    };
    if (animated) {
        // TabBarControllerNode: a selection change animates with .spring(duration: 0.4).
        [UIView animateWithDuration:0.4 delay:0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState animations:apply completion:nil];
    } else {
        apply();
    }
}

- (void)barTapped:(UITapGestureRecognizer *)tap {
    // tabBarItemIndex(at:): the item under the point, else the nearest along x.
    CGPoint location = [tap locationInView:_background.contentView];
    NSInteger closest = -1;
    CGFloat best = CGFLOAT_MAX;
    for (NSUInteger i = 0; i < _itemViews.count; i++) {
        CGRect frame = [_itemViews[i] frame];
        if (CGRectContainsPoint(frame, location)) { closest = (NSInteger)i; break; }
        CGFloat distance = MIN(fabsf((float)(location.x - CGRectGetMinX(frame))), fabsf((float)(location.x - CGRectGetMaxX(frame))));
        if (distance < best) { best = distance; closest = (NSInteger)i; }
    }
    if (closest < 0) return;
    if ((NSUInteger)closest == _selectedIndex) {
        UINavigationController *nav = _viewControllers[_selectedIndex];
        if (nav.viewControllers.count > 1) [nav popToRootViewControllerAnimated:YES];
        return;
    }
    self.selectedIndex = (NSUInteger)closest;
    [self layoutLensAnimated:YES];
    NGTabBarItemView *view = _itemViews[(NSUInteger)closest];
    if (view.animationFrames) {
        view.animationView.animationDuration = view.animationFrames.count / 60.0;
        view.animationView.animationRepeatCount = 1;
        [view.animationView startAnimating];
    }
}

- (void)setSelectedIndex:(NSUInteger)selectedIndex {
    NSUInteger previous = _selectedIndex;
    _selectedIndex = selectedIndex;
    if (!self.isViewLoaded) return;
    if (previous < _itemViews.count) [self updateItemAtIndex:previous];
    if (selectedIndex < _itemViews.count) [self updateItemAtIndex:selectedIndex];
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
    [self.view bringSubviewToFront:_bar];
    [self.view setNeedsLayout];
    [self layoutSelectedController];
}

- (void)layoutSelectedController {
    [self selectedController].view.frame = _contentView.bounds;
}

#pragma mark - Hiding with pushes

- (void)navigationController:(UINavigationController *)navigationController willShowViewController:(UIViewController *)viewController animated:(BOOL)animated {
    if (navigationController != [self selectedController]) return;
    BOOL hide = viewController.hidesBottomBarWhenPushed;
    if (hide == _barHidden) return;
    _barHidden = hide;
    // TabBarControllerNode: a hidden bar sits below the screen's bottom edge.
    void (^move)(void) = ^{ self->_bar.frame = [self barFrame]; };
    if (animated && _layoutDone) {
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
