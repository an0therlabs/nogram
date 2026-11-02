# Nogram для iOS 6

Демоклиент в стиле Telegram на Objective-C, собирается через Theos под armv7 и
запускается на iOS 6+ (iPhone 3GS / 4 / 4S / 5, iPod touch 4/5).

Это **UI-демо на локальных данных**: сети нет, чаты, контакты и звонки
захардкожены в `Sources/NGModel.m`. Отправка работает локально: сообщение
проходит «часики → одна галка → две галки», собеседник «печатает…» и отвечает.

Цвета и метрики взяты из дневной темы Telegram в этом репо
(`DefaultDayPresentationTheme.swift`, градиенты аватарок из `AvatarNode.swift`).
Иконки рисуются CoreGraphics в коде, ассетов нет.

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
