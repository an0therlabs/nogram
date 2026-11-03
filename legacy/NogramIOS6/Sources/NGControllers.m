#import "NGControllers.h"
#import "NGChatController.h"
#import "NGTheme.h"
#import "NGViews.h"
#import "NGOriginal.h"
#import "NGTabBarController.h"
#import "NGSettingsScreens.h"
#import "NGTelegram.h"
#import <QuartzCore/QuartzCore.h>

static void NGPrepareTable(UITableView *table, UIColor *background) {
    table.separatorStyle = UITableViewCellSeparatorStyleNone;
    table.contentInset = UIEdgeInsetsMake([NGHeaderView height], 0, NGTabBarHeight, 0);
    table.scrollIndicatorInsets = table.contentInset;
    table.contentOffset = CGPointMake(0, -[NGHeaderView height]);
    table.backgroundColor = background;
    table.backgroundView = nil;
    table.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
}

#pragma mark - List base

@implementation NGListController {
    BOOL _hasBackButton;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if ([self respondsToSelector:@selector(setAutomaticallyAdjustsScrollViewInsets:)]) {
        self.automaticallyAdjustsScrollViewInsets = NO;
    }
    _header = [[NGHeaderView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, [NGHeaderView height])];
    _header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _header.title = self.title;
    [self.tableView addSubview:_header];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:animated];
    // A pushed list leads with the bar's glass back button.
    NSArray *stack = self.navigationController.viewControllers;
    if (stack.count > 1 && stack[0] != self && !_hasBackButton) {
        _hasBackButton = YES;
        self.header.leftButtons = @[ [NGGlassButton iconButton:@"nav_back" tint:NGGlassButtonTintGeneric target:self action:@selector(ng_back)] ];
    }
}

- (void)ng_back {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self pinHeader];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    [self pinHeader];
}

- (void)pinHeader {
    CGRect frame = _header.frame;
    frame.origin.y = self.tableView.contentOffset.y;
    frame.size.width = self.tableView.bounds.size.width;
    _header.frame = frame;
    [self.tableView bringSubviewToFront:_header];
}

@end

#pragma mark - Chats

@interface NGChatListController () <UITextFieldDelegate>
@end

@implementation NGChatListController {
    NSArray *_rows;
    NSString *_query;
    NGGlassButton *_editButton;
    UIView *_searchPlaceholder;
    NSTimer *_refreshTimer;
    BOOL _loading;
}

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        self.title = @"Чаты";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [NGTheme disableExtendedLayoutFor:self];
    NGPrepareTable(self.tableView, [UIColor whiteColor]);
    self.tableView.rowHeight = 76;
    self.tableView.tableHeaderView = [self searchHeader];

    _editButton = [NGGlassButton textButton:@"Изм." target:self action:@selector(toggleEditing)];
    self.header.leftButtons = @[ _editButton ];
    // ChatListController: the compose button has the accent tint.
    self.header.rightButtons = @[ [NGGlassButton iconButton:@"nav_compose" tint:NGGlassButtonTintAccent target:self action:@selector(compose)] ];
}

// The search field under the bar: a 44pt capsule, icon and placeholder centred.
- (UIView *)searchHeader {
    CGFloat w = self.view.bounds.size.width;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 56)];
    header.backgroundColor = [UIColor whiteColor];
    UIView *field = [[UIView alloc] initWithFrame:CGRectMake(16, 4, w - 32, 44)];
    field.backgroundColor = NGHexA(0x767680, 0.12f);
    field.layer.cornerRadius = 22;
    field.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    UITextField *text = [[UITextField alloc] initWithFrame:CGRectMake(16, 0, w - 32 - 32, 44)];
    text.font = [NGTheme regularFont:17];
    text.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    text.clearButtonMode = UITextFieldViewModeWhileEditing;
    text.returnKeyType = UIReturnKeySearch;
    text.autocorrectionType = UITextAutocorrectionTypeNo;
    text.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    text.delegate = self;
    [text addTarget:self action:@selector(searchChanged:) forControlEvents:UIControlEventEditingChanged];
    [field addSubview:text];

    UIView *placeholder = [[UIView alloc] initWithFrame:CGRectZero];
    placeholder.userInteractionEnabled = NO;
    UIImageView *icon = [[UIImageView alloc] initWithImage:NGTintedAsset(@"list_search", NGHex(0x8e8e93))];
    UILabel *label = [NGTheme labelWithFont:[NGTheme regularFont:17] color:NGHex(0x8e8e93)];
    label.text = @"Поиск";
    CGFloat lw = [NGTheme widthOfText:label.text font:label.font];
    icon.frame = CGRectMake(0, 7, 30, 30);
    label.frame = CGRectMake(32, 0, lw, 44);
    placeholder.frame = CGRectMake(floorf((field.bounds.size.width - 32 - lw) / 2), 0, 32 + lw, 44);
    placeholder.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    [placeholder addSubview:icon];
    [placeholder addSubview:label];
    [field addSubview:placeholder];
    _searchPlaceholder = placeholder;
    [header addSubview:field];
    return header;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadRows];
    [self loadRemoteDialogs];
    [_refreshTimer invalidate];
    /* No updates connection yet, so the list polls, but gently: 30 s, and
       only while the app is in front. */
    _refreshTimer = [NSTimer scheduledTimerWithTimeInterval:30.0 target:self selector:@selector(loadRemoteDialogs) userInfo:nil repeats:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_refreshTimer invalidate];
    _refreshTimer = nil;
}

// With an account, the list is the account's dialogs (messages.getDialogs).
- (void)loadRemoteDialogs {
    if (![NGTelegram shared].isAuthorized || _loading) return;
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
    _loading = YES;
    [[NGTelegram shared] loadDialogs:^(NSArray *chats, NSString *error) {
        self->_loading = NO;
        if (!chats) return;
        NSMutableArray *store = [NGDemoData shared].chats;
        [store removeAllObjects];
        [store addObjectsFromArray:chats];
        if (!self.editing) [self reloadRows];
    }];
}

- (void)reloadRows {
    NSMutableArray *pinned = [NSMutableArray array], *rest = [NSMutableArray array];
    for (NGChat *chat in [NGDemoData shared].chats) {
        if (_query.length && [chat.title rangeOfString:_query options:NSCaseInsensitiveSearch].location == NSNotFound) continue;
        [(chat.pinned ? pinned : rest) addObject:chat];
    }
    [rest sortUsingComparator:^NSComparisonResult(NGChat *a, NGChat *b) {
        return [[b lastMessage].date compare:[a lastMessage].date];
    }];
    _rows = [pinned arrayByAddingObjectsFromArray:rest];
    [self.tableView reloadData];
    [self updateBadge];
}

- (void)updateBadge {
    NSInteger unread = 0;
    for (NGChat *chat in [NGDemoData shared].chats) {
        if (!chat.muted) unread += chat.unreadCount;
    }
    [[self ng_tabBarController] setBadgeValue:(unread ? [NSString stringWithFormat:@"%ld", (long)unread] : nil) atIndex:2];
}

- (void)searchChanged:(UITextField *)field {
    _query = field.text;
    _searchPlaceholder.hidden = field.text.length > 0;
    [self reloadRows];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (void)toggleEditing {
    [self setEditing:!self.editing animated:YES];
    _editButton.title = self.editing ? @"Готово" : @"Изм.";
    [self.header setNeedsLayout];
}

- (void)compose {
    NGContactsController *contacts = [NGContactsController new];
    __weak NGChatListController *weakSelf = self;
    contacts.onSelect = ^(NGUser *user) {
        [weakSelf dismissViewControllerAnimated:YES completion:^{
            [weakSelf openChat:[[NGDemoData shared] chatWithUser:user]];
        }];
    };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:contacts];
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)openChat:(NGChat *)chat {
    chat.unreadCount = 0;
    [self.navigationController pushViewController:[[NGChatController alloc] initWithChat:chat] animated:YES];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _rows.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NGChatListCell *cell = [tableView dequeueReusableCellWithIdentifier:@"chat"];
    if (!cell) cell = [[NGChatListCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"chat"];
    [cell configureWithChat:_rows[indexPath.row]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self.view endEditing:YES];
    [self openChat:_rows[indexPath.row]];
}

- (NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath {
    return @"Удалить";
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) return;
    [[NGDemoData shared].chats removeObject:_rows[indexPath.row]];
    NSMutableArray *rows = [_rows mutableCopy];
    [rows removeObjectAtIndex:indexPath.row];
    _rows = rows;
    [tableView deleteRowsAtIndexPaths:@[ indexPath ] withRowAnimation:UITableViewRowAnimationFade];
    [self updateBadge];
}

@end

#pragma mark - Contacts

@implementation NGContactsController {
    NSArray *_contacts;
}

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        self.title = @"Контакты";
        _contacts = [NGTelegram shared].isAuthorized ? @[] : [NGDemoData shared].contacts;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [NGTheme disableExtendedLayoutFor:self];
    NGPrepareTable(self.tableView, [UIColor whiteColor]);
    if (self.onSelect) {
        self.title = @"Новое сообщение";
        self.header.title = self.title;
        self.header.leftButtons = @[ [NGGlassButton textButton:@"Отмена" target:self action:@selector(cancel)] ];
    } else {
        self.header.leftButtons = @[ [NGGlassButton textButton:@"Сорт." target:nil action:NULL] ];
        self.header.rightButtons = @[ [NGGlassButton iconButton:@"contacts_add" tint:NGGlassButtonTintGeneric target:nil action:NULL] ];
    }
}

- (void)cancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

// With an account, the list is the account's contacts (contacts.getContacts).
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (![NGTelegram shared].isAuthorized) return;
    [[NGTelegram shared] loadContacts:^(NSArray *users, NSString *error) {
        if (!users) return;
        self->_contacts = users;
        [self.tableView reloadData];
    }];
}

- (NSArray *)actions {
    if (self.onSelect) return @[ @[ @"contacts_add", @"Создать группу" ], @[ @"contacts_add", @"Новый контакт" ] ];
    return @[ @[ @"contacts_add", @"Добавить контакт" ], @[ @"contacts_invite", @"Пригласить друзей" ] ];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? (NSInteger)[self actions].count : (NSInteger)_contacts.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 0 ? 48 : 52;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        NGActionCell *cell = [tableView dequeueReusableCellWithIdentifier:@"action"];
        if (!cell) cell = [[NGActionCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"action"];
        NSArray *action = [self actions][indexPath.row];
        cell.iconView.image = NGTintedAsset(action[0], [NGTheme accentColor]);
        cell.titleLabel.text = action[1];
        return cell;
    }
    NGPeerCell *cell = [tableView dequeueReusableCellWithIdentifier:@"peer"];
    if (!cell) cell = [[NGPeerCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"peer"];
    NGUser *user = _contacts[indexPath.row];
    [cell.avatar configureWithUser:user];
    cell.avatar.showsOnline = NO;
    cell.titleLabel.text = [user displayName];
    cell.subtitleLabel.text = [user statusText];
    cell.subtitleLabel.textColor = user.online ? [NGTheme accentColor] : [NGTheme secondaryTextColor];
    cell.detailLabel.text = nil;
    cell.subtitleIcon.image = nil;
    cell.hidesSeparator = indexPath.row == (NSInteger)_contacts.count - 1;
    [cell setNeedsLayout];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) return;
    NGUser *user = _contacts[indexPath.row];
    if (self.onSelect) {
        self.onSelect(user);
        return;
    }
    [self.navigationController pushViewController:[[NGChatController alloc] initWithChat:[[NGDemoData shared] chatWithUser:user]] animated:YES];
}

@end

#pragma mark - Calls

@implementation NGCallsController

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        self.title = @"Звонки";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [NGTheme disableExtendedLayoutFor:self];
    NGPrepareTable(self.tableView, [UIColor whiteColor]);
    self.tableView.rowHeight = 52;
    self.header.leftButtons = @[ [NGGlassButton textButton:@"Изм." target:nil action:NULL] ];
    self.header.rightButtons = @[ [NGGlassButton iconButton:@"settings_phone" tint:NGGlassButtonTintGeneric target:nil action:NULL] ];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [NGDemoData shared].calls.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NGPeerCell *cell = [tableView dequeueReusableCellWithIdentifier:@"call"];
    if (!cell) cell = [[NGPeerCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"call"];
    NGCall *call = [NGDemoData shared].calls[indexPath.row];
    [cell.avatar configureWithUser:call.user];
    cell.avatar.showsOnline = NO;
    cell.titleLabel.text = [call.user displayName];
    cell.titleLabel.textColor = call.missed ? NGHex(0xff3b30) : [UIColor blackColor];
    NSString *kind = call.missed ? @"Пропущенный" : (call.outgoing ? @"Исходящий" : @"Входящий");
    cell.subtitleLabel.text = call.minutes ? [NSString stringWithFormat:@"%@ (%ld мин)", kind, (long)call.minutes] : kind;
    cell.subtitleLabel.textColor = [NGTheme secondaryTextColor];
    cell.subtitleIcon.image = NGTintedAsset(call.outgoing ? @"list_call_out" : @"list_call_in", NGHex(0x8e8e93));
    cell.detailLabel.text = [NGTheme listDateString:call.date];
    cell.hidesSeparator = indexPath.row == (NSInteger)[NGDemoData shared].calls.count - 1;
    [cell setNeedsLayout];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NGCall *call = [NGDemoData shared].calls[indexPath.row];
    [self.navigationController pushViewController:[[NGChatController alloc] initWithChat:[[NGDemoData shared] chatWithUser:call.user]] animated:YES];
}

@end

#pragma mark - Settings

// PeerInfoScreen in settings mode (PeerInfoSettingsItems.swift), day theme:
// blocks background 0xefeff4, white cards inset by 16 with 26pt "glass"
// corners (PresentationResourcesItemList.cornersImage(glass: true)), 24pt
// between sections.
static const CGFloat NGSettingsSideInset = 16.0f;     // peerInfoSideInsets: sectionLeft
static const CGFloat NGSettingsSectionSpacing = 24.0f;
static const CGFloat NGSettingsCornerRadius = 26.0f;

// cornersImage(theme, top:, bottom:, glass: true): the blocks colour with the
// card's rounded corners cut out, laid over the row.
static UIImage *NGCornersImage(BOOL top, BOOL bottom) {
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
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:bounds byRoundingCorners:corners cornerRadii:CGSizeMake(NGSettingsCornerRadius, NGSettingsCornerRadius)];
    CGContextAddPath(context, path.CGPath);
    CGContextFillPath(context);
    UIImage *image = [UIGraphicsGetImageFromCurrentImageContext() stretchableImageWithLeftCapWidth:28 topCapHeight:28];
    UIGraphicsEndImageContext();
    cache[key] = image;
    return image;
}

// PeerInfoScreenDisclosureItemNode: Font.regular(17), height = text + 32,
// 30pt icon at 16, text at 16 + 29 + 16, arrow 7pt from the right edge,
// label (secondary colour) right-aligned before the arrow, separator from
// the text's left edge minus 1.
@interface NGSettingsCell : UITableViewCell
@property (nonatomic, readonly) UIImageView *iconView;
@property (nonatomic, readonly) UILabel *titleLabel;
@property (nonatomic, readonly) UILabel *detailLabel;
@property (nonatomic) BOOL firstInSection, lastInSection;
@property (nonatomic) CGFloat gapBelow;   // the section spacing, carried by the last row
@end

@implementation NGSettingsCell {
    UIView *_card;
    UIView *_highlight;
    UIImageView *_chevron;
    UIView *_separator;
    UIImageView *_corners;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [NGTheme blocksBackgroundColor];
        UIView *bg = [[UIView alloc] initWithFrame:CGRectZero];
        bg.backgroundColor = [NGTheme blocksBackgroundColor];
        self.backgroundView = bg;

        _card = [[UIView alloc] initWithFrame:CGRectZero];
        _card.backgroundColor = [UIColor whiteColor];          // itemBlocksBackgroundColor
        _highlight = [[UIView alloc] initWithFrame:CGRectZero];
        _highlight.backgroundColor = NGHex(0xe5e5ea);          // itemHighlightedBackgroundColor
        _highlight.hidden = YES;
        _iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _titleLabel = [NGTheme labelWithFont:[NGTheme regularFont:17] color:[UIColor blackColor]];
        _detailLabel = [NGTheme labelWithFont:[NGTheme regularFont:17] color:NGHex(0x8e8e93)];
        _detailLabel.textAlignment = NSTextAlignmentRight;
        _chevron = [[UIImageView alloc] initWithImage:NGTintedAsset(@"list_disclosure", NGHex(0xbab9be))];
        _separator = [NGTheme separatorView];                   // itemBlocksSeparatorColor
        _corners = [[UIImageView alloc] initWithFrame:CGRectZero];
        [self.contentView addSubview:_card];
        for (UIView *v in @[ _highlight, _iconView, _titleLabel, _detailLabel, _chevron, _separator ]) {
            [_card addSubview:v];
        }
        [self.contentView addSubview:_corners];
    }
    return self;
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    _highlight.hidden = !highlighted;
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];
    _highlight.hidden = !selected;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width, h = self.contentView.bounds.size.height - self.gapBelow;
    CGRect cardFrame = CGRectMake(NGSettingsSideInset, 0, w - NGSettingsSideInset * 2.0f, h);
    _card.frame = cardFrame;
    _highlight.frame = _card.bounds;
    CGFloat width = cardFrame.size.width;
    const CGFloat sideInset = 16.0f;
    CGFloat leftInset = sideInset + 29.0f + 16.0f;
    CGFloat rightInset = sideInset + 18.0f;

    _iconView.frame = CGRectMake(sideInset, floorf((h - 30.0f) / 2.0f), 30.0f, 30.0f);
    CGSize arrow = _chevron.image.size;
    _chevron.frame = CGRectMake(width - 7.0f - arrow.width, floorf((h - arrow.height) / 2.0f), arrow.width, arrow.height);
    CGFloat textWidth = [NGTheme widthOfText:_titleLabel.text font:_titleLabel.font];
    CGFloat textHeight = ceilf(_titleLabel.font.lineHeight);
    _titleLabel.frame = CGRectMake(leftInset, floorf((h - textHeight) / 2.0f), MIN(textWidth, width - leftInset - rightInset), textHeight);
    CGFloat labelWidth = MIN([NGTheme widthOfText:_detailLabel.text font:_detailLabel.font], width - textWidth - leftInset - rightInset);
    _detailLabel.frame = CGRectMake(width - rightInset - labelWidth, floorf((h - textHeight) / 2.0f), labelWidth, textHeight);
    CGFloat px = [NGTheme pixel];
    _separator.hidden = self.lastInSection;
    _separator.frame = CGRectMake(leftInset - 1.0f, h - px, width - leftInset + 1.0f, px);

    _corners.image = NGCornersImage(self.firstInSection, self.lastInSection);
    _corners.hidden = _corners.image == nil;
    _corners.frame = cardFrame;
}

@end

// PeerInfoHeaderNode in settings: a 100pt avatar 22pt below the status bar,
// the name in Font.medium(28) 9pt under it, then the phone and username in
// Font.regular(17), secondary colour, 1pt lower.
@interface NGSettingsHeaderView : UIView
@end

@implementation NGSettingsHeaderView {
    NGAvatarView *_avatar;
    UILabel *_name;
    UILabel *_info;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [NGTheme blocksBackgroundColor];
        NGUser *me = [NGDemoData shared].me;
        _avatar = [[NGAvatarView alloc] initWithFrame:CGRectMake(0, 0, 100, 100)];
        [_avatar configureWithUser:me];
        _avatar.showsOnline = NO;
        _name = [NGTheme labelWithFont:[NGTheme mediumFont:28.0f] color:[UIColor blackColor]];
        _name.textAlignment = NSTextAlignmentCenter;
        _name.text = [me displayName];
        _info = [NGTheme labelWithFont:[NGTheme regularFont:17.0f] color:NGHex(0x8e8e93)];
        _info.textAlignment = NSTextAlignmentCenter;
        _info.text = [NSString stringWithFormat:@"%@ • @%@", me.phone, me.username];
        [self addSubview:_avatar];
        [self addSubview:_name];
        [self addSubview:_info];
    }
    return self;
}

+ (CGFloat)heightForWidth:(CGFloat)width {
    CGFloat nameH = ceilf([NGTheme mediumFont:28.0f].lineHeight);
    CGFloat infoH = ceilf([NGTheme regularFont:17.0f].lineHeight);
    // contentHeight += headerHeight; contentHeight += sectionSpacing + 12
    return 22.0f + 100.0f + 9.0f + nameH + 1.0f + infoH + NGSettingsSectionSpacing + 12.0f;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    _avatar.frame = CGRectMake(floorf((w - 100.0f) / 2.0f), 22.0f, 100.0f, 100.0f);
    CGFloat nameH = ceilf(_name.font.lineHeight);
    _name.frame = CGRectMake(16.0f, CGRectGetMaxY(_avatar.frame) + 9.0f, w - 32.0f, nameH);
    _info.frame = CGRectMake(16.0f, CGRectGetMaxY(_name.frame) + 1.0f, w - 32.0f, ceilf(_info.font.lineHeight));
}

@end

@implementation NGSettingsController {
    NSArray *_sections;
}

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        self.title = @"Настройки";
        // The sections settingsItems builds, in order: myProfile, shortcuts,
        // advanced, support (the account, wallet and payment sections need a
        // server). Colours: PresentationResourcesSettings.
        UIColor *red = NGHex(0xFF453A), *green = NGHex(0x34C759), *blue = NGHex(0x0a84ff), *lightBlue = NGHex(0x32ADE6);
        UIColor *orange = NGHex(0xFF9F0A), *purple = NGHex(0xAF52DE), *gray = NGHex(0x8E8E93);
        _sections = @[
            @[ @[ @"settings_profile", red, @"Мой профиль", @"" ] ],
            @[
                @[ @"settings_saved", blue, @"Избранное", @"" ],
                @[ @"settings_phone", green, @"Недавние звонки", @"" ],
                @[ @"settings_devices", orange, @"Устройства", @"2" ],
                @[ @"settings_folder", lightBlue, @"Папки с чатами", @"" ],
            ],
            @[
                @[ @"settings_notifications", red, @"Уведомления и звуки", @"" ],
                @[ @"settings_privacy", gray, @"Конфиденциальность", @"" ],
                @[ @"settings_data", green, @"Данные и память", @"" ],
                @[ @"settings_appearance", lightBlue, @"Оформление", @"" ],
                @[ @"settings_power", orange, @"Энергосбережение", @"Выкл." ],
                @[ @"settings_language", purple, @"Язык", @"Русский" ],
            ],
            @[
                @[ @"settings_support", orange, @"Задать вопрос", @"" ],
                @[ @"settings_faq", lightBlue, @"Вопросы о Telegram", @"" ],
                @[ @"settings_tips", NGHex(0xffcc02), @"Возможности Telegram", @"" ],
            ],
        ];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [NGTheme disableExtendedLayoutFor:self];
    NGPrepareTable(self.tableView, [NGTheme blocksBackgroundColor]);
    // The bar floats over the profile header, which starts at the top.
    self.tableView.contentInset = UIEdgeInsetsMake(0, 0, NGTabBarHeight, 0);
    self.tableView.scrollIndicatorInsets = self.tableView.contentInset;
    self.tableView.contentOffset = CGPointZero;
    self.header.title = nil;
    self.header.showsBackdrop = NO;
    self.header.rightButtons = @[ [NGGlassButton textButton:@"Изм." target:nil action:NULL] ];
    CGFloat w = self.view.bounds.size.width;
    NGSettingsHeaderView *profile = [[NGSettingsHeaderView alloc] initWithFrame:CGRectMake(0, 0, w, [NGSettingsHeaderView heightForWidth:w])];
    profile.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.tableView.tableHeaderView = profile;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return _sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [_sections[section] count];
}

- (CGFloat)gapBelowRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row + 1 < (NSInteger)[_sections[indexPath.section] count]) return 0.0f;
    return indexPath.section + 1 < (NSInteger)_sections.count ? NGSettingsSectionSpacing : 18.0f;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return ceilf([NGTheme regularFont:17].lineHeight) + 32.0f + [self gapBelowRowAtIndexPath:indexPath];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NGSettingsCell *cell = [tableView dequeueReusableCellWithIdentifier:@"item"];
    if (!cell) cell = [[NGSettingsCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"item"];
    NSArray *rows = _sections[indexPath.section];
    NSArray *item = rows[indexPath.row];
    cell.iconView.image = NGSettingsIcon(item[0], @[ item[1] ]);
    cell.titleLabel.text = item[2];
    cell.detailLabel.text = item[3];
    cell.firstInSection = indexPath.row == 0;
    cell.lastInSection = indexPath.row + 1 == (NSInteger)rows.count;
    cell.gapBelow = [self gapBelowRowAtIndexPath:indexPath];
    [cell setNeedsLayout];
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    cell.backgroundColor = [NGTheme blocksBackgroundColor];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    UIViewController *next = nil;
    NSInteger section = indexPath.section, row = indexPath.row;
    if (section == 0) {
        next = NGProfileScreen();
    } else if (section == 1) {
        if (row == 0) {
            for (NGChat *chat in [NGDemoData shared].chats) {
                if (chat.kind == NGChatKindSaved) next = [[NGChatController alloc] initWithChat:chat];
            }
        } else if (row == 1) {
            next = NGRecentCallsScreen();
        } else if (row == 2) {
            next = NGDevicesScreen();
        } else {
            next = NGChatFoldersScreen();
        }
    } else if (section == 2) {
        switch (row) {
            case 0: next = NGNotificationsScreen(); break;
            case 1: next = NGPrivacyScreen(); break;
            case 2: next = NGDataAndStorageScreen(); break;
            case 3: next = NGAppearanceScreen(); break;
            case 4: next = NGPowerSavingScreen(); break;
            default: next = NGLanguageScreen(); break;
        }
    } else {
        next = NGSupportScreen(_sections[section][row][2]);
    }
    if (next) [self.navigationController pushViewController:next animated:YES];
}

@end
