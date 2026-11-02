#import "NGViews.h"
#import "NGOriginal.h"

#pragma mark - Avatar

@implementation NGAvatarView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.opaque = NO;
        self.backgroundColor = [UIColor clearColor];
        self.contentMode = UIViewContentModeRedraw;
        self.userInteractionEnabled = NO;
    }
    return self;
}

- (void)configureWithChat:(NGChat *)chat {
    self.colorIndex = chat.colorIndex;
    self.initials = [chat initials];
    self.hasIcon = chat.kind == NGChatKindSaved;
    self.showsOnline = chat.kind == NGChatKindPrivate && chat.user.online;
    [self setNeedsDisplay];
}

- (void)configureWithUser:(NGUser *)user {
    self.colorIndex = user.colorIndex;
    self.initials = [user initials];
    self.hasIcon = NO;
    self.showsOnline = user.online;
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGFloat d = MIN(self.bounds.size.width, self.bounds.size.height);
    CGRect circle = CGRectMake(0, 0, d, d);

    CGContextSaveGState(ctx);
    [[UIBezierPath bezierPathWithOvalInRect:circle] addClip];
    // AvatarNode.savedMessagesColors for the Saved Messages icon, gradientColors otherwise.
    NSArray *colors = self.hasIcon ? @[ NGHex(0x2a9ef1), NGHex(0x72d5fd) ] : [NGTheme avatarColorsAtIndex:self.colorIndex];
    UIColor *bottom = colors[0], *top = colors[1];
    NSArray *stops = @[ (__bridge id)top.CGColor, (__bridge id)bottom.CGColor ];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGGradientRef gradient = CGGradientCreateWithColors(space, (__bridge CFArrayRef)stops, NULL);
    CGContextDrawLinearGradient(ctx, gradient, CGPointZero, CGPointMake(0, d), 0);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);
    CGContextRestoreGState(ctx);

    if (self.hasIcon) {
        // AvatarNode .savedMessagesIcon: the asset scaled by width / 60, tinted white.
        UIImage *icon = NGTintedAsset(@"avatar_saved", [UIColor whiteColor]);
        CGFloat factor = d / 60.0f;
        CGSize s = CGSizeMake(icon.size.width * factor, icon.size.height * factor);
        [icon drawInRect:CGRectMake((d - s.width) / 2.0f, (d - s.height) / 2.0f, s.width, s.height)];
    } else if (self.initials.length) {
        // avatarPlaceholderFont(size: floor(diameter * 26 / 60)): rounded bold, plain bold before iOS 13.
        UIFont *font = [NGTheme boldFont:floorf(d * 26.0f / 60.0f)];
        CGSize size = [self.initials sizeWithFont:font];
        [[UIColor whiteColor] setFill];
        [self.initials drawAtPoint:CGPointMake(floorf((d - size.width) / 2.0f), floorf((d - size.height) / 2.0f)) withFont:font];
    }

    if (self.showsOnline) {
        // recentStatusOnlineIcon(.regular): 14pt, item background ring, onlineDotColor 0x4cc91f;
        // ChatListItem places it at (width - 14 - 2, height - 14 - 2).
        CGRect bounds = CGRectMake(d - 14.0f - 2.0f, d - 14.0f - 2.0f, 14.0f, 14.0f);
        [[UIColor whiteColor] setFill];
        [[UIBezierPath bezierPathWithOvalInRect:bounds] fill];
        [NGHex(0x4cc91f) setFill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectInset(bounds, 2.0f, 2.0f)] fill];
    }
}

@end

#pragma mark - Peer cell

@implementation NGPeerCell {
    UIView *_separator;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier])) {
        self.backgroundColor = [UIColor whiteColor];
        self.selectedBackgroundView = [NGTheme highlightView];
        _avatar = [[NGAvatarView alloc] initWithFrame:CGRectMake(0, 0, 40, 40)];
        _titleLabel = [NGTheme labelWithFont:[NGTheme mediumFont:17] color:[UIColor blackColor]];
        _subtitleLabel = [NGTheme labelWithFont:[NGTheme regularFont:14] color:[NGTheme secondaryTextColor]];
        _detailLabel = [NGTheme labelWithFont:[NGTheme regularFont:14] color:[NGTheme secondaryTextColor]];
        _subtitleIcon = [[UIImageView alloc] initWithFrame:CGRectZero];
        _separator = [NGTheme separatorView];
        for (UIView *v in @[ _avatar, _titleLabel, _subtitleLabel, _detailLabel, _subtitleIcon, _separator ]) {
            [self.contentView addSubview:v];
        }
    }
    return self;
}

- (void)setHidesSeparator:(BOOL)hidesSeparator {
    _hidesSeparator = hidesSeparator;
    _separator.hidden = hidesSeparator;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width, h = self.contentView.bounds.size.height;
    CGFloat left = 65;
    _avatar.frame = CGRectMake(14, floorf((h - 40) / 2), 40, 40);
    [_detailLabel sizeToFit];
    CGFloat dw = _detailLabel.text.length ? _detailLabel.frame.size.width : 0;
    _detailLabel.frame = CGRectMake(w - 14 - dw, floorf((h - 18) / 2), dw, 18);
    CGFloat right = w - 14 - (dw ? dw + 8 : 0);
    _titleLabel.frame = CGRectMake(left, 6, right - left, 21);
    CGFloat iconW = _subtitleIcon.image ? 16 : 0;
    _subtitleIcon.frame = CGRectMake(left, 29, iconW, iconW);
    _subtitleLabel.frame = CGRectMake(left + (iconW ? iconW + 4 : 0), 28, right - left - iconW, 18);
    CGFloat px = [NGTheme pixel];
    _separator.frame = CGRectMake(left, h - px, w - left, px);
}

@end

#pragma mark - Action cell

@implementation NGActionCell {
    UIView *_separator;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier])) {
        self.backgroundColor = [UIColor whiteColor];
        self.selectedBackgroundView = [NGTheme highlightView];
        _iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _iconView.contentMode = UIViewContentModeCenter;
        _titleLabel = [NGTheme labelWithFont:[NGTheme regularFont:17] color:[NGTheme accentColor]];
        _separator = [NGTheme separatorView];
        [self.contentView addSubview:_iconView];
        [self.contentView addSubview:_titleLabel];
        [self.contentView addSubview:_separator];
    }
    return self;
}

- (void)setHidesSeparator:(BOOL)hidesSeparator {
    _hidesSeparator = hidesSeparator;
    _separator.hidden = hidesSeparator;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width, h = self.contentView.bounds.size.height;
    _iconView.frame = CGRectMake(14, 0, 40, h);
    _titleLabel.frame = CGRectMake(65, 0, w - 80, h);
    CGFloat px = [NGTheme pixel];
    _separator.frame = CGRectMake(65, h - px, w - 65, px);
}

@end

#pragma mark - Spacer

@implementation NGSpacerCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [NGTheme blocksBackgroundColor];
        UIView *bg = [[UIView alloc] initWithFrame:CGRectZero];
        bg.backgroundColor = [NGTheme blocksBackgroundColor];
        self.backgroundView = bg;
    }
    return self;
}

@end

#pragma mark - Chat list cell

// Metrics follow ChatListItem: 76pt rows, 60pt avatar, text column at 80.
@implementation NGChatListCell {
    NGAvatarView *_avatar;
    UILabel *_title;
    UILabel *_message;
    UILabel *_date;
    UILabel *_badge;
    UIImageView *_badgeBackground;
    UIImageView *_pin;
    UIImageView *_mute;
    UIImageView *_checks;
    UIView *_separator;
    UIView *_background;
    NGChat *_chat;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier])) {
        _background = [[UIView alloc] initWithFrame:CGRectZero];
        self.backgroundView = _background;
        self.selectedBackgroundView = [NGTheme highlightView];

        _avatar = [[NGAvatarView alloc] initWithFrame:CGRectMake(0, 0, 60, 60)];
        // ChatListItem: Font.semibold(16), Font.regular(15), Font.regular(14), semibold(12) badge.
        _title = [NGTheme labelWithFont:[NGTheme semiboldFont:16] color:[UIColor blackColor]];
        _message = [NGTheme labelWithFont:[NGTheme regularFont:15] color:[NGTheme secondaryTextColor]];
        _message.numberOfLines = 2;
        _date = [NGTheme labelWithFont:[NGTheme regularFont:14] color:[NGTheme secondaryTextColor]];
        _badgeBackground = [[UIImageView alloc] initWithFrame:CGRectZero];
        _badge = [NGTheme labelWithFont:[NGTheme semiboldFont:12] color:[UIColor whiteColor]];
        _badge.textAlignment = NSTextAlignmentCenter;
        // chatList.pinnedBadgeColor 0xb6b6bb, muteIconColor 0xa7a7ad
        _pin = [[UIImageView alloc] initWithImage:NGTintedAsset(@"list_pinned", NGHex(0xb6b6bb))];
        _mute = [[UIImageView alloc] initWithImage:NGTintedAsset(@"list_muted", NGHex(0xa7a7ad))];
        _checks = [[UIImageView alloc] initWithFrame:CGRectZero];
        _separator = [NGTheme separatorView];

        for (UIView *v in @[ _avatar, _title, _message, _date, _badgeBackground, _badge, _pin, _mute, _checks, _separator ]) {
            [self.contentView addSubview:v];
        }
    }
    return self;
}

- (void)configureWithChat:(NGChat *)chat {
    _chat = chat;
    [_avatar configureWithChat:chat];
    _title.text = chat.title;
    _background.backgroundColor = chat.pinned ? NGHex(0xf7f7f7) : [UIColor whiteColor];

    NGMessage *last = [chat lastMessage];
    _date.text = last ? [NGTheme listDateString:last.date] : @"";

    UIFont *font = [NGTheme regularFont:15];
    UIColor *gray = [NGTheme secondaryTextColor];
    if (chat.typing) {
        _message.attributedText = nil;
        _message.text = @"печатает…";
        _message.textColor = [NGTheme accentColor];
    } else if (chat.draft.length) {
        NSString *prefix = @"Черновик: ";
        NSMutableAttributedString *s = [[NSMutableAttributedString alloc] initWithString:[prefix stringByAppendingString:chat.draft]
                                                                              attributes:@{ NSFontAttributeName: font, NSForegroundColorAttributeName: gray }];
        [s addAttribute:NSForegroundColorAttributeName value:NGHex(0xdd4b39) range:NSMakeRange(0, prefix.length)];
        _message.attributedText = s;
    } else if (chat.kind == NGChatKindGroup && last) {
        NSString *author = last.outgoing ? @"Вы" : [last.author firstName];
        NSMutableAttributedString *s = [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@\n%@", author, last.text]
                                                                              attributes:@{ NSFontAttributeName: font, NSForegroundColorAttributeName: gray }];
        [s addAttribute:NSForegroundColorAttributeName value:[UIColor blackColor] range:NSMakeRange(0, author.length)];
        _message.attributedText = s;
    } else {
        _message.attributedText = nil;
        _message.text = last.text ?: @"";
        _message.textColor = gray;
        _message.font = font;
    }

    BOOL showChecks = last.outgoing && chat.kind != NGChatKindSaved && chat.kind != NGChatKindChannel && !chat.draft.length;
    _checks.hidden = !showChecks;
    // chatList.checkmarkColor: dayClassic is not `day`, so 0x21c004;
    // pendingIndicatorColor 0x8e8e93 for the clock.
    if (last.status == NGMessageStatusSending) {
        _checks.image = NGClockFrameImage(NGHex(0x8e8e93));
    } else {
        _checks.image = NGStatusCheckImage(NGHex(0x21c004), last.status != NGMessageStatusRead);
    }

    _badge.text = chat.unreadCount > 0 ? [NSString stringWithFormat:@"%ld", (long)chat.unreadCount] : nil;
    _badge.hidden = _badgeBackground.hidden = chat.unreadCount == 0;
    // unreadBadgeActiveBackgroundColor = accent, unreadBadgeInactiveBackgroundColor 0xb6b6bb, diameter 20
    _badgeBackground.image = NGBadgeBackgroundImage(chat.muted ? NGHex(0xb6b6bb) : [NGTheme accentColor], 20.0f);
    _pin.hidden = !(chat.pinned && chat.unreadCount == 0);
    _mute.hidden = !chat.muted;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width, h = self.contentView.bounds.size.height;
    CGFloat left = 80, right = w - 10;

    _avatar.frame = CGRectMake(10, floorf((h - 60) / 2), 60, 60);

    CGFloat dateW = [NGTheme widthOfText:_date.text font:_date.font];
    _date.frame = CGRectMake(right - dateW, 10, dateW, 18);
    CGFloat titleRight = right - dateW - 6;
    if (!_checks.hidden) {
        CGSize cs = _checks.image.size;
        _checks.frame = CGRectMake(right - dateW - 2 - cs.width, 12, cs.width, cs.height);
        titleRight -= cs.width + 2;
    }

    CGSize muteSize = _mute.image.size;
    CGFloat titleMax = titleRight - left - (_mute.hidden ? 0 : muteSize.width + 2);
    CGFloat titleW = MIN(titleMax, [NGTheme widthOfText:_title.text font:_title.font]);
    _title.frame = CGRectMake(left, 8, titleW, 21);
    _mute.frame = CGRectMake(left + titleW + 1, 7, muteSize.width, muteSize.height);

    CGFloat messageRight = right;
    if (!_badge.hidden) {
        CGFloat bw = MAX(20, [NGTheme widthOfText:_badge.text font:_badge.font] + 12);
        _badgeBackground.frame = CGRectMake(right - bw, 42, bw, 20);
        _badge.frame = _badgeBackground.frame;
        messageRight -= bw + 6;
    } else if (!_pin.hidden) {
        CGSize ps = _pin.image.size;
        _pin.frame = CGRectMake(right - ps.width, 41, ps.width, ps.height);
        messageRight -= ps.width + 6;
    }
    CGSize fit = [_message sizeThatFits:CGSizeMake(messageRight - left, 40)];
    _message.frame = CGRectMake(left, 30, messageRight - left, MIN(40, ceilf(fit.height)));

    CGFloat px = [NGTheme pixel];
    _separator.frame = CGRectMake(left, h - px, w - left, px);
}

@end
