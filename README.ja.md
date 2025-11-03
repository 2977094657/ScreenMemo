<div align="center">

<img src="logo.png" alt="ScreenMemo ロゴ" width="120"/>

# ScreenMemo

スマートスクリーンショット・メモ & 情報管理ツール

「画面に跡は残さず、記憶に刻む」

[![Dart](https://img.shields.io/badge/Dart-3.8.1+-0175C2?logo=dart)](https://dart.dev) [![Android](https://img.shields.io/badge/Android-3DDC84?logo=android)](https://www.android.com) [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Flutter ベースのスマートなスクリーンショット管理アプリ。重要情報の取得・整理・振り返りを効率化します。

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

## プロジェクト概要・利用シーン

ScreenMemo はローカルファーストのスマートなスクリーンショット・メモ／検索ツールです。Android デバイスの画面を自動記録し、OCR と AI 要約によって情報を検索可能・振り返り可能・蓄積可能にします。必要なときに手がかりを素早く見つけ、当時の文脈を再構築できます。

できること:
- さまざまなアプリに現れたテキスト（記事の断片／チャット履歴／字幕など）を復元。元の内容が削除・撤回されてもローカル履歴から検索できます。
- 「どこで見たか思い出せない」を時間範囲やアプリで絞り込み、当時の画面を素早く特定。
- 同時間帯の複数スクリーンショットを AI が要約し「デイリーサマリー」を生成。1日の重要な活動や要点を効率よく振り返り。
- ローカルライブラリのエクスポート／バックアップで「第二の記憶」を移行・アーカイブ。

典型的なユースケース:
- 撤回／削除されたメッセージやページ内容を思い出す／誤って閉じたウィンドウの情報を取り戻す。
- キーワード検索で複数日にわたり繰り返し登場する台詞・用語・キーフィールドを横断し、記憶の断片をつなぎ合わせる（出現回数の把握とクイックレビュー）。
- 重要期間の振り返り（プロジェクト・卒論・レビュー／評価の準備）。「デイリーサマリー」で当日の要点をすばやく把握し、整理コストを削減。
- 「記憶のトレジャーハント」：見落としていた細部や着想を掘り起こし、創作や意思決定を支援。

---

### 今日からあなたの「デジタル記憶」の構築を始めましょう

### なぜ今、記録を始めるのか？
- 他の人たちはすでにパーソナル AI を育て始めています
- 取り残されないために。記録しない 1 日ごとは、未来の AI アシスタントにとって失われる知識です

### AI のアドバンテージ格差
- 今日から個人データを収集し始めた人は、AI がさらに強力になったときに何年もの優位性を得ます

### 散在するデジタル自己
- 価値ある個人コンテキストはアプリやデバイスに分散・閉じ込められています——ScreenMemo がなければ横断活用は困難です

---

## 仕組み

1. 画面キャプチャ: ユーザー許可後、Android 11+ のアクセシビリティによるスクリーンショット機能（`takeScreenshot`）を利用し、指定間隔で前面アプリの画面を取得。アプリ／時間帯ごとの有効化・除外に対応。
2. ローカル保存: 元画像をアプリのプライベート領域に保存し、タイムスタンプ／前面アプリのパッケージ名などのメタデータをローカル DB（SQLite）に記録。タイムラインとフィルタを支援。
3. テキスト抽出（OCR）: 新規スクリーンショットに対して OCR を実行し、テキストを抽出して画像とインデックス付け。多言語文字セットに対応し全文検索を実現。
4. インデックスと検索: 「時間／アプリ／キーワード」による倒立インデックスを構築。検索画面でキーワード一致・時間範囲・アプリフィルタを提供し、過去画面を迅速に特定。
5. AI 処理: 同一時間帯のスクリーンショットを集約して「イベント」や「デイリーサマリー」を生成。複数のモデルプロバイダを選択・設定可能。
6. プライバシーと安全性: 生データとインデックスはすべてローカル保存。いつでも取得を一時停止／データ消去／バックアップのエクスポートが可能。NSFW 設定でセンシティブ内容のマスキングも可能。
7. ストレージ管理: ポリシーに基づく画像圧縮と期限切れクリーンアップでディスク占有を自動制御。ライブラリサイズを適正化。
8. ディープリンク: Deep Link により検索／統計から画像ビューアや特定ページへジャンプし、当時の文脈に素早く戻る。

---

## スクリーンショット

<table>
  <tr>
    <td align="center" valign="top">
      <img src="assets/screenshots/home.jpg" alt="ホーム" width="240" loading="lazy" />
      <div align="center"><sub>ホーム</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/search.jpg" alt="検索" width="240" loading="lazy" />
      <div align="center"><sub>検索</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/timeLine.jpg" alt="タイムライン" width="240" loading="lazy" />
      <div align="center"><sub>タイムライン</sub></div>
    </td>
  </tr>
  <tr>
    <td align="center" valign="top">
      <img src="assets/screenshots/daySummary.jpg" alt="デイリーサマリー" width="240" loading="lazy" />
      <div align="center"><sub>デイリーサマリー</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/event.jpg" alt="イベント" width="240" loading="lazy" />
      <div align="center"><sub>イベント</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/collect.jpg" alt="お気に入り" width="240" loading="lazy" />
      <div align="center"><sub>お気に入り</sub></div>
    </td>
  </tr>
  <tr>
    <td align="center" valign="top">
      <img src="assets/screenshots/prompt.jpg" alt="プロンプト管理" width="240" loading="lazy" />
      <div align="center"><sub>プロンプト管理</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/addAi.jpg" alt="AI 追加" width="240" loading="lazy" />
      <div align="center"><sub>AI 追加</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/aiChat.jpg" alt="AI チャット" width="240" loading="lazy" />
      <div align="center"><sub>AI チャット</sub></div>
    </td>
  </tr>
  <tr>
    <td align="center" valign="top">
      <img src="assets/screenshots/setting.jpg" alt="設定" width="240" loading="lazy" />
      <div align="center"><sub>設定</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/nsfw.jpg" alt="NSFW フィルタ" width="240" loading="lazy" />
      <div align="center"><sub>NSFW フィルタ</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/deepLink.jpg" alt="ディープリンク" width="240" loading="lazy" />
      <div align="center"><sub>ディープリンク</sub></div>
    </td>
  </tr>
</table>


### 主な機能

- ディープリンク: ブラウザリンクの自動記録に対応
- NSFW マスキング: 一般的なアダルトドメインを自動マスク。カスタムドメインにも対応
- アプリ別設定: アプリごとに取得戦略（取得可否・間隔・解像度／圧縮 等）を設定。ゲーム／動画／読書系アプリ向けの最適化プリセットあり

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

### ワンコマンド最適化ビルド（推奨）

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

## 権限

アプリは以下の権限を使用します:

| 権限 | 用途 | 必須 |
|-----|------|------|
| ストレージ | スクリーンショットとデータの保存 | 必須 |
| 通知 | サービス状態と通知の表示 | 必須 |
| アクセシビリティサービス | 自動スクリーンショットと前面アプリ検出 | 必須 |
| 使用状況統計 | 前面アプリの取得（Usage Stats） | 必須 |

> すべての権限は初回起動時にガイドし、いつでもシステム設定から取り消せます。

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

## ライセンス

本プロジェクトは MIT ライセンスで公開されています。詳細は [LICENSE](LICENSE) を参照してください。

---

## 謝辞

以下のオープンソースに感謝します:
- [Flutter](https://flutter.dev) - UI フレームワーク
- [Google ML Kit](https://developers.google.com/ml-kit) - テキスト認識
- [SQLite](https://www.sqlite.org/) - データベースエンジン
- すべてのコントリビューターと依存パッケージのメンテナ
