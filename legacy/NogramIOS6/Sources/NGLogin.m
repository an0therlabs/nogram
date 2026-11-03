#import "NGLogin.h"
#import "NGTelegram.h"
#import "NGTheme.h"
#import "NGItemList.h"
#import <QuartzCore/QuartzCore.h>

// AuthorizationSequencePhoneEntryControllerNode / CodeEntryControllerNode:
// 24pt insets, the title in Font.bold(28), the notice in Font.regular(17),
// the phone block in Font.regular(20) with the country in the accent
// colour, and a 50pt Continue capsule 24pt above the bottom (or keyboard).
static const CGFloat NGLoginInset = 24.0f;

static UIColor *NGPlaceholderColor(void) { return NGHex(0xc8c8ce); }   // list.itemPlaceholderTextColor

#pragma mark - Continue button

// SolidRoundedButtonNode(height: 50, cornerRadius: 25) in the accent colour.
@interface NGProceedButton : UIControl
@property (nonatomic, copy) NSString *title;
@property (nonatomic) BOOL busy;
@end

@implementation NGProceedButton {
    UILabel *_label;
    UIActivityIndicatorView *_spinner;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [NGTheme accentColor];
        self.layer.cornerRadius = 25.0f;
        _label = [NGTheme labelWithFont:[NGTheme semiboldFont:17.0f] color:[UIColor whiteColor]];
        _label.textAlignment = NSTextAlignmentCenter;
        _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
        _spinner.hidesWhenStopped = YES;
        [self addSubview:_label];
        [self addSubview:_spinner];
    }
    return self;
}

- (void)setTitle:(NSString *)title { _title = [title copy]; _label.text = title; }

- (void)setBusy:(BOOL)busy {
    _busy = busy;
    _label.hidden = busy;
    if (busy) [_spinner startAnimating]; else [_spinner stopAnimating];
    self.userInteractionEnabled = !busy;
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    self.alpha = enabled ? 1.0f : 0.5f;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    _label.alpha = highlighted ? 0.6f : 1.0f;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _label.frame = self.bounds;
    _spinner.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
}

@end

#pragma mark - Base

// layoutAuthorizationItems (AuthorizationLayout.swift): every item has a
// spacing before and after with a weight and a cap. Free height is shared by
// weight, capped spacings are fixed and the rest re-shared, three passes; the
// column is then centred vertically in the bounds.
typedef struct { CGFloat height, beforeWeight, beforeMax, afterWeight, afterMax; } NGAuthItem;

static CGFloat NGSolveAuthorizationLayout(const NGAuthItem *items, int n, CGFloat boundsY, CGFloat boundsHeight, CGFloat *outY) {
    CGFloat before[8], after[8];
    BOOL beforeSet[8] = {0}, afterSet[8] = {0};
    CGFloat fixedHeight = 0, totalWeight = 0;
    for (int i = 0; i < n; i++) {
        fixedHeight += items[i].height;
        totalWeight += items[i].beforeWeight + items[i].afterWeight;
    }
    CGFloat remaining = MAX(0.0f, boundsHeight - fixedHeight);
    for (int pass = 0; pass < 3; pass++) {
        if (pass == 0 || pass == 2) {
            for (int i = 0; i < n; i++) {
                if (!beforeSet[i]) {
                    before[i] = items[i].beforeMax == 0 ? 0 : floorf(items[i].beforeWeight * remaining / MAX(totalWeight, 0.0001f));
                    beforeSet[i] = YES;
                }
                if (!afterSet[i]) {
                    after[i] = items[i].afterMax == 0 ? 0 : floorf(items[i].afterWeight * remaining / MAX(totalWeight, 0.0001f));
                    afterSet[i] = YES;
                }
            }
        } else {
            BOOL updated = NO;
            for (int i = 0; i < n; i++) {
                if (items[i].beforeMax != 0 && before[i] > items[i].beforeMax) updated = YES;
                if (items[i].afterMax != 0 && after[i] > items[i].afterMax) updated = YES;
            }
            if (!updated) continue;
            for (int i = 0; i < n; i++) {
                if (items[i].beforeMax != 0) {
                    if (before[i] > items[i].beforeMax) before[i] = items[i].beforeMax; else beforeSet[i] = NO;
                }
                if (items[i].afterMax != 0) {
                    if (after[i] > items[i].afterMax) after[i] = items[i].afterMax; else afterSet[i] = NO;
                }
            }
            fixedHeight = 0; totalWeight = 0;
            for (int i = 0; i < n; i++) {
                fixedHeight += items[i].height;
                if (beforeSet[i]) fixedHeight += before[i]; else if (items[i].beforeMax != 0) totalWeight += items[i].beforeWeight;
                if (afterSet[i]) fixedHeight += after[i]; else if (items[i].afterMax != 0) totalWeight += items[i].afterWeight;
            }
            remaining = MAX(0.0f, boundsHeight - fixedHeight);
        }
    }
    CGFloat total = 0;
    for (int i = 0; i < n; i++) total += before[i] + after[i] + items[i].height;
    CGFloat y = boundsY + floorf((boundsHeight - total) / 2.0f);
    for (int i = 0; i < n; i++) {
        y += before[i];
        outY[i] = y;
        y += items[i].height + after[i];
    }
    return total;
}

static BOOL NGIsNarrowScreen(void) {
    return [UIScreen mainScreen].bounds.size.width <= 320.0f;
}

@interface NGLoginStepController : UIViewController
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *noticeLabel;
@property (nonatomic, strong) NGProceedButton *proceed;
@property (nonatomic, copy) void (^onLoggedIn)(void);
@property (nonatomic) CGFloat keyboardHeight;
@property (nonatomic) BOOL busy;
// Subclass hooks.
- (BOOL)showsNavigationBar;          /* phone: only on a 320pt screen; code: always (back) */
- (BOOL)usesProceedButton;           /* the 50pt capsule (wider than 320pt only) */
- (BOOL)wantsNextItem;               /* "Далее" in the bar where the capsule is hidden */
- (void)setProceedEnabled:(BOOL)enabled;
- (CGFloat)contentHeight;
- (CGFloat)contentSpacingBefore;
- (CGFloat)contentSpacingAfter;
- (void)layoutContentAtY:(CGFloat)y width:(CGFloat)width;
- (void)proceedTapped;
- (void)showError:(NSString *)error;
@end

@implementation NGLoginStepController

- (void)viewDidLoad {
    [super viewDidLoad];
    [NGTheme disableExtendedLayoutFor:self];
    self.view.backgroundColor = [UIColor whiteColor];
    self.navigationItem.backBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Назад" style:UIBarButtonItemStylePlain target:nil action:nil];
    // Font.bold(28) title, Font.regular(17) centred notice.
    _titleLabel = [NGTheme labelWithFont:[NGTheme boldFont:28.0f] color:[UIColor blackColor]];
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    _noticeLabel = [NGTheme labelWithFont:[NGTheme regularFont:17.0f] color:[UIColor blackColor]];
    _noticeLabel.textAlignment = NSTextAlignmentCenter;
    _noticeLabel.numberOfLines = 0;
    _proceed = [[NGProceedButton alloc] initWithFrame:CGRectZero];
    [_proceed addTarget:self action:@selector(proceedTapped) forControlEvents:UIControlEventTouchUpInside];
    for (UIView *v in @[ _titleLabel, _noticeLabel, _proceed ]) [self.view addSubview:v];
}

- (BOOL)showsNavigationBar { return NGIsNarrowScreen(); }
- (BOOL)usesProceedButton { return !NGIsNarrowScreen(); }
- (BOOL)wantsNextItem { return NO; }
- (CGFloat)contentHeight { return 0; }
- (CGFloat)contentSpacingBefore { return 30.0f; }
- (CGFloat)contentSpacingAfter { return 0; }
- (void)layoutContentAtY:(CGFloat)y width:(CGFloat)width {}
- (void)proceedTapped {}

// Narrow screens: Common_Next ("Далее", done style) in the navigation bar,
// a spinner in its place while a request runs (updateNavigationItems).
- (void)updateNavigationItems {
    if (![self usesProceedButton] && [self wantsNextItem]) {
        if (_busy) {
            UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
            [spinner startAnimating];
            self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:spinner];
        } else {
            UIBarButtonItem *next = [[UIBarButtonItem alloc] initWithTitle:@"Далее" style:UIBarButtonItemStyleDone target:self action:@selector(proceedTapped)];
            next.enabled = _proceed.enabled;
            self.navigationItem.rightBarButtonItem = next;
        }
    } else {
        self.navigationItem.rightBarButtonItem = nil;
    }
}

- (void)setBusy:(BOOL)busy {
    _busy = busy;
    _proceed.busy = busy;
    [self updateNavigationItems];
}

- (void)setProceedEnabled:(BOOL)enabled {
    _proceed.enabled = enabled;
    self.navigationItem.rightBarButtonItem.enabled = enabled;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:![self showsNavigationBar] animated:animated];
    [self updateNavigationItems];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillChangeFrameNotification object:nil];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillChangeFrameNotification object:nil];
}

- (void)keyboardChanged:(NSNotification *)note {
    CGRect end = [self.view convertRect:[note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue] fromView:nil];
    _keyboardHeight = MAX(0, self.view.bounds.size.height - end.origin.y);
    NSTimeInterval duration = [note.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    [UIView animateWithDuration:duration animations:^{ [self.view setNeedsLayout]; [self.view layoutIfNeeded]; }];
}

// containerLayoutUpdated: title (spacing titleInset), notice (18), content
// (contentSpacingBefore/After), laid out between the top inset and the
// keyboard less additionalBottomInset (80 above 320pt for the button, else 10).
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width, h = self.view.bounds.size.height;
    BOOL narrow = NGIsNarrowScreen();
    CGFloat maxWidth = MIN(430.0f, w);
    CGFloat top = 0;
    if (![self showsNavigationBar] && [[UIDevice currentDevice].systemVersion floatValue] >= 7.0f) top = 20.0f;   /* status bar */
    CGFloat titleInset = narrow ? 0.0f : 18.0f;
    CGFloat additionalBottom = narrow ? 10.0f : 80.0f;

    BOOL button = [self usesProceedButton];
    _proceed.hidden = !button;
    CGFloat proceedW = maxWidth - NGLoginInset * 2.0f;
    _proceed.frame = CGRectMake(floorf((w - proceedW) / 2.0f), h - _keyboardHeight - 50.0f - NGLoginInset, proceedW, 50.0f);
    if (!button) additionalBottom = narrow ? 10.0f : 20.0f;

    CGSize titleSize = [NGTheme sizeOfText:_titleLabel.text font:_titleLabel.font width:maxWidth];
    CGFloat noticeWidth = MIN(274.0f + 32.0f, maxWidth - 28.0f);
    CGSize noticeSize = [NGTheme sizeOfText:_noticeLabel.text font:_noticeLabel.font width:noticeWidth];
    NGAuthItem items[3] = {
        { titleSize.height, titleInset, titleInset, 0, 0 },
        { noticeSize.height, 18.0f, 18.0f, 0, 0 },
        { [self contentHeight], [self contentSpacingBefore], [self contentSpacingBefore], [self contentSpacingAfter], [self contentSpacingAfter] },
    };
    CGFloat ys[3];
    NGSolveAuthorizationLayout(items, 3, top, h - top - _keyboardHeight - additionalBottom, ys);
    _titleLabel.frame = CGRectMake(floorf((w - titleSize.width) / 2.0f), ys[0], titleSize.width, titleSize.height);
    _noticeLabel.frame = CGRectMake(floorf((w - noticeWidth) / 2.0f), ys[1], noticeWidth, noticeSize.height);
    [self layoutContentAtY:ys[2] width:w];
}

// Errors are alerts, as in AuthorizationSequenceController.
- (void)showError:(NSString *)error {
    if (!error.length) return;
    [[[UIAlertView alloc] initWithTitle:nil message:error delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
}

@end

#pragma mark - Code entry

// CodeInputView: one rounded box per digit, the typed digits large.
@interface NGCodeController : NGLoginStepController <UITextFieldDelegate>
@property (nonatomic, copy) NSString *phone;
@property (nonatomic, copy) NSString *phoneCodeHash;
@property (nonatomic, copy) NSString *deliveredVia;
@property (nonatomic) NSInteger codeLength;
@property (nonatomic) BOOL failed;
@end

static CGFloat NGCodeItemHeight(void) { return NGIsNarrowScreen() ? 44.0f : 51.0f; }

// Font.monospace(floor(13·h/28)); Menlo ships from iOS 7, Courier before.
static UIFont *NGCodeFont(CGFloat itemHeight) {
    CGFloat size = floorf(13.0f * itemHeight / 28.0f);
    return [UIFont fontWithName:@"Menlo-Regular" size:size] ?: [UIFont fontWithName:@"Courier" size:size] ?: [UIFont systemFontOfSize:size];
}

@implementation NGCodeController {
    BOOL _failed;
    UITextField *_hidden;
    NSArray *_boxes;
    NSArray *_digits;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.titleLabel.text = @"Введите код";
    if ([self.deliveredVia isEqualToString:@"app"]) {
        self.noticeLabel.text = @"Мы отправили код в приложение Telegram на другом вашем устройстве.";
    } else if ([self.deliveredVia isEqualToString:@"call"]) {
        self.noticeLabel.text = [NSString stringWithFormat:@"Мы звоним на номер +%@ и продиктуем код.", self.phone];
    } else {
        self.noticeLabel.text = [NSString stringWithFormat:@"Мы отправили SMS с кодом на номер +%@.", self.phone];
    }
    _hidden = [[UITextField alloc] initWithFrame:CGRectZero];
    _hidden.keyboardType = UIKeyboardTypeNumberPad;
    _hidden.delegate = self;
    [_hidden addTarget:self action:@selector(codeChanged) forControlEvents:UIControlEventEditingChanged];
    [self.view addSubview:_hidden];

    NSMutableArray *boxes = [NSMutableArray array], *digits = [NSMutableArray array];
    for (NSInteger i = 0; i < MAX(1, self.codeLength); i++) {
        // CodeInputView.ItemView: no fill, a 1pt+pixel border (plain separator,
        // accent on the focused box, destructive after a wrong code), radius 15.
        UIView *box = [[UIView alloc] initWithFrame:CGRectZero];
        box.layer.cornerRadius = 15.0f;
        box.layer.borderWidth = 1.0f + [NGTheme pixel];
        box.clipsToBounds = YES;
        UILabel *digit = [NGTheme labelWithFont:NGCodeFont(NGCodeItemHeight()) color:[UIColor blackColor]];
        digit.textAlignment = NSTextAlignmentCenter;
        [box addSubview:digit];
        [self.view addSubview:box];
        [boxes addObject:box];
        [digits addObject:digit];
    }
    _boxes = boxes;
    _digits = digits;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:_hidden action:@selector(becomeFirstResponder)];
    [self.view addGestureRecognizer:tap];
    [self codeChanged];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [_hidden becomeFirstResponder];
}

// The code screen has no Continue button: a full code submits itself, and the
// navigation bar carries the back button.
- (BOOL)showsNavigationBar { return YES; }
- (BOOL)usesProceedButton { return NO; }
- (CGFloat)contentHeight { return NGCodeItemHeight(); }
- (CGFloat)contentSpacingBefore { return 30.0f; }
- (CGFloat)contentSpacingAfter { return 104.0f; }

// CodeInputView.update: item height 44 (compact) or 51, width 24·h/28,
// spacing 15, centred.
- (void)layoutContentAtY:(CGFloat)y width:(CGFloat)width {
    CGFloat boxH = NGCodeItemHeight(), boxW = floorf(24.0f * boxH / 28.0f), spacing = 15.0f;
    NSInteger n = _boxes.count;
    CGFloat total = n * boxW + (n - 1) * spacing;
    CGFloat x = floorf((width - total) / 2.0f);
    for (NSInteger i = 0; i < n; i++) {
        UIView *box = _boxes[i];
        box.frame = CGRectMake(x + i * (boxW + spacing), y, boxW, boxH);
        [_digits[i] setFrame:box.bounds];
    }
}

- (void)setFailed:(BOOL)failed {
    _failed = failed;
    [self codeChanged];
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    NSString *updated = [textField.text stringByReplacingCharactersInRange:range withString:string];
    NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    return [updated rangeOfCharacterFromSet:nonDigits].location == NSNotFound && (NSInteger)updated.length <= (NSInteger)_boxes.count;
}

- (void)codeChanged {
    NSString *code = _hidden.text ?: @"";
    for (NSUInteger i = 0; i < _boxes.count; i++) {
        UILabel *digit = _digits[i];
        digit.text = i < code.length ? [code substringWithRange:NSMakeRange(i, 1)] : @"";
        UIColor *border = _failed ? NGHex(0xff3b30) : (i == code.length ? [NGTheme accentColor] : NGHex(0xc8c7cc));
        [_boxes[i] layer].borderColor = border.CGColor;
    }
    if (code.length > 0 && _failed) { _failed = NO; [self codeChanged]; return; }
    if (code.length == _boxes.count) [self submit];
}

- (void)submit {
    NSString *code = _hidden.text;
    if (code.length == 0 || self.busy) return;
    self.busy = YES;
    [[NGTelegram shared] signIn:self.phone phoneCodeHash:self.phoneCodeHash code:code completion:^(NSDictionary *user, NSString *error) {
        self.busy = NO;
        if (user) {
            if (self.onLoggedIn) self.onLoggedIn();
            return;
        }
        if ([error isEqualToString:@"PHONE_CODE_INVALID"]) {
            /* As CodeInputView: the boxes turn red and shake, no alert. */
            self->_hidden.text = @"";
            self.failed = YES;
            CABasicAnimation *shake = [CABasicAnimation animationWithKeyPath:@"transform.translation.x"];
            shake.fromValue = @(-8); shake.toValue = @(8); shake.duration = 0.06; shake.autoreverses = YES; shake.repeatCount = 3;
            for (UIView *box in self->_boxes) [box.layer addAnimation:shake forKey:@"shake"];
            return;
        }
        if ([error isEqualToString:@"PHONE_CODE_EXPIRED"]) error = @"Срок действия кода истёк. Запросите новый.";
        else if ([error isEqualToString:@"SESSION_PASSWORD_NEEDED"]) error = @"У аккаунта включена двухэтапная аутентификация. Вход с облачным паролем этот клиент пока не умеет.";
        self->_hidden.text = @"";
        [self codeChanged];
        [self showError:error];
    }];
}

@end

#pragma mark - Phone entry

@interface NGPhoneController : NGLoginStepController <UITextFieldDelegate>
@end

// countryButtonBackground (136×67, cap 69): a separator along the top, and
// along the bottom 10pt up with a notch pointing down under the code field.
static UIImage *NGCountryBackground(void) {
    CGSize size = CGSizeMake(136.0f, 67.0f);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGFloat lw = [NGTheme pixel], inset = 24.0f, arrow = 10.0f;
    CGContextSetStrokeColorWithColor(c, NGHex(0xc8c7cc).CGColor);
    CGContextSetLineWidth(c, lw);
    CGContextMoveToPoint(c, inset, lw / 2.0f);
    CGContextAddLineToPoint(c, size.width - inset, lw / 2.0f);
    CGContextStrokePath(c);
    CGContextMoveToPoint(c, size.width - inset, size.height - arrow - lw / 2.0f);
    CGContextAddLineToPoint(c, 69.0f, size.height - arrow - lw / 2.0f);
    CGContextAddLineToPoint(c, 69.0f - arrow, size.height - lw / 2.0f);
    CGContextAddLineToPoint(c, 69.0f - arrow - arrow, size.height - arrow - lw / 2.0f);
    CGContextAddLineToPoint(c, inset, size.height - arrow - lw / 2.0f);
    CGContextStrokePath(c);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [image stretchableImageWithLeftCapWidth:69 topCapHeight:1];
}

// phoneInputBackground (96×57, cap 95): the bottom separator and the short
// vertical line between the code and the number.
static UIImage *NGPhoneInputBackground(void) {
    CGSize size = CGSizeMake(96.0f, 57.0f);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGFloat lw = [NGTheme pixel], inset = 24.0f;
    CGContextSetStrokeColorWithColor(c, NGHex(0xc8c7cc).CGColor);
    CGContextSetLineWidth(c, lw);
    CGContextMoveToPoint(c, inset, size.height - lw / 2.0f);
    CGContextAddLineToPoint(c, size.width, size.height - lw / 2.0f);
    CGContextStrokePath(c);
    CGContextMoveToPoint(c, size.width - 2.0f + lw / 2.0f, size.height - 9.0f);
    CGContextAddLineToPoint(c, size.width - 2.0f + lw / 2.0f, 8.0f);
    CGContextStrokePath(c);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [image stretchableImageWithLeftCapWidth:95 topCapHeight:2];
}

@implementation NGPhoneController {
    UIButton *_country;
    UITextField *_codeField;
    UITextField *_numberField;
    UIImageView *_countryArrow;
    UIImageView *_phoneBackground;
}

// The countries most numbers on this client will come from; the code field
// takes any other code.
static NSString *NGCountryForCode(NSString *code) {
    NSDictionary *names = @{ @"7": @"Россия", @"380": @"Украина", @"375": @"Беларусь", @"998": @"Узбекистан", @"1": @"США",
                             @"49": @"Германия", @"44": @"Великобритания", @"90": @"Турция", @"995": @"Грузия", @"374": @"Армения",
                             @"996": @"Киргизия", @"992": @"Таджикистан", @"371": @"Латвия", @"370": @"Литва", @"372": @"Эстония",
                             @"48": @"Польша", @"972": @"Израиль", @"999": @"Тестовые номера" };
    return names[code] ?: (code.length ? @"Неизвестный код страны" : @"Выберите страну");
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.titleLabel.text = @"Ваш телефон";
    self.noticeLabel.text = @"Проверьте код страны и введите свой номер телефона.";
    self.proceed.title = @"Продолжить";

    // countryButton: 67pt, title inset (0, 40, 10, 0), over the stretchable
    // line image with the arrow notch at x 49–69, the disclosure arrow right.
    _country = [UIButton buttonWithType:UIButtonTypeCustom];
    _country.titleLabel.font = [NGTheme regularFont:20.0f];
    _country.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [_country setTitleColor:[NGTheme accentColor] forState:UIControlStateNormal];
    _country.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    _country.contentEdgeInsets = UIEdgeInsetsMake(0, 24.0f + 16.0f, 10.0f, 24.0f + 20.0f);
    [_country setBackgroundImage:NGCountryBackground() forState:UIControlStateNormal];
    _country.adjustsImageWhenHighlighted = NO;
    _country.userInteractionEnabled = NO;
    _countryArrow = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"list_disclosure"]];
    [_country addSubview:_countryArrow];
    _phoneBackground = [[UIImageView alloc] initWithImage:NGPhoneInputBackground()];

    _codeField = [[UITextField alloc] initWithFrame:CGRectZero];
    _codeField.font = [NGTheme regularFont:20.0f];
    _codeField.keyboardType = UIKeyboardTypeNumberPad;
    _codeField.text = @"+7";
    _codeField.delegate = self;
    _codeField.textAlignment = NSTextAlignmentCenter;
    _codeField.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    [_codeField addTarget:self action:@selector(fieldsChanged) forControlEvents:UIControlEventEditingChanged];

    _numberField = [[UITextField alloc] initWithFrame:CGRectZero];
    _numberField.font = [NGTheme regularFont:20.0f];
    _numberField.keyboardType = UIKeyboardTypeNumberPad;
    _numberField.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    _numberField.delegate = self;
    _numberField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"Номер телефона"
                                                                         attributes:@{ NSForegroundColorAttributeName: NGPlaceholderColor(), NSFontAttributeName: [NGTheme regularFont:20.0f] }];
    [_numberField addTarget:self action:@selector(fieldsChanged) forControlEvents:UIControlEventEditingChanged];


    for (UIView *v in @[ _phoneBackground, _country, _codeField, _numberField ]) [self.view addSubview:v];
    if (![NGTelegram hasCredentials]) {
        [self showError:@"В NGConfig.h не указаны NG_API_ID и NG_API_HASH. Получите их на my.telegram.org и пересоберите приложение."];
    }
    [self fieldsChanged];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [_numberField becomeFirstResponder];
}

- (BOOL)wantsNextItem { return YES; }
- (void)proceedTapped { if (self.proceed.enabled && !self.busy) [self submit]; }
- (CGFloat)contentHeight { return 115.0f; }
- (CGFloat)contentSpacingBefore { return 30.0f; }

// PhoneAndCountryNode.layout(), the node 115pt high and the full width.
- (void)layoutContentAtY:(CGFloat)y width:(CGFloat)width {
    CGFloat inset = 24.0f, h = 115.0f;
    _country.frame = CGRectMake(0, y, width, 67.0f);
    CGSize arrow = _countryArrow.image.size;
    _countryArrow.frame = CGRectMake(width - arrow.width - 24.0f - 3.0f, 16.0f + [NGTheme pixel], arrow.width, arrow.height);
    _phoneBackground.frame = CGRectMake(0, y + h - 57.0f, width - inset, 57.0f);
    _codeField.frame = CGRectMake(18.0f, y + h - 58.0f, 71.0f, 57.0f);
    _numberField.frame = CGRectMake(107.0f, y + h - 58.0f, width - 96.0f - 8.0f - 24.0f, 57.0f);
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    NSString *updated = [textField.text stringByReplacingCharactersInRange:range withString:string];
    if (textField == _codeField) {
        NSString *digits = [[updated componentsSeparatedByCharactersInSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]] componentsJoinedByString:@""];
        textField.text = [@"+" stringByAppendingString:[digits substringToIndex:MIN(digits.length, 4)]];
        [self fieldsChanged];
        return NO;
    }
    return updated.length <= 15;
}

- (NSString *)countryCode {
    return [_codeField.text stringByReplacingOccurrencesOfString:@"+" withString:@""];
}

- (void)fieldsChanged {
    // countryFlagAndNameAttributedString: "<flag> <name>". iOS 6 draws only a
    // few flag emoji, so the others show the name alone.
    NSDictionary *flags = @{ @"7": @"🇷🇺", @"1": @"🇺🇸", @"49": @"🇩🇪", @"44": @"🇬🇧", @"33": @"🇫🇷", @"39": @"🇮🇹", @"34": @"🇪🇸" };
    NSString *flag = flags[[self countryCode]];
    NSString *name = NGCountryForCode([self countryCode]);
    [_country setTitle:flag ? [NSString stringWithFormat:@"%@ %@", flag, name] : name forState:UIControlStateNormal];
    [self setProceedEnabled:[NGTelegram hasCredentials] && [self countryCode].length > 0 && _numberField.text.length >= 5];
}

- (void)submit {
    NSString *phone = [[self countryCode] stringByAppendingString:_numberField.text ?: @""];
    self.busy = YES;
    [[NGTelegram shared] sendCode:phone completion:^(NSString *hash, NSString *via, NSInteger length, NSString *error) {
        self.busy = NO;
        if (!hash) {
            if ([error isEqualToString:@"PHONE_NUMBER_INVALID"]) error = @"Неверный номер. Проверьте код страны и номер.";
            else if ([error hasPrefix:@"FLOOD_WAIT_"]) error = @"Слишком много попыток. Попробуйте позже.";
            else if ([error isEqualToString:@"API_ID_INVALID"] || [error isEqualToString:@"CONNECTION_API_ID_INVALID"]) error = @"Сервер не принял api_id/api_hash из NGConfig.h.";
            [self showError:error];
            return;
        }
        NGCodeController *code = [NGCodeController new];
        code.phone = phone;
        code.phoneCodeHash = hash;
        code.deliveredVia = via;
        code.codeLength = length > 0 && length <= 8 ? length : 5;
        code.onLoggedIn = self.onLoggedIn;
        [self.navigationController pushViewController:code animated:YES];
    }];
}

@end

UIViewController *NGLoginScreen(void (^onLoggedIn)(void)) {
    NGPhoneController *phone = [NGPhoneController new];
    phone.onLoggedIn = onLoggedIn;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:phone];
    nav.navigationBarHidden = !NGIsNarrowScreen();
    return nav;
}
