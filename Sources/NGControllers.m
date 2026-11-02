#import "NGControllers.h"
#import "NGChatController.h"
#import "NGTheme.h"
#import "NGViews.h"
#import "NGOriginal.h"
#import "NGTabBarController.h"
#import <QuartzCore/QuartzCore.h>

static void NGPrepareTable(UITableView *table, UIColor *background) {
    table.separatorStyle = UITableViewCellSeparatorStyleNone;
    table.contentInset = UIEdgeInsetsMake(0, 0, NGTabBarHeight, 0);
    table.scrollIndicatorInsets = table.contentInset;
    table.backgroundColor = background;
    table.backgroundView = nil;
    table.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
}

#pragma mark - Chats

@interface NGChatListController () <UITextFieldDelegate>
@end

@implementation NGChatListController {
    NSArray *_rows;
    NSString *_query;
    UIBarButtonItem *_editItem;
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

    _editItem = [NGTheme barButtonWithTitle:@"Изм." bold:NO target:self action:@selector(toggleEditing)];
    self.navigationItem.leftBarButtonItem = _editItem;
    self.navigationItem.rightBarButtonItem = [NGTheme barButtonWithAsset:@"nav_compose" target:self action:@selector(compose)];
}

- (UIView *)searchHeader {
    CGFloat w = self.view.bounds.size.width;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 52)];
    header.backgroundColor = [UIColor whiteColor];
    UIView *field = [[UIView alloc] initWithFrame:CGRectMake(8, 8, w - 16, 36)];
    field.backgroundColor = NGHex(0xe9e9e9);
    field.layer.cornerRadius = 10;
    field.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    UIImageView *icon = [[UIImageView alloc] initWithImage:NGTintedAsset(@"list_search", NGHex(0x8e8e93))];
    icon.frame = CGRectMake(3, 3, 30, 30);
    [field addSubview:icon];
    UITextField *text = [[UITextField alloc] initWithFrame:CGRectMake(32, 0, w - 16 - 40, 36)];
    text.placeholder = @"Поиск";
    text.font = [NGTheme regularFont:17];
    text.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    text.clearButtonMode = UITextFieldViewModeWhileEditing;
    text.returnKeyType = UIReturnKeySearch;
    text.autocorrectionType = UITextAutocorrectionTypeNo;
    text.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    text.delegate = self;
    [text addTarget:self action:@selector(searchChanged:) forControlEvents:UIControlEventEditingChanged];
    [field addSubview:text];
    [header addSubview:field];
    return header;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadRows];
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
    [self reloadRows];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (void)toggleEditing {
    [self setEditing:!self.editing animated:YES];
    [NGTheme setTitle:(self.editing ? @"Готово" : @"Изм.") ofBarButton:_editItem];
    UIButton *button = (UIButton *)_editItem.customView;
    button.titleLabel.font = self.editing ? [NGTheme mediumFont:17] : [NGTheme regularFont:17];
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
        _contacts = [NGDemoData shared].contacts;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [NGTheme disableExtendedLayoutFor:self];
    NGPrepareTable(self.tableView, [UIColor whiteColor]);
    if (self.onSelect) {
        self.title = @"Новое сообщение";
        self.navigationItem.leftBarButtonItem = [NGTheme barButtonWithTitle:@"Отмена" bold:NO target:self action:@selector(cancel)];
    } else {
        self.navigationItem.leftBarButtonItem = [NGTheme barButtonWithTitle:@"Сорт." bold:NO target:nil action:NULL];
        self.navigationItem.rightBarButtonItem = [NGTheme barButtonWithAsset:@"contacts_add" target:nil action:NULL];
    }
}

- (void)cancel {
    [self dismissViewControllerAnimated:YES completion:nil];
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
    self.navigationItem.leftBarButtonItem = [NGTheme barButtonWithTitle:@"Изм." bold:NO target:nil action:NULL];
    self.navigationItem.rightBarButtonItem = [NGTheme barButtonWithAsset:@"settings_phone" target:nil action:NULL];
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

@interface NGSettingsCell : UITableViewCell
@property (nonatomic, readonly) UIImageView *iconView;
@property (nonatomic, readonly) UILabel *titleLabel;
@property (nonatomic, readonly) UILabel *detailLabel;
@property (nonatomic) BOOL hidesSeparator;
@end

@implementation NGSettingsCell {
    UIImageView *_chevron;
    UIView *_separator;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier])) {
        self.backgroundColor = [UIColor whiteColor];
        UIView *bg = [[UIView alloc] initWithFrame:CGRectZero];
        bg.backgroundColor = [UIColor whiteColor];
        self.backgroundView = bg;
        self.selectedBackgroundView = [NGTheme highlightView];
        _iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _titleLabel = [NGTheme labelWithFont:[NGTheme regularFont:17] color:[UIColor blackColor]];
        _detailLabel = [NGTheme labelWithFont:[NGTheme regularFont:17] color:[NGTheme secondaryTextColor]];
        _detailLabel.textAlignment = NSTextAlignmentRight;
        _chevron = [[UIImageView alloc] initWithImage:NGTintedAsset(@"list_disclosure", NGHex(0xbab9be))];
        _separator = [NGTheme separatorView];
        for (UIView *v in @[ _iconView, _titleLabel, _detailLabel, _chevron, _separator ]) {
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
    _iconView.frame = CGRectMake(15, floorf((h - 30) / 2), 30, 30);
    CGSize cs = _chevron.image.size;
    _chevron.frame = CGRectMake(w - 8 - cs.width, floorf((h - cs.height) / 2), cs.width, cs.height);
    CGFloat dw = _detailLabel.text.length ? [NGTheme widthOfText:_detailLabel.text font:_detailLabel.font] : 0;
    _detailLabel.frame = CGRectMake(w - 30 - dw, 0, dw, h);
    _titleLabel.frame = CGRectMake(59, 0, w - 59 - 40 - dw, h);
    CGFloat px = [NGTheme pixel];
    _separator.frame = CGRectMake(59, h - px, w - 59, px);
}

@end

@implementation NGSettingsController {
    NSArray *_rows;
}

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        self.title = @"Настройки";
        // One flat list with spacer rows: plain-style section headers would stick
        // to the top while scrolling, and grouped style on iOS 6 is the old card look.
        NSNull *gap = [NSNull null];
        // PresentationResourcesSettings: colorRed 0xFF453A, colorGreen 0x34C759,
        // colorBlue 0x0a84ff, colorLightBlue 0x32ADE6, colorOrange 0xFF9F0A,
        // colorPurple 0xAF52DE, colorGray 0x8E8E93; tips 0xffcc02.
        _rows = @[
            gap,
            @[ @"settings_saved", NGHex(0x0a84ff), @"Избранное", @"" ],
            @[ @"settings_phone", NGHex(0x34C759), @"Недавние звонки", @"" ],
            @[ @"settings_devices", NGHex(0xFF9F0A), @"Устройства", @"2" ],
            @[ @"settings_folder", NGHex(0x32ADE6), @"Папки с чатами", @"" ],
            gap,
            @[ @"settings_notifications", NGHex(0xFF453A), @"Уведомления и звуки", @"" ],
            @[ @"settings_privacy", NGHex(0x8E8E93), @"Конфиденциальность", @"" ],
            @[ @"settings_data", NGHex(0x34C759), @"Данные и память", @"" ],
            @[ @"settings_appearance", NGHex(0x32ADE6), @"Оформление", @"" ],
            @[ @"settings_power", NGHex(0xFF9F0A), @"Энергосбережение", @"Выкл." ],
            @[ @"settings_language", NGHex(0xAF52DE), @"Язык", @"Русский" ],
            gap,
            @[ @"settings_support", NGHex(0xFF9F0A), @"Задать вопрос", @"" ],
            @[ @"settings_faq", NGHex(0x32ADE6), @"Вопросы о Telegram", @"" ],
            @[ @"settings_tips", NGHex(0xffcc02), @"Возможности Telegram", @"" ],
            gap,
        ];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [NGTheme disableExtendedLayoutFor:self];
    NGPrepareTable(self.tableView, [NGTheme blocksBackgroundColor]);
    self.tableView.tableHeaderView = [self profileHeader];
    self.navigationItem.rightBarButtonItem = [NGTheme barButtonWithTitle:@"Изм." bold:NO target:nil action:NULL];
}

- (UIView *)profileHeader {
    CGFloat w = self.view.bounds.size.width;
    NGUser *me = [NGDemoData shared].me;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 196)];
    header.backgroundColor = [NGTheme blocksBackgroundColor];

    NGAvatarView *avatar = [[NGAvatarView alloc] initWithFrame:CGRectMake(floorf((w - 96) / 2), 16, 96, 96)];
    [avatar configureWithUser:me];
    avatar.showsOnline = NO;
    avatar.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    [header addSubview:avatar];

    UILabel *name = [NGTheme labelWithFont:[NGTheme mediumFont:26] color:[UIColor blackColor]];
    name.text = [me displayName];
    name.textAlignment = NSTextAlignmentCenter;
    name.frame = CGRectMake(0, 122, w, 32);
    name.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [header addSubview:name];

    UILabel *info = [NGTheme labelWithFont:[NGTheme regularFont:16] color:[NGTheme secondaryTextColor]];
    info.text = [NSString stringWithFormat:@"%@ • @%@", me.phone, me.username];
    info.textAlignment = NSTextAlignmentCenter;
    info.frame = CGRectMake(0, 156, w, 20);
    info.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [header addSubview:info];
    return header;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _rows.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return [_rows[indexPath.row] isKindOfClass:[NSNull class]] ? 35 : 44;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    id row = _rows[indexPath.row];
    if ([row isKindOfClass:[NSNull class]]) {
        NGSpacerCell *cell = [tableView dequeueReusableCellWithIdentifier:@"gap"];
        if (!cell) cell = [[NGSpacerCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"gap"];
        return cell;
    }
    NGSettingsCell *cell = [tableView dequeueReusableCellWithIdentifier:@"item"];
    if (!cell) cell = [[NGSettingsCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"item"];
    NSArray *item = row;
    cell.iconView.image = NGSettingsIcon(item[0], @[ item[1] ]);
    cell.titleLabel.text = item[2];
    cell.detailLabel.text = item[3];
    BOOL lastInBlock = indexPath.row + 1 >= (NSInteger)_rows.count || [_rows[indexPath.row + 1] isKindOfClass:[NSNull class]];
    cell.hidesSeparator = lastInBlock;
    [cell setNeedsLayout];
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    BOOL gap = [_rows[indexPath.row] isKindOfClass:[NSNull class]];
    cell.backgroundColor = gap ? [NGTheme blocksBackgroundColor] : [UIColor whiteColor];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row == 1) {
        NGChat *saved = nil;
        for (NGChat *chat in [NGDemoData shared].chats) {
            if (chat.kind == NGChatKindSaved) saved = chat;
        }
        if (saved) [self.navigationController pushViewController:[[NGChatController alloc] initWithChat:saved] animated:YES];
    }
}

@end
