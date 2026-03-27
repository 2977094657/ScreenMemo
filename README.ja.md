<div align="center">

<img src="logo.png" alt="ScreenMemo ロゴ" width="120"/>

# ScreenMemo

スマートスクリーンショット・メモ & 情報管理ツール

「画面に跡は残さず、記憶に刻む」

[![Dart](https://img.shields.io/badge/Dart-3.8.1+-0175C2?logo=dart)](https://dart.dev) [![Android](https://img.shields.io/badge/Android-3DDC84?logo=android)](https://www.android.com) [![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](LICENSE)

ローカルファーストのスクショ記憶ツール：自動キャプチャ、OCR 全文検索、必要に応じた AI 要約/リプレイに対応します。

</div>

---

<p align="center">
  <b>言語</b>:
  <a href="README.md">简体中文</a> |
  <a href="README.en.md">English</a> |
  日本語 |
  <a href="README.ko.md">한국어</a>
</p>

---

## プロジェクト概要

ScreenMemo はローカルファーストのスクリーンショット・メモ／検索ツールです。権限を許可すると Android 端末の画面を自動記録し、OCR で検索できるようにします。AI 要約は必要なときだけ有効化でき、一定期間のスクショから振り返り用のメモ（デイリーサマリー等）を作れます。

---

## 今日からあなたのパーソナルデジタル記憶を構築しよう

**なぜ今始めるべきなのか？**
- **不可逆な知識の喪失**：多くの人が日常データでパーソナルAIを訓練し始めている中、記録しない1日1日は、将来のあなたのAIアシスタントが「あなたを理解する」ための土台を失うことを意味します。
- **静かに開く時間の複利**：データは一朝一夕には構築できません。今日からデジタル標本の蓄積を始める人は、将来AIが質的な飛躍を遂げる際、他の誰も追いつけない専用の記憶庫を自然に持つことになります。
- **散らばったデジタルの自己を拾い上げる**：最も貴重なコンテキストは、多くの場合さまざまなアプリやデバイスに散逸しています。ScreenMemoで適切に収集しなければ、それらは時間の経過とともに消え去り、二度と完全には呼び覚まされなくなります。

---

## 仕組み

1. 画面キャプチャ: ユーザー許可後、Android 11+ のアクセシビリティによるスクリーンショット機能（`takeScreenshot`）を利用し、指定間隔で前面アプリの画面を取得。アプリ／時間帯ごとの有効化・除外に対応。
2. ローカル保存: 元画像をアプリのプライベート領域に保存し、タイムスタンプ／前面アプリのパッケージ名などのメタデータをローカル DB（SQLite）に記録。タイムラインとフィルタを支援。最近のバージョンでは、スクショ/DB/キャッシュは内部 `files/output` 配下に保存され、ログはデバッグ用にアプリ私有の外部ディレクトリ（`<externalFiles>/output/logs`）に出力されます。起動時に旧外部データは自動移行されます。
3. テキスト抽出（OCR）: 新規スクリーンショットに対して OCR（Android ML Kit）を実行し、テキストを抽出して画像とインデックス付け。全文検索を実現。
4. インデックスと検索: 「時間／アプリ／キーワード」による倒立インデックスを構築。検索画面でキーワード一致・時間範囲・アプリフィルタを提供し、過去画面を迅速に特定。
5. AI 処理（任意）: 同一時間帯のスクリーンショットを集約して「イベント」や「デイリーサマリー」を生成。複数のモデルプロバイダを選択・設定可能。
6. プライバシーと安全性: スクショ/OCR/索引は既定でローカル保存。AI 要約は有効化した場合のみ通信します。いつでも取得を一時停止／データ消去／バックアップのエクスポートが可能。NSFW 設定でセンシティブ内容のマスキングも可能。
7. ストレージ管理: ポリシーに基づく画像圧縮と期限切れクリーンアップでディスク占有を自動制御。ライブラリサイズを適正化。
8. ディープリンク: Deep Link により検索／統計から画像ビューアや特定ページへジャンプし、当時の文脈に素早く戻る。
9. AI リクエストゲートウェイ（AI 有効時）: モデル呼び出しは流式優先のゲートウェイで統一し、異常時は非流式へ自動フォールバックして複数プロバイダ互換性を高めます。

---

## Flutter 対話コンテキストシステム（Codex-style）

> 設計ドキュメント：`docs/CONTEXT_MEMORY.md`

- **3 層ストレージ**：UI の末尾履歴（`ai_messages`）+ 全量ログ（`ai_messages_full`）+ 圧縮メモリ（`ai_conversations.summary/tool_memory_json`）。
- **コンテキスト注入**：各リクエストで `<conversation_context>`（要約 + tool memory）を注入し、直近の全量ログ tail を prompt history として追加。
- **自動圧縮**：会話が長くなるとローリング要約を生成し、繰り返し/ループを抑制。
- **可観測性**：直近 prompt の概算 tokens（bytes/4）を記録し、UI パネルで確認/手動圧縮/クリアが可能。

---

## スクリーンショット

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
      <img src="assets/screenshots/timeline-replay-generation.jpg" alt="タイムラインとリプレイ生成" width="240" loading="lazy" />
      <div align="center"><sub>タイムラインとリプレイ生成</sub></div>
    </td>
  </tr>
  <tr>
    <td align="center" valign="top">
      <img src="assets/screenshots/event-detail.jpg" alt="イベント詳細" width="240" loading="lazy" />
      <div align="center"><sub>イベント詳細</sub></div>
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
      <img src="assets/screenshots/storage-analysis.jpg" alt="ストレージ分析" width="240" loading="lazy" />
      <div align="center"><sub>ストレージ分析</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/nsfw-search-results.jpg" alt="NSFW 検索結果" width="240" loading="lazy" />
      <div align="center"><sub>NSFW 検索結果</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/ai-review-chat.jpg" alt="AI 振り返りチャット" width="240" loading="lazy" />
      <div align="center"><sub>AI 振り返りチャット</sub></div>
    </td>
  </tr>
  <tr>
    <td align="center" valign="top">
      <img src="assets/screenshots/ai-sensitive-content-analysis.jpg" alt="センシティブ内容分析" width="240" loading="lazy" />
      <div align="center"><sub>センシティブ内容分析</sub></div>
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


### 主な機能

- ディープリンク: ブラウザリンクの自動記録に対応し、検索/統計からワンタップで復帰
- NSFW マスキング: 一般的なアダルトドメインを自動マスク。ルールのカスタマイズに対応
- アプリ別設定: アプリごとに取得戦略（取得可否・間隔・解像度／圧縮 等）を設定。ゲーム／動画／読書系アプリ向けの最適化プリセットあり
- テーマ/配色: ライト/ダークとシードカラー切り替え
- サマリー: デイリー/週間サマリー、ユーザー像（Persona）記事（ストリーミング出力）
- ストレージ分析: アプリデータ/キャッシュ/スクショ/ログの内訳表示

---

## FAQ

<details>
<summary>月あたりのストレージ使用量はどのくらい？</summary>

- 例: 画像圧縮を有効（約 50 KB/枚）・1 分に 1 枚の取得で、30 日 ≈ 43,200 枚、約 2.1 GB/月
- 概算式: 月使用量（GB） ≈ (60 ÷ 取得間隔[秒]) × 60 × 24 × 30 × 1 枚あたりサイズ[KB] ÷ 1024 ÷ 1024
- 削減のコツ: 取得間隔を延長（例: 60 秒/枚以上）、画像圧縮を有効化、有効期限クリーンアップを有効化（直近 30/60 日のみ保持）、不要アプリ／シーンを除外
</details>

<details>
<summary>データはクラウドにアップロードされますか？</summary>

- 既定ではすべてのデータ（スクショ・OCR テキスト・インデックス・統計）はローカル保存で、クラウドへはアップロードされません。いつでも取得の一時停止／データ消去／バックアップのエクスポートが可能です。
</details>

<details>
<summary>機微なアプリを除外する方法は？</summary>

- 設定で特定アプリの取得を無効化し、機微な内容の記録を避けられます。
</details>

<details>
<summary>バッテリーや性能への影響は？</summary>

- 取得間隔・画像サイズ／圧縮・前面認識頻度に依存します。圧縮と有効期限クリーンアップを有効にすることを推奨します。
</details>

<details>
<summary>バックアップ／移行の方法は？</summary>

- 「データのインポート／エクスポート」で、アセットと DB を一括エクスポート／インポートできます（移行やアーカイブ用途）。
</details>

## クイックスタート

### 必要環境
- **Flutter SDK**: 3.8.1 以上
- **Dart SDK**: 3.8.1+
- **Android Studio** / **VS Code** + Flutter プラグイン
- **Android SDK**:
  - 最低バージョン（minSdkVersion）: 21
  - 目標バージョン（targetSdkVersion）: 34
- プラットフォーム要件: 自動スクリーンショットは Android 11（API 30）以上のアクセシビリティ `takeScreenshot` に依存
- **JDK**: 11 以上

### インストール

1. **リポジトリのクローン**
   ```bash
   git clone <repository-url>
   cd screen_memo
   ```

2. **依存関係の取得**
   ```bash
   flutter pub get
   ```

3. **ローカライズファイルの生成**
   ```bash
   flutter gen-l10n
   ```

4. **アプリの起動**（開発モード）
   ```bash
   # Android デバイス接続 or エミュレータ起動
   flutter run
   ```

### 開発コマンド

```bash
# Debug APK をビルド
flutter build apk --debug

# 端末へインストール
flutter install

# ログ表示
adb logcat | findstr "ScreenMemo"  # Windows
adb logcat | grep "ScreenMemo"     # Linux/macOS

# 静的解析
flutter analyze
```

---

## リリースビルド

ABI 別に分割した最適化 APK（サイズ最小化）を生成:

```powershell
flutter clean
flutter pub get
flutter build apk --release --split-per-abi --tree-shake-icons --obfuscate --split-debug-info=build/symbols
```

**生成物の場所**:
- `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
- `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk`
- `build/app/outputs/flutter-apk/app-x86_64-release.apk`

---

## 自動リリース（GitHub Actions）

本プロジェクトは、タグのプッシュをトリガーとして自動でビルドし GitHub Releases に公開するように設定されています。通常のプッシュやコミットではトリガーされず、タグ（例：`v1.0.0`）をプッシュした時のみビルドされます。

### リリース手順

```bash
git tag v1.0.0
git push origin v1.0.0
```

プッシュ後、GitHub Actions は自動的に **ABI別に分割された Release APK** をビルドし、同名のリリースを作成して生成物（APK、`symbols-*.zip`、および任意で `mapping-*.txt`）を添付します。

バージョン規則：タグ（`v` 接頭辞を除く）が `--build-name` として、`github.run_number` が `--build-number` として使用されます。

### 任意：本番用署名の設定（推奨）

Release APK を（デバッグキーではなく）本番用キーストアで署名したい場合は、リポジトリの `Settings -> Secrets and variables -> Actions` に以下のシークレットを追加してください：

- `ANDROID_KEYSTORE_BASE64`：`jks`/`keystore` ファイルのBase64エンコード文字列
- `ANDROID_KEYSTORE_PASSWORD`：キーストアのパスワード
- `ANDROID_KEY_ALIAS`：キーエイリアス
- `ANDROID_KEY_PASSWORD`：キーのパスワード

> ワークフローはデフォルトで GitHub 組み込みの `GITHUB_TOKEN` を使用してリリースを公開します。個人のトークンを追加で提供する必要はありません。

---

## デスクトップデータ合併ツール

スマホ側での合併インポートは重い場合があるため、Windows/macOS/Linux 向けのデスクトップ合併ツールを用意しています。複数のエクスポート ZIP バックアップを高速に統合できます。

### 機能

- エクスポートした ZIP バックアップを複数選択
- 出力ディレクトリを指定（合併後の保存先）
- 進捗と詳細結果を表示
- スクショと DB をまとめて合併

### 実行ファイルのビルド

**Windows**：
```powershell
flutter build windows -t lib/main_desktop_merger.dart --release
```

**macOS**：
```bash
flutter build macos -t lib/main_desktop_merger.dart --release
```

**Linux**：
```bash
flutter build linux -t lib/main_desktop_merger.dart --release
```

### 出力先

| プラットフォーム | 出力ディレクトリ |
|------|----------|
| Windows | `build/windows/x64/runner/Release/` |
| macOS | `build/macos/Build/Products/Release/` |
| Linux | `build/linux/x64/release/bundle/` |

> 生成物はフォルダです。Windows の場合は `screen_memo.exe` と必要な DLL が含まれるため、フォルダごとコピーして実行できます。

---

## 権限

アプリは必要に応じて以下の権限を案内します（機能により異なります）:

| 権限 | 用途 | 必須 |
|-----|------|------|
| 通知 | 前台サービス状態/通知の表示 | 必須（バックグラウンド取得） |
| アクセシビリティサービス | 自動スクショ（Android 11+ `takeScreenshot`）と前面アプリ検出 | 必須（自動取得） |
| 使用状況統計 | 前面アプリの取得（Usage Stats） | 必須 |
| 写真/メディア | 画像/動画をギャラリーに保存 | 任意 |
| 正確なアラーム | デイリー/週間サマリーのリマインド | 任意 |

> 注：アプリデータはアプリ私有領域に保存されるため、従来の `READ/WRITE_EXTERNAL_STORAGE` 実行時権限は不要です。権限は必要なタイミングで案内され、いつでもシステム設定から取り消せます。

---

## 国際化

対応言語:
- 簡体字中国語（既定）
- 英語
- 日本語
- 韓国語

### 言語を追加する

1. `lib/l10n/` に新しい `.arb` を作成（例: `app_ja.arb`）
2. `app_en.arb` の内容をコピーして翻訳
3. `flutter gen-l10n` を実行してコード生成
4. `LocaleService` に新ロケールを登録

### i18n 監査（翻訳漏れ/ハードコード回帰の防止）

「ユーザーに見える文言なのに未翻訳」という事故を避けるため、本プロジェクトでは監査ツールとテストでガードしています。

- **ARB 整合性**：`lib/l10n/*.arb` はテンプレート（`app_en.arb`）と key が完全一致（不足/余剰で失敗）。
- **プラットフォーム側のローカライズ**：iOS/Android の主要なローカライズ宣言/リソースが欠けていると失敗。
- **Flutter UI のハードコード文言**：baseline モードで **新規追加** のハードコードのみをブロック。既存分は baseline に記録され、徐々に削減できます。

チェック実行：
```bash
dart run tool/i18n_audit.dart --check
```

baseline 更新（本当に既存/例外のときのみ）：
```bash
dart run tool/i18n_audit.dart --update-baseline
```

無視ルール（慎重に）：
- 行末に `// i18n-ignore`：その行を無視
- ファイル内の任意位置に `// i18n-ignore-file`：ファイル全体を無視

`flutter test` では `test/i18n_audit_test.dart` が自動実行され、回帰を防ぎます。

---

## コントリビューションガイド

Issue／PR／機能提案を歓迎します。

1. 本リポジトリを Fork
2. フィーチャーブランチを作成（`git checkout -b feature/AmazingFeature`）
3. 変更をコミット（`git commit -m 'feat: add some amazing feature'`）
4. ブランチへプッシュ（`git push origin feature/AmazingFeature`）
5. Pull Request を作成

次を必ず満たしてください:
- `flutter analyze` をパス
- 必要なテストを追加
- 関連ドキュメントを更新

---

## 謝辞

以下のオープンソースに感謝します:
- [Flutter](https://flutter.dev) - UI フレームワーク
- [Google ML Kit](https://developers.google.com/ml-kit) - テキスト認識
- [SQLite](https://www.sqlite.org/) - データベースエンジン
- すべてのコントリビューターと依存パッケージのメンテナ
