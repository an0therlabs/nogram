#import "NGProfile.h"
#import "NGItemList.h"
#import "NGTheme.h"
#import "NGViews.h"
#import "NGOriginal.h"
#import "NGGlass.h"
#import <QuartzCore/QuartzCore.h>

#pragma mark - Header buttons

// PeerInfoHeaderButtonNode: a 58pt platter (itemBlocksBackgroundColor, radius
// min(16, h / 2)), the 40pt icon at y 1 and the lowercased title in
// Font.regular(11) 9pt above the bottom, both in the accent colour.
@interface NGProfileButton : UIControl
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *iconName;
@end

@implementation NGProfileButton {
    UIView *_platter;
    UIImageView *_icon;
    UILabel *_label;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _platter = [[UIView alloc] initWithFrame:CGRectZero];
        _platter.backgroundColor = [UIColor whiteColor];
        _platter.userInteractionEnabled = NO;
        _icon = [[UIImageView alloc] initWithFrame:CGRectZero];
        _label = [NGTheme labelWithFont:[NGTheme regularFont:11.0f] color:[NGTheme accentColor]];
        _label.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_platter];
        [_platter addSubview:_icon];
        [_platter addSubview:_label];
    }
    return self;
}

- (void)setTitle:(NSString *)title {
    _title = [title copy];
    _label.text = [title lowercaseString];
}

- (void)setIconName:(NSString *)iconName {
    _iconName = [iconName copy];
    _icon.image = NGTintedAsset(iconName, [NGTheme accentColor]);
    [self setNeedsLayout];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    _platter.alpha = highlighted ? 0.6f : 1.0f;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    _platter.frame = self.bounds;
    _platter.layer.cornerRadius = MIN(16.0f, size.height * 0.5f);
    CGSize iconSize = _icon.image.size;
    _icon.frame = CGRectMake(floorf((size.width - iconSize.width) / 2.0f), 1.0f, iconSize.width, iconSize.height);
    CGFloat th = ceilf(_label.font.lineHeight);
    _label.frame = CGRectMake(0, size.height - th - 9.0f, size.width, th);
}

@end

#pragma mark - Header

@interface NGProfileHeaderView : UIView
- (instancetype)initWithChat:(NGChat *)chat width:(CGFloat)width openedFromChat:(BOOL)openedFromChat;
@property (nonatomic, copy) void (^onMessage)(void);
@end

@implementation NGProfileHeaderView {
    NGChat *_chat;
    NGAvatarView *_avatar;
    UILabel *_name;
    UILabel *_status;
    NSArray *_buttons;
    UIControl *_music;
    UILabel *_musicLabel;
    UIImageView *_musicIcon;
    UIImageView *_musicArrow;
}

static const CGFloat NGAvatarSize = 100.0f;    // PeerInfoHeaderNode: presentedInFormSheet ? 200 : 100

- (NGUser *)user {
    return _chat.kind == NGChatKindPrivate ? _chat.user : nil;
}

- (BOOL)hasMusic {
    return [self user].musicTitle.length > 0;
}

// peerInfoHeaderButtons(peer:isOpenedFromChat:videoCallsEnabled: width > 320 ...)
- (NSArray *)buttonSpecsOpenedFromChat:(BOOL)fromChat width:(CGFloat)width {
    NSString *mute = _chat.muted ? @"Вкл. звук" : @"Выкл. звук";
    NSString *muteIcon = _chat.muted ? @"profile_unmute" : @"profile_mute";
    NSMutableArray *specs = [NSMutableArray array];
    if (_chat.kind == NGChatKindPrivate) {
        if (!fromChat) [specs addObject:@[ @"Чат", @"profile_message" ]];
        [specs addObject:@[ @"Звонок", @"profile_call" ]];
        if (width > 320.0f) [specs addObject:@[ @"Видео", @"profile_video" ]];
        [specs addObject:@[ mute, muteIcon ]];
        if (fromChat) [specs addObject:@[ @"Поиск", @"profile_search" ]];
    } else if (_chat.kind == NGChatKindChannel) {
        if (!fromChat) [specs addObject:@[ @"Чат", @"profile_message" ]];
        [specs addObject:@[ mute, muteIcon ]];
        [specs addObject:@[ @"Поиск", @"profile_search" ]];
        [specs addObject:@[ @"Выйти", @"profile_leave" ]];
    } else {
        if (!fromChat) [specs addObject:@[ @"Чат", @"profile_message" ]];
        [specs addObject:@[ mute, muteIcon ]];
        [specs addObject:@[ @"Поиск", @"profile_search" ]];
        [specs addObject:@[ @"Ещё", @"profile_more" ]];
    }
    return specs;
}

- (instancetype)initWithChat:(NGChat *)chat width:(CGFloat)width openedFromChat:(BOOL)openedFromChat {
    if ((self = [super initWithFrame:CGRectMake(0, 0, width, 0)])) {
        _chat = chat;
        self.backgroundColor = [NGTheme blocksBackgroundColor];

        _avatar = [[NGAvatarView alloc] initWithFrame:CGRectMake(0, 0, NGAvatarSize, NGAvatarSize)];
        [_avatar configureWithChat:chat];
        _avatar.showsOnline = NO;
        [self addSubview:_avatar];

        _name = [NGTheme labelWithFont:[NGTheme mediumFont:28.0f] color:[UIColor blackColor]];
        _name.textAlignment = NSTextAlignmentCenter;
        _name.text = chat.title;
        [self addSubview:_name];

        // subtitleColor: accent while online, secondary otherwise.
        _status = [NGTheme labelWithFont:[NGTheme regularFont:17.0f] color:[NGTheme secondaryTextColor]];
        _status.textAlignment = NSTextAlignmentCenter;
        _status.text = [chat statusText];
        if (chat.kind == NGChatKindPrivate && chat.user.online) _status.textColor = [NGTheme accentColor];
        [self addSubview:_status];

        NSMutableArray *buttons = [NSMutableArray array];
        for (NSArray *spec in [self buttonSpecsOpenedFromChat:openedFromChat width:width]) {
            NGProfileButton *button = [[NGProfileButton alloc] initWithFrame:CGRectZero];
            button.title = spec[0];
            button.iconName = spec[1];
            [button addTarget:self action:@selector(buttonTapped:) forControlEvents:UIControlEventTouchUpInside];
            [self addSubview:button];
            [buttons addObject:button];
        }
        _buttons = buttons;

        if ([self hasMusic]) {
            // The music strip: SmallAudio, the track in Font.semibold(12) accent,
            // the artist in Font.regular(12) secondary, InlineTextRightArrow.
            _music = [[UIControl alloc] initWithFrame:CGRectZero];
            _musicIcon = [[UIImageView alloc] initWithImage:NGTintedAsset(@"profile_music", [NGTheme accentColor])];
            _musicLabel = [NGTheme labelWithFont:[NGTheme regularFont:12.0f] color:[NGTheme secondaryTextColor]];
            NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithString:[self user].musicTitle
                                                                                     attributes:@{ NSFontAttributeName: [NGTheme semiboldFont:12.0f], NSForegroundColorAttributeName: [NGTheme accentColor] }];
            [text appendAttributedString:[[NSAttributedString alloc] initWithString:[@"  " stringByAppendingString:[self user].musicArtist]
                                                                         attributes:@{ NSFontAttributeName: [NGTheme regularFont:12.0f], NSForegroundColorAttributeName: [NGTheme secondaryTextColor] }]];
            _musicLabel.attributedText = text;
            _musicArrow = [[UIImageView alloc] initWithImage:NGTintedAsset(@"profile_music_arrow", [NGTheme secondaryTextColor])];
            [_music addSubview:_musicIcon];
            [_music addSubview:_musicLabel];
            [_music addSubview:_musicArrow];
            [_music addTarget:self action:@selector(musicTapped) forControlEvents:UIControlEventTouchUpInside];
            [self addSubview:_music];
        }
        CGRect frame = self.frame;
        frame.size.height = [self layoutForWidth:width apply:NO];
        self.frame = frame;
    }
    return self;
}

- (void)buttonTapped:(NGProfileButton *)button {
    if ([button.iconName isEqualToString:@"profile_mute"] || [button.iconName isEqualToString:@"profile_unmute"]) {
        _chat.muted = !_chat.muted;
        button.title = _chat.muted ? @"Вкл. звук" : @"Выкл. звук";
        button.iconName = _chat.muted ? @"profile_unmute" : @"profile_mute";
    } else if ([button.iconName isEqualToString:@"profile_message"]) {
        if (self.onMessage) self.onMessage();
    }
}

- (void)musicTapped {
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:[self user].musicTitle message:[self user].musicArtist delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
    [alert show];
}

// avatar at 22, name 9 below it, status 1 below the name, then the buttons
// 16 below and, with music, the 16pt strip 16 below the buttons.
- (CGFloat)layoutForWidth:(CGFloat)width apply:(BOOL)apply {
    CGFloat y = 22.0f;
    CGRect avatarFrame = CGRectMake(floorf((width - NGAvatarSize) / 2.0f), y, NGAvatarSize, NGAvatarSize);
    y = CGRectGetMaxY(avatarFrame) + 9.0f;
    CGFloat nameH = ceilf(_name.font.lineHeight);
    CGRect nameFrame = CGRectMake(16.0f, y, width - 32.0f, nameH);
    y += nameH + 1.0f;
    CGFloat statusH = ceilf(_status.font.lineHeight);
    CGRect statusFrame = CGRectMake(16.0f, y, width - 32.0f, statusH);
    y += statusH + 16.0f;

    const CGFloat buttonSpacing = 8.0f, buttonSideInset = 16.0f;
    NSUInteger count = _buttons.count;
    CGFloat buttonWidth = count ? (width - buttonSideInset * 2.0f + buttonSpacing) / (CGFloat)count - buttonSpacing : 0.0f;
    CGFloat buttonsY = y;
    if (count) y += 58.0f;

    CGRect musicFrame = CGRectZero;
    if (_music) {
        y += 16.0f;
        CGFloat labelWidth = MIN(ceilf([_musicLabel sizeThatFits:CGSizeMake(width, 16)].width), width - 96.0f);
        CGFloat total = 14.0f + 4.0f + labelWidth + 4.0f + 8.0f;
        musicFrame = CGRectMake(floorf((width - total) / 2.0f), y, total, 16.0f);
        y += 16.0f;
        if (apply) {
            _musicIcon.frame = CGRectMake(0, 1, 14, 14);
            _musicLabel.frame = CGRectMake(18.0f, 0, labelWidth, 16.0f);
            _musicArrow.frame = CGRectMake(18.0f + labelWidth + 4.0f, 2, 8, 12);
        }
    }
    y += 8.0f;

    if (apply) {
        _avatar.frame = avatarFrame;
        _name.frame = nameFrame;
        _status.frame = statusFrame;
        CGFloat x = buttonSideInset;
        for (NGProfileButton *button in _buttons) {
            button.frame = CGRectMake(floorf(x), buttonsY, floorf(buttonWidth), 58.0f);
            x += buttonWidth + buttonSpacing;
        }
        _music.frame = musicFrame;
    }
    return y;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self layoutForWidth:self.bounds.size.width apply:YES];
}

@end

#pragma mark - Panes

// PeerInfoPaneContainerNode: the tabs in a 40pt glass capsule 10pt down,
// Font.medium(15), the selected one under a lens; the pane below.
@interface NGProfilePanesView : UIView
- (instancetype)initWithChat:(NGChat *)chat width:(CGFloat)width;
@property (nonatomic, copy) void (^heightChanged)(void);
@end

@implementation NGProfilePanesView {
    NGChat *_chat;
    NGGlassView *_tabsGlass;
    UIScrollView *_tabsScroll;
    UIView *_lens;
    NSArray *_tabButtons;
    NSArray *_paneKeys;
    NSUInteger _selected;
    UIView *_content;
}

static const CGFloat NGTabsHeight = 40.0f;
static CGFloat NGTabsAreaHeight(void) { return 10.0f + NGTabsHeight + 10.0f + 6.0f; }

- (instancetype)initWithChat:(NGChat *)chat width:(CGFloat)width {
    if ((self = [super initWithFrame:CGRectMake(0, 0, width, 0)])) {
        _chat = chat;
        self.backgroundColor = [NGTheme blocksBackgroundColor];
        // availablePanes, in PeerInfoPaneContainerNode's order.
        if (chat.kind == NGChatKindPrivate) {
            _paneKeys = @[ @"Медиа", @"Файлы", @"Ссылки", @"Музыка", @"Голосовые", @"Группы" ];
        } else if (chat.kind == NGChatKindGroup) {
            _paneKeys = @[ @"Участники", @"Медиа", @"Файлы", @"Ссылки", @"Музыка", @"Голосовые" ];
        } else {
            _paneKeys = @[ @"Медиа", @"Файлы", @"Ссылки", @"Музыка", @"Похожие" ];
        }

        _tabsGlass = [[NGGlassView alloc] initWithFrame:CGRectZero];
        [self addSubview:_tabsGlass];
        _tabsScroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
        _tabsScroll.showsHorizontalScrollIndicator = NO;
        _tabsScroll.scrollsToTop = NO;
        [_tabsGlass.contentView addSubview:_tabsScroll];
        _lens = [[UIView alloc] initWithFrame:CGRectZero];
        _lens.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.075f];
        [_tabsScroll addSubview:_lens];
        NSMutableArray *buttons = [NSMutableArray array];
        for (NSUInteger i = 0; i < _paneKeys.count; i++) {
            UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
            button.titleLabel.font = [NGTheme mediumFont:15.0f];
            [button setTitle:_paneKeys[i] forState:UIControlStateNormal];
            [button setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
            button.tag = (NSInteger)i;
            [button addTarget:self action:@selector(tabTapped:) forControlEvents:UIControlEventTouchUpInside];
            [_tabsScroll addSubview:button];
            [buttons addObject:button];
        }
        _tabButtons = buttons;
        [self showPane:0];
    }
    return self;
}

- (void)tabTapped:(UIButton *)button {
    [self showPane:(NSUInteger)button.tag];
    [UIView animateWithDuration:0.3 animations:^{ [self layoutTabs]; }];
    if (self.heightChanged) self.heightChanged();
}

- (void)layoutTabs {
    CGFloat w = self.bounds.size.width;
    CGFloat x = 4.0f;
    for (UIButton *button in _tabButtons) {
        CGFloat bw = [NGTheme widthOfText:[button titleForState:UIControlStateNormal] font:button.titleLabel.font] + 28.0f;
        button.frame = CGRectMake(x, 0, bw, NGTabsHeight);
        x += bw;
    }
    x += 4.0f;
    CGFloat maxWidth = w - 32.0f;
    CGFloat glassWidth = MIN(x, maxWidth);
    _tabsGlass.frame = CGRectMake(floorf((w - glassWidth) / 2.0f), 10.0f, glassWidth, NGTabsHeight);
    _tabsScroll.frame = _tabsGlass.bounds;
    _tabsScroll.contentSize = CGSizeMake(x, NGTabsHeight);
    UIButton *selected = _tabButtons[_selected];
    _lens.frame = CGRectInset(selected.frame, 0, 4.0f);
    _lens.layer.cornerRadius = _lens.frame.size.height * 0.5f;
    [_tabsScroll scrollRectToVisible:CGRectInset(selected.frame, -20, 0) animated:NO];
}

- (UIView *)gridForWidth:(CGFloat)width {
    // PeerInfoVisualMediaPaneNode: three columns, 1pt apart.
    UIView *grid = [[UIView alloc] initWithFrame:CGRectZero];
    grid.backgroundColor = [UIColor whiteColor];
    CGFloat side = floorf((width - 2.0f) / 3.0f);
    for (int i = 0; i < 12; i++) {
        UIView *holder = [[UIView alloc] initWithFrame:CGRectMake((i % 3) * (side + 1.0f), (i / 3) * (side + 1.0f), i % 3 == 2 ? width - 2.0f * (side + 1.0f) : side, side)];
        holder.clipsToBounds = YES;
        NSArray *colors = [NGTheme avatarColorsAtIndex:i];
        CAGradientLayer *gradient = [CAGradientLayer layer];
        gradient.frame = holder.bounds;
        gradient.colors = @[ (__bridge id)[colors[1] CGColor], (__bridge id)[colors[0] CGColor] ];
        gradient.startPoint = CGPointMake(0, 0);
        gradient.endPoint = CGPointMake(1, 1);
        [holder.layer addSublayer:gradient];
        [grid addSubview:holder];
    }
    grid.frame = CGRectMake(0, 0, width, 4.0f * (side + 1.0f) - 1.0f);
    return grid;
}

- (UIView *)listWithRows:(NSArray *)rows width:(CGFloat)width icon:(NSString *)icon {
    UIView *list = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 0)];
    list.backgroundColor = [UIColor whiteColor];
    CGFloat y = 0;
    for (NSUInteger i = 0; i < rows.count; i++) {
        NSArray *row = rows[i];
        UIView *thumb = [[UIView alloc] initWithFrame:CGRectMake(16, y + 8, 44, 44)];
        thumb.backgroundColor = [NGTheme accentColor];
        thumb.layer.cornerRadius = [icon isEqualToString:@"round"] ? 22.0f : 8.0f;
        [list addSubview:thumb];
        UILabel *title = [NGTheme labelWithFont:[NGTheme semiboldFont:16.0f] color:[UIColor blackColor]];
        title.text = row[0];
        title.frame = CGRectMake(72, y + 10, width - 72 - 70, 20);
        UILabel *subtitle = [NGTheme labelWithFont:[NGTheme regularFont:14.0f] color:[NGTheme secondaryTextColor]];
        subtitle.text = row[1];
        subtitle.frame = CGRectMake(72, y + 31, width - 72 - 16, 18);
        UILabel *date = [NGTheme labelWithFont:[NGTheme regularFont:14.0f] color:[NGTheme secondaryTextColor]];
        date.text = row.count > 2 ? row[2] : @"";
        date.textAlignment = NSTextAlignmentRight;
        date.frame = CGRectMake(width - 16 - 60, y + 11, 60, 18);
        for (UIView *v in @[ title, subtitle, date ]) [list addSubview:v];
        y += 60.0f;
        if (i + 1 < rows.count) {
            UIView *separator = [NGTheme separatorView];
            separator.frame = CGRectMake(72, y - [NGTheme pixel], width - 72, [NGTheme pixel]);
            [list addSubview:separator];
        }
    }
    list.frame = CGRectMake(0, 0, width, y);
    return list;
}

- (UIView *)paneForKey:(NSString *)key width:(CGFloat)width {
    if ([key isEqualToString:@"Медиа"]) return [self gridForWidth:width];
    if ([key isEqualToString:@"Музыка"]) {
        return [self listWithRows:@[ @[ @"Группа крови", @"Кино", @"4:47" ], @[ @"Кукла колдуна", @"Король и Шут", @"3:23" ], @[ @"Кончится лето", @"Кино", @"5:58" ] ] width:width icon:@"round"];
    }
    if ([key isEqualToString:@"Файлы"]) {
        return [self listWithRows:@[ @[ @"p0sixspwn-1.0.8.zip", @"3,4 МБ", @"12.03" ], @[ @"Nogram_0.5.0.deb", @"512 КБ", @"вчера" ] ] width:width icon:@"square"];
    }
    if ([key isEqualToString:@"Ссылки"]) {
        return [self listWithRows:@[ @[ @"theos.dev", @"Theos: cross-platform build system", @"пн" ], @[ @"github.com/theos/sdks", @"Patched iOS SDKs", @"вс" ] ] width:width icon:@"square"];
    }
    if ([key isEqualToString:@"Голосовые"]) {
        return [self listWithRows:@[ @[ @"Голосовое сообщение", @"0:42", @"вчера" ] ] width:width icon:@"round"];
    }
    if ([key isEqualToString:@"Участники"]) {
        NSMutableArray *rows = [NSMutableArray array];
        for (NGUser *member in _chat.members) [rows addObject:@[ [member displayName], [member statusText], @"" ]];
        return [self listWithRows:rows width:width icon:@"round"];
    }
    if ([key isEqualToString:@"Группы"]) {
        return [self listWithRows:@[ @[ @"Гараж iOS 6", @"4 участника", @"" ] ] width:width icon:@"round"];
    }
    return [self listWithRows:@[ @[ @"iPhone Club", @"12 400 подписчиков", @"" ] ] width:width icon:@"round"];
}

- (void)showPane:(NSUInteger)index {
    _selected = index;
    [_content removeFromSuperview];
    CGFloat w = self.bounds.size.width;
    _content = [self paneForKey:_paneKeys[index] width:w];
    CGRect frame = _content.frame;
    frame.origin.y = NGTabsAreaHeight();
    _content.frame = frame;
    [self addSubview:_content];
    CGRect own = self.frame;
    own.size.height = CGRectGetMaxY(frame);
    self.frame = own;
    [self layoutTabs];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self layoutTabs];
    CGRect frame = _content.frame;
    frame.size.width = self.bounds.size.width;
    frame.origin.y = NGTabsAreaHeight();
    _content.frame = frame;
}

@end

#pragma mark - Screen

// infoItems(...): for a user the phone, username, birthday and bio; for a
// group or channel its description and link.
UIViewController *NGPeerInfoScreen(NGChat *chat, BOOL openedFromChat) {
    CGFloat width = [UIScreen mainScreen].bounds.size.width;
    NSMutableArray *items = [NSMutableArray array];
    if (chat.kind == NGChatKindPrivate) {
        NGUser *user = chat.user;
        if (user.phone.length) [items addObject:[NGItem labeled:@"мобильный" value:user.phone accent:YES]];
        if (user.username.length) [items addObject:[NGItem labeled:@"имя пользователя" value:[@"@" stringByAppendingString:user.username] accent:YES]];
        if (user.birthday.length) [items addObject:[NGItem labeled:@"день рождения" value:user.birthday accent:NO]];
        if (user.bio.length) [items addObject:[NGItem labeled:@"о себе" value:user.bio accent:NO]];
    } else {
        if (chat.about.length) [items addObject:[NGItem labeled:(chat.kind == NGChatKindChannel ? @"описание" : @"о группе") value:chat.about accent:NO]];
        if (chat.link.length) [items addObject:[NGItem labeled:@"ссылка" value:[@"https://" stringByAppendingString:chat.link] accent:YES]];
    }
    if (chat.kind == NGChatKindPrivate) {
        [items addObject:[NGItem action:@"Отправить контакт"]];
        [items addObject:[NGItem action:@"Добавить в контакты"]];
        [items addObject:[NGItem destructive:@"Заблокировать"]];
    } else {
        NGItem *notifications = [NGItem toggle:@"Уведомления" on:!chat.muted];
        notifications.action = ^(NGItem *item) { chat.muted = !item.on; };
        [items addObject:notifications];
    }

    NGProfilePanesView *panes = [[NGProfilePanesView alloc] initWithChat:chat width:width];
    NGItem *panesItem = [NGItem fullWidth:panes];
    [items addObject:panesItem];

    NGItemListController *screen = [[NGItemListController alloc] initWithTitle:chat.title items:items];
    NGProfileHeaderView *header = [[NGProfileHeaderView alloc] initWithChat:chat width:width openedFromChat:openedFromChat];
    screen.headerView = header;
    __weak NGItemListController *weakScreen = screen;
    panes.heightChanged = ^{ [weakScreen reloadHeights]; };
    header.onMessage = ^{ [weakScreen.navigationController popViewControllerAnimated:YES]; };
    (void)screen.view;   // the bar exists once the view has loaded
    screen.header.rightButtons = @[ [NGGlassButton textButton:@"Изм." target:nil action:NULL] ];
    return screen;
}
