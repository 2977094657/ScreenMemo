<div align="center">

<img src="logo.png" alt="ScreenMemo Logo" width="120"/>

# ScreenMemo

Intelligent screenshot memo & information management tool

"Trace-free screen, traceable memory"

[![Dart](https://img.shields.io/badge/Dart-3.8.1+-0175C2?logo=dart)](https://dart.dev) [![Android](https://img.shields.io/badge/Android-3DDC84?logo=android)](https://www.android.com) [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A Flutter-based intelligent screenshot management app to help you efficiently capture, organize, and review important information.

</div>

---

<p align="center">
  <b>Languages</b>:
  <a href="README.md">简体中文</a> |
  English |
  <a href="README.ja.md">日本語</a> |
  <a href="README.ko.md">한국어</a>
</p>

---

## Project Overview & Use Cases

ScreenMemo is a local-first intelligent screenshot memo and retrieval tool: it automatically records the screen on your Android device. With OCR and AI summaries, information becomes searchable and reviewable, helping you quickly retrieve clues and reconstruct context when needed.

What it can do:
- Recover text that appeared across different apps (e.g., article snippets, chat logs, subtitles), even if the original content was withdrawn or removed — searchable in your local history.
- Trace “I’ve seen it somewhere but can’t recall where”: filter by time range and app to quickly locate historical screens.
- Aggregate multiple screenshots within the same time span for AI summaries into “Daily Summary”, helping you review key activities, operations, and takeaways of the day.
- Export/backup your local library to migrate or archive your “second memory”.

Typical scenarios:
- Recall messages or page content that were withdrawn/deleted; retrieve information from windows closed by mistake.
- Search for recurring lines, terms, or key fields across days by keywords, connecting memory fragments with counts and quick review.
- Retrospect important phases (e.g., project work, thesis writing, review/prep), using “Daily Summary” to quickly review daily highlights and reduce organization costs.
- “Memory treasure hunt”: browse past overlooked details or sparks of inspiration to inform creation and decision-making.
---

## Start building your personal digital memory today

Why start recording now?
- Others are already training their personal AI
- Don’t be left behind — every day without recording is lost knowledge for your future AI assistant

AI advantage gap
- Those who start collecting personal data today will have years of advantage when AI becomes more capable

Scattered digital self
- Valuable personal context is trapped across apps and devices — making it hard to leverage without ScreenMemo

---

## How It Works

1. Screen capture: after user authorization, based on Android 11+ Accessibility screenshot capability (`takeScreenshot`), capture the current foreground app at configured intervals; can be enabled/excluded by app or time range.
2. Local storage: save the original image to the app’s private directory, and record metadata (timestamp, foreground app package name, etc.) to a local database (SQLite) to power timeline and filtering.
3. Text extraction (OCR): run OCR on new screenshots, extract text and index with the image; support multilingual character sets for full-text search.
4. Indexing & search: build inverted indexes by time/app/keywords; the Search page supports keyword match, time range, and app filters to quickly locate historical screens.
5. AI processing: aggregate multiple screenshots within the same time segment to form “Events” and “Daily Summary”; you can choose and configure different model providers.
6. Privacy & security: all raw data and indexes are stored locally; you can pause capture, purge data, and export backups at any time; NSFW preference for sensitive content masking.
7. Space management: compress images and clean up expired data by policy to automatically control disk usage and keep the library size manageable.
8. Deep links: via deep links, jump from Search/Statistics to the image viewer or specific pages to quickly return to the original context.

---

## Screenshots

<table>
  <tr>
    <td align="center" valign="top">
      <img src="assets/screenshots/home.jpg" alt="Home" width="240" loading="lazy" />
      <div align="center"><sub>Home</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/search.jpg" alt="Search" width="240" loading="lazy" />
      <div align="center"><sub>Search</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/timeLine.jpg" alt="Timeline" width="240" loading="lazy" />
      <div align="center"><sub>Timeline</sub></div>
    </td>
  </tr>
  <tr>
    <td align="center" valign="top">
      <img src="assets/screenshots/daySummary.jpg" alt="Daily Summary" width="240" loading="lazy" />
      <div align="center"><sub>Daily Summary</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/event.jpg" alt="Events" width="240" loading="lazy" />
      <div align="center"><sub>Events</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/collect.jpg" alt="Favorites" width="240" loading="lazy" />
      <div align="center"><sub>Favorites</sub></div>
    </td>
  </tr>
  <tr>
    <td align="center" valign="top">
      <img src="assets/screenshots/prompt.jpg" alt="Prompt Manager" width="240" loading="lazy" />
      <div align="center"><sub>Prompt Manager</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/addAi.jpg" alt="Add AI" width="240" loading="lazy" />
      <div align="center"><sub>Add AI</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/aiChat.jpg" alt="AI Chat" width="240" loading="lazy" />
      <div align="center"><sub>AI Chat</sub></div>
    </td>
  </tr>
  <tr>
    <td align="center" valign="top">
      <img src="assets/screenshots/setting.jpg" alt="Settings" width="240" loading="lazy" />
      <div align="center"><sub>Settings</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/nsfw.jpg" alt="NSFW Filtering" width="240" loading="lazy" />
      <div align="center"><sub>NSFW Filtering</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/deepLink.jpg" alt="Deep Link" width="240" loading="lazy" />
      <div align="center"><sub>Deep Link</sub></div>
    </td>
  </tr>
</table>


### Key Features

- Deep links: automatically record browser links.
- NSFW masking: automatically mask common adult domains; customizable domain list.
- App-specific settings: per-app capture strategy (whether to capture, capture frequency, resolution/compression, etc.) with optimized presets for game/video/reading apps.

---

## FAQ

<details>
<summary>How much storage does it take per month?</summary>

- Example: if image compression is enabled to ~50 KB per image and one screenshot per minute, 30 days ≈ 43,200 images, about 2.1 GB/month.
- Estimation formula: Monthly usage (GB) ≈ (60 ÷ interval seconds) × 60 × 24 × 30 × single image size (KB) ÷ 1024 ÷ 1024.
- Tips to reduce usage: increase screenshot interval (e.g., ≥ 60s/image), enable image compression, enable expiration cleanup (keep only recent 30/60 days), and exclude unnecessary apps/scenarios.
</details>

<details>
<summary>Will my data be uploaded to the cloud?</summary>

- By default, all data (screenshots, OCR text, indexes, statistics) are stored locally and are not uploaded. You can pause capture, clear data, and export backups at any time.
</details>

<details>
<summary>How to exclude sensitive apps?</summary>

- You can disable capture for specific apps in settings to avoid recording sensitive content.
</details>

<details>
<summary>What is the impact on battery and performance?</summary>

- It mainly relates to the screenshot interval, image size/compression, and foreground recognition frequency. Enabling compression and expiration cleanup is recommended to reduce resource usage.
</details>

<details>
<summary>How to backup/migrate data?</summary>

- Use “Data Import/Export” to export/import assets and database in one click for migration or archiving.
</details>

## Quick Start

### Requirements
- **Flutter SDK**: 3.8.1 or higher
- **Dart SDK**: 3.8.1+
- **Android Studio** / **VS Code** + Flutter plugin
- **Android SDK**:
  - Minimum (minSdkVersion): 21
  - Target (targetSdkVersion): 34
- Platform requirement: automatic screenshot relies on Android 11 (API 30)+ via Accessibility `takeScreenshot`
- **JDK**: 11 or higher

### Installation

1. **Clone the project**
   ```bash
   git clone <repository-url>
   cd screen_memo
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Generate localization files**
   ```bash
   flutter gen-l10n
   ```

4. **Run the app** (development mode)
   ```bash
   # Connect an Android device or start an emulator
   flutter run
   ```

### Development Commands

```bash
# Build Debug APK
flutter build apk --debug

# Install to device
flutter install

# View logs
adb logcat | findstr "ScreenMemo"  # Windows
adb logcat | grep "ScreenMemo"     # Linux/macOS

# Static analysis
flutter analyze
```

---

## Build

Generate ABI-split optimized APKs (minimized size):

```powershell
flutter clean
flutter pub get
flutter build apk --release --split-per-abi --tree-shake-icons --obfuscate --split-debug-info=build/symbols
```

**Artifacts**:
- `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
- `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk`
- `build/app/outputs/flutter-apk/app-x86_64-release.apk`
---

## Permissions

The app needs the following permissions to provide full functionality:

| Permission | Purpose | Required |
|-----------|---------|----------|
| Storage | Save screenshots and data files | Required |
| Notifications | Show service status and notifications | Required |
| Accessibility Service | Automatic screenshots and foreground app detection | Required |
| Usage Stats | Get foreground app (Usage Stats) | Required |

> All permissions are requested on first launch and can be revoked anytime in system settings.

---

## Internationalization

Supported languages:
- Simplified Chinese (default)
- English
- Japanese
- Korean

Add a new language

1. Create a new `.arb` file in `lib/l10n/` (e.g., `app_ja.arb`)
2. Copy the content of `app_en.arb` and translate
3. Run `flutter gen-l10n` to generate code
4. Register the new locale in `LocaleService`

---

## Contributing

Contributions, issues, and feature requests are welcome!

1. Fork this repository
2. Create a feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'feat: add some amazing feature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

Please ensure:
- Code passes `flutter analyze`
- Add necessary tests
- Update relevant documentation

---

## Acknowledgements

Thanks to the following open-source projects:
- [Flutter](https://flutter.dev) - UI framework
- [Google ML Kit](https://developers.google.com/ml-kit) - Text recognition
- [SQLite](https://www.sqlite.org/) - Database engine
- All contributors and maintainers of dependencies
