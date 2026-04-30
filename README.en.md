<div align="center">

<img src="logo.png" alt="ScreenMemo Logo" width="120"/>

# ScreenMemo

Local-first smart screenshot memo and retrieval for Android: automatic capture, OCR, and AI-assisted search and review.

"Trace-free screen, traceable memory"

[![Dart](https://img.shields.io/badge/Dart-3.8.1+-0175C2?logo=dart)](https://dart.dev) [![Android](https://img.shields.io/badge/Android-3DDC84?logo=android)](https://www.android.com) [![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](LICENSE) [![QQ Group](https://img.shields.io/badge/QQ-ScreenMemo%20640740880-12B7F5?logo=tencentqq&logoColor=white)](https://qm.qq.com/q/ob2NMRDzna) [<img src="https://gh-down-badges.linkof.link/297709457/ScreenMemo" alt="Downloads" />](https://github.com/2977094657/ScreenMemo/releases)

</div>

<p align="center">
  <b>Languages</b>:
  <a href="README.md">简体中文</a> |
  English |
  <a href="README.ja.md">日本語</a> |
  <a href="README.ko.md">한국어</a>
</p>

---

## Project Overview

ScreenMemo is a local-first smart screenshot memo and retrieval tool. It automatically records what appears on your Android screen, then uses OCR and an AI assistant to make it searchable so you can quickly recover clues and restore context later.

### Start Building Your Personal Digital Memory Today

**Why start now?**

- **Irreversible knowledge loss**: As more people begin feeding their personal AI with everyday data, every unrecorded day leaves your future AI assistant with a little less grounding to truly understand you.
- **The quiet compounding power of time**: Data cannot be crammed at the last minute. People who start preserving digital specimens today will naturally own a personal memory vault that others will struggle to catch up with when AI reaches its next leap.
- **Recover your scattered digital self**: Your most valuable context is often fragmented across different apps and devices. Without ScreenMemo to preserve it, much of it will fade with time and become difficult to fully awaken again.

## Screenshots

The screenshots below cover some of the pages people use most often. More details and screens are not shown here, and you are welcome to try the app yourself.

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
      <img src="assets/screenshots/timeline-replay-generation.jpg" alt="Timeline & Replay" width="240" loading="lazy" />
      <div align="center"><sub>Timeline & Replay</sub></div>
    </td>
  </tr>
  <tr>
    <td align="center" valign="top">
      <img src="assets/screenshots/event-detail.jpg" alt="Activity Detail" width="240" loading="lazy" />
      <div align="center"><sub>Activity Detail</sub></div>
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
      <img src="assets/screenshots/daySummary.jpg" alt="Daily Summary" width="240" loading="lazy" />
      <div align="center"><sub>Daily Summary</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/storage-analysis.jpg" alt="Storage Analysis" width="240" loading="lazy" />
      <div align="center"><sub>Storage Analysis</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/ai-review-chat.jpg" alt="AI Review Chat" width="240" loading="lazy" />
      <div align="center"><sub>AI Review Chat</sub></div>
    </td>
  </tr>
  <tr>
    <td align="center" valign="top">
      <img src="assets/screenshots/addAi.jpg" alt="AI Providers" width="240" loading="lazy" />
      <div align="center"><sub>AI Providers</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/prompt.jpg" alt="Prompt Manager" width="240" loading="lazy" />
      <div align="center"><sub>Prompt Manager</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/nsfw-search-results.jpg" alt="NSFW Search Results" width="240" loading="lazy" />
      <div align="center"><sub>NSFW Search Results</sub></div>
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

## Community Chat

<div align="center">
  <table>
    <tr>
      <td align="center" valign="top">
        <a href="https://qm.qq.com/q/ob2NMRDzna">
          <img src="assets/screenshots/qrcode_1774681804122.jpg" alt="QQ Group QR Code" width="320" loading="lazy" />
        </a>
        <div align="center"><sub>QQ Group: 640740880</sub></div>
        <div align="center"><sub><a href="https://qm.qq.com/q/ob2NMRDzna">Join the ScreenMemo group chat</a></sub></div>
      </td>
    </tr>
  </table>
</div>

## FAQ

<details>
<summary>How much storage does it take per month?</summary>

- Example: if your compressed image size is about 50 KB and you capture one screenshot per minute, 30 days is about 43,200 images, or roughly 2.1 GB / month
- Formula: Monthly usage (GB) ≈ `(60 ÷ interval seconds) × 60 × 24 × 30 × image size(KB) ÷ 1024 ÷ 1024`
- To reduce usage: increase the capture interval, enable target-size compression, enable expiration cleanup, and only capture the apps you actually care about
</details>

<details>
<summary>Will my data be uploaded to the cloud?</summary>

- No, not by default. Screenshots, OCR, indexes, statistics, and most settings stay local
- Only the AI features you explicitly enable will send requests to the provider you configured
</details>

<details>
<summary>Which AI providers are supported?</summary>

- Built-in provider types currently include `OpenAI`, `Azure OpenAI`, `Claude`, `Gemini`, and `Custom`
- `Custom` is suitable for OpenAI-compatible self-hosted or third-party endpoints
- Different AI contexts can use different providers and models
</details>

<details>
<summary>Does the main app support iOS or desktop capture?</summary>

- Not today. The main capture pipeline is built around Android Accessibility screenshot APIs
- The desktop target in this repo is a backup-merger tool, not a full cross-platform capture client
</details>

<details>
<summary>How do I back up or migrate data?</summary>

- Use the “Data & backup” section to export a ZIP backup; ScreenMemo scans the scope first, writes a manifest, and shows categorized progress before and during export
- Import supports both overwrite and merge modes; merge tries to deduplicate while preserving existing data
- For very large or multiple backups, use the desktop merger on your computer first, then move the merged result back to Android
- If imported data is missing OCR or index state, use Import Diagnostics to inspect and repair it
- Backups intentionally exclude cache, code cache, temporary thumbnails, and external logs
</details>

<details>
<summary>What is the battery / performance impact?</summary>

- The biggest factors are capture interval, compression strategy, AI rebuild frequency, and how well the device keeps the app alive in the background
- A practical setup is target-size compression, expiration cleanup, and app-specific capture policies so low-value apps are not recorded continuously
</details>

## Quick Start

### Requirements

- **Flutter SDK**: `3.35.7` (current CI-verified version)
- **Dart SDK**: `3.9.2` (bundled with Flutter `3.35.7`; the project constraint is `>=3.8.1`)
- **JDK**: `17` recommended (CI uses `17`; Android source / target compatibility still emits Java 11 bytecode)
- **Android SDK**: the release workflow uses `Platform 36`, `Build-Tools 36.0.0`, and `NDK 27.0.12077973`
- **Current APK build config**: `minSdk 24`, `targetSdk 36`
- **Main feature platform requirement**: automatic capture requires Android 11 (API 30)+
- **IDE**: Android Studio / VS Code with the Flutter plugin

### Install and Run

1. **Clone the repo**
   ```bash
   git clone <repository-url>
   cd screen_memo
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Generate localization code**
   ```bash
   flutter gen-l10n
   ```

4. **Run the app**
   ```bash
   flutter run
   ```

### Test with an Android Emulator

1. Create an Android 11+ AVD in Android Studio **Device Manager**
2. Start the emulator, then run:
   ```bash
   flutter emulators
   flutter devices
   flutter run -d <device_id>
   ```

### Development and Verification Commands

```bash
# Static analysis
flutter analyze

# Flutter tests
flutter test

# i18n audit
dart run tool/i18n_audit.dart --check

# Debug APK
flutter build apk --debug

# Release APKs (split per ABI)
flutter build apk --release --split-per-abi --tree-shake-icons --obfuscate --split-debug-info=build/symbols
```

Android JVM unit tests:

**Windows**
```powershell
cd android
.\gradlew.bat test
```

**macOS / Linux**
```bash
cd android
./gradlew test
```

## Desktop Data Merger

Merging multiple large backup ZIPs on a phone can be slow, so the project includes a separate desktop entry at `lib/main_desktop_merger.dart`.

- Select multiple ZIP backups and an output directory
- Run a structural preflight audit before merge starts
- Merge the backup `output` tree: screenshot files, shard databases, and main metadata while skipping duplicates
- Merge favorites, NSFW flags, and user settings metadata
- Show live progress, warnings, affected apps, and dedupe results
- Pack the merged result back into a new ZIP archive

### Build Commands

**Windows**
```powershell
flutter build windows -t lib/main_desktop_merger.dart --release
```

**macOS**
```bash
flutter build macos -t lib/main_desktop_merger.dart --release
```

**Linux**
```bash
flutter build linux -t lib/main_desktop_merger.dart --release
```

## Permissions

| Permission | Why it is used | Recommendation |
| --- | --- | --- |
| Notifications | Foreground service, export / repair / rebuild progress, daily reminders | Recommended |
| Accessibility service | Automatic capture, activity rebuilding, some background AI flows | Required for core capture |
| Usage stats | Foreground app detection, app-level filtering and statistics | Strongly recommended |
| Installed app visibility | Enumerating installed apps for app selection, filtering, and statistics | Needed for the main app-selection flow |
| Ignore battery optimization / auto-start | Improves background capture and rebuild stability | Strongly recommended |
| Exact alarm | Daily summary reminders | Optional |
| Photos / downloads write access | Saving screenshots, replay videos, or export results | Optional |

## Internationalization

Both the app UI and the README set currently target these 4 languages:

- Simplified Chinese
- English
- Japanese
- Korean

App UI copy is maintained in `lib/l10n/app_*.arb`, while native Android notification, permission, and foreground-service copy lives in `android/app/src/main/res/values*/strings.xml`. Do not hard-code new UI copy directly in Dart widgets or Android XML attributes; add the matching locale resources first, then rerun `flutter gen-l10n`.

Common commands:

```bash
# Generate l10n code
flutter gen-l10n

# Check ARB parity, platform localization, and new hard-coded strings
dart run tool/i18n_audit.dart --check

# Update the audit baseline only after reviewing the exception
dart run tool/i18n_audit.dart --update-baseline
```

`flutter test` automatically runs `test/i18n_audit_test.dart` to prevent localization regressions.

## Sponsor

If this project helps you, sponsorship is welcome. Please include a link you want publicly shown in the payment note, such as a personal homepage, Bilibili profile, or GitHub repository. We will list it in the Sponsor Thanks table in this README.

<div align="center">
  <table>
    <tr>
      <td align="center">
        <a href="https://github.com/LifeArchiveProject/BilibiliHistoryFetcher/raw/master/public/wechat.png">
          <img src="https://github.com/LifeArchiveProject/BilibiliHistoryFetcher/raw/master/public/wechat.png" alt="WeChat Donation QR" width="220">
        </a><br>
        WeChat
      </td>
      <td align="center">
        <a href="https://github.com/LifeArchiveProject/BilibiliHistoryFetcher/raw/master/public/zfb.jpg">
          <img src="https://github.com/LifeArchiveProject/BilibiliHistoryFetcher/raw/master/public/zfb.jpg" alt="Alipay Donation QR" width="220">
        </a><br>
        Alipay
      </td>
    </tr>
  </table>
</div>

### Sponsor Thanks

| Sponsor | Public Link |
| --- | --- |
| None yet | None yet |

## Contributing

Contributions, bug reports, and suggestions are welcome.

1. Fork the repo
2. Create a branch: `git checkout -b feature/your-change`
3. Commit your work: `git commit -m "feat: describe your change"`
4. Push the branch: `git push origin feature/your-change`
5. Open a Pull Request

Before sending a change, it is recommended to run:

- `flutter analyze`
- `flutter test`
- `dart run tool/i18n_audit.dart --check`

## Acknowledgements

- [Flutter](https://flutter.dev)
- [Google ML Kit](https://developers.google.com/ml-kit)
- [SQLite](https://www.sqlite.org/)
- All contributors and dependency maintainers
