# Nogram для iOS 6

Демоклиент в стиле Telegram на Objective-C, собирается через Theos под armv7 и
запускается на iOS 6+ (iPhone 3GS / 4 / 4S / 5, iPod touch 4/5).

Это **UI-демо на локальных данных**: сети нет, чаты, контакты и звонки
захардкожены в `Sources/NGModel.m`. Отправка работает локально: сообщение
проходит «часики → одна галка → две галки», собеседник «печатает…» и отвечает.

Внешний вид не нарисован заново, а перенесён из Swift-кода этого репо:

| Что | Откуда (Swift) | Здесь |
|---|---|---|
| Пузыри | `ChatMessageBubbleImages.swift` `messageBubbleImage` | `NGOriginal.m` построчно |
| Галочки, часики | `PresentationThemeEssentialGraphics.swift`, `PresentationResourcesChatList.swift` | `NGOriginal.m` |
| Иконки настроек | `PresentationResourcesSettings.swift` `renderSettingsIcon` | `NGOriginal.m` |
| Обои: градиент + анимация фазы | `SoftwareGradientBackground.swift` | `NGWallpaper.m` |
| Обои: узор | `fqv01SQemVIBAAAApND8LDRUhRU.tgv`, soft light 50% | `Resources/wallpaper_pattern*.png` |
| Таббар (капсула, линза) | `TabBarComponent.swift`, `TabBarItemsLayout.swift`, `LiquidLensView.swift` | `NGTabBarController.m` |
| Стекло (капсулы) | `GlassBackgroundComponent.swift` `generateLegacyGlassImage` / `generateLegacyShadowImage` | `NGOriginal.m`, `NGGlass.m` |
| Шапка с пилюлями | `NavigationBarComponent`, `NavigationButtonComponent` | `NGGlass.m` (`NGHeaderView`) |
| Экран настроек | `PeerInfoSettingsItems.swift`, `PeerInfoScreenDisclosureItem.swift`, `PeerInfoHeaderNode.swift`, `cornersImage(glass:)` | `NGControllers.m` |
| Внутренние экраны настроек | `ItemListUI` (glass), `NotificationsAndSoundsController`, `PrivacyAndSecurityController`, `DataAndStorageSettingsController`, `ThemeSettingsController`, `EnergySavingSettingsScreen`, `RecentSessionsController` | `NGItemList.m`, `NGSettingsScreens.m` |
| Профиль собеседника / группы / канала | `PeerInfoHeaderNode`, `PeerInfoHeaderButtonNode`, `PeerInfoProfileItems.infoItems`, `PeerInfoScreenLabeledValueItem`, `PeerInfoPaneContainerNode`, `PeerInfoProfileMusic` | `NGProfile.m` |
| Панель ввода | `ChatTextInputPanelNode.swift` (стеклянный круг 40 + капсула поля) | `NGChatController.m` |
| Кривые отправки | `ChatMessageTransitionNode.swift` (`.bezier`), `Spring.swift` | `NGCurves.m` |
| Метрики сообщений | `ChatMessageItemLayoutConstants.compact`, `ChatMessageDateAndStatusNode` | `NGChatController.m` |
| Иконки | `submodules/TelegramUI/Images.xcassets` | `tools/import_assets.py` → `Resources/` |

## Что есть

- Таббар: Контакты, Звонки, Чаты, Настройки.
- Список чатов: аватарки-градиенты, закреп, mute, бейджи, галочки прочтения,
  черновики, автор в группах, поиск, свайп для удаления, «Новое сообщение».
- Чат: обои, пузыри с хвостиками и склейкой подряд идущих, время и галки
  внутри пузыря, плашки дат, имена и аватарки в группах, канал с кнопкой звука,
  растущее поле ввода, микрофон ↔ кнопка отправки.
- Настройки: профиль и пункты с цветными иконками.

## Сборка

Нужны Theos и SDK из [theos/sdks](https://github.com/theos/sdks).
Берите **iPhoneOS9.3.sdk**: только в нём `.tbd` ещё содержат armv7-символы
(в 10.3 нет `objc_msgSend_stret`, `_Unwind_SjLj_*`, `__modsi3`).

```sh
cp -r sdks/iPhoneOS9.3.sdk $THEOS/sdks/
./tools/fix-sdk-9.3.sh          # один раз: заглушка liblaunch + memcpy/memset
make package FINALPACKAGE=1     # → packages/com.nogram.legacy_*.deb
make package install THEOS_DEVICE_IP=192.168.1.5   # сразу на девайс по SSH
```

Предупреждения `linking in .tbd file ... built for iOS Simulator` безвредны.
Оригинальные иконки перегоняются `tools/import_assets.py` (нужен `pdftocairo` из poppler).
Анимации иконок таббара (`TabChats.json` и др.) подхватятся, если положить в `Resources/`
кадры `anim_tab_<имя>_<n>.png`; без них таббар показывает статичные иконки.

Иконка и launch-картинки (`Default-568h@2x.png` обязателен, иначе на iPhone 5
будет letterbox) генерятся `tools/make_images.py`.

## Ограничения iOS 6, которые учтены в коде

- Никакого `boundingRectWithSize`, TextKit и `NSForegroundColorAttributeName`
  в атрибутах баров: всё через `sizeWithFont:` и `UITextAttribute*`.
- На iOS 6 нет плоских баров: фон баров — свои картинки, кнопки — кастомные view.
- Подписи в ячейках с `backgroundColor = clear`, иначе iOS 6 рисует белый фон.
- Всё, чего нет на iOS 6, вызывается только за проверкой `respondsToSelector:`
  и слинковано weak (`UIFontWeightMedium`).

## Подключить настоящую сеть

Следующий шаг — TDLib (C++, собирается под armv7) через `td_json_client`:
заменить `NGDemoData` на адаптер, который наполняет те же `NGChat`/`NGMessage`.

## Настоящий вход: MTProto

`Sources/mtproto/ngmt.c` — своё ядро MTProto 2.0 на C: TCP (intermediate) или HTTP-транспорт,
генерация ключа авторизации (DH + RSA_PAD, ключи серверов из MtProtoKit), шифрование AES-256-IGE /
SHA-256, сериализация TL, `rpc_result` / `rpc_error` / `msg_container` / `gzip_packed` /
`bad_server_salt`. Криптография — CommonCrypto на iOS, OpenSSL в тесте. Поверх него `NGTelegram`
(ObjC): `initConnection`, `auth.sendCode`, `auth.signIn`, переезд на DC по `*_MIGRATE_X`, ключ хранится
в NSUserDefaults. Экраны входа — `NGLogin.m` (как в AuthorizationUI).

**Перед сборкой** создайте `Sources/NGConfig.local.h` (он в .gitignore) с `#define NG_API_ID …` и `#define NG_API_HASH "…"`
(my.telegram.org → API development tools). Без них экран входа предупредит и не даст продолжить.

Тест ядра на Linux/macOS с настоящим тестовым сервером Telegram (создаёт ключ, ping, `initConnection`):

```sh
cc -O2 -ISources/mtproto tests/ngmt_test.c -lssl -lcrypto -lz -o ngmt_test && ./ngmt_test
# где MTProto по TCP закрыт: NGMT_HTTP=1 ./ngmt_test
```

После входа список чатов — настоящие диалоги аккаунта (`messages.getDialogs`, обновление раз в 10 с),
чат — настоящая история (`messages.getHistory`, раз в 4 с, пока чат открыт), отправка текста
(`messages.sendMessage`) и прочтение (`messages.readHistory` / `channels.readHistory`).
Ответы разбирает `Sources/mtproto/ngtl.c` по таблице конструкторов, сгенерированной из схемы
(`tools/gen_tl_schema.py` → `ngtl_schema.c`; перегенерировать при смене слоя), тест — `tests/ngtl_test.c`.

Пока не умеет: вход с облачным паролем (SRP), обновления в реальном времени (вместо них опрос),
видео/файлы/голосовые (подписью «🎤 Голосовое сообщение»…), звонки — демо.

Фото в чатах и аватарки грузятся через `upload.getFile` с нужного DC (перенос авторизации
`auth.exportAuthorization` → `auth.importAuthorization`), с размытым превью из `photoStrippedSize`
и дисковым кешем; контакты — `contacts.getContacts`. Живой тест на тестовых серверах:
`tests/ngmt_live_test.c` (NG_API_ID/NG_API_HASH из окружения).
