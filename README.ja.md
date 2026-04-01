<div align="center">

<img src="logo.png" alt="ScreenMemo ロゴ" width="120"/>

# ScreenMemo

ローカルで動作する Android 向けスマートスクリーンショット記録・検索ツール。自動記録した画面を OCR と AI アシスタントで検索・振り返りできます。

「画面に跡は残さず、記憶に刻む」

[![Dart](https://img.shields.io/badge/Dart-3.8.1+-0175C2?logo=dart)](https://dart.dev) [![Android](https://img.shields.io/badge/Android-3DDC84?logo=android)](https://www.android.com) [![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](LICENSE) [![QQ グループ](https://img.shields.io/badge/QQ-%E5%B1%8F%E5%BF%86%20640740880-12B7F5?logo=tencentqq&logoColor=white)](https://qm.qq.com/q/ob2NMRDzna) [<img src="https://gh-down-badges.linkof.link/297709457/ScreenMemo" alt="Downloads" />](https://github.com/2977094657/ScreenMemo/releases)

</div>

<p align="center">
  <b>言語</b>:
  <a href="README.md">简体中文</a> |
  <a href="README.en.md">English</a> |
  日本語 |
  <a href="README.ko.md">한국어</a>
</p>

---

## プロジェクト概要

ScreenMemo はローカルで動作するスマートなスクリーンショット記録・検索ツールです。Android 端末の画面を自動で記録し、OCR と AI アシスタントで情報を検索できる形にして、必要なときに手がかりをすばやくたどり、文脈を取り戻せるようにします。

### 今日から、あなた自身のデジタル記憶を育てよう

**なぜ今すぐ始めるべきなのか？**

- **取り戻せない知識の損失**：日々のデータで個人 AI を育てる人が増えるほど、記録されなかった一日一日が、未来の AI アシスタントがあなたを深く理解するための土台を少しずつ失わせていきます。
- **静かに開いていく時間の複利**：データは短期間で作り込めるものではありません。今この瞬間からデジタル標本を蓄積し始めた人は、AI が次の飛躍を迎える頃には、他の人が簡単には追いつけない専用の記憶庫を自然と手にしています。
- **散らばったデジタルな自分をすくい上げる**：あなたにとって本当に大切な文脈は、さまざまなアプリや端末に断片として散らばっています。ScreenMemo が丁寧に受け止めなければ、それらは時間とともに薄れ、二度と完全な形では呼び戻せなくなります。

## スクリーンショット

以下は利用頻度の高いページの一部です。ここに載せていない画面や細かな機能もまだあるので、ぜひ実際に試してみてください。

<table>
  <tr>
    <td align="center" valign="top">
      <img src="assets/screenshots/home-overview.jpg" alt="ホーム概要" width="240" loading="lazy" />
      <div align="center"><sub>ホーム概要</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/search-semantic-results.jpg" alt="セマンティック検索" width="240" loading="lazy" />
      <div align="center"><sub>セマンティック検索</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/timeline-replay-generation.jpg" alt="タイムラインとリプレイ" width="240" loading="lazy" />
      <div align="center"><sub>タイムラインとリプレイ</sub></div>
    </td>
  </tr>
  <tr>
    <td align="center" valign="top">
      <img src="assets/screenshots/event-detail.jpg" alt="アクティビティ詳細" width="240" loading="lazy" />
      <div align="center"><sub>アクティビティ詳細</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/favorites-notes.jpg" alt="お気に入りとメモ" width="240" loading="lazy" />
      <div align="center"><sub>お気に入りとメモ</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/settings-overview.jpg" alt="設定概要" width="240" loading="lazy" />
      <div align="center"><sub>設定概要</sub></div>
    </td>
  </tr>
  <tr>
    <td align="center" valign="top">
      <img src="assets/screenshots/daySummary.jpg" alt="デイリーサマリー" width="240" loading="lazy" />
      <div align="center"><sub>デイリーサマリー</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/storage-analysis.jpg" alt="ストレージ分析" width="240" loading="lazy" />
      <div align="center"><sub>ストレージ分析</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/ai-review-chat.jpg" alt="AI レビューチャット" width="240" loading="lazy" />
      <div align="center"><sub>AI レビューチャット</sub></div>
    </td>
  </tr>
  <tr>
    <td align="center" valign="top">
      <img src="assets/screenshots/addAi.jpg" alt="AI プロバイダー" width="240" loading="lazy" />
      <div align="center"><sub>AI プロバイダー</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/prompt.jpg" alt="プロンプト管理" width="240" loading="lazy" />
      <div align="center"><sub>プロンプト管理</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/nsfw-search-results.jpg" alt="NSFW 検索結果" width="240" loading="lazy" />
      <div align="center"><sub>NSFW 検索結果</sub></div>
    </td>
  </tr>
  <tr>
    <td align="center" valign="top">
      <img src="assets/screenshots/ai-sensitive-content-analysis.jpg" alt="敏感コンテンツ分析" width="240" loading="lazy" />
      <div align="center"><sub>敏感コンテンツ分析</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/ai-tool-calling-report.jpg" alt="AI ツール呼び出しレポート" width="240" loading="lazy" />
      <div align="center"><sub>AI ツール呼び出しレポート</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/deep-link-entry.jpg" alt="ディープリンク" width="240" loading="lazy" />
      <div align="center"><sub>ディープリンク</sub></div>
    </td>
  </tr>
</table>

## コミュニティチャット

<div align="center">
  <table>
    <tr>
      <td align="center" valign="top">
        <a href="https://qm.qq.com/q/ob2NMRDzna">
          <img src="assets/screenshots/qrcode_1774681804122.jpg" alt="QQ グループ QR コード" width="320" loading="lazy" />
        </a>
        <div align="center"><sub>QQ グループ: 640740880</sub></div>
        <div align="center"><sub><a href="https://qm.qq.com/q/ob2NMRDzna">リンクから「屏忆」グループに参加</a></sub></div>
      </td>
    </tr>
  </table>
</div>

## FAQ

<details>
<summary>月あたりどのくらい容量を使いますか？</summary>

- 例：1 枚あたり約 50 KB、1 分ごとに 1 枚取得する場合、30 日で約 43,200 枚、約 2.1 GB / 月です
- 目安式：月間使用量（GB）≈ `(60 ÷ 間隔秒) × 60 × 24 × 30 × 画像サイズ(KB) ÷ 1024 ÷ 1024`
- 削減策：取得間隔を長くする、目標サイズ圧縮を使う、期限切れ削除を有効にする、必要なアプリだけ取得する
</details>

<details>
<summary>データはクラウドにアップロードされますか？</summary>

- 既定ではされません。スクリーンショット、OCR、索引、統計、ほとんどの設定はローカルに残ります
- AI 機能を明示的に有効化した場合のみ、設定したプロバイダへリクエストが送られます
</details>

<details>
<summary>どの AI プロバイダを利用できますか？</summary>

- 現在の組み込みプロバイダ種別は `OpenAI`、`Azure OpenAI`、`Claude`、`Gemini`、`Custom` です
- `Custom` は OpenAI 互換 API の自前 / サードパーティエンドポイント向けです
- AI の用途ごとに別のプロバイダ / モデルを使えます
</details>

<details>
<summary>iOS やデスクトップで自動取得できますか？</summary>

- 現時点ではできません。メインの取得パイプラインは Android の Accessibility スクリーンショット API を前提にしています
- デスクトップ側はバックアップ統合ツールであり、完全なクロスプラットフォーム取得クライアントではありません
</details>

<details>
<summary>バックアップや移行はどう行いますか？</summary>

- バックアップ機能から ZIP バックアップをエクスポートできます。事前に範囲をスキャンし、manifest を生成してから進捗を表示します
- インポートは上書き / マージの両方に対応し、マージでは既存データを残しつつ重複排除を試みます
- 大きなバックアップや複数バックアップは、先にデスクトップ統合ツールでまとめてから Android に戻すのが実用的です
- OCR や索引が欠けている場合はインポート診断機能で診断と修復ができます
- バックアップには cache、code cache、一時サムネイル、外部ログは含まれません
</details>

<details>
<summary>バッテリーや性能への影響は？</summary>

- 主な要因は取得間隔、圧縮方針、AI 再構築頻度、端末のバックグラウンド維持状況です
- 実運用では目標サイズ圧縮、期限切れ削除、アプリ別取得ポリシーの組み合わせがおすすめです
</details>

## クイックスタート

### 必要環境

- **Flutter SDK**：`3.35.7`（現在 CI で検証している版）
- **Dart SDK**：`3.9.2`（Flutter `3.35.7` に同梱。プロジェクト制約は `>=3.8.1`）
- **JDK**：`17` 推奨（CI は `17` を使用。Android 側の bytecode target は Java 11）
- **Android SDK**：Release ワークフローでは `Platform 36`、`Build-Tools 36.0.0`、`NDK 27.0.12077973` を使用
- **現在の APK ビルド設定**：`minSdk 24`、`targetSdk 36`
- **主要機能のプラットフォーム要件**：自動キャプチャは Android 11（API 30）以上が必要
- **IDE**：Android Studio / VS Code + Flutter プラグイン

### インストールと実行

1. **リポジトリを取得**
   ```bash
   git clone <repository-url>
   cd screen_memo
   ```

2. **依存関係を取得**
   ```bash
   flutter pub get
   ```

3. **多言語コードを生成**
   ```bash
   flutter gen-l10n
   ```

4. **アプリを起動**
   ```bash
   flutter run
   ```

### Android エミュレータで試す

1. Android Studio の **Device Manager** で Android 11+ の AVD を作成
2. エミュレータ起動後、次を実行：
   ```bash
   flutter emulators
   flutter devices
   flutter run -d <device_id>
   ```

### 開発・検証コマンド

```bash
# 静的解析
flutter analyze

# Flutter テスト
flutter test

# i18n 監査
dart run tool/i18n_audit.dart --check

# Debug APK
flutter build apk --debug

# Release APK（ABI 分割）
flutter build apk --release --split-per-abi --tree-shake-icons --obfuscate --split-debug-info=build/symbols
```

Android JVM 単体テスト：

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

## デスクトップ版バックアップ統合ツール

スマホ上で複数の大きなバックアップ ZIP を扱うのは重いため、別エントリ `lib/main_desktop_merger.dart` を用意しています。

- 複数の ZIP バックアップと出力先ディレクトリを選択
- 統合前に構造の事前監査を実行
- バックアップの `output` ツリーを統合し、スクリーンショット、シャード DB、メインメタデータの重複をスキップ
- お気に入り、NSFW フラグ、ユーザー設定などのメタデータも統合
- ライブ進捗、警告、影響アプリ、重複排除結果を表示
- 統合結果を新しい ZIP に再パック

### ビルドコマンド

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

## 権限

| 権限 | 用途 | 推奨 |
| --- | --- | --- |
| 通知 | 前景サービス、エクスポート / 修復 / 再構築進捗、デイリー通知 | 推奨 |
| Accessibility サービス | 自動キャプチャ、アクティビティ再構築、一部バックグラウンド AI フロー | 主要機能に必須 |
| 使用状況アクセス | 前面アプリ判定、アプリ別フィルタ、統計 | 強く推奨 |
| インストール済みアプリ可視性 | アプリ選択、フィルタ、統計のためにインストール済みアプリ一覧を列挙 | メインのアプリ選択フローに必要 |
| バッテリー最適化除外 / 自動起動 | バックグラウンド取得と再構築の安定性向上 | 強く推奨 |
| 正確なアラーム | デイリーサマリー通知 | 任意 |
| 写真 / Downloads への書き込み | スクリーンショット、リプレイ動画、エクスポート結果の保存 | 任意 |

## 国際化

README とアプリ UI は現在以下の 4 言語を対象にしています。

- 簡体字中国語
- English
- 日本語
- 한국어

よく使うコマンド：

```bash
# l10n コード生成
flutter gen-l10n

# ARB 整合性 / プラットフォーム側翻訳 / UI のハードコード回帰を確認
dart run tool/i18n_audit.dart --check

# 例外を確認したうえで baseline を更新
dart run tool/i18n_audit.dart --update-baseline
```

`flutter test` では `test/i18n_audit_test.dart` が自動実行され、多言語回帰を防ぎます。

## スポンサーと支援

このプロジェクトが役に立った場合は、以下の方法で支援できます。支払い時の備考に、公開表示してよいリンク（個人サイト、Bilibili ページ、GitHub リポジトリなど）を記入してください。README の「スポンサー謝辞」表に掲載します。

<div align="center">
  <table>
    <tr>
      <td align="center">
        <a href="https://github.com/LifeArchiveProject/BilibiliHistoryFetcher/raw/master/public/wechat.png">
          <img src="https://github.com/LifeArchiveProject/BilibiliHistoryFetcher/raw/master/public/wechat.png" alt="WeChat 支援 QR" width="220">
        </a><br>
        WeChat 支援
      </td>
      <td align="center">
        <a href="https://github.com/LifeArchiveProject/BilibiliHistoryFetcher/raw/master/public/zfb.jpg">
          <img src="https://github.com/LifeArchiveProject/BilibiliHistoryFetcher/raw/master/public/zfb.jpg" alt="Alipay 支援 QR" width="220">
        </a><br>
        Alipay 支援
      </td>
    </tr>
  </table>
</div>

### スポンサー謝辞

| スポンサー | 公開リンク |
| --- | --- |
| まだありません | まだありません |

## コントリビュート

バグ報告、提案、コード提供を歓迎します。

1. このリポジトリを Fork
2. ブランチ作成：`git checkout -b feature/your-change`
3. 変更をコミット：`git commit -m "feat: describe your change"`
4. ブランチを push：`git push origin feature/your-change`
5. Pull Request を作成

提出前の推奨コマンド：

- `flutter analyze`
- `flutter test`
- `dart run tool/i18n_audit.dart --check`

## 謝辞

- [Flutter](https://flutter.dev)
- [Google ML Kit](https://developers.google.com/ml-kit)
- [SQLite](https://www.sqlite.org/)
- すべてのコントリビュータと依存パッケージのメンテナ
