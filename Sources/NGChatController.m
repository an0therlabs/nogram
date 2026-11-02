#import "NGChatController.h"
#import "NGTheme.h"
#import "NGViews.h"
#import "NGOriginal.h"
#import "NGWallpaper.h"
#import "NGCurves.h"
#import "NGGlass.h"
#import <QuartzCore/QuartzCore.h>

#pragma mark - Layout constants

// ChatMessageItemLayoutConstants.compact and the day-classic message colours
// (DefaultDayPresentationTheme.swift, `message`).
static const CGFloat NGBubbleEdgeInset = 3.0f;          // bubble.edgeInset
static const CGFloat NGBubbleTailInset = 6.0f;          // bubble.contentInsets.left
static const CGFloat NGCompactInset = 36.0f;            // maximumWidthFill.compactInset
static const CGFloat NGAvatarInset = 38.0f;             // avatarInset: 34 + 4
static const CGFloat NGTextInsetLeft = 11.0f;           // text.bubbleInsets
static const CGFloat NGTextInsetRight = 11.0f;
static const CGFloat NGStatusHeight = 14.0f;
static const CGFloat NGBubbleMainRadius = 16.0f;        // PresentationChatBubbleSettings.default
static const CGFloat NGBubbleAuxiliaryRadius = 8.0f;

static CGFloat NGPx(void) { return [NGTheme pixel]; }
static CGFloat NGTextInsetTop(void) { return 6.0f + NGPx(); }
static CGFloat NGTextInsetBottom(void) { return 6.0f - NGPx(); }
static CGFloat NGDefaultSpacing(void) { return 2.0f + NGPx(); }   // bubble.defaultSpacing; mergedSpacing is 0

static UIFont *NGMessageFont(void) { return [NGTheme regularFont:17.0f]; }
// ChatMessageDateAndStatusNode: Font.regular(floor(baseDisplaySize * 11 / 17))
static UIFont *NGDateFont(void) { return [NGTheme regularFont:11.0f]; }
static UIFont *NGNameFont(void) { return [NGTheme mediumFont:14.0f]; }

static UIColor *NGOutgoingFill(void) { return NGHex(0xe1ffc7); }
static UIColor *NGIncomingFill(void) { return [UIColor whiteColor]; }
static UIColor *NGOutgoingSecondary(void) { return NGHexA(0x008c09, 0.8f); }
static UIColor *NGIncomingSecondary(void) { return NGHexA(0x525252, 0.6f); }
static UIColor *NGOutgoingCheck(void) { return NGHex(0x19c700); }

#pragma mark - Images

static UIImage *NGBubble(BOOL incoming, NGBubbleNeighbors neighbors) {
    static NSMutableDictionary *cache;
    if (!cache) cache = [NSMutableDictionary new];
    NSString *key = [NSString stringWithFormat:@"%d-%ld", incoming, (long)neighbors];
    UIImage *image = cache[key];
    if (!image) {
        image = NGMessageBubbleImage(NGBubbleMainRadius, NGBubbleAuxiliaryRadius, incoming, incoming ? NGIncomingFill() : NGOutgoingFill(), neighbors);
        cache[key] = image;
    }
    return image;
}

static UIImage *NGCachedImage(NSString *key, UIImage *(^make)(void)) {
    static NSMutableDictionary *cache;
    if (!cache) cache = [NSMutableDictionary new];
    UIImage *image = cache[key];
    if (!image) {
        image = make();
        if (image) cache[key] = image;
    }
    return image;
}

#pragma mark - Message layout

typedef struct {
    CGSize contentSize;     // the bubble's background frame size
    CGRect textFrame;       // in background coordinates
    CGRect statusFrame;
    CGFloat nameHeight;
} NGBubbleLayout;

// The width of the last line the label draws, so the date can share it
// (TextNode's trailingLineWidth).
static CGFloat NGLastLineWidth(NSString *text, UIFont *font, CGFloat maxWidth) {
    NSString *paragraph = [[text componentsSeparatedByString:@"\n"] lastObject];
    NSString *line = @"";
    for (NSString *word in [paragraph componentsSeparatedByString:@" "]) {
        NSString *candidate = line.length ? [line stringByAppendingFormat:@" %@", word] : word;
        if (line.length == 0 || [candidate sizeWithFont:font].width <= maxWidth) {
            line = candidate;
        } else {
            line = word;
        }
    }
    CGFloat width = [line sizeWithFont:font].width;
    while (width > maxWidth) width -= maxWidth;
    return ceilf(width);
}

static CGFloat NGStatusWidth(NGMessage *m, BOOL checks) {
    return 5.0f + [NGTheme widthOfText:[NGTheme timeString:m.date] font:NGDateFont()] + (checks ? 13.0f : 0.0f);
}

static NGBubbleLayout NGLayoutMessage(NGMessage *m, CGFloat maximumWidth, BOOL incoming, BOOL showName, BOOL checks) {
    NGBubbleLayout l;
    CGFloat tail = incoming ? NGBubbleTailInset : 0.0f;
    CGFloat maxTextWidth = maximumWidth - NGBubbleTailInset - NGTextInsetLeft - NGTextInsetRight;
    UIFont *font = NGMessageFont();
    CGSize textSize = [NGTheme sizeOfText:m.text font:font width:maxTextWidth];
    textSize.height = MAX(textSize.height, ceilf(font.lineHeight));

    CGFloat statusWidth = NGStatusWidth(m, checks);
    CGFloat lastLine = NGLastLineWidth(m.text, font, maxTextWidth);
    BOOL inlineStatus = lastLine + statusWidth <= maxTextWidth;
    CGFloat contentWidth = MAX(textSize.width, inlineStatus ? lastLine + statusWidth : statusWidth);

    l.nameHeight = showName ? 20.0f : 0.0f;
    if (showName) {
        contentWidth = MAX(contentWidth, MIN(maxTextWidth, [NGTheme widthOfText:[m.author displayName] font:NGNameFont()]));
    }
    CGFloat textTop = NGTextInsetTop() + l.nameHeight;
    CGFloat textBottom = textTop + textSize.height + (inlineStatus ? 0.0f : NGStatusHeight);
    l.textFrame = CGRectMake(tail + NGTextInsetLeft, textTop, textSize.width, textSize.height);
    l.statusFrame = CGRectMake(tail + NGTextInsetLeft + contentWidth - statusWidth, textBottom - NGStatusHeight, statusWidth, NGStatusHeight);
    // bubble.minimumSize 40 x 35
    l.contentSize = CGSizeMake(MAX(40.0f, NGBubbleTailInset + NGTextInsetLeft + contentWidth + NGTextInsetRight),
                               MAX(35.0f, textBottom + NGTextInsetBottom()));
    return l;
}

static CGFloat NGMaximumWidth(CGFloat width, BOOL avatarSpace) {
    // maximumWidthFill.widthFor(width) under compactWidthBoundary: width - compactInset
    return MAX(1.0f, width - NGCompactInset - (avatarSpace ? NGAvatarInset : 0.0f));
}

#pragma mark - Message cell

@interface NGMessageCell : UITableViewCell
@property (nonatomic, strong) NGMessage *message;
@property (nonatomic) BOOL mergedTop, mergedBottom, showName, showAvatar, avatarSpace, showChecks;
@property (nonatomic, readonly) UIView *bubbleContainer;
+ (CGFloat)heightForMessage:(NGMessage *)m width:(CGFloat)width mergedTop:(BOOL)mt mergedBottom:(BOOL)mb showName:(BOOL)name avatarSpace:(BOOL)avatarSpace checks:(BOOL)checks;
- (void)refresh;
@end

@implementation NGMessageCell {
    UIImageView *_bubble;
    UILabel *_text;
    UILabel *_name;
    UILabel *_date;
    UIImageView *_checkSent;
    UIImageView *_checkRead;
    UIImageView *_clockFrame;
    UIImageView *_clockMin;
    NGAvatarView *_avatar;
}

+ (CGFloat)heightForMessage:(NGMessage *)m width:(CGFloat)width mergedTop:(BOOL)mt mergedBottom:(BOOL)mb showName:(BOOL)name avatarSpace:(BOOL)avatarSpace checks:(BOOL)checks {
    NGBubbleLayout l = NGLayoutMessage(m, NGMaximumWidth(width, avatarSpace), !m.outgoing, name, checks);
    return (mt ? 0.0f : NGDefaultSpacing()) + l.contentSize.height;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor clearColor];
        _bubbleContainer = [[UIView alloc] initWithFrame:CGRectZero];
        _bubble = [[UIImageView alloc] initWithFrame:CGRectZero];
        _text = [NGTheme labelWithFont:NGMessageFont() color:[UIColor blackColor]];
        _text.numberOfLines = 0;
        _text.lineBreakMode = NSLineBreakByWordWrapping;
        _name = [NGTheme labelWithFont:NGNameFont() color:[UIColor blackColor]];
        _date = [NGTheme labelWithFont:NGDateFont() color:[UIColor grayColor]];
        _checkSent = [[UIImageView alloc] initWithFrame:CGRectZero];
        _checkRead = [[UIImageView alloc] initWithFrame:CGRectZero];
        _clockFrame = [[UIImageView alloc] initWithFrame:CGRectZero];
        _clockMin = [[UIImageView alloc] initWithFrame:CGRectZero];
        _avatar = [[NGAvatarView alloc] initWithFrame:CGRectMake(0, 0, 34, 34)];
        [self.contentView addSubview:_avatar];
        [self.contentView addSubview:_bubbleContainer];
        for (UIView *v in @[ _bubble, _name, _text, _date, _checkSent, _checkRead, _clockFrame, _clockMin ]) {
            [_bubbleContainer addSubview:v];
        }
    }
    return self;
}

- (NGBubbleNeighbors)neighbors {
    // messageBubbleArguments: .none / .top(side: false) / .bottom / .both
    if (self.mergedTop && self.mergedBottom) return NGBubbleNeighborsBoth;
    if (self.mergedBottom) return NGBubbleNeighborsTop;
    if (self.mergedTop) return NGBubbleNeighborsBottom;
    return NGBubbleNeighborsNone;
}

- (void)refresh {
    NGMessage *m = self.message;
    BOOL incoming = !m.outgoing;
    _bubble.image = NGBubble(incoming, [self neighbors]);

    _text.text = m.text;
    _name.hidden = !self.showName;
    _name.text = [m.author displayName];
    _name.textColor = [NGTheme nameColorAtIndex:m.author.colorIndex];
    _date.text = [NGTheme timeString:m.date];
    _date.textColor = incoming ? NGIncomingSecondary() : NGOutgoingSecondary();

    BOOL checks = self.showChecks;
    BOOL sending = checks && m.status == NGMessageStatusSending;
    _clockFrame.hidden = _clockMin.hidden = !sending;
    _checkSent.hidden = !checks || sending;
    _checkRead.hidden = !checks || m.status != NGMessageStatusRead;
    UIColor *checkColor = NGOutgoingCheck();
    _checkSent.image = NGCachedImage(@"check-full", ^{ return NGCheckImage(NO, checkColor, 11.0f); });
    _checkRead.image = NGCachedImage(@"check-partial", ^{ return NGCheckImage(YES, checkColor, 11.0f); });
    UIColor *pending = NGOutgoingSecondary();
    _clockFrame.image = NGCachedImage(@"clock-frame", ^{ return NGClockFrameImage(pending); });
    _clockMin.image = NGCachedImage(@"clock-min", ^{ return NGClockMinImage(pending); });
    [self updateClockAnimation];

    _avatar.hidden = !self.showAvatar;
    if (self.showAvatar) [_avatar configureWithUser:m.author];
    _avatar.showsOnline = NO;
    [self setNeedsLayout];
}

// The pending clock's hands turn: the minute hand once a second, the frame's
// hand once in six (ChatMessageDateAndStatusNode's clock animations).
- (void)updateClockAnimation {
    if (_clockMin.hidden) {
        [_clockMin.layer removeAllAnimations];
        [_clockFrame.layer removeAllAnimations];
        return;
    }
    if ([_clockMin.layer animationForKey:@"clock"]) return;
    CABasicAnimation *minute = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    minute.fromValue = @0;
    minute.toValue = @(M_PI * 2.0);
    minute.duration = 1.0;
    minute.repeatCount = HUGE_VALF;
    [_clockMin.layer addAnimation:minute forKey:@"clock"];
    CABasicAnimation *hour = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    hour.fromValue = @0;
    hour.toValue = @(M_PI * 2.0);
    hour.duration = 6.0;
    hour.repeatCount = HUGE_VALF;
    [_clockFrame.layer addAnimation:hour forKey:@"clock"];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width, h = self.contentView.bounds.size.height;
    NGMessage *m = self.message;
    BOOL incoming = !m.outgoing;
    NGBubbleLayout l = NGLayoutMessage(m, NGMaximumWidth(w, self.avatarSpace), incoming, self.showName, self.showChecks);

    CGFloat top = self.mergedTop ? 0.0f : NGDefaultSpacing();
    CGFloat x = incoming ? NGBubbleEdgeInset + (self.avatarSpace ? NGAvatarInset : 0.0f) : w - NGBubbleEdgeInset - l.contentSize.width;
    _bubbleContainer.transform = CGAffineTransformIdentity;
    _bubbleContainer.frame = CGRectMake(x, top, l.contentSize.width, l.contentSize.height);
    // ChatMessageBackground: the image overhangs the background frame by 1pt.
    _bubble.frame = CGRectInset(_bubbleContainer.bounds, -1.0f, -1.0f);

    _name.frame = CGRectMake(l.textFrame.origin.x, NGTextInsetTop(), l.contentSize.width - l.textFrame.origin.x - NGTextInsetRight, 18.0f);
    _text.frame = l.textFrame;

    CGRect s = l.statusFrame;
    CGFloat dateWidth = [NGTheme widthOfText:_date.text font:_date.font];
    _date.frame = CGRectMake(s.origin.x + 5.0f, s.origin.y, dateWidth, NGStatusHeight);
    CGFloat statusLeft = s.origin.x + 5.0f;
    CGFloat checkOffset = 6.0f;   // floor(baseDisplaySize * 6 / 17)
    CGSize checkSize = _checkSent.image.size;
    CGFloat checkX = statusLeft + dateWidth + 5.0f + 13.0f - checkSize.width;
    _checkRead.frame = CGRectMake(checkX, s.origin.y + 3.0f, checkSize.width, checkSize.height);
    _checkSent.frame = CGRectMake(checkX - checkOffset, s.origin.y + 3.0f, checkSize.width, checkSize.height);
    CGPoint clock = CGPointMake(statusLeft + dateWidth + 8.5f, s.origin.y + 7.5f);
    _clockFrame.bounds = CGRectMake(0, 0, 11, 11);
    _clockFrame.center = clock;
    _clockMin.bounds = CGRectMake(0, 0, 11, 11);
    _clockMin.center = clock;

    _avatar.frame = CGRectMake(NGBubbleEdgeInset + 1.0f, h - 34.0f, 34.0f, 34.0f);
}

@end

#pragma mark - Date header

@interface NGDateCell : UITableViewCell
@property (nonatomic, readonly) UILabel *label;
@end

@implementation NGDateCell {
    UIView *_pill;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor clearColor];
        _pill = [[UIView alloc] initWithFrame:CGRectZero];
        _pill.backgroundColor = NGHexA(0x000000, 0.2f);   // defaultServiceBackgroundColor
        _pill.layer.cornerRadius = 10.0f;
        _label = [NGTheme labelWithFont:[NGTheme mediumFont:13.0f] color:[UIColor whiteColor]];
        _label.textAlignment = NSTextAlignmentCenter;
        [self.contentView addSubview:_pill];
        [self.contentView addSubview:_label];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    CGFloat tw = [NGTheme widthOfText:_label.text font:_label.font] + 16.0f;
    _pill.frame = CGRectMake(floorf((w - tw) / 2.0f), 7.0f, tw, 20.0f);
    _label.frame = _pill.frame;
}

@end

#pragma mark - Controller

@interface NGChatController () <UITableViewDataSource, UITableViewDelegate, UITextViewDelegate>
@end

@implementation NGChatController {
    NGChat *_chat;
    NSMutableArray *_rows;
    NGWallpaperView *_wallpaper;
    UITableView *_table;
    NGHeaderView *_header;
    UIView *_panel;
    NGGlassView *_attachGlass;
    NGGlassView *_field;
    UITextView *_textView;
    UILabel *_placeholder;
    UIButton *_attach;
    UIButton *_send;
    UIImageView *_stickers;
    UIButton *_channelButton;
    UILabel *_titleLabel;
    UILabel *_subtitleLabel;
    CGFloat _keyboardOverlap;
    NGMessage *_animatingMessage;
    CGRect _sourceFieldFrame;
}

- (instancetype)initWithChat:(NGChat *)chat {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _chat = chat;
        self.hidesBottomBarWhenPushed = YES;
    }
    return self;
}

- (BOOL)isChannel { return _chat.kind == NGChatKindChannel; }

- (void)viewDidLoad {
    [super viewDidLoad];
    [NGTheme disableExtendedLayoutFor:self];
    self.view.backgroundColor = [UIColor whiteColor];

    _wallpaper = [[NGWallpaperView alloc] initWithFrame:self.view.bounds];
    _wallpaper.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_wallpaper];

    _table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    _table.backgroundColor = [UIColor clearColor];
    _table.backgroundView = nil;
    _table.separatorStyle = UITableViewCellSeparatorStyleNone;
    _table.dataSource = self;
    _table.delegate = self;
    _table.contentInset = UIEdgeInsetsMake([NGHeaderView height] + 4, 0, 6, 0);
    _table.scrollIndicatorInsets = UIEdgeInsetsMake([NGHeaderView height], 0, 0, 0);
    if ([_table respondsToSelector:@selector(setKeyboardDismissMode:)]) {
        _table.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    }
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    tap.cancelsTouchesInView = NO;
    [_table addGestureRecognizer:tap];
    [self.view addSubview:_table];

    [self buildPanel];
    [self buildNavigationItem];
    [self buildRows];
}

// The chat's bar in the new design: a glass back circle, the title in a glass
// capsule, the avatar on the right; no backdrop over the wallpaper.
- (void)buildNavigationItem {
    _header = [[NGHeaderView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, [NGHeaderView height])];
    _header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _header.showsBackdrop = NO;
    _header.leftButtons = @[ [NGGlassButton iconButton:@"nav_back" tint:NGGlassButtonTintGeneric target:self action:@selector(back)] ];

    NGGlassView *titlePill = [[NGGlassView alloc] initWithFrame:CGRectMake(0, 0, 180, 44)];
    _titleLabel = [NGTheme labelWithFont:[NGTheme semiboldFont:16.0f] color:[UIColor blackColor]];
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    _titleLabel.text = _chat.title;
    _subtitleLabel = [NGTheme labelWithFont:[NGTheme regularFont:12.0f] color:[NGTheme secondaryTextColor]];
    _subtitleLabel.textAlignment = NSTextAlignmentCenter;
    [titlePill.contentView addSubview:_titleLabel];
    [titlePill.contentView addSubview:_subtitleLabel];
    CGFloat titleWidth = [NGTheme widthOfText:_chat.title font:_titleLabel.font];
    CGFloat pillWidth = MIN(200.0f, MAX(110.0f, titleWidth + 32.0f));
    titlePill.bounds = CGRectMake(0, 0, pillWidth, 44);
    _titleLabel.autoresizingMask = _subtitleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    if (_chat.kind == NGChatKindSaved) {
        _titleLabel.frame = CGRectMake(12, 11, pillWidth - 24, 22);
        _subtitleLabel.hidden = YES;
    } else {
        _titleLabel.frame = CGRectMake(12, 5, pillWidth - 24, 20);
        _subtitleLabel.frame = CGRectMake(12, 24, pillWidth - 24, 15);
    }
    _header.titleView = titlePill;

    NGAvatarView *avatar = [[NGAvatarView alloc] initWithFrame:CGRectMake(0, 0, 44, 44)];
    [avatar configureWithChat:_chat];
    avatar.showsOnline = NO;
    _header.rightButtons = @[ avatar ];
    [self.view addSubview:_header];
    [self updateSubtitle];
}

- (void)updateSubtitle {
    _subtitleLabel.text = [_chat statusText];
    BOOL accent = _chat.typing || (_chat.kind == NGChatKindPrivate && _chat.user.online);
    _subtitleLabel.textColor = accent ? [NGTheme accentColor] : [NGTheme secondaryTextColor];
}

// ChatTextInputPanelNode, new design: no panel background; a 40pt glass
// circle for attachments at x 8, then (6pt on) the field's glass capsule to
// 8pt from the right, with the send/record button inside its right end.
- (void)buildPanel {
    UIColor *control = NGHex(0x858e99);   // inputPanel.panelControlColor
    _panel = [[UIView alloc] initWithFrame:CGRectZero];
    _panel.backgroundColor = [UIColor clearColor];
    [self.view addSubview:_panel];

    if ([self isChannel]) {
        NGGlassView *glass = [[NGGlassView alloc] initWithFrame:CGRectZero];
        glass.tag = 1;
        [_panel addSubview:glass];
        _channelButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _channelButton.titleLabel.font = [NGTheme mediumFont:17];
        [_channelButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
        [_channelButton setTitleColor:[UIColor colorWithWhite:0 alpha:0.4f] forState:UIControlStateHighlighted];
        [_channelButton addTarget:self action:@selector(toggleMute) forControlEvents:UIControlEventTouchUpInside];
        [glass.contentView addSubview:_channelButton];
        [self updateChannelButton];
        return;
    }

    _attachGlass = [[NGGlassView alloc] initWithFrame:CGRectZero];
    [_panel addSubview:_attachGlass];
    _attach = [UIButton buttonWithType:UIButtonTypeCustom];
    [_attach setImage:NGTintedAsset(@"input_attach", control) forState:UIControlStateNormal];
    [_attachGlass.contentView addSubview:_attach];

    _field = [[NGGlassView alloc] initWithFrame:CGRectZero];
    [_panel addSubview:_field];

    _textView = [[UITextView alloc] initWithFrame:CGRectZero];
    _textView.font = [NGTheme regularFont:17.0f];
    _textView.backgroundColor = [UIColor clearColor];
    _textView.delegate = self;
    _textView.scrollEnabled = NO;
    _textView.scrollsToTop = NO;
    [_field.contentView addSubview:_textView];

    _placeholder = [NGTheme labelWithFont:[NGTheme regularFont:17.0f] color:NGHex(0x8e8e93)];
    _placeholder.text = @"Сообщение";
    [_field.contentView addSubview:_placeholder];

    _stickers = [[UIImageView alloc] initWithImage:NGTintedAsset(@"input_stickers", control)];
    [_field.contentView addSubview:_stickers];

    _send = [UIButton buttonWithType:UIButtonTypeCustom];
    [_send addTarget:self action:@selector(sendTapped) forControlEvents:UIControlEventTouchUpInside];
    [_field.contentView addSubview:_send];
    [self updateSendButton];
}

- (void)updateChannelButton {
    [_channelButton setTitle:(_chat.muted ? @"Включить звук" : @"Выключить звук") forState:UIControlStateNormal];
}

- (void)toggleMute {
    _chat.muted = !_chat.muted;
    [self updateChannelButton];
}

- (void)updateSendButton {
    BOOL hasText = [_textView.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length > 0;
    UIImage *image;
    if (hasText) {
        // The send button: SendIcon on an accent circle.
        image = NGCachedImage(@"send-button", ^{
            UIImage *icon = [UIImage imageNamed:@"input_send"];
            CGFloat d = 34.0f;
            UIGraphicsBeginImageContextWithOptions(CGSizeMake(d, d), NO, 0);
            [[NGTheme accentColor] setFill];
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, d, d)] fill];
            [icon drawInRect:CGRectMake(floorf((d - icon.size.width) / 2.0f), floorf((d - icon.size.height) / 2.0f), icon.size.width, icon.size.height)];
            UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
            return result;
        });
    } else {
        image = NGTintedAsset(@"input_mic", NGHex(0x858e99));
    }
    [_send setImage:image forState:UIControlStateNormal];
    _placeholder.hidden = _textView.text.length > 0;
    _stickers.hidden = hasText;
}

- (CGFloat)fieldHeight {
    if (!_textView) return 40.0f;
    CGFloat height;
    if ([_textView respondsToSelector:@selector(textContainer)]) {
        height = [_textView sizeThatFits:CGSizeMake(_textView.bounds.size.width, CGFLOAT_MAX)].height;
    } else {
        height = _textView.contentSize.height;
    }
    return MIN(MAX(ceilf(height) + 2.0f, 40.0f), 110.0f);
}

- (void)layoutViews {
    CGFloat w = self.view.bounds.size.width, h = self.view.bounds.size.height;
    const CGFloat bottomInset = 8.0f;
    CGFloat fieldH = [self fieldHeight];
    CGFloat panelH = ([self isChannel] ? 44.0f : fieldH) + bottomInset + 8.0f;
    _panel.frame = CGRectMake(0, h - _keyboardOverlap - panelH, w, panelH);
    _table.frame = CGRectMake(0, 0, w, _panel.frame.origin.y + 8.0f);
    _header.frame = CGRectMake(0, 0, w, [NGHeaderView height]);
    [self.view bringSubviewToFront:_header];

    if ([self isChannel]) {
        UIView *glass = [_panel viewWithTag:1];
        CGFloat bw = MIN(w - 32.0f, [NGTheme widthOfText:_channelButton.currentTitle font:_channelButton.titleLabel.font] + 48.0f);
        glass.frame = CGRectMake(floorf((w - bw) / 2.0f), 8.0f, bw, 44.0f);
        _channelButton.frame = glass.bounds;
        return;
    }
    _attachGlass.frame = CGRectMake(8.0f, 8.0f + fieldH - 40.0f, 40.0f, 40.0f);
    _attach.frame = _attachGlass.bounds;
    CGFloat fieldX = 8.0f + 40.0f + 6.0f;
    _field.frame = CGRectMake(fieldX, 8.0f, w - fieldX - 8.0f, fieldH);
    CGFloat fw = _field.bounds.size.width;
    _send.frame = CGRectMake(fw - 40.0f, fieldH - 40.0f, 40.0f, 40.0f);
    _stickers.frame = CGRectMake(fw - 40.0f - 26.0f, fieldH - 32.0f, 24.0f, 24.0f);
    BOOL hasText = _textView.text.length > 0;
    _textView.frame = CGRectMake(6.0f, -1.0f, fw - 6.0f - (hasText ? 40.0f : 66.0f), fieldH + 2.0f);
    _textView.scrollEnabled = fieldH >= 110.0f;
    _placeholder.frame = CGRectMake(14.0f, floorf((40.0f - 21.0f) / 2.0f), 200.0f, 21.0f);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillChange:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [self.navigationController setNavigationBarHidden:YES animated:animated];
    [self layoutViews];
    [_table reloadData];
    [self scrollToBottomAnimated:NO];
    _chat.unreadCount = 0;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillChangeFrameNotification object:nil];
    [self.view endEditing:YES];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutViews];
}

- (void)back {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

- (void)keyboardWillChange:(NSNotification *)note {
    NSDictionary *info = note.userInfo;
    CGRect end = [self.view convertRect:[info[UIKeyboardFrameEndUserInfoKey] CGRectValue] fromView:nil];
    _keyboardOverlap = MAX(0, self.view.bounds.size.height - end.origin.y);
    NSTimeInterval duration = [info[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationOptions curve = (UIViewAnimationOptions)([info[UIKeyboardAnimationCurveUserInfoKey] integerValue] << 16);
    [UIView animateWithDuration:duration delay:0 options:curve | UIViewAnimationOptionBeginFromCurrentState animations:^{
        [self layoutViews];
        [self scrollToBottomAnimated:NO];
    } completion:nil];
}

#pragma mark - Rows

- (void)buildRows {
    _rows = [NSMutableArray array];
    NSDate *day = nil;
    for (NGMessage *m in _chat.messages) {
        if (!day || ![NGTheme date:day isSameDayAs:m.date]) {
            day = m.date;
            [_rows addObject:m.date];
        }
        [_rows addObject:m];
    }
}

- (void)scrollToBottomAnimated:(BOOL)animated {
    if (_rows.count == 0) return;
    [_table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:_rows.count - 1 inSection:0] atScrollPosition:UITableViewScrollPositionBottom animated:animated];
}

- (NGMessage *)messageAt:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_rows.count) return nil;
    id row = _rows[index];
    return [row isKindOfClass:[NGMessage class]] ? row : nil;
}

static BOOL NGGroups(NGMessage *a, NGMessage *b) {
    return a && b && a.outgoing == b.outgoing && a.author == b.author && fabs([a.date timeIntervalSinceDate:b.date]) < 600;
}

- (BOOL)isGroupIncoming:(NGMessage *)m {
    return _chat.kind == NGChatKindGroup && !m.outgoing;
}

- (BOOL)showsChecksFor:(NGMessage *)m {
    return m.outgoing && _chat.kind != NGChatKindSaved && _chat.kind != NGChatKindChannel;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _rows.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    NGMessage *m = [self messageAt:indexPath.row];
    if (!m) return 34.0f;   // timestampHeaderHeight
    BOOL mt = NGGroups(m, [self messageAt:indexPath.row - 1]);
    BOOL mb = NGGroups(m, [self messageAt:indexPath.row + 1]);
    BOOL group = [self isGroupIncoming:m];
    return [NGMessageCell heightForMessage:m width:tableView.bounds.size.width mergedTop:mt mergedBottom:mb showName:(group && !mt) avatarSpace:group checks:[self showsChecksFor:m]];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NGMessage *m = [self messageAt:indexPath.row];
    if (!m) {
        NGDateCell *cell = [tableView dequeueReusableCellWithIdentifier:@"date"];
        if (!cell) cell = [[NGDateCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"date"];
        cell.label.text = [NGTheme dayHeaderString:_rows[indexPath.row]];
        [cell setNeedsLayout];
        return cell;
    }
    NGMessageCell *cell = [tableView dequeueReusableCellWithIdentifier:@"msg"];
    if (!cell) cell = [[NGMessageCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"msg"];
    BOOL group = [self isGroupIncoming:m];
    cell.message = m;
    cell.mergedTop = NGGroups(m, [self messageAt:indexPath.row - 1]);
    cell.mergedBottom = NGGroups(m, [self messageAt:indexPath.row + 1]);
    cell.avatarSpace = group;
    cell.showName = group && !cell.mergedTop;
    cell.showAvatar = group && !cell.mergedBottom;
    cell.showChecks = [self showsChecksFor:m];
    [cell refresh];
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    cell.backgroundColor = [UIColor clearColor];
    if (_animatingMessage && [cell isKindOfClass:[NGMessageCell class]] && ((NGMessageCell *)cell).message == _animatingMessage) {
        _animatingMessage = nil;
        [cell layoutIfNeeded];
        [self animateSentBubbleInCell:(NGMessageCell *)cell];
    }
}

#pragma mark - Input

- (void)textViewDidChange:(UITextView *)textView {
    [self updateSendButton];
    [UIView animateWithDuration:0.15 animations:^{
        [self layoutViews];
    }];
    [self scrollToBottomAnimated:NO];
}

- (void)sendTapped {
    NSString *text = [_textView.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length == 0) return;
    _sourceFieldFrame = [self.view convertRect:_field.frame fromView:_panel];
    _textView.text = @"";
    [self textViewDidChange:_textView];

    NGMessage *sent = [NGMessage messageWithText:text outgoing:YES date:[NSDate date]];
    sent.status = _chat.kind == NGChatKindSaved ? NGMessageStatusRead : NGMessageStatusSending;
    _chat.draft = nil;
    NSMutableArray *chats = [NGDemoData shared].chats;
    if (![chats containsObject:_chat]) [chats addObject:_chat];

    _animatingMessage = sent;
    [self appendMessage:sent animated:YES];
    // ChatControllerNode: the send transition also steps the wallpaper.
    [_wallpaper animateEventWithDuration:NGSendTransitionDuration];

    if (_chat.kind != NGChatKindSaved) [self simulateDeliveryOf:sent];
}

- (void)appendMessage:(NGMessage *)message animated:(BOOL)animated {
    [_chat.messages addObject:message];
    [self buildRows];
    [_table reloadData];
    if (!animated) {
        [self scrollToBottomAnimated:YES];
        return;
    }
    // The list scrolls with the bubble's vertical curve (verticalListCurve).
    CGFloat bottom = MAX(-_table.contentInset.top, _table.contentSize.height + _table.contentInset.bottom - _table.bounds.size.height);
    [CATransaction begin];
    [CATransaction setAnimationTimingFunction:NGCurveTimingFunction(NGCurveSendVertical)];
    [UIView animateWithDuration:NGSendTransitionDuration animations:^{
        self->_table.contentOffset = CGPointMake(0, bottom);
    }];
    [CATransaction commit];
}

// ChatMessageTransitionNode, text case: the bubble starts where the input
// field is and moves into place on separate horizontal and vertical curves.
- (void)animateSentBubbleInCell:(NGMessageCell *)cell {
    UIView *bubble = cell.bubbleContainer;
    CGRect target = [self.view convertRect:bubble.bounds fromView:bubble];
    CGFloat dx = CGRectGetMinX(_sourceFieldFrame) - CGRectGetMinX(target);
    CGFloat dy = CGRectGetMaxY(_sourceFieldFrame) - CGRectGetMaxY(target);
    if (dx > 0) dx = MIN(dx, CGRectGetMaxX(_sourceFieldFrame) - CGRectGetMaxX(target));

    CABasicAnimation *x = [CABasicAnimation animationWithKeyPath:@"transform.translation.x"];
    x.fromValue = @(dx);
    x.toValue = @0;
    x.duration = NGSendTransitionDuration;
    x.timingFunction = NGCurveTimingFunction(NGCurveSendHorizontal);
    CABasicAnimation *y = [CABasicAnimation animationWithKeyPath:@"transform.translation.y"];
    y.fromValue = @(dy);
    y.toValue = @0;
    y.duration = NGSendTransitionDuration;
    y.timingFunction = NGCurveTimingFunction(NGCurveSendVertical);
    [bubble.layer addAnimation:x forKey:@"sendX"];
    [bubble.layer addAnimation:y forKey:@"sendY"];
}

- (void)refreshVisible {
    for (UITableViewCell *cell in _table.visibleCells) {
        if ([cell isKindOfClass:[NGMessageCell class]]) [(NGMessageCell *)cell refresh];
    }
}

// Local stand-in for the network: sent, read, typing, then an answer.
- (void)simulateDeliveryOf:(NGMessage *)message {
    __weak NGChatController *weakSelf = self;
    NGChat *chat = _chat;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        message.status = NGMessageStatusSent;
        [weakSelf refreshVisible];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        message.status = NGMessageStatusRead;
        chat.typing = YES;
        [weakSelf refreshVisible];
        [weakSelf updateSubtitle];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        chat.typing = NO;
        NGMessage *reply = [NGMessage messageWithText:[[NGDemoData shared] randomReply] outgoing:NO date:[NSDate date]];
        reply.author = chat.kind == NGChatKindGroup ? chat.members[arc4random_uniform((uint32_t)chat.members.count)] : chat.user;
        NGChatController *strongSelf = weakSelf;
        if (strongSelf && strongSelf.isViewLoaded && strongSelf.view.window) {
            [strongSelf appendMessage:reply animated:NO];
            [strongSelf updateSubtitle];
        } else {
            [chat.messages addObject:reply];
            chat.unreadCount += 1;
        }
    });
}

@end
