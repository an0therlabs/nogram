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

@interface NGLoginStepController : UIViewController
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *noticeLabel;
@property (nonatomic, strong) UILabel *errorLabel;
@property (nonatomic, strong) NGProceedButton *proceed;
@property (nonatomic, copy) void (^onLoggedIn)(void);
@property (nonatomic) CGFloat keyboardHeight;
- (CGFloat)layoutContentFromY:(CGFloat)y width:(CGFloat)width;
- (void)showError:(NSString *)error;
@end

@implementation NGLoginStepController

- (void)viewDidLoad {
    [super viewDidLoad];
    [NGTheme disableExtendedLayoutFor:self];
    self.view.backgroundColor = [UIColor whiteColor];
    _titleLabel = [NGTheme labelWithFont:[NGTheme boldFont:28.0f] color:[UIColor blackColor]];
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    _noticeLabel = [NGTheme labelWithFont:[NGTheme regularFont:17.0f] color:[UIColor blackColor]];
    _noticeLabel.textAlignment = NSTextAlignmentCenter;
    _noticeLabel.numberOfLines = 0;
    _errorLabel = [NGTheme labelWithFont:[NGTheme regularFont:15.0f] color:NGHex(0xff3b30)];
    _errorLabel.textAlignment = NSTextAlignmentCenter;
    _errorLabel.numberOfLines = 0;
    _proceed = [[NGProceedButton alloc] initWithFrame:CGRectZero];
    for (UIView *v in @[ _titleLabel, _noticeLabel, _errorLabel, _proceed ]) [self.view addSubview:v];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:animated];
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

- (CGFloat)layoutContentFromY:(CGFloat)y width:(CGFloat)width { return y; }

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width, h = self.view.bounds.size.height;
    CGFloat maxWidth = w - NGLoginInset * 2.0f;
    CGFloat y = _keyboardHeight > 0 ? 16.0f : 44.0f;
    CGSize titleSize = [NGTheme sizeOfText:_titleLabel.text font:_titleLabel.font width:maxWidth];
    _titleLabel.frame = CGRectMake(NGLoginInset, y, maxWidth, titleSize.height);
    y += titleSize.height + 18.0f;
    CGFloat noticeWidth = MIN(274.0f, w - 28.0f);
    CGSize noticeSize = [NGTheme sizeOfText:_noticeLabel.text font:_noticeLabel.font width:noticeWidth];
    _noticeLabel.frame = CGRectMake(floorf((w - noticeWidth) / 2.0f), y, noticeWidth, noticeSize.height);
    y += noticeSize.height + 30.0f;
    y = [self layoutContentFromY:y width:w];
    CGSize errorSize = [NGTheme sizeOfText:_errorLabel.text ?: @"" font:_errorLabel.font width:maxWidth];
    _errorLabel.frame = CGRectMake(NGLoginInset, y + 10.0f, maxWidth, errorSize.height);
    _proceed.frame = CGRectMake(NGLoginInset, h - _keyboardHeight - 50.0f - NGLoginInset, maxWidth, 50.0f);
}

- (void)showError:(NSString *)error {
    _errorLabel.text = error;
    [self.view setNeedsLayout];
    if (error.length) {
        CABasicAnimation *shake = [CABasicAnimation animationWithKeyPath:@"transform.translation.x"];
        shake.fromValue = @(-8);
        shake.toValue = @(8);
        shake.duration = 0.06;
        shake.autoreverses = YES;
        shake.repeatCount = 3;
        [_errorLabel.layer addAnimation:shake forKey:@"shake"];
    }
}

@end

#pragma mark - Code entry

// CodeInputView: one rounded box per digit, the typed digits large.
@interface NGCodeController : NGLoginStepController <UITextFieldDelegate>
@property (nonatomic, copy) NSString *phone;
@property (nonatomic, copy) NSString *phoneCodeHash;
@property (nonatomic, copy) NSString *deliveredVia;
@property (nonatomic) NSInteger codeLength;
@end

@implementation NGCodeController {
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
    UIButton *back = [UIButton buttonWithType:UIButtonTypeCustom];
    back.titleLabel.font = [NGTheme regularFont:17.0f];
    [back setTitle:@"Изменить номер" forState:UIControlStateNormal];
    [back setTitleColor:[NGTheme accentColor] forState:UIControlStateNormal];
    [back setTitleColor:[[NGTheme accentColor] colorWithAlphaComponent:0.4f] forState:UIControlStateHighlighted];
    [back addTarget:self.navigationController action:@selector(popViewControllerAnimated:) forControlEvents:UIControlEventTouchUpInside];
    back.frame = CGRectMake(8, 2, 150, 40);
    back.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    [self.view addSubview:back];
    self.proceed.title = @"Продолжить";
    [self.proceed addTarget:self action:@selector(submit) forControlEvents:UIControlEventTouchUpInside];

    _hidden = [[UITextField alloc] initWithFrame:CGRectZero];
    _hidden.keyboardType = UIKeyboardTypeNumberPad;
    _hidden.delegate = self;
    [_hidden addTarget:self action:@selector(codeChanged) forControlEvents:UIControlEventEditingChanged];
    [self.view addSubview:_hidden];

    NSMutableArray *boxes = [NSMutableArray array], *digits = [NSMutableArray array];
    for (NSInteger i = 0; i < MAX(1, self.codeLength); i++) {
        UIView *box = [[UIView alloc] initWithFrame:CGRectZero];
        box.backgroundColor = NGHex(0xf2f2f7);   // list.itemInputField backgroundColor
        box.layer.cornerRadius = 10.0f;
        box.layer.borderColor = [NGTheme accentColor].CGColor;
        UILabel *digit = [NGTheme labelWithFont:[NGTheme regularFont:24.0f] color:[UIColor blackColor]];
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

- (CGFloat)layoutContentFromY:(CGFloat)y width:(CGFloat)width {
    CGFloat boxW = 40.0f, boxH = 52.0f, spacing = 8.0f;
    NSInteger n = _boxes.count;
    CGFloat total = n * boxW + (n - 1) * spacing;
    CGFloat x = floorf((width - total) / 2.0f);
    for (NSInteger i = 0; i < n; i++) {
        UIView *box = _boxes[i];
        box.frame = CGRectMake(x + i * (boxW + spacing), y, boxW, boxH);
        [_digits[i] setFrame:box.bounds];
    }
    return y + boxH;
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
        [_boxes[i] layer].borderWidth = i == code.length ? 1.5f : 0.0f;
    }
    self.proceed.enabled = code.length == _boxes.count;
    if (code.length == _boxes.count) [self submit];
}

- (void)submit {
    NSString *code = _hidden.text;
    if (code.length == 0 || self.proceed.busy) return;
    self.proceed.busy = YES;
    [self showError:nil];
    [[NGTelegram shared] signIn:self.phone phoneCodeHash:self.phoneCodeHash code:code completion:^(NSDictionary *user, NSString *error) {
        self.proceed.busy = NO;
        if (user) {
            if (self.onLoggedIn) self.onLoggedIn();
            return;
        }
        if ([error isEqualToString:@"PHONE_CODE_INVALID"]) error = @"Неверный код. Попробуйте ещё раз.";
        else if ([error isEqualToString:@"PHONE_CODE_EXPIRED"]) error = @"Срок действия кода истёк. Запросите новый.";
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

@implementation NGPhoneController {
    UIButton *_country;
    UITextField *_codeField;
    UITextField *_numberField;
    UIView *_separator1, *_separator2, *_separator3;
    UILabel *_syncLabel;
    NGSwitch *_syncSwitch;
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
    [self.proceed addTarget:self action:@selector(submit) forControlEvents:UIControlEventTouchUpInside];

    _country = [UIButton buttonWithType:UIButtonTypeCustom];
    _country.titleLabel.font = [NGTheme regularFont:20.0f];
    [_country setTitleColor:[NGTheme accentColor] forState:UIControlStateNormal];
    _country.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    _country.userInteractionEnabled = NO;

    _codeField = [[UITextField alloc] initWithFrame:CGRectZero];
    _codeField.font = [NGTheme regularFont:20.0f];
    _codeField.keyboardType = UIKeyboardTypeNumberPad;
    _codeField.text = @"+7";
    _codeField.delegate = self;
    _codeField.textAlignment = NSTextAlignmentCenter;
    [_codeField addTarget:self action:@selector(fieldsChanged) forControlEvents:UIControlEventEditingChanged];

    _numberField = [[UITextField alloc] initWithFrame:CGRectZero];
    _numberField.font = [NGTheme regularFont:20.0f];
    _numberField.keyboardType = UIKeyboardTypeNumberPad;
    _numberField.delegate = self;
    _numberField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"Номер телефона"
                                                                         attributes:@{ NSForegroundColorAttributeName: NGPlaceholderColor(), NSFontAttributeName: [NGTheme regularFont:20.0f] }];
    [_numberField addTarget:self action:@selector(fieldsChanged) forControlEvents:UIControlEventEditingChanged];

    _separator1 = [NGTheme separatorView];
    _separator2 = [NGTheme separatorView];
    _separator3 = [NGTheme separatorView];

    _syncLabel = [NGTheme labelWithFont:[NGTheme regularFont:17.0f] color:[UIColor blackColor]];
    _syncLabel.text = @"Синхронизировать контакты";
    _syncSwitch = [[NGSwitch alloc] initWithFrame:CGRectZero];
    _syncSwitch.on = YES;

    for (UIView *v in @[ _country, _codeField, _numberField, _separator1, _separator2, _separator3, _syncLabel, _syncSwitch ]) {
        [self.view addSubview:v];
    }
    if (![NGTelegram hasCredentials]) {
        [self showError:@"В NGConfig.h не указаны NG_API_ID и NG_API_HASH. Получите их на my.telegram.org и пересоберите приложение."];
    }
    [self fieldsChanged];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [_numberField becomeFirstResponder];
}

// phoneAndCountryNode: 115pt — the country row, then the code | number row.
- (CGFloat)layoutContentFromY:(CGFloat)y width:(CGFloat)width {
    CGFloat px = [NGTheme pixel];
    CGFloat rowH = 57.0f;
    _separator1.frame = CGRectMake(NGLoginInset, y, width - NGLoginInset * 2.0f, px);
    _country.frame = CGRectMake(NGLoginInset + 14.0f, y, width - NGLoginInset * 2.0f - 14.0f, rowH);
    _separator2.frame = CGRectMake(NGLoginInset, y + rowH, width - NGLoginInset * 2.0f, px);
    _codeField.frame = CGRectMake(NGLoginInset, y + rowH, 70.0f, rowH);
    _separator3.frame = CGRectMake(NGLoginInset + 70.0f, y + rowH + 12.0f, px, rowH - 24.0f);
    _numberField.frame = CGRectMake(NGLoginInset + 84.0f, y + rowH, width - NGLoginInset * 2.0f - 84.0f, rowH);
    y += 115.0f + 14.0f;
    _syncLabel.frame = CGRectMake(NGLoginInset, y, width - NGLoginInset * 2.0f - 60.0f, 31.0f);
    _syncSwitch.frame = CGRectMake(width - NGLoginInset - 51.0f, y, 51.0f, 31.0f);
    return y + 31.0f;
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
    [_country setTitle:NGCountryForCode([self countryCode]) forState:UIControlStateNormal];
    self.proceed.enabled = [NGTelegram hasCredentials] && [self countryCode].length > 0 && _numberField.text.length >= 5;
}

- (void)submit {
    NSString *phone = [[self countryCode] stringByAppendingString:_numberField.text ?: @""];
    self.proceed.busy = YES;
    [self showError:nil];
    [[NGTelegram shared] sendCode:phone completion:^(NSString *hash, NSString *via, NSInteger length, NSString *error) {
        self.proceed.busy = NO;
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
    nav.navigationBarHidden = YES;
    return nav;
}
