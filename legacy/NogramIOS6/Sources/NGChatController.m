#import "NGChatController.h"
#import "NGTheme.h"
#import "NGViews.h"
#import <QuartzCore/QuartzCore.h>

#pragma mark - Bubble

// A bubble body with an optional tail at its bottom outer corner. The path is
// built for an outgoing bubble (tail on the right) and mirrored for incoming.
@interface NGBubbleView : UIView
@property (nonatomic) BOOL outgoing;
@property (nonatomic) BOOL tail;
@property (nonatomic) BOOL mergedTop;
@property (nonatomic) BOOL mergedBottom;
@property (nonatomic, strong) UIColor *fill;
@end

static const CGFloat NGTailWidth = 6;

@implementation NGBubbleView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.opaque = NO;
        self.backgroundColor = [UIColor clearColor];
        self.contentMode = UIViewContentModeRedraw;
    }
    return self;
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGFloat bw = self.bounds.size.width - NGTailWidth, h = self.bounds.size.height;
    CGFloat R = MIN(16, h / 2), rt = self.mergedTop ? MIN(6, R) : R, rb = self.mergedBottom ? MIN(6, R) : R;

    if (!self.outgoing) {
        CGContextTranslateCTM(ctx, self.bounds.size.width, 0);
        CGContextScaleCTM(ctx, -1, 1);
    }

    CGMutablePathRef p = CGPathCreateMutable();
    CGPathMoveToPoint(p, NULL, R, 0);
    CGPathAddLineToPoint(p, NULL, bw - rt, 0);
    CGPathAddArcToPoint(p, NULL, bw, 0, bw, rt, rt);
    if (self.tail) {
        CGPathAddLineToPoint(p, NULL, bw, h - 12);
        CGPathAddCurveToPoint(p, NULL, bw, h - 4, bw + 2.5f, h - 0.8f, bw + NGTailWidth, h - 0.2f);
        CGPathAddQuadCurveToPoint(p, NULL, bw + 1, h + 0.3f, bw - 8, h);
    } else {
        CGPathAddLineToPoint(p, NULL, bw, h - rb);
        CGPathAddArcToPoint(p, NULL, bw, h, bw - rb, h, rb);
    }
    CGPathAddLineToPoint(p, NULL, R, h);
    CGPathAddArcToPoint(p, NULL, 0, h, 0, h - R, R);
    CGPathAddLineToPoint(p, NULL, 0, R);
    CGPathAddArcToPoint(p, NULL, 0, 0, R, 0, R);
    CGPathCloseSubpath(p);

    CGContextAddPath(ctx, p);
    CGContextSetFillColorWithColor(ctx, self.fill.CGColor);
    CGContextFillPath(ctx);
    CGPathRelease(p);
}

@end

#pragma mark - Message layout

typedef struct {
    CGFloat bodyWidth;
    CGFloat bodyHeight;
    CGFloat textTop;
    CGSize textSize;
} NGBubbleLayout;

static UIFont *NGMessageFont(void) { return [NGTheme regularFont:17]; }
static UIFont *NGTimeFont(void) { return [NGTheme regularFont:12]; }
static UIFont *NGNameFont(void) { return [NGTheme mediumFont:15]; }

// Width of the last line the label will draw, so the time can share it.
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
    return [NGTheme widthOfText:[NGTheme timeString:m.date] font:NGTimeFont()] + (checks ? 19 : 0);
}

static NGBubbleLayout NGLayoutMessage(NGMessage *m, CGFloat maxBodyWidth, BOOL showName, BOOL checks) {
    NGBubbleLayout l;
    CGFloat textMax = maxBodyWidth - 24;
    UIFont *font = NGMessageFont();
    l.textSize = [NGTheme sizeOfText:m.text font:font width:textMax];
    l.textSize.height = MAX(l.textSize.height, ceilf(font.lineHeight));
    l.textTop = showName ? 26 : 6;

    CGFloat status = NGStatusWidth(m, checks);
    CGFloat lastLine = NGLastLineWidth(m.text, font, textMax);
    CGFloat content;
    if (lastLine + 10 + status <= textMax) {
        content = MAX(l.textSize.width, lastLine + 10 + status);
        l.bodyHeight = l.textTop + l.textSize.height + 7;
    } else {
        content = MAX(l.textSize.width, status);
        l.bodyHeight = l.textTop + l.textSize.height + 21;
    }
    if (showName) {
        content = MAX(content, MIN(textMax, [NGTheme widthOfText:[m.author displayName] font:NGNameFont()]));
    }
    l.bodyWidth = content + 24;
    return l;
}

#pragma mark - Message cell

@interface NGMessageCell : UITableViewCell
@property (nonatomic, strong) NGMessage *message;
@property (nonatomic) BOOL mergedTop, mergedBottom, showName, showAvatar, avatarSpace, showChecks;
+ (CGFloat)heightForMessage:(NGMessage *)m width:(CGFloat)width mergedTop:(BOOL)mt mergedBottom:(BOOL)mb showName:(BOOL)name avatarSpace:(BOOL)avatarSpace checks:(BOOL)checks;
- (void)refresh;
@end

static CGFloat NGMaxBodyWidth(CGFloat width, BOOL avatarSpace) {
    return floorf((width - (avatarSpace ? 44 : 0)) * 0.8f) - NGTailWidth;
}

@implementation NGMessageCell {
    NGBubbleView *_bubble;
    UILabel *_text;
    UILabel *_name;
    UILabel *_time;
    NGChecksView *_checks;
    NGAvatarView *_avatar;
}

+ (CGFloat)heightForMessage:(NGMessage *)m width:(CGFloat)width mergedTop:(BOOL)mt mergedBottom:(BOOL)mb showName:(BOOL)name avatarSpace:(BOOL)avatarSpace checks:(BOOL)checks {
    NGBubbleLayout l = NGLayoutMessage(m, NGMaxBodyWidth(width, avatarSpace), name, checks);
    return (mt ? 1 : 4) + l.bodyHeight + (mb ? 1 : 4);
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor clearColor];
        _bubble = [[NGBubbleView alloc] initWithFrame:CGRectZero];
        _text = [NGTheme labelWithFont:NGMessageFont() color:[UIColor blackColor]];
        _text.numberOfLines = 0;
        _text.lineBreakMode = NSLineBreakByWordWrapping;
        _name = [NGTheme labelWithFont:NGNameFont() color:[UIColor blackColor]];
        _time = [NGTheme labelWithFont:NGTimeFont() color:[UIColor grayColor]];
        _checks = [[NGChecksView alloc] initWithFrame:CGRectMake(0, 0, 16, 12)];
        _avatar = [[NGAvatarView alloc] initWithFrame:CGRectMake(0, 0, 36, 36)];
        for (UIView *v in @[ _avatar, _bubble, _name, _text, _time, _checks ]) {
            [self.contentView addSubview:v];
        }
    }
    return self;
}

- (void)refresh {
    NGMessage *m = self.message;
    BOOL out = m.outgoing;
    _bubble.outgoing = out;
    _bubble.tail = !self.mergedBottom;
    _bubble.mergedTop = self.mergedTop;
    _bubble.mergedBottom = self.mergedBottom;
    _bubble.fill = out ? NGHex(0xe1ffc7) : [UIColor whiteColor];
    [_bubble setNeedsDisplay];

    _text.text = m.text;
    _name.hidden = !self.showName;
    _name.text = [m.author displayName];
    _name.textColor = [NGTheme nameColorAtIndex:m.author.colorIndex];
    _time.text = [NGTheme timeString:m.date];
    UIColor *secondary = out ? NGHexA(0x3fa632, 0.85f) : NGHexA(0x525252, 0.6f);
    _time.textColor = secondary;
    _checks.hidden = !self.showChecks;
    _checks.color = secondary;
    _checks.status = m.status;
    _avatar.hidden = !self.showAvatar;
    if (self.showAvatar) [_avatar configureWithUser:m.author];
    _avatar.showsOnline = NO;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width, h = self.contentView.bounds.size.height;
    NGMessage *m = self.message;
    NGBubbleLayout l = NGLayoutMessage(m, NGMaxBodyWidth(w, self.avatarSpace), self.showName, self.showChecks);

    CGFloat top = self.mergedTop ? 1 : 4;
    CGFloat viewWidth = l.bodyWidth + NGTailWidth;
    CGFloat bubbleX = m.outgoing ? w - 4 - viewWidth : (self.avatarSpace ? 44 : 2);
    _bubble.frame = CGRectMake(bubbleX, top, viewWidth, l.bodyHeight);
    CGFloat bodyX = m.outgoing ? bubbleX : bubbleX + NGTailWidth;

    _name.frame = CGRectMake(bodyX + 12, top + 5, l.bodyWidth - 24, 19);
    _text.frame = CGRectMake(bodyX + 12, top + l.textTop, l.textSize.width, l.textSize.height);

    CGFloat statusRight = bodyX + l.bodyWidth - 10;
    CGFloat statusY = top + l.bodyHeight - 20;
    if (self.showChecks) {
        _checks.frame = CGRectMake(statusRight - 16, statusY + 2, 16, 12);
        statusRight -= 19;
    }
    CGFloat tw = [NGTheme widthOfText:_time.text font:_time.font];
    _time.frame = CGRectMake(statusRight - tw, statusY, tw, 15);

    _avatar.frame = CGRectMake(5, h - (self.mergedBottom ? 1 : 4) - 36, 36, 36);
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
        _pill.backgroundColor = NGHexA(0x000000, 0.2f);
        _pill.layer.cornerRadius = 11;
        _label = [NGTheme labelWithFont:[NGTheme mediumFont:13] color:[UIColor whiteColor]];
        _label.textAlignment = NSTextAlignmentCenter;
        [self.contentView addSubview:_pill];
        [self.contentView addSubview:_label];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    CGFloat tw = [NGTheme widthOfText:_label.text font:_label.font] + 18;
    _pill.frame = CGRectMake(floorf((w - tw) / 2), 8, tw, 22);
    _label.frame = _pill.frame;
}

@end

#pragma mark - Controller

@interface NGChatController () <UITableViewDataSource, UITableViewDelegate, UITextViewDelegate>
@end

@implementation NGChatController {
    NGChat *_chat;
    NSMutableArray *_rows;
    UITableView *_table;
    UIView *_panel;
    UIView *_panelLine;
    UIView *_field;
    UITextView *_textView;
    UILabel *_placeholder;
    UIButton *_attach;
    UIButton *_send;
    UIButton *_channelButton;
    UILabel *_titleLabel;
    UILabel *_subtitleLabel;
    CGFloat _keyboardOverlap;
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

    CGSize screen = [UIScreen mainScreen].bounds.size;
    UIImageView *wallpaper = [[UIImageView alloc] initWithFrame:self.view.bounds];
    wallpaper.image = [NGTheme wallpaperImageWithSize:screen];
    wallpaper.contentMode = UIViewContentModeScaleAspectFill;
    wallpaper.clipsToBounds = YES;
    wallpaper.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:wallpaper];

    _table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    _table.backgroundColor = [UIColor clearColor];
    _table.backgroundView = nil;
    _table.separatorStyle = UITableViewCellSeparatorStyleNone;
    _table.dataSource = self;
    _table.delegate = self;
    _table.contentInset = UIEdgeInsetsMake(4, 0, 6, 0);
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

- (void)buildNavigationItem {
    NSArray *stack = self.navigationController.viewControllers;
    NSString *backTitle = @"Назад";
    if (stack.count >= 2) {
        UIViewController *previous = stack[stack.count - 2];
        if (previous.title.length) backTitle = previous.title;
    }
    self.navigationItem.leftBarButtonItem = [NGTheme backButtonWithTitle:backTitle target:self action:@selector(back)];

    UIView *titleView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 180, 44)];
    _titleLabel = [NGTheme labelWithFont:[NGTheme mediumFont:16] color:[UIColor blackColor]];
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    _titleLabel.text = _chat.title;
    _titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _subtitleLabel = [NGTheme labelWithFont:[NGTheme regularFont:13] color:[NGTheme secondaryTextColor]];
    _subtitleLabel.textAlignment = NSTextAlignmentCenter;
    _subtitleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [titleView addSubview:_titleLabel];
    [titleView addSubview:_subtitleLabel];
    if (_chat.kind == NGChatKindSaved) {
        _titleLabel.frame = CGRectMake(0, 11, 180, 22);
        _subtitleLabel.hidden = YES;
    } else {
        _titleLabel.frame = CGRectMake(0, 4, 180, 21);
        _subtitleLabel.frame = CGRectMake(0, 24, 180, 16);
    }
    self.navigationItem.titleView = titleView;
    [self updateSubtitle];

    NGAvatarView *avatar = [[NGAvatarView alloc] initWithFrame:CGRectMake(0, 0, 36, 36)];
    [avatar configureWithChat:_chat];
    avatar.showsOnline = NO;
    UIView *holder = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 36, 36)];
    [holder addSubview:avatar];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:holder];
}

- (void)updateSubtitle {
    _subtitleLabel.text = [_chat statusText];
    BOOL accent = _chat.typing || (_chat.kind == NGChatKindPrivate && _chat.user.online);
    _subtitleLabel.textColor = accent ? [NGTheme accentColor] : [NGTheme secondaryTextColor];
}

- (void)buildPanel {
    _panel = [[UIView alloc] initWithFrame:CGRectZero];
    _panel.backgroundColor = NGHex(0xf7f7f7);
    _panelLine = [NGTheme separatorView];
    _panelLine.backgroundColor = NGHex(0xb2b2b2);
    [_panel addSubview:_panelLine];
    [self.view addSubview:_panel];

    if ([self isChannel]) {
        _channelButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _channelButton.titleLabel.font = [NGTheme regularFont:17];
        [_channelButton setTitleColor:[NGTheme accentColor] forState:UIControlStateNormal];
        [_channelButton setTitleColor:[[NGTheme accentColor] colorWithAlphaComponent:0.4f] forState:UIControlStateHighlighted];
        [_channelButton addTarget:self action:@selector(toggleMute) forControlEvents:UIControlEventTouchUpInside];
        [_panel addSubview:_channelButton];
        [self updateChannelButton];
        return;
    }

    _attach = [UIButton buttonWithType:UIButtonTypeCustom];
    [_attach setImage:[NGTheme icon:NGIconAttach size:28 color:NGHex(0x858e99)] forState:UIControlStateNormal];
    [_panel addSubview:_attach];

    _field = [[UIView alloc] initWithFrame:CGRectZero];
    _field.backgroundColor = [UIColor whiteColor];
    _field.layer.cornerRadius = 17;
    _field.layer.borderWidth = [NGTheme pixel];
    _field.layer.borderColor = NGHex(0xd9dcdf).CGColor;
    _field.clipsToBounds = YES;
    [_panel addSubview:_field];

    _textView = [[UITextView alloc] initWithFrame:CGRectZero];
    _textView.font = [NGTheme regularFont:16];
    _textView.backgroundColor = [UIColor clearColor];
    _textView.delegate = self;
    _textView.scrollEnabled = NO;
    _textView.scrollsToTop = NO;
    [_field addSubview:_textView];

    _placeholder = [NGTheme labelWithFont:[NGTheme regularFont:16] color:NGHex(0x8e8e93)];
    _placeholder.text = @"Сообщение";
    [_field addSubview:_placeholder];

    _send = [UIButton buttonWithType:UIButtonTypeCustom];
    [_send addTarget:self action:@selector(sendTapped) forControlEvents:UIControlEventTouchUpInside];
    [_panel addSubview:_send];
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
    UIImage *image = hasText ? [NGTheme sendButtonImage] : [NGTheme icon:NGIconMic size:28 color:NGHex(0x858e99)];
    [_send setImage:image forState:UIControlStateNormal];
    _placeholder.hidden = _textView.text.length > 0;
}

- (CGFloat)fieldHeight {
    if (!_textView) return 34;
    CGFloat height;
    if ([_textView respondsToSelector:@selector(textContainer)]) {
        height = [_textView sizeThatFits:CGSizeMake(_textView.bounds.size.width, CGFLOAT_MAX)].height;
    } else {
        height = _textView.contentSize.height;
    }
    return MIN(MAX(ceilf(height), 34), 104);
}

- (void)layoutViews {
    CGFloat w = self.view.bounds.size.width, h = self.view.bounds.size.height;
    CGFloat fieldH = [self fieldHeight];
    CGFloat panelH = [self isChannel] ? 45 : fieldH + 11;
    _panel.frame = CGRectMake(0, h - _keyboardOverlap - panelH, w, panelH);
    _panelLine.frame = CGRectMake(0, 0, w, [NGTheme pixel]);
    _table.frame = CGRectMake(0, 0, w, _panel.frame.origin.y);

    if ([self isChannel]) {
        _channelButton.frame = _panel.bounds;
        return;
    }
    _attach.frame = CGRectMake(0, panelH - 45, 44, 45);
    _send.frame = CGRectMake(w - 44, panelH - 45, 44, 45);
    _field.frame = CGRectMake(44, 5, w - 88, fieldH);
    _textView.frame = CGRectMake(4, 0, w - 88 - 8, fieldH);
    _textView.scrollEnabled = fieldH >= 104;
    _placeholder.frame = CGRectMake(12, floorf((34 - 20) / 2), 200, 20);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillChange:) name:UIKeyboardWillChangeFrameNotification object:nil];
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

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _rows.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    NGMessage *m = [self messageAt:indexPath.row];
    if (!m) return 38;
    BOOL mt = NGGroups(m, [self messageAt:indexPath.row - 1]);
    BOOL mb = NGGroups(m, [self messageAt:indexPath.row + 1]);
    BOOL group = [self isGroupIncoming:m];
    return [NGMessageCell heightForMessage:m width:tableView.bounds.size.width mergedTop:mt mergedBottom:mb showName:(group && !mt) avatarSpace:group checks:[self showsChecksFor:m]];
}

- (BOOL)showsChecksFor:(NGMessage *)m {
    return m.outgoing && _chat.kind != NGChatKindSaved && _chat.kind != NGChatKindChannel;
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
    _textView.text = @"";
    [self textViewDidChange:_textView];
    [self appendMessage:[NGMessage messageWithText:text outgoing:YES date:[NSDate date]]];
    NGMessage *sent = [_chat lastMessage];
    sent.status = NGMessageStatusSending;
    _chat.draft = nil;

    NSMutableArray *chats = [NGDemoData shared].chats;
    if (![chats containsObject:_chat]) [chats addObject:_chat];

    if (_chat.kind == NGChatKindSaved) {
        sent.status = NGMessageStatusRead;
        return;
    }
    [self simulateDeliveryOf:sent];
}

- (void)appendMessage:(NGMessage *)message {
    [_chat.messages addObject:message];
    [self buildRows];
    [_table reloadData];
    [self scrollToBottomAnimated:YES];
}

- (void)refreshVisible {
    [_table reloadData];
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
            [strongSelf appendMessage:reply];
            [strongSelf updateSubtitle];
        } else {
            [chat.messages addObject:reply];
            chat.unreadCount += 1;
        }
    });
}

@end
