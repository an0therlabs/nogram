#import "NGSettingsScreens.h"
#import "NGItemList.h"
#import "NGTheme.h"
#import "NGViews.h"
#import "NGOriginal.h"
#import "NGWallpaper.h"
#import "NGChatController.h"

// PresentationResourcesSettings colours.
#define NGRed NGHex(0xFF453A)
#define NGGreen NGHex(0x34C759)
#define NGBlue NGHex(0x0a84ff)
#define NGLightBlue NGHex(0x32ADE6)
#define NGOrange NGHex(0xFF9F0A)
#define NGPurple NGHex(0xAF52DE)
#define NGViolet NGHex(0x5E5CE6)
#define NGGray NGHex(0x8E8E93)

static NGItemListController *NGList(NSString *title, NSArray *items) {
    return [[NGItemListController alloc] initWithTitle:title items:items];
}

// A row that opens a list of exclusive choices and shows the chosen one as
// its label, as SelectivePrivacySettingsController and the pickers do.
static NGItem *NGChoice(NSString *title, NSString *icon, UIColor *color, NSString *header, NSArray *options, NSUInteger selected, NSArray *(^extra)(void)) {
    NGItem *row = icon ? [NGItem disclosure:title detail:options[selected] icon:icon color:color] : [NGItem disclosure:title detail:options[selected]];
    __weak NGItem *weakRow = row;
    row.destination = ^UIViewController *{
        NSMutableArray *items = [NSMutableArray array];
        if (header.length) [items addObject:[NGItem header:header]];
        for (NSString *option in options) {
            NGItem *check = [NGItem check:option subtitle:nil group:@"choice" selected:[option isEqualToString:weakRow.detail]];
            check.action = ^(NGItem *item) { weakRow.detail = item.title; };
            [items addObject:check];
        }
        if (extra) [items addObjectsFromArray:extra()];
        return NGList(title, items);
    };
    return row;
}

#pragma mark - Shortcuts

UIViewController *NGProfileScreen(void) {
    NGUser *me = [NGDemoData shared].me;
    return NGList(@"Мой профиль", @[
        [NGItem info:@"мобильный" subtitle:me.phone],
        [NGItem info:@"имя пользователя" subtitle:[@"@" stringByAppendingString:me.username]],
        [NGItem info:@"о себе" subtitle:@"Собираю Telegram под iOS 6 в гараже"],
        [NGItem disclosure:@"Изменить" detail:@""],
    ]);
}

UIViewController *NGRecentCallsScreen(void) {
    NGCallsController *calls = [NGCallsController new];
    calls.hidesBottomBarWhenPushed = YES;
    return calls;
}

// RecentSessionsController
UIViewController *NGDevicesScreen(void) {
    NSMutableArray *items = [NSMutableArray array];
    [items addObject:[NGItem header:@"Это устройство"]];
    [items addObject:[NGItem info:@"Nogram iOS 0.5" subtitle:@"iPhone 4, iOS 6.1.3 · Москва, Россия"]];
    NGItem *terminate = [NGItem destructive:@"Завершить другие сеансы"];
    [items addObject:terminate];
    [items addObject:[NGItem footer:@"Выйти на всех устройствах, кроме этого."]];
    [items addObject:[NGItem header:@"Автоматически завершать сеансы"]];
    [items addObject:NGChoice(@"Если сеанс неактивен", nil, nil, @"Если сеанс неактивен", @[ @"1 неделя", @"1 месяц", @"3 месяца", @"6 месяцев", @"1 год" ], 3, nil)];
    [items addObject:[NGItem header:@"Активные сеансы"]];
    NSArray *sessions = @[
        [NGItem info:@"Telegram Desktop 5.6" subtitle:@"Windows 11 · Москва · 14:02"],
        [NGItem info:@"Telegram Web A 10.9" subtitle:@"Chrome, macOS · Москва · вчера"],
    ];
    [items addObjectsFromArray:sessions];
    [items addObject:[NGItem footer:@"Нажмите на сеанс, чтобы его завершить."]];
    NGItemListController *list = NGList(@"Устройства", items);
    __weak NGItemListController *weakList = list;
    terminate.action = ^(NGItem *item) {
        NSMutableArray *rest = [weakList.items mutableCopy];
        [rest removeObjectsInArray:sessions];
        weakList.items = rest;
    };
    return list;
}

// ChatListFilterPresetListController
UIViewController *NGChatFoldersScreen(void) {
    return NGList(@"Папки с чатами", @[
        [NGItem footer:@"Создавайте папки для разных групп чатов и быстро переключайтесь между ними."],
        [NGItem header:@"Папки"],
        [NGItem action:@"Создать новую папку"],
        [NGItem footer:@"Нажмите и удерживайте папку, чтобы изменить порядок или удалить её."],
        [NGItem header:@"Рекомендованные папки"],
        [NGItem info:@"Непрочитанные" subtitle:@"Новые сообщения из всех чатов"],
        [NGItem info:@"Личные" subtitle:@"Сообщения только из личных чатов"],
        [NGItem header:@"Вид"],
        [NGItem toggle:@"Показывать папки слева" on:NO],
    ]);
}

#pragma mark - Notifications

static UIViewController *NGNotificationCategory(NSString *title) {
    return NGList(title, @[
        [NGItem toggle:@"Показывать уведомления" on:YES],
        [NGItem toggle:@"Предпросмотр сообщений" on:YES],
        NGChoice(@"Звук", nil, nil, @"Звуки уведомлений", @[ @"Нота", @"Аккорд", @"Бамбук", @"Колокол", @"Попкорн", @"Нет" ], 0, nil),
        [NGItem header:@"Исключения"],
        [NGItem action:@"Добавить исключение"],
    ]);
}

// NotificationsAndSoundsController: notificationsAndSoundsEntries
UIViewController *NGNotificationsScreen(void) {
    NGItem *(^category)(NSString *, NSString *, UIColor *) = ^NGItem *(NSString *title, NSString *icon, UIColor *color) {
        NGItem *item = [NGItem disclosure:title detail:@"Вкл." icon:icon color:color];
        item.destination = ^UIViewController *{ return NGNotificationCategory(title); };
        return item;
    };
    return NGList(@"Уведомления и звуки", @[
        [NGItem header:@"Уведомления о сообщениях"],
        category(@"Личные чаты", @"settings_member", NGBlue),
        category(@"Группы", @"settings_group", NGGreen),
        category(@"Каналы", @"settings_channel", NGOrange),
        category(@"Истории", @"settings_stories", NGViolet),
        category(@"Реакции", @"settings_reactions", NGHex(0xFF2D55)),
        [NGItem header:@"В приложении"],
        [NGItem toggle:@"Звук" on:YES],
        [NGItem toggle:@"Вибрация" on:YES],
        [NGItem toggle:@"Предпросмотр сообщений" on:YES],
        [NGItem toggle:@"Имена на экране блокировки" on:YES],
        [NGItem footer:@"Показывать имена отправителей и названия групп в уведомлениях на заблокированном экране."],
        [NGItem header:@"Счётчик на иконке"],
        [NGItem toggle:@"Включая каналы" on:NO],
        [NGItem toggle:@"Считать сообщения" on:YES],
        [NGItem footer:@"Выключите, чтобы счётчик показывал количество непрочитанных чатов, а не сообщений."],
        [NGItem toggle:@"Новые контакты" on:YES],
        [NGItem footer:@"Получать уведомления, когда ваши контакты присоединяются к Telegram."],
        [NGItem destructive:@"Сбросить все уведомления"],
        [NGItem footer:@"Отменить все пользовательские настройки уведомлений для контактов и групп."],
    ]);
}

#pragma mark - Privacy

static NGItem *NGPrivacyRow(NSString *title, NSString *question, NSUInteger selected) {
    NSArray *options = @[ @"Все", @"Мои контакты", @"Никто" ];
    return NGChoice(title, nil, nil, question, options, selected, ^NSArray *{
        return @[
            [NGItem footer:@"Можно добавить пользователей или целые группы в исключения."],
            [NGItem header:@"Исключения"],
            [NGItem disclosure:@"Всегда разрешать" detail:@"Добавить"],
            [NGItem disclosure:@"Всегда запрещать" detail:@"Добавить"],
        ];
    });
}

// PrivacyAndSecurityController: privacyAndSecurityControllerEntries
UIViewController *NGPrivacyScreen(void) {
    return NGList(@"Конфиденциальность", @[
        [NGItem disclosure:@"Чёрный список" detail:@"3" icon:@"settings_block" color:NGRed],
        [NGItem disclosure:@"Код-пароль" detail:@"Выкл." icon:@"settings_faceid" color:NGGreen],
        [NGItem disclosure:@"Облачный пароль" detail:@"Вкл." icon:@"settings_privacy" color:NGOrange],
        NGChoice(@"Автоудаление сообщений", @"settings_timer", NGPurple, @"Автоудаление сообщений", @[ @"Выкл.", @"1 день", @"1 неделя", @"1 месяц" ], 0, nil),
        [NGItem footer:@"Автоматически удалять сообщения для всех участников во всех новых чатах, которые вы начнёте."],
        [NGItem disclosure:@"Почта для входа" detail:@"" icon:@"settings_email" color:NGViolet],
        [NGItem footer:@"Эта почта используется для входа в аккаунт вместо SMS-кода."],
        [NGItem header:@"Конфиденциальность"],
        NGPrivacyRow(@"Номер телефона", @"Кто видит мой номер телефона", 1),
        NGPrivacyRow(@"Время захода", @"Кто видит время моего последнего входа", 0),
        NGPrivacyRow(@"Фотографии профиля", @"Кто видит мои фотографии", 0),
        NGPrivacyRow(@"О себе", @"Кто видит информацию о себе", 0),
        NGPrivacyRow(@"Подарки", @"Кто может видеть мои подарки", 0),
        NGPrivacyRow(@"Дата рождения", @"Кто видит мою дату рождения", 1),
        NGPrivacyRow(@"Пересылка сообщений", @"Кто может ссылаться на мой аккаунт", 0),
        NGPrivacyRow(@"Звонки", @"Кто может мне звонить", 0),
        NGPrivacyRow(@"Голосовые сообщения", @"Кто может отправлять голосовые", 0),
        NGPrivacyRow(@"Сообщения", @"Кто может мне писать", 0),
        NGPrivacyRow(@"Приглашения", @"Кто может приглашать меня в группы", 0),
        [NGItem header:@"Удалить мой аккаунт"],
        NGChoice(@"Если я не захожу", nil, nil, @"Удалить мой аккаунт", @[ @"1 месяц", @"3 месяца", @"6 месяцев", @"1 год" ], 2, nil),
        [NGItem footer:@"Если вы ни разу не загрузите Telegram за это время, аккаунт будет удалён вместе со всеми сообщениями и контактами."],
        [NGItem disclosure:@"Управление данными" detail:@""],
        [NGItem footer:@"Выберите, какие данные хранить в облаке для удобства использования Telegram."],
        NGChoice(@"Открывать ссылки в", nil, nil, @"Открывать ссылки в", @[ @"Telegram", @"Safari" ], 0, nil),
    ]);
}

#pragma mark - Data and storage

// DataAndStorageSettingsController: dataAndStorageControllerEntries
UIViewController *NGDataAndStorageScreen(void) {
    NGItem *reset = [NGItem action:@"Сбросить настройки автозагрузки"];
    reset.disabled = YES;
    NGItem *(^autoSave)(NSString *, NSString *, UIColor *) = ^NGItem *(NSString *title, NSString *icon, UIColor *color) {
        return NGChoice(title, icon, color, title, @[ @"Выкл.", @"Только фото", @"Фото и видео" ], 0, nil);
    };
    NGItem *(^autoDownload)(NSString *, NSString *, UIColor *) = ^NGItem *(NSString *title, NSString *icon, UIColor *color) {
        NGItem *item = [NGItem disclosure:title detail:@"Вкл." icon:icon color:color];
        item.destination = ^UIViewController *{
            return NGList(title, @[
                [NGItem toggle:@"Автозагрузка медиа" on:YES],
                [NGItem header:@"Типы медиа"],
                [NGItem toggle:@"Фото" on:YES],
                [NGItem toggle:@"Видео" on:YES],
                [NGItem toggle:@"Файлы" on:NO],
                [NGItem header:@"Объём данных"],
                [NGItem slider:0.5f],
            ]);
        };
        return item;
    };
    return NGList(@"Данные и память", @[
        [NGItem disclosure:@"Использование памяти" detail:@"1,2 ГБ" icon:@"settings_pie" color:NGOrange],
        [NGItem disclosure:@"Использование трафика" detail:@"356 МБ" icon:@"settings_stats" color:NGPurple],
        [NGItem header:@"Автозагрузка медиа"],
        autoDownload(@"Через сотовую сеть", @"settings_cellular", NGGreen),
        autoDownload(@"Через Wi-Fi", @"settings_wifi", NGBlue),
        reset,
        [NGItem header:@"Сохранять в галерею"],
        autoSave(@"Личные чаты", @"settings_member", NGBlue),
        autoSave(@"Группы", @"settings_group", NGGreen),
        autoSave(@"Каналы", @"settings_channel", NGOrange),
        [NGItem footer:@"Автоматически сохранять в галерею все новые фото и видео из этих чатов."],
        [NGItem toggle:@"Экономия трафика в звонках" on:NO],
        [NGItem footer:@"Звонки будут использовать меньше трафика, но качество звука может ухудшиться."],
        [NGItem header:@"Другое"],
        [NGItem toggle:@"Сохранять отредактированные фото" on:YES],
        [NGItem toggle:@"Пауза музыки при записи" on:YES],
        [NGItem toggle:@"Поднести к уху" on:YES],
        [NGItem footer:@"Поднесите телефон к уху, чтобы прослушать или записать голосовое сообщение."],
        [NGItem header:@"Тип соединения"],
        NGChoice(@"Прокси", nil, nil, @"Прокси", @[ @"Выкл.", @"SOCKS5", @"MTProxy" ], 0, nil),
    ]);
}

#pragma mark - Appearance

// ThemeSettingsChatPreviewItem: two bubbles over the chat wallpaper.
static UIView *NGChatPreview(void) {
    UIView *preview = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 288, 150)];
    NGWallpaperView *wallpaper = [[NGWallpaperView alloc] initWithFrame:preview.bounds];
    wallpaper.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [preview addSubview:wallpaper];
    NSArray *lines = @[ @[ @NO, @"Доброе утро! 👋" ], @[ @NO, @"Ты в курсе, который час в Токио?" ], @[ @YES, @"Да, там уже вечер 😉" ] ];
    CGFloat y = 12.0f;
    for (NSArray *line in lines) {
        BOOL outgoing = [line[0] boolValue];
        NSString *text = line[1];
        UIFont *font = [NGTheme regularFont:17.0f];
        CGSize size = [NGTheme sizeOfText:text font:font width:200.0f];
        CGFloat bw = size.width + 6.0f + 22.0f, bh = MAX(35.0f, size.height + 12.0f);
        UIImageView *bubble = [[UIImageView alloc] initWithImage:NGMessageBubbleImage(16.0f, 8.0f, !outgoing, outgoing ? NGHex(0xe1ffc7) : [UIColor whiteColor], NGBubbleNeighborsNone)];
        bubble.autoresizingMask = outgoing ? UIViewAutoresizingFlexibleLeftMargin : UIViewAutoresizingFlexibleRightMargin;
        CGFloat x = outgoing ? preview.bounds.size.width - 3.0f - bw : 3.0f;
        bubble.frame = CGRectInset(CGRectMake(x, y, bw, bh), -1.0f, -1.0f);
        UILabel *label = [NGTheme labelWithFont:font color:[UIColor blackColor]];
        label.text = text;
        label.frame = CGRectMake((outgoing ? 0.0f : 6.0f) + 11.0f + 1.0f, 7.0f, size.width, size.height);
        [bubble addSubview:label];
        [preview addSubview:bubble];
        y += bh + 4.0f;
    }
    return preview;
}

// ThemeSettingsController: themeSettingsControllerEntries
UIViewController *NGAppearanceScreen(void) {
    NGItem *powerSaving = [NGItem disclosure:@"Энергосбережение" detail:@""];
    powerSaving.destination = ^UIViewController *{ return NGPowerSavingScreen(); };
    NGItem *nightMode = NGChoice(@"Ночная тема", nil, nil, @"Ночная тема", @[ @"Отключено", @"Системная", @"По расписанию", @"Автоматически" ], 1, nil);
    return NGList(@"Оформление", @[
        [NGItem header:@"Цветовая тема"],
        [NGItem custom:NGChatPreview()],
        [NGItem disclosure:@"Темы для чатов" detail:@""],
        [NGItem disclosure:@"Обои для чатов" detail:@""],
        [NGItem disclosure:@"Ваш цвет" detail:[NGDemoData shared].me.firstName],
        nightMode,
        NGChoice(@"Размер текста", nil, nil, @"Размер текста", @[ @"Мелкий", @"Стандартный", @"Крупный", @"Очень крупный" ], 1, nil),
        [NGItem disclosure:@"Форма сообщений" detail:@""],
        powerSaving,
        [NGItem disclosure:@"Стикеры и эмодзи" detail:@""],
        [NGItem header:@"Другое"],
        [NGItem toggle:@"Следующее медиа по нажатию" on:YES],
        [NGItem footer:@"Нажимайте у края экрана при просмотре медиа, чтобы перейти к следующему или предыдущему."],
    ]);
}

#pragma mark - Power saving

// EnergySavingSettingsScreen
UIViewController *NGPowerSavingScreen(void) {
    return NGList(@"Энергосбережение", @[
        [NGItem header:@"Режим энергосбережения"],
        [NGItem slider:0.15f],
        [NGItem footer:@"Отключает все ресурсоёмкие процессы, когда заряд батареи ниже 15%."],
        [NGItem header:@"Ресурсоёмкие процессы"],
        [NGItem toggle:@"Автозапуск видео" on:YES],
        [NGItem toggle:@"Автозапуск GIF" on:YES],
        [NGItem toggle:@"Анимированные стикеры" on:YES],
        [NGItem toggle:@"Анимированные эмодзи" on:YES],
        [NGItem toggle:@"Эффекты в интерфейсе" on:YES],
        [NGItem toggle:@"Анимации в чатах" on:YES],
        [NGItem toggle:@"Обновление в фоне" on:YES],
        [NGItem footer:@"Эти процессы будут отключаться автоматически, когда включён режим энергосбережения."],
    ]);
}

#pragma mark - Language

// LocalizationListController: the translate toggle, then the languages,
// each its native name over its English one.
UIViewController *NGLanguageScreen(void) {
    NSMutableArray *items = [NSMutableArray array];
    [items addObject:[NGItem toggle:@"Показывать кнопку «Перевести»" on:NO]];
    [items addObject:[NGItem footer:@"Кнопка «Перевести» появится в меню сообщений на других языках."]];
    [items addObject:[NGItem header:@"Язык интерфейса"]];
    NSArray *languages = @[
        @[ @"Русский", @"Russian" ], @[ @"English", @"English" ], @[ @"Українська", @"Ukrainian" ],
        @[ @"Беларуская", @"Belarusian" ], @[ @"Deutsch", @"German" ], @[ @"Español", @"Spanish" ],
        @[ @"Français", @"French" ], @[ @"Italiano", @"Italian" ], @[ @"Türkçe", @"Turkish" ], @[ @"Oʻzbek", @"Uzbek" ],
    ];
    for (NSArray *language in languages) {
        [items addObject:[NGItem check:language[0] subtitle:language[1] group:@"lang" selected:[language[0] isEqualToString:@"Русский"]]];
    }
    return NGList(@"Язык", items);
}

#pragma mark - Support

UIViewController *NGSupportScreen(NSString *title) {
    return NGList(title, @[
        [NGItem footer:@"В демо нет сети, поэтому этот раздел не открывается."],
    ]);
}
