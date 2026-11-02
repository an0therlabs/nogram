#import "NGItemList.h"
#import "NGTheme.h"
#import "NGOriginal.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat NGCardInset = 16.0f;          // peerInfoSideInsets / item list block inset
static const CGFloat NGCardRadius = 26.0f;         // cornersImage(glass: true)
static const CGFloat NGBlockSpacing = 24.0f;       // itemListNeighborsGroupedInsets, rounded layout
static const CGFloat NGRowVerticalInset = 15.0f;   // ItemListDisclosureItem, .glass

static UIColor *NGSectionTextColor(void) { return NGHex(0x6d6d72); }   // list.sectionHeaderTextColor / freeTextColor
static UIColor *NGSecondaryColor(void) { return NGHex(0x8e8e93); }     // list.itemSecondaryTextColor
static UIColor *NGDestructiveColor(void) { return NGHex(0xff3b30); }   // list.itemDestructiveColor
static UIFont *NGRowFont(void) { return [NGTheme regularFont:17.0f]; }
static UIFont *NGSectionFont(void) { return [NGTheme regularFont:13.0f]; }
static UIFont *NGSubtitleFont(void) { return [NGTheme regularFont:15.0f]; }

UIImage *NGBlockCornersImage(BOOL top, BOOL bottom) {
    if (!top && !bottom) return nil;
    static NSMutableDictionary *cache;
    if (!cache) cache = [NSMutableDictionary new];
    NSString *key = [NSString stringWithFormat:@"%d%d", top, bottom];
    if (cache[key]) return cache[key];
    CGSize size = CGSizeMake(56.0f, 56.0f);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGRect bounds = CGRectMake(0, 0, size.width, size.height);
    CGContextSetFillColorWithColor(context, [NGTheme blocksBackgroundColor].CGColor);
    CGContextFillRect(context, bounds);
    CGContextSetBlendMode(context, kCGBlendModeClear);
    UIRectCorner corners = 0;
    if (top) corners |= UIRectCornerTopLeft | UIRectCornerTopRight;
    if (bottom) corners |= UIRectCornerBottomLeft | UIRectCornerBottomRight;
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:bounds byRoundingCorners:corners cornerRadii:CGSizeMake(NGCardRadius, NGCardRadius)];
    CGContextAddPath(context, path.CGPath);
    CGContextFillPath(context);
    UIImage *image = [UIGraphicsGetImageFromCurrentImageContext() stretchableImageWithLeftCapWidth:28 topCapHeight:28];
    UIGraphicsEndImageContext();
    cache[key] = image;
    return image;
}

#pragma mark - Item

@implementation NGItem

+ (instancetype)itemOfKind:(NGItemKind)kind title:(NSString *)title {
    NGItem *item = [self new];
    item.kind = kind;
    item.title = title;
    return item;
}

+ (instancetype)header:(NSString *)text { return [self itemOfKind:NGItemKindHeader title:[text uppercaseString]]; }
+ (instancetype)footer:(NSString *)text { return [self itemOfKind:NGItemKindFooter title:text]; }

+ (instancetype)disclosure:(NSString *)title detail:(NSString *)detail {
    NGItem *item = [self itemOfKind:NGItemKindDisclosure title:title];
    item.detail = detail;
    return item;
}

+ (instancetype)disclosure:(NSString *)title detail:(NSString *)detail icon:(NSString *)icon color:(UIColor *)color {
    NGItem *item = [self disclosure:title detail:detail];
    item.iconName = icon;
    item.iconColor = color;
    return item;
}

+ (instancetype)toggle:(NSString *)title on:(BOOL)on {
    NGItem *item = [self itemOfKind:NGItemKindSwitch title:title];
    item.on = on;
    return item;
}

+ (instancetype)check:(NSString *)title subtitle:(NSString *)subtitle group:(NSString *)group selected:(BOOL)selected {
    NGItem *item = [self itemOfKind:NGItemKindCheck title:title];
    item.detail = subtitle;
    item.group = group;
    item.on = selected;
    return item;
}

+ (instancetype)action:(NSString *)title { return [self itemOfKind:NGItemKindAction title:title]; }
+ (instancetype)destructive:(NSString *)title { return [self itemOfKind:NGItemKindDestructive title:title]; }

+ (instancetype)info:(NSString *)title subtitle:(NSString *)subtitle {
    NGItem *item = [self itemOfKind:NGItemKindInfo title:title];
    item.detail = subtitle;
    return item;
}

+ (instancetype)slider:(float)value {
    NGItem *item = [self itemOfKind:NGItemKindSlider title:nil];
    item.value = value;
    return item;
}

+ (instancetype)labeled:(NSString *)label value:(NSString *)value accent:(BOOL)accent {
    NGItem *item = [self itemOfKind:NGItemKindLabeled title:label];
    item.detail = value;
    item.accent = accent;
    return item;
}

+ (instancetype)fullWidth:(UIView *)view {
    NGItem *item = [self itemOfKind:NGItemKindFullWidth title:nil];
    item.customView = view;
    return item;
}

+ (instancetype)custom:(UIView *)view {
    NGItem *item = [self itemOfKind:NGItemKindCustom title:nil];
    item.customView = view;
    return item;
}

- (BOOL)isRow {
    return self.kind != NGItemKindHeader && self.kind != NGItemKindFooter;
}

@end

#pragma mark - Switch

// Display's SwitchNode with list.itemSwitchColors (frame 0xe9e9ea, content
// 0x35c759, handle white), drawn by hand: iOS 6's UISwitch is the old one.
@interface NGSwitch : UIControl
@property (nonatomic, getter=isOn) BOOL on;
- (void)setOn:(BOOL)on animated:(BOOL)animated;
@end

@implementation NGSwitch {
    UIView *_track;
    UIView *_fill;
    UIView *_knob;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:CGRectMake(frame.origin.x, frame.origin.y, 51, 31)])) {
        _track = [[UIView alloc] initWithFrame:self.bounds];
        _track.backgroundColor = NGHex(0xe9e9ea);
        _track.layer.cornerRadius = 15.5f;
        _track.userInteractionEnabled = NO;
        _fill = [[UIView alloc] initWithFrame:self.bounds];
        _fill.backgroundColor = NGHex(0x35c759);
        _fill.layer.cornerRadius = 15.5f;
        _fill.userInteractionEnabled = NO;
        _knob = [[UIView alloc] initWithFrame:CGRectMake(2, 2, 27, 27)];
        _knob.backgroundColor = [UIColor whiteColor];
        _knob.layer.cornerRadius = 13.5f;
        _knob.layer.shadowColor = [UIColor blackColor].CGColor;
        _knob.layer.shadowOpacity = 0.2f;
        _knob.layer.shadowOffset = CGSizeMake(0, 2);
        _knob.layer.shadowRadius = 2.5f;
        _knob.layer.shadowPath = [UIBezierPath bezierPathWithOvalInRect:_knob.bounds].CGPath;
        _knob.userInteractionEnabled = NO;
        [self addSubview:_track];
        [self addSubview:_fill];
        [self addSubview:_knob];
        [self addTarget:self action:@selector(tapped) forControlEvents:UIControlEventTouchUpInside];
        [self apply];
    }
    return self;
}

- (void)apply {
    _fill.alpha = _on ? 1.0f : 0.0f;
    _fill.transform = _on ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.4f, 0.4f);
    _knob.frame = CGRectMake(_on ? 51 - 2 - 27 : 2, 2, 27, 27);
}

- (void)setOn:(BOOL)on {
    [self setOn:on animated:NO];
}

- (void)setOn:(BOOL)on animated:(BOOL)animated {
    _on = on;
    if (animated) {
        [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{ [self apply]; } completion:nil];
    } else {
        [self apply];
    }
}

- (void)tapped {
    [self setOn:!_on animated:YES];
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}

@end

#pragma mark - Cell

@interface NGItemCell : UITableViewCell
@property (nonatomic, strong) NGItem *item;
@property (nonatomic) CGFloat topGap;
@property (nonatomic) BOOL firstInBlock, lastInBlock;
@property (nonatomic, copy) void (^changed)(NGItem *item);
+ (CGFloat)contentHeightForItem:(NGItem *)item width:(CGFloat)width;
@end

@implementation NGItemCell {
    UIView *_card;
    UIView *_highlight;
    UIImageView *_iconView;
    UILabel *_titleLabel;
    UILabel *_detailLabel;
    UILabel *_sectionLabel;
    UIImageView *_chevron;
    UIImageView *_checkView;
    NGSwitch *_switch;
    UISlider *_slider;
    UIView *_separator;
    UIImageView *_corners;
    UIView *_customView;
    UILabel *_valueLabel;
}

static CGFloat NGTextHeight(NSString *text, UIFont *font, CGFloat width) {
    return [NGTheme sizeOfText:text ?: @"" font:font width:width].height;
}

+ (CGFloat)contentHeightForItem:(NGItem *)item width:(CGFloat)width {
    CGFloat sectionWidth = width - NGCardInset * 2.0f - 15.0f * 2.0f;
    switch (item.kind) {
        case NGItemKindHeader:
            // ItemListSectionHeaderItem: title height + 13, title at y 7
            return NGTextHeight(item.title, NGSectionFont(), sectionWidth) + 13.0f;
        case NGItemKindFooter:
            // ItemListTextItem: 7 above and below
            return NGTextHeight(item.title, NGSectionFont(), sectionWidth) + 14.0f;
        case NGItemKindCheck:
        case NGItemKindInfo:
            if (item.detail.length) {
                return NGRowVerticalInset * 2.0f - 4.0f + ceilf(NGRowFont().lineHeight) + 1.0f + ceilf(NGSubtitleFont().lineHeight);
            }
            return NGRowVerticalInset * 2.0f + ceilf(NGRowFont().lineHeight);
        case NGItemKindSwitch:
            return 52.0f;   // ItemListSwitchItem: contentSize.height = 52
        case NGItemKindSlider:
            return 52.0f;
        case NGItemKindCustom:
        case NGItemKindFullWidth:
            return item.customView.bounds.size.height;
        case NGItemKindLabeled: {
            // PeerInfoScreenLabeledValueItem: 15 + label + 3 + text + 15
            CGFloat textWidth = width - NGCardInset * 2.0f - 16.0f * 2.0f;
            return 15.0f + ceilf([NGTheme regularFont:14.0f].lineHeight) + 3.0f + NGTextHeight(item.detail, NGRowFont(), textWidth) + 15.0f;
        }
        default:
            return NGRowVerticalInset * 2.0f + ceilf(NGRowFont().lineHeight);
    }
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [NGTheme blocksBackgroundColor];
        UIView *bg = [[UIView alloc] initWithFrame:CGRectZero];
        bg.backgroundColor = [NGTheme blocksBackgroundColor];
        self.backgroundView = bg;

        _card = [[UIView alloc] initWithFrame:CGRectZero];
        _card.backgroundColor = [UIColor whiteColor];
        _card.clipsToBounds = YES;
        _highlight = [[UIView alloc] initWithFrame:CGRectZero];
        _highlight.backgroundColor = NGHex(0xe5e5ea);
        _highlight.hidden = YES;
        _iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _titleLabel = [NGTheme labelWithFont:NGRowFont() color:[UIColor blackColor]];
        _detailLabel = [NGTheme labelWithFont:NGRowFont() color:NGSecondaryColor()];
        _sectionLabel = [NGTheme labelWithFont:NGSectionFont() color:NGSectionTextColor()];
        _sectionLabel.numberOfLines = 0;
        _chevron = [[UIImageView alloc] initWithImage:NGTintedAsset(@"list_disclosure", NGHex(0xbab9be))];
        _checkView = [[UIImageView alloc] initWithImage:NGCheckImage(NO, [NGTheme accentColor], 14.0f)];
        _switch = [[NGSwitch alloc] initWithFrame:CGRectZero];
        [_switch addTarget:self action:@selector(switchChanged) forControlEvents:UIControlEventValueChanged];
        _slider = [[UISlider alloc] initWithFrame:CGRectZero];
        _slider.minimumTrackTintColor = [NGTheme accentColor];
        [_slider addTarget:self action:@selector(sliderChanged) forControlEvents:UIControlEventValueChanged];
        _separator = [NGTheme separatorView];
        _corners = [[UIImageView alloc] initWithFrame:CGRectZero];

        [self.contentView addSubview:_sectionLabel];
        [self.contentView addSubview:_card];
        for (UIView *v in @[ _highlight, _iconView, _titleLabel, _detailLabel, _chevron, _checkView, _switch, _slider, _separator ]) {
            [_card addSubview:v];
        }
        [self.contentView addSubview:_corners];
    }
    return self;
}

- (void)switchChanged {
    self.item.on = _switch.on;
    if (self.changed) self.changed(self.item);
}

- (void)sliderChanged {
    self.item.value = _slider.value;
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    NGItemKind kind = self.item.kind;
    BOOL tappable = kind == NGItemKindDisclosure || kind == NGItemKindCheck || kind == NGItemKindAction || kind == NGItemKindDestructive || kind == NGItemKindLabeled;
    _highlight.hidden = !(highlighted && tappable && !self.item.disabled);
}

- (void)setItem:(NGItem *)item {
    _item = item;
    [_customView removeFromSuperview];
    _customView = nil;
    if (item.kind == NGItemKindCustom) {
        _customView = item.customView;
        [_card addSubview:_customView];
    } else if (item.kind == NGItemKindFullWidth) {
        _customView = item.customView;
        [self.contentView addSubview:_customView];
    }
    if (!_valueLabel) {
        _valueLabel = [NGTheme labelWithFont:NGRowFont() color:[UIColor blackColor]];
        _valueLabel.numberOfLines = 0;
        [_card addSubview:_valueLabel];
    }
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    NGItem *item = self.item;
    CGFloat w = self.contentView.bounds.size.width;
    CGFloat top = self.topGap;
    CGFloat h = self.contentView.bounds.size.height - top;
    BOOL isRow = item.kind != NGItemKindHeader && item.kind != NGItemKindFooter;

    _sectionLabel.hidden = isRow;
    _card.hidden = !isRow || item.kind == NGItemKindFullWidth;
    _corners.hidden = YES;
    if (item.kind == NGItemKindFullWidth) {
        _customView.frame = CGRectMake(0, top, w, h);
        return;
    }
    if (!isRow) {
        CGFloat sw = w - NGCardInset * 2.0f - 15.0f * 2.0f;
        CGFloat th = NGTextHeight(item.title, NGSectionFont(), sw);
        _sectionLabel.text = item.title;
        _sectionLabel.frame = CGRectMake(NGCardInset + 15.0f, top + 7.0f, sw, th);
        return;
    }

    CGRect cardFrame = CGRectMake(NGCardInset, top, w - NGCardInset * 2.0f, h);
    _card.frame = cardFrame;
    _highlight.frame = _card.bounds;
    CGFloat width = cardFrame.size.width;

    // ItemListDisclosureItem: 16pt side inset, the icon's 29 + 16 before the text.
    const CGFloat sideInset = 16.0f;
    BOOL hasIcon = item.iconName.length > 0;
    CGFloat leftInset = hasIcon ? sideInset + 29.0f + 16.0f : sideInset;
    _iconView.hidden = !hasIcon;
    if (hasIcon) {
        _iconView.image = NGSettingsIcon(item.iconName, @[ item.iconColor ?: NGHex(0x0a84ff) ]);
        _iconView.frame = CGRectMake(sideInset, floorf((h - 30.0f) / 2.0f), 30.0f, 30.0f);
    }

    UIColor *titleColor = [UIColor blackColor];
    if (item.kind == NGItemKindAction) titleColor = [NGTheme accentColor];
    if (item.kind == NGItemKindDestructive) titleColor = NGDestructiveColor();
    if (item.disabled) titleColor = NGSecondaryColor();
    _titleLabel.textColor = titleColor;
    _titleLabel.text = item.title;
    _titleLabel.hidden = item.kind == NGItemKindSlider || item.kind == NGItemKindCustom;
    _valueLabel.hidden = item.kind != NGItemKindLabeled;
    if (item.kind == NGItemKindLabeled) {
        UIFont *labelFont = [NGTheme regularFont:14.0f];
        _titleLabel.font = labelFont;
        _titleLabel.textColor = [UIColor blackColor];
        CGFloat textWidth = width - 32.0f;
        _titleLabel.frame = CGRectMake(16.0f, 15.0f, textWidth, ceilf(labelFont.lineHeight));
        _valueLabel.text = item.detail;
        _valueLabel.textColor = item.accent ? [NGTheme accentColor] : [UIColor blackColor];
        _valueLabel.frame = CGRectMake(16.0f, CGRectGetMaxY(_titleLabel.frame) + 3.0f, textWidth, NGTextHeight(item.detail, NGRowFont(), textWidth));
        _detailLabel.hidden = YES;
        _chevron.hidden = _checkView.hidden = _switch.hidden = _slider.hidden = YES;
        _iconView.hidden = YES;
        CGFloat px = [NGTheme pixel];
        _separator.hidden = self.lastInBlock;
        _separator.frame = CGRectMake(16.0f, h - px, width - 16.0f, px);
        _corners.image = NGBlockCornersImage(self.firstInBlock, self.lastInBlock);
        _corners.hidden = _corners.image == nil;
        _corners.frame = cardFrame;
        return;
    }
    _titleLabel.font = NGRowFont();

    _chevron.hidden = item.kind != NGItemKindDisclosure;
    _checkView.hidden = !(item.kind == NGItemKindCheck && item.on);
    _switch.hidden = item.kind != NGItemKindSwitch;
    _slider.hidden = item.kind != NGItemKindSlider;

    CGFloat rightInset = sideInset + (item.kind == NGItemKindDisclosure ? 18.0f : 0.0f);
    if (item.kind == NGItemKindSwitch) rightInset = sideInset + 51.0f + 8.0f;
    if (item.kind == NGItemKindCheck) rightInset = sideInset + 22.0f;

    CGFloat titleH = ceilf(NGRowFont().lineHeight);
    BOOL twoLine = (item.kind == NGItemKindCheck || item.kind == NGItemKindInfo) && item.detail.length;
    if (twoLine) {
        CGFloat subH = ceilf(NGSubtitleFont().lineHeight);
        CGFloat y = floorf((h - titleH - 1.0f - subH) / 2.0f);
        _titleLabel.frame = CGRectMake(leftInset, y, width - leftInset - rightInset, titleH);
        _detailLabel.font = NGSubtitleFont();
        _detailLabel.textAlignment = NSTextAlignmentLeft;
        _detailLabel.text = item.detail;
        _detailLabel.frame = CGRectMake(leftInset, y + titleH + 1.0f, width - leftInset - rightInset, subH);
        _detailLabel.hidden = NO;
    } else {
        CGFloat textWidth = MIN([NGTheme widthOfText:item.title font:NGRowFont()], width - leftInset - rightInset);
        _titleLabel.frame = CGRectMake(leftInset, floorf((h - titleH) / 2.0f), textWidth, titleH);
        BOOL hasLabel = item.kind == NGItemKindDisclosure && item.detail.length;
        _detailLabel.hidden = !hasLabel;
        if (hasLabel) {
            _detailLabel.font = NGRowFont();
            _detailLabel.textAlignment = NSTextAlignmentRight;
            _detailLabel.text = item.detail;
            CGFloat lw = MIN([NGTheme widthOfText:item.detail font:NGRowFont()], width - textWidth - leftInset - rightInset - 10.0f);
            _detailLabel.frame = CGRectMake(width - rightInset - lw, floorf((h - titleH) / 2.0f), lw, titleH);
        }
    }

    CGSize arrow = _chevron.image.size;
    _chevron.frame = CGRectMake(width - 7.0f - arrow.width, floorf((h - arrow.height) / 2.0f), arrow.width, arrow.height);
    CGSize check = _checkView.image.size;
    _checkView.frame = CGRectMake(width - sideInset - check.width, floorf((h - check.height) / 2.0f), check.width, check.height);
    _switch.on = item.on;
    _switch.frame = CGRectMake(width - sideInset - 51.0f, floorf((h - 31.0f) / 2.0f), 51.0f, 31.0f);
    _slider.value = item.value;
    _slider.frame = CGRectMake(sideInset, floorf((h - 23.0f) / 2.0f), width - sideInset * 2.0f, 23.0f);
    _customView.frame = _card.bounds;

    CGFloat px = [NGTheme pixel];
    _separator.hidden = self.lastInBlock;
    CGFloat separatorX = hasIcon ? leftInset - 1.0f : leftInset;
    _separator.frame = CGRectMake(separatorX, h - px, width - separatorX, px);

    _corners.image = NGBlockCornersImage(self.firstInBlock, self.lastInBlock);
    _corners.hidden = _corners.image == nil;
    _corners.frame = cardFrame;
}

@end

#pragma mark - Controller

@implementation NGItemListController

- (instancetype)initWithTitle:(NSString *)title items:(NSArray *)items {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        self.title = title;
        _items = [items copy];
        self.hidesBottomBarWhenPushed = YES;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.backgroundColor = [NGTheme blocksBackgroundColor];
    self.tableView.backgroundView = nil;
    self.tableView.contentInset = UIEdgeInsetsMake([NGHeaderView height], 0, 0, 0);
    self.tableView.scrollIndicatorInsets = self.tableView.contentInset;
    self.tableView.contentOffset = CGPointMake(0, -[NGHeaderView height]);
    UIView *footer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, NGBlockSpacing + 11.0f)];
    footer.backgroundColor = [NGTheme blocksBackgroundColor];
    self.tableView.tableFooterView = footer;
    self.header.showsBackdrop = NO;
    if (_headerView) {
        _headerView.frame = CGRectMake(0, 0, self.view.bounds.size.width, _headerView.bounds.size.height);
        _headerView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        self.tableView.tableHeaderView = _headerView;
        self.tableView.contentInset = UIEdgeInsetsZero;
        self.tableView.scrollIndicatorInsets = UIEdgeInsetsZero;
        self.tableView.contentOffset = CGPointZero;
        self.header.title = nil;
    }
}

- (void)reloadHeights {
    [self.tableView beginUpdates];
    [self.tableView endUpdates];
    for (UITableViewCell *cell in self.tableView.visibleCells) [cell setNeedsLayout];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (void)setItems:(NSArray *)items {
    _items = [items copy];
    if (self.isViewLoaded) [self.tableView reloadData];
}

- (NGItem *)itemAt:(NSInteger)index {
    return index >= 0 && index < (NSInteger)_items.count ? _items[index] : nil;
}

- (BOOL)isRow:(NGItem *)item {
    return item && item.kind != NGItemKindHeader && item.kind != NGItemKindFooter;
}

// itemListNeighborsGroupedInsets: 24 above the first item, 24 between a
// block's end (or its footer) and the next section, nothing inside a section.
- (CGFloat)topGapAt:(NSInteger)index {
    NGItem *item = [self itemAt:index], *previous = [self itemAt:index - 1];
    if (item.kind == NGItemKindFullWidth) return previous ? NGBlockSpacing - 14.0f : 0.0f;
    if (!previous && _headerView) return 0.0f;
    if (!previous) return item.kind == NGItemKindHeader ? NGBlockSpacing - 7.0f : NGBlockSpacing;
    if (previous.kind == NGItemKindHeader) return 0.0f;
    if ([self isRow:previous] && [self isRow:item]) return 0.0f;
    if ([self isRow:previous] && item.kind == NGItemKindFooter) return 0.0f;
    return item.kind == NGItemKindHeader ? NGBlockSpacing - 7.0f : NGBlockSpacing;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _items.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return [self topGapAt:indexPath.row] + [NGItemCell contentHeightForItem:_items[indexPath.row] width:tableView.bounds.size.width];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NGItemCell *cell = [tableView dequeueReusableCellWithIdentifier:@"item"];
    if (!cell) cell = [[NGItemCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"item"];
    NGItem *item = _items[indexPath.row];
    cell.item = item;
    cell.topGap = [self topGapAt:indexPath.row];
    cell.firstInBlock = ![self isRow:[self itemAt:indexPath.row - 1]];
    cell.lastInBlock = ![self isRow:[self itemAt:indexPath.row + 1]];
    cell.changed = item.action;
    [cell setNeedsLayout];
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    cell.backgroundColor = [NGTheme blocksBackgroundColor];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NGItem *item = _items[indexPath.row];
    if (item.disabled) return;
    switch (item.kind) {
        case NGItemKindCheck:
            for (NGItem *other in _items) {
                if (other.kind == NGItemKindCheck && [other.group isEqualToString:item.group]) other.on = other == item;
            }
            if (item.action) item.action(item);
            [tableView reloadData];
            break;
        case NGItemKindDisclosure:
        case NGItemKindLabeled:
        case NGItemKindAction:
        case NGItemKindDestructive:
            if (item.destination) {
                UIViewController *next = item.destination();
                if (next) [self.navigationController pushViewController:next animated:YES];
            } else if (item.action) {
                item.action(item);
            }
            break;
        default:
            break;
    }
}

@end
