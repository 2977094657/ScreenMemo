<div align="center">

<img src="logo.png" alt="ScreenMemo Logo" width="120"/>

# ScreenMemo

Intelligent screenshot memo & information management tool

"Trace-free screen, traceable memory"

[![Dart](https://img.shields.io/badge/Dart-3.8.1+-0175C2?logo=dart)](https://dart.dev) [![Android](https://img.shields.io/badge/Android-3DDC84?logo=android)](https://www.android.com) [![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](LICENSE)

A local-first screenshot memory tool: automatic capture, OCR full-text search, plus optional AI summaries/replay.

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

## Project Overview

ScreenMemo is a local-first screenshot memo and retrieval tool. After you grant permission, it automatically captures your screen on Android and makes it searchable with OCR; you can also enable AI summaries when you need them, turning a time range into reviewable notes so you can quickly find what you saw and restore context.

---

## Start Building Your Personal Digital Memory Today

**Why start right now?**
- **Irreversible Knowledge Loss**: As more people use daily data to train their personal AI, every day you don't record is a loss of "understanding you" for your future AI assistant.
- **The Quiet Compound Interest of Time**: Data cannot be rushed. Those who start accumulating digital specimens today will naturally possess an irreplaceable, exclusive memory vault when AI achieves its next breakthrough.
- **Salvaging Your Scattered Digital Self**: Your most precious context is often shattered across various apps and devices—without ScreenMemo to properly collect them, they will eventually fade with time, never to be fully awakened again.

---

## How It Works

1. Screen capture: after user authorization, based on Android 11+ Accessibility screenshot capability (`takeScreenshot`), capture the current foreground app at configured intervals; can be enabled/excluded by app or time range.
2. Local storage: save screenshots to app-private storage, and record metadata (timestamp, foreground app package name, etc.) to a local database (SQLite) to power timeline and filtering. Since recent versions, screenshots/database/cache live under internal `files/output`; logs are written to the app-private external directory `<externalFiles>/output/logs` for easier export/debug; the app migrates older external data on startup.
3. Text extraction (OCR): run OCR on new screenshots (Android ML Kit), extract text and index with the image for full-text search.
4. Indexing & search: build inverted indexes by time/app/keywords; the Search page supports keyword match, time range, and app filters to quickly locate historical screens.
5. AI processing (optional): aggregate multiple screenshots within the same time segment to form “Events” and “Daily Summary”; you can choose and configure different model providers.
6. Privacy & security: screenshots/OCR/index are stored locally by default; AI summaries only make network requests after you enable them. You can pause capture, purge data, and export backups at any time; NSFW preference for sensitive content masking.
7. Space management: compress images and clean up expired data by policy to automatically control disk usage and keep the library size manageable.
8. Deep links: via deep links, jump from Search/Statistics to the image viewer or specific pages to quickly return to the original context.
9. AI request gateway (when AI is enabled): all model calls go through a streaming-first gateway, with automatic fallback to non-streaming to improve multi-provider compatibility.

---

## Flutter Chat Context System (Codex-style)

> Design doc: `docs/CONTEXT_MEMORY.md`

- **Three-layer storage**: UI tail (`ai_messages`) + full transcripts (`ai_messages_full`) + compressed memory (`ai_conversations.summary/tool_memory_json`).
- **Context injection**: each request injects `<conversation_context>` (summary + tool memory) and appends recent tail transcripts as prompt history.
- **Auto compression**: when conversations grow, a rolling summary is generated to reduce repetition/looping.
- **Observability**: estimate tokens (bytes/4) of the last prompt and provide a UI panel to inspect/compress/clear memory.

---

## Screenshots

<table>
  <tr>
    <td align="center" valign="top">
      <img src="assets/screenshots/home-overview.jpg" alt="Home Overview" width="240" loading="lazy" />
      <div align="center"><sub>Home Overview</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/search-semantic-results.jpg" alt="Semantic Search" width="240" loading="lazy" />
      <div align="center"><sub>Semantic Search</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/timeline-replay-generation.jpg" alt="Timeline & Replay Generation" width="240" loading="lazy" />
      <div align="center"><sub>Timeline & Replay Generation</sub></div>
    </td>
  </tr>
  <tr>
    <td align="center" valign="top">
      <img src="assets/screenshots/event-detail.jpg" alt="Event Detail" width="240" loading="lazy" />
      <div align="center"><sub>Event Detail</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/favorites-notes.jpg" alt="Favorites & Notes" width="240" loading="lazy" />
      <div align="center"><sub>Favorites & Notes</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/settings-overview.jpg" alt="Settings Overview" width="240" loading="lazy" />
      <div align="center"><sub>Settings Overview</sub></div>
    </td>
  </tr>
  <tr>
    <td align="center" valign="top">
      <img src="assets/screenshots/storage-analysis.jpg" alt="Storage Analysis" width="240" loading="lazy" />
      <div align="center"><sub>Storage Analysis</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/nsfw-search-results.jpg" alt="NSFW Search Results" width="240" loading="lazy" />
      <div align="center"><sub>NSFW Search Results</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/ai-review-chat.jpg" alt="AI Review Chat" width="240" loading="lazy" />
      <div align="center"><sub>AI Review Chat</sub></div>
    </td>
  </tr>
  <tr>
    <td align="center" valign="top">
      <img src="assets/screenshots/ai-sensitive-content-analysis.jpg" alt="Sensitive Content Analysis" width="240" loading="lazy" />
      <div align="center"><sub>Sensitive Content Analysis</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/ai-tool-calling-report.jpg" alt="AI Tool-Calling Report" width="240" loading="lazy" />
      <div align="center"><sub>AI Tool-Calling Report</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/deep-link-entry.jpg" alt="Deep Link" width="240" loading="lazy" />
      <div align="center"><sub>Deep Link</sub></div>
    </td>
  </tr>
</table>


### Key Features

- Deep links: automatically record browser links and jump back from Search/Stats.
- NSFW masking: auto-mask common adult domains; customizable rules.
- App-specific settings: per-app capture strategy (enable/disable, interval, resolution/compression) with presets for gaming/video/reading.
- Theme & colors: light/dark and seed color switching.
- Summaries: daily and weekly summaries, plus persona articles (streamed output).
- Storage analysis: breakdown for app data, cache, screenshots, and logs.

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
- When importing you can choose “Overwrite Import” or “Merge Import”. Merge keeps existing data and deduplicates the archive before merging, which is useful for stitching multiple backups together.
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

## Automated Release (GitHub Actions)

This project is configured to automatically build and publish to GitHub Releases when a tag is pushed: it will only build when you push a tag (e.g., `v1.0.0`), and will not trigger on regular pushes/commits.

### Release Steps

```bash
git tag v1.0.0
git push origin v1.0.0
```

After pushing, GitHub Actions will automatically build **ABI-split Release APKs** and create a Release with the same name, attaching the artifacts (APKs, `symbols-*.zip`, and optional `mapping-*.txt`).

Version rules: the tag (without the `v` prefix) will be used as `--build-name`, and `github.run_number` as `--build-number`.

### Optional: Configure Production Signature (Recommended)

If you want the Release APKs to be signed with a production keystore (instead of the debug key), add the following Secrets in your repository under `Settings -> Secrets and variables -> Actions`:

- `ANDROID_KEYSTORE_BASE64`: Base64 of the `jks`/`keystore` file
- `ANDROID_KEYSTORE_PASSWORD`: Keystore password
- `ANDROID_KEY_ALIAS`: Key alias
- `ANDROID_KEY_PASSWORD`: Key password

> The workflow uses the built-in `GITHUB_TOKEN` to publish the Release by default; you do not need to provide a personal token.

---

## Desktop Data Merger Tool

Because merging imports on mobile can be slow, ScreenMemo provides a Windows/macOS/Linux desktop data merger tool to efficiently merge multiple exported ZIP backup files.

### Features

- Select multiple exported ZIP backup files
- Choose an output directory (where the merged data will be saved)
- Show merge progress and detailed results
- Full merge of screenshots and databases

### Build executable

**Windows**:
```powershell
flutter build windows -t lib/main_desktop_merger.dart --release
```

**macOS**:
```bash
flutter build macos -t lib/main_desktop_merger.dart --release
```

**Linux**:
```bash
flutter build linux -t lib/main_desktop_merger.dart --release
```

### Output

| Platform | Output directory |
|------|----------|
| Windows | `build/windows/x64/runner/Release/` |
| macOS | `build/macos/Build/Products/Release/` |
| Linux | `build/linux/x64/release/bundle/` |

> The artifact is a folder. On Windows it contains `screen_memo.exe` and required DLLs. Copy the whole folder to run.
---

## Permissions

The app may request the following permissions (depending on features you enable):

| Permission | Purpose | Required |
|-----------|---------|----------|
| Notifications | Foreground service status & reminders | Required (background capture) |
| Accessibility Service | Automatic screenshots (`takeScreenshot`, Android 11+) and foreground detection | Required (auto capture) |
| Usage Stats | Get foreground app (Usage Stats) for tagging/filtering | Required |
| Photos/Media | Save images/videos to system gallery | Optional |
| Exact alarm | Scheduled daily/weekly summary reminders | Optional |

> Note: app data is stored in app-private storage; legacy `READ/WRITE_EXTERNAL_STORAGE` runtime permissions are not required. Permissions are requested when needed and can be revoked anytime in system settings.

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

### i18n Audit (Prevent missing translations/hardcoded regressions)

To avoid introducing new user-visible strings that are not localized, the project provides an audit tool and a test guard:

- **ARB consistency**: all `lib/l10n/*.arb` must have exactly the same keys as the template (`app_en.arb`).
- **Platform localization**: required iOS/Android locale declarations and resources must be present.
- **Hardcoded Flutter UI strings**: baseline mode blocks only **new** hardcoded strings; existing ones are recorded in the baseline and can be reduced over time.

Run check:
```bash
dart run tool/i18n_audit.dart --check
```

Update baseline (use only when it’s truly legacy/intentional):
```bash
dart run tool/i18n_audit.dart --update-baseline
```

Ignore rules (use with care):
- Add `// i18n-ignore` at end of line to ignore that line
- Add `// i18n-ignore-file` anywhere in a file to ignore the whole file

`flutter test` runs `test/i18n_audit_test.dart` to prevent regressions.

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
