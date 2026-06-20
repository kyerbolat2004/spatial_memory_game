# MemoryFly → TestFlight: инструкция

> ⚠️ **Главное ограничение:** собрать и загрузить iOS-приложение можно **только с macOS** (нужен Xcode).
> Ты сейчас на Windows. Варианты:
> 1. **Mac** (свой / рабочий / арендованный «Mac in cloud», например macincloud.com).
> 2. **CI-сервис без своего Mac** — [Codemagic](https://codemagic.io) или GitHub Actions с `macos`-раннером:
>    они сами соберут и зальют в TestFlight по конфигу. Для старта проще всего Codemagic (есть UI).

---

## 0. Что нужно один раз
- **Apple Developer Program** — платный, 99 $/год (https://developer.apple.com/programs/).
- **App Store Connect** доступ (https://appstoreconnect.apple.com).
- Уникальный **Bundle ID**, например `com.yourcompany.memoryfly`.

---

## 1. Настроить Bundle ID и подпись (на Mac, в Xcode)
1. Открой проект: `open ios/Runner.xcworkspace`.
2. Вкладка **Runner → Signing & Capabilities**:
   - **Team** — выбери свою команду разработчика.
   - **Bundle Identifier** — `com.yourcompany.memoryfly` (тот же, что заведёшь в App Store Connect).
   - Галочка **Automatically manage signing** — включить.
3. Проверь **Display Name** = `MemoryFly` (я уже прописал в `ios/Runner/Info.plist`).

## 2. Создать приложение в App Store Connect
1. https://appstoreconnect.apple.com → **My Apps → +** → **New App**.
2. Platform: iOS, Name: **MemoryFly**, язык, тот же **Bundle ID**, SKU (любой, напр. `memoryfly01`).

## 3. Поднять версию/билд (по необходимости)
В `pubspec.yaml` строка `version: 1.0.0+1` → формат `маркетинговая+номер_сборки`.
Каждую новую загрузку увеличивай **номер сборки** (`+2`, `+3`, …), иначе TestFlight отклонит дубликат.

## 4. Собрать релизный IPA (на Mac)
```bash
flutter clean
flutter pub get
flutter build ipa --release
```
Готовый файл: `build/ios/ipa/MemoryFly.ipa`.

## 5. Загрузить в TestFlight
Любой из способов:
- **Transporter** (приложение из Mac App Store): открыть → перетащить `.ipa` → **Deliver**.
- Или из Xcode: **Product → Archive** → **Distribute App → App Store Connect → Upload**.
- Или CLI:
  ```bash
  xcrun altool --upload-app -f build/ios/ipa/MemoryFly.ipa -t ios \
    --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>
  ```

## 6. Раздать тестировщикам
1. App Store Connect → **MemoryFly → TestFlight**.
2. Дождись окончания **Processing** билда (5–30 мин).
3. Заполни **Test Information** (что тестировать, контакт) — нужно для внешних тестеров.
4. **Internal Testing** — добавь тестировщиков (до 100, члены команды) — доступ почти сразу.
   **External Testing** — до 10 000, но требует короткого **Beta App Review**.
5. Тестировщики ставят приложение **TestFlight** из App Store и принимают приглашение.

---

## Вариант без Mac (Codemagic, кратко)
1. Залей проект в Git (GitHub/GitLab).
2. Codemagic → подключи репозиторий → Flutter app.
3. В настройках workflow укажи **iOS code signing** (загрузить сертификат/App Store Connect API key) и
   **Publishing → App Store Connect (TestFlight)**.
4. Запусти сборку — Codemagic соберёт IPA на своём Mac и сам зальёт в TestFlight.

> API-ключ для загрузки: App Store Connect → **Users and Access → Integrations / Keys** → создать ключ
> с ролью **App Manager**, скачать `.p8`, запомнить **Key ID** и **Issuer ID**.
