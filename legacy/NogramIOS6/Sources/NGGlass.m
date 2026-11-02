#import "NGGlass.h"
#import "NGTheme.h"
#import "NGOriginal.h"

@implementation NGGlassView {
    UIImageView *_shadowView;
    UIImageView *_foregroundView;
    CGFloat _appliedRadius;
    UIColor *_appliedFill;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor clearColor];
        _fillColor = [UIColor colorWithWhite:1.0f alpha:0.7f];
        _shadowView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _foregroundView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _contentView = [[UIView alloc] initWithFrame:self.bounds];
        _contentView.backgroundColor = [UIColor clearColor];
        [self addSubview:_shadowView];
        [self addSubview:_foregroundView];
        [self addSubview:_contentView];
    }
    return self;
}

- (void)setFillColor:(UIColor *)fillColor {
    _fillColor = fillColor;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    CGFloat radius = floorf(MIN(size.width, size.height) * 0.5f);
    if (radius != _appliedRadius || ![_fillColor isEqual:_appliedFill]) {
        _appliedRadius = radius;
        _appliedFill = _fillColor;
        _shadowView.image = NGLegacyShadowImage(radius);
        _foregroundView.image = NGLegacyGlassImage(radius, 1.0f, _fillColor);
    }
    CGRect outer = CGRectInset(self.bounds, -NGGlassShadowInset, -NGGlassShadowInset);
    _shadowView.frame = outer;
    _foregroundView.frame = outer;
    _contentView.frame = self.bounds;
}

@end

@implementation NGGlassButton {
    NGGlassView *_glass;
    UILabel *_label;
    UIImageView *_icon;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _glass = [[NGGlassView alloc] initWithFrame:self.bounds];
        _glass.userInteractionEnabled = NO;
        [self addSubview:_glass];
    }
    return self;
}

+ (instancetype)textButton:(NSString *)title target:(id)target action:(SEL)action {
    NGGlassButton *button = [[self alloc] initWithFrame:CGRectZero];
    button->_label = [NGTheme labelWithFont:[NGTheme mediumFont:17.0f] color:[UIColor blackColor]];
    button->_label.textAlignment = NSTextAlignmentCenter;
    [button->_glass.contentView addSubview:button->_label];
    button.title = title;
    if (target) [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

+ (instancetype)iconButton:(NSString *)assetName tint:(NGGlassButtonTint)tint target:(id)target action:(SEL)action {
    NGGlassButton *button = [[self alloc] initWithFrame:CGRectZero];
    UIColor *foreground = tint == NGGlassButtonTintAccent ? [UIColor whiteColor] : [UIColor blackColor];
    if (tint == NGGlassButtonTintAccent) button->_glass.fillColor = [NGTheme accentColor];
    button->_icon = [[UIImageView alloc] initWithImage:NGTintedAsset(assetName, foreground)];
    button->_icon.contentMode = UIViewContentModeCenter;
    [button->_glass.contentView addSubview:button->_icon];
    if (target) [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)setTitle:(NSString *)title {
    _title = [title copy];
    _label.text = title;
    [self.superview setNeedsLayout];
}

- (CGSize)preferredSize {
    if (_label) {
        CGFloat textWidth = [NGTheme widthOfText:_title font:_label.font];
        return CGSizeMake(MAX(44.0f, textWidth + 12.0f * 2.0f), 44.0f);
    }
    return CGSizeMake(44.0f, 44.0f);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _glass.frame = self.bounds;
    _label.frame = self.bounds;
    _icon.frame = self.bounds;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    // The glass press: a slight grow while the finger is down.
    [UIView animateWithDuration:0.2 animations:^{
        self->_glass.transform = highlighted ? CGAffineTransformMakeScale(1.08f, 1.08f) : CGAffineTransformIdentity;
    }];
}

@end

@implementation NGHeaderView {
    CAGradientLayer *_backdrop;
    UILabel *_titleLabel;
}

+ (CGFloat)height { return 60.0f; }

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor clearColor];
        // The bar's backdrop: the background colour, fading out below the row.
        _backdrop = [CAGradientLayer layer];
        UIColor *white = [UIColor whiteColor];
        _backdrop.colors = @[ (__bridge id)[white colorWithAlphaComponent:0.9f].CGColor,
                              (__bridge id)[white colorWithAlphaComponent:0.75f].CGColor,
                              (__bridge id)[white colorWithAlphaComponent:0.0f].CGColor ];
        _backdrop.locations = @[ @0.0, @0.6, @1.0 ];
        [self.layer addSublayer:_backdrop];
        _titleLabel = [NGTheme labelWithFont:[NGTheme semiboldFont:17.0f] color:[UIColor blackColor]];
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_titleLabel];
        _showsBackdrop = YES;
    }
    return self;
}

- (void)setShowsBackdrop:(BOOL)showsBackdrop {
    _showsBackdrop = showsBackdrop;
    _backdrop.hidden = !showsBackdrop;
}

static CGSize NGPreferredSize(UIView *view) {
    if ([view respondsToSelector:@selector(preferredSize)]) return [(NGGlassButton *)view preferredSize];
    return view.bounds.size;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self ? nil : hit;   // the backdrop lets touches through
}

- (void)setLeftButtons:(NSArray *)leftButtons {
    for (UIView *v in _leftButtons) [v removeFromSuperview];
    _leftButtons = [leftButtons copy];
    for (UIView *v in _leftButtons) [self addSubview:v];
    [self setNeedsLayout];
}

- (void)setRightButtons:(NSArray *)rightButtons {
    for (UIView *v in _rightButtons) [v removeFromSuperview];
    _rightButtons = [rightButtons copy];
    for (UIView *v in _rightButtons) [self addSubview:v];
    [self setNeedsLayout];
}

- (void)setTitle:(NSString *)title {
    _title = [title copy];
    _titleLabel.text = title;
    [self setNeedsLayout];
}

- (void)setTitleView:(UIView *)titleView {
    [_titleView removeFromSuperview];
    _titleView = titleView;
    if (titleView) [self addSubview:titleView];
    _titleLabel.hidden = titleView != nil;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    const CGFloat sideInset = 16.0f, rowY = 8.0f, spacing = 12.0f;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _backdrop.frame = CGRectMake(0, 0, w, self.bounds.size.height + 16.0f);
    [CATransaction commit];

    CGFloat x = sideInset;
    for (UIView *b in _leftButtons) {
        CGSize s = NGPreferredSize(b);
        b.frame = CGRectMake(x, rowY, s.width, s.height);
        x += s.width + spacing;
    }
    CGFloat leftExtent = x - spacing;
    x = w - sideInset;
    for (UIView *b in [_rightButtons reverseObjectEnumerator]) {
        CGSize s = NGPreferredSize(b);
        x -= s.width;
        b.frame = CGRectMake(x, rowY, s.width, s.height);
        x -= spacing;
    }
    CGFloat rightExtent = w - (x + spacing);
    // navigationBarTitleAvailableWidth: symmetric, clear of the wider side + 8.
    CGFloat commonInset = MAX(MAX(leftExtent, rightExtent), sideInset) + 8.0f;
    CGRect titleFrame = CGRectMake(commonInset, rowY, MAX(0.0f, w - commonInset * 2.0f), 44.0f);
    _titleLabel.frame = titleFrame;
    if (_titleView) {
        CGSize s = _titleView.bounds.size;
        CGFloat tw = MIN(s.width, titleFrame.size.width);
        _titleView.frame = CGRectMake(floorf((w - tw) / 2.0f), rowY, tw, 44.0f);
    }
}

@end
