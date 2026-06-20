// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appTitle => 'スクリーンメモ';

  @override
  String get settingsTitle => '設定';

  @override
  String get searchPlaceholder => 'スクリーンショットを検索...';

  @override
  String get homeEmptyTitle => '監視対象のアプリはありません';

  @override
  String get homeEmptySubtitle => '設定で監視するアプリを選択してください';

  @override
  String get navSelectApps => 'スクリーンショット対象アプリを選択';

  @override
  String get dialogOk => 'OK';

  @override
  String get dialogCancel => 'キャンセル';

  @override
  String get dialogDone => '完了';

  @override
  String get actionConfirm => '確認';

  @override
  String get customizeBottomNavTitle => '下部ナビをカスタマイズ';

  @override
  String get customizeBottomNavSubtitle =>
      'よく使う機能へ素早く移動できるよう、下部ナビを追加、削除、並べ替えできます。';

  @override
  String get bottomNavHome => 'ホーム';

  @override
  String get bottomNavHomeDesc => '監視アプリの概要';

  @override
  String get bottomNavFavorites => 'お気に入り';

  @override
  String get bottomNavFavoritesDesc => '保存したスクリーンショット';

  @override
  String get bottomNavAi => 'AI';

  @override
  String get bottomNavAiDesc => '振り返りとチャット';

  @override
  String get bottomNavTimeline => 'タイムライン';

  @override
  String get bottomNavTimelineDesc => '画面履歴を閲覧';

  @override
  String get bottomNavSettings => '設定';

  @override
  String get bottomNavSettingsDesc => 'アプリ設定';

  @override
  String get bottomNavDynamic => '動的';

  @override
  String get bottomNavDynamicDesc => 'AI アクティビティ要約';

  @override
  String get bottomNavStorage => 'ストレージ';

  @override
  String get bottomNavStorageDesc => 'ストレージ使用状況';

  @override
  String get bottomNavMinTabsToast => '少なくとも3個のタブを残してください';

  @override
  String get bottomNavMaxTabsToast => '追加できるタブは最大6個です';

  @override
  String get permissionStatusTitle => '権限ステータス';

  @override
  String get permissionMissing => '権限が不足しています';

  @override
  String get startScreenshot => 'キャプチャを開始';

  @override
  String get stopScreenshot => 'キャプチャを停止';

  @override
  String get screenshotEnabledToast => 'キャプチャを有効にしました';

  @override
  String get screenshotDisabledToast => 'キャプチャを無効にしました';

  @override
  String get intervalSettingTitle => 'キャプチャ間隔を設定';

  @override
  String get intervalLabel => '間隔（秒）';

  @override
  String get intervalHint => '1～60 の整数を入力してください';

  @override
  String intervalSavedToast(Object seconds) {
    return 'キャプチャ間隔を $seconds 秒に設定しました';
  }

  @override
  String get languageSettingTitle => '言語';

  @override
  String get languageSystem => 'システム';

  @override
  String get languageChinese => '簡体字中国語';

  @override
  String get languageEnglish => '英語';

  @override
  String get languageJapanese => '日本語';

  @override
  String get languageKorean => '韓国語';

  @override
  String languageChangedToast(Object name) {
    return '$name に切り替えました';
  }

  @override
  String get nsfwWarningTitle => 'コンテンツ警告：成人向けコンテンツ';

  @override
  String get nsfwWarningSubtitle => 'このコンテンツはアダルト コンテンツとしてマークされています';

  @override
  String get show => '表示';

  @override
  String get appSearchPlaceholder => 'アプリを検索...';

  @override
  String selectedCount(Object count) {
    return '選択済み $count 件';
  }

  @override
  String get refreshAppsTooltip => 'アプリを再読み込み';

  @override
  String get selectAll => 'すべて選択';

  @override
  String get clearAll => 'すべてクリア';

  @override
  String get noAppsFound => 'アプリが見つかりません';

  @override
  String get noAppsMatched => '一致するアプリがありません';

  @override
  String get pinduoduoWarningTitle => 'リスク警告';

  @override
  String get pinduoduoWarningMessage =>
      '拼多多でスクリーンショットを撮影すると、注文がキャンセルされる可能性があります。監視を有効にすることは推奨されません。';

  @override
  String get pinduoduoWarningCancel => '選択を取り消す';

  @override
  String get pinduoduoWarningKeep => '続行する';

  @override
  String stepProgress(Object current, Object total) {
    return 'ステップ $current/$total';
  }

  @override
  String get onboardingWelcomeTitle => 'スクリーンメモへようこそ';

  @override
  String get onboardingWelcomeDesc =>
      '重要な情報を効率的に取得、整理、確認できるインテリジェントなメモおよび情報管理ツールです。';

  @override
  String get onboardingKeyFeaturesTitle => '主な特徴';

  @override
  String get featureSmartNotes => 'スマートな情報収集';

  @override
  String get featureQuickSearch => '高速コンテンツ検索';

  @override
  String get featureLocalStorage => 'ローカルデータストレージ';

  @override
  String get featureUsageAnalytics => '使用状況分析';

  @override
  String get onboardingPermissionsTitle => '必要な権限を付与する';

  @override
  String get refreshPermissionStatus => '権限ステータスの更新';

  @override
  String get onboardingPermissionsDesc => '完全なエクスペリエンスを提供するには、次の権限を付与してください。';

  @override
  String get storagePermissionTitle => 'ストレージ許可';

  @override
  String get storagePermissionDesc => 'スクリーンショット ファイルをデバイス ストレージに保存する';

  @override
  String get notificationPermissionTitle => '通知許可';

  @override
  String get notificationPermissionDesc => 'サービスステータス通知を表示する';

  @override
  String get accessibilityPermissionTitle => 'アクセシビリティサービス';

  @override
  String get accessibilityPermissionDesc => 'アプリの切り替えを監視し、スクリーンショットを撮る';

  @override
  String get usageStatsPermissionTitle => '使用状況統計の権限';

  @override
  String get usageStatsPermissionDesc => '正確なフォアグラウンド アプリ検出を保証する';

  @override
  String get batteryOptimizationTitle => 'バッテリー最適化のホワイトリスト';

  @override
  String get batteryOptimizationDesc => 'スクリーンショットサービスを安定して実行し続ける';

  @override
  String get pleaseCompleteInSystemSettings => 'システム設定で認証を完了してからアプリに戻ってください';

  @override
  String get autostartPermissionTitle => '自動起動許可';

  @override
  String get autostartPermissionDesc => 'アプリがバックグラウンドで再起動できるようにする';

  @override
  String get permissionsFooterNote => '権限は付与後も保持され、システム設定でいつでも変更できます。';

  @override
  String get grantedLabel => '付与された';

  @override
  String get authorizeAction => '承認する';

  @override
  String get onboardingSelectAppsTitle => '監視するアプリを選択';

  @override
  String get onboardingSelectAppsDesc =>
      'スクリーンショットを監視するアプリを選択してください。続行するには少なくとも 1 つを選択してください。';

  @override
  String get onboardingDoneTitle => '準備完了です！';

  @override
  String get onboardingDoneDesc => 'すべての権限が付与されています。これで、ScreenMemo の使用を開始できます。';

  @override
  String get nextStepTitle => '次のステップ';

  @override
  String get onboardingNextStepDesc =>
      '「使用を開始」をタップしてメイン画面に入り、強力なスクリーンショット機能を体験してください。';

  @override
  String get prevStep => '前へ';

  @override
  String get startUsing => '利用開始';

  @override
  String get finishSelection => '選択を完了';

  @override
  String get nextStep => '次へ';

  @override
  String get confirmPermissionSettingsTitle => '権限設定を確認する';

  @override
  String get confirmAutostartQuestion => 'システム設定の「自動起動許可」の設定はお済みですか？';

  @override
  String get notYet => 'まだ';

  @override
  String get done => '完了';

  @override
  String get startingScreenshotServiceInfo => 'キャプチャ サービスを開始しています...';

  @override
  String get startServiceFailedCheckPermissions =>
      'キャプチャサービスの開始に失敗しました。権限設定を確認してください';

  @override
  String get startFailedTitle => '開始に失敗しました';

  @override
  String get startFailedUnknown => '開始失敗: 不明なエラー';

  @override
  String get tipIfProblemPersists =>
      'ヒント: 問題が解決しない場合は、アプリを再起動するか、権限を再構成してください。';

  @override
  String get autoDisabledDueToPermissions => '権限が不十分なため、キャプチャは無効になりました';

  @override
  String get refreshingPermissionsInfo => '許可ステータスを更新しています...';

  @override
  String get permissionsRefreshed => '権限ステータスが更新されました';

  @override
  String refreshPermissionsFailed(Object error) {
    return '権限ステータスを更新できませんでした: $error';
  }

  @override
  String get screenRecordingPermissionTitle => '画面録画許可';

  @override
  String get goToSettings => '設定へ移動';

  @override
  String get notGrantedLabel => '未許可';

  @override
  String get removeMonitoring => '監視を解除';

  @override
  String selectedItemsCount(Object count) {
    return '$count を選択しました';
  }

  @override
  String get whySomeAppsHidden => '一部のアプリが見つからないのはなぜですか?';

  @override
  String get excludedAppsTitle => '除外されたアプリ';

  @override
  String get excludedAppsIntro => '以下のアプリは除外され、選択できません。';

  @override
  String get excludedThisApp => '・このアプリ（自己干渉を避けるため）';

  @override
  String get excludedAutomationApps =>
      '・自動スキップ系アプリ（例：GKD などの自動タップツール、誤分類を防ぐため）';

  @override
  String get excludedImeApps => '・入力方式（キーボード）アプリ：';

  @override
  String get excludedImeAppsFiltered => '・入力方法（キーボード）アプリ（自動フィルタリング）';

  @override
  String currentDefaultIme(Object name, Object package) {
    return '現在のデフォルトの IME: $name ($package)';
  }

  @override
  String get imeExplainText =>
      '別のアプリでキーボードがポップアップすると、システムは IME ウィンドウに切り替わります。除外しない場合、IMEを使用していると誤認され、フローティングウィンドウの検出が誤る可能性があります。 IME アプリは自動的に除外されますが、IME が検出されたときに IME がポップアップする前にフローティング ウィンドウをアプリに移動します。';

  @override
  String get gotIt => 'わかった';

  @override
  String get unknownIme => '不明な IME';

  @override
  String get intervalRangeNote =>
      'キャプチャのタイミングを優先するため、目標サイズ圧縮を有効にすると先にスクリーンショットを保存し、正確な圧縮は後でバックグラウンドで完了する場合があります。';

  @override
  String get intervalInvalidInput => '1 ～ 60 の有効な整数を入力してください';

  @override
  String get removeMonitoringMessage => '監視のみ解除し、画像は削除しません。続行しますか？';

  @override
  String get remove => '解除';

  @override
  String removedMonitoringToast(Object count) {
    return '$count 件のアプリの監視を解除しました（画像は削除されません）';
  }

  @override
  String checkPermissionStatusFailed(Object error) {
    return '権限ステータスの確認に失敗しました: $error';
  }

  @override
  String get accessibilityNotEnabledDetail =>
      'ユーザー補助サービスが有効になっていません\\n設定でユーザー補助を有効にしてください';

  @override
  String get storagePermissionNotGrantedDetail =>
      'ストレージ権限が付与されていません\\n設定でストレージ権限を付与してください';

  @override
  String get serviceNotRunningDetail => 'サービスが正しく実行されていません\\nアプリを再起動してください';

  @override
  String get androidVersionNotSupportedDetail =>
      'Android バージョンはサポートされていません\\nAndroid 11.0 以降が必要です';

  @override
  String get permissionsSectionTitle => '権限';

  @override
  String get permissionsSectionDesc => 'ストレージ/通知/ユーザー補助/常駐';

  @override
  String get displayAndSortSectionTitle => '表示と並べ替え';

  @override
  String get screenshotSectionTitle => 'キャプチャ設定';

  @override
  String get screenshotSectionDesc => '間隔/品質/期限削除';

  @override
  String get segmentSummarySectionTitle => 'ダイナミック設定';

  @override
  String get segmentSummarySectionDesc => 'サンプリング/長さ/AI間隔';

  @override
  String get dailyReminderSectionTitle => '毎日の概要リマインダー';

  @override
  String get dailyReminderSectionDesc => '時刻/バナー権限/テスト';

  @override
  String get aiAssistantSectionTitle => 'AIアシスタント';

  @override
  String get dataBackupSectionTitle => 'データとバックアップ';

  @override
  String get dataBackupSectionDesc => 'ストレージ/インポート/エクスポート/再集計';

  @override
  String get advancedSectionTitle => '高度な設定';

  @override
  String get advancedSectionDesc => 'ログとパフォーマンス';

  @override
  String get aboutSectionTitle => 'このアプリについて';

  @override
  String get aboutSectionDesc => 'バージョン、フィードバック、オープンソースライセンス';

  @override
  String get aboutAppName => 'スクリーンメモ / ScreenMemo';

  @override
  String get aboutSlogan => '画面は残さず、記憶は残す';

  @override
  String get aboutDescription =>
      'ローカルで動作するインテリジェントなスクリーンショットメモ・検索ツールです。OCR、セマンティック検索、AI 回顧、バックアップ移行に対応します。';

  @override
  String get aboutVersionSectionTitle => 'バージョン情報';

  @override
  String get aboutCurrentVersion => '現在のバージョン';

  @override
  String get aboutFeedbackTitle => 'コミュニティとフィードバック';

  @override
  String get aboutFeedbackDesc => '不具合報告や機能要望を送信';

  @override
  String get aboutGithub => 'GitHub プロジェクト';

  @override
  String get aboutQqGroup => 'QQ グループ';

  @override
  String get aboutIssueFeedback => '問題を報告';

  @override
  String get supportSectionTitle => 'メンテナンスを支援';

  @override
  String get supportEntryTitle => 'ScreenMemo を支援';

  @override
  String get supportEntrySubtitle => '大切な手がかりを見つける助けになったなら、作者にコーヒーをおごることができます。';

  @override
  String get supportPageTitle => 'ScreenMemo を支援';

  @override
  String get supportIntroTitle => 'このプロジェクトを支えてくれてありがとうございます';

  @override
  String get supportIntroBody =>
      'ScreenMemo は、ローカル優先の記録、検索、振り返りを大切にして開発を続けます。支援は長期メンテナンス、互換性対応、機能の磨き込みを直接後押しします。';

  @override
  String get supportWishListTitle => '支援が後押しする改善';

  @override
  String get supportWishMorePlatforms =>
      '完全なマルチプラットフォームエコシステム：PC などの対応を開発し、個人のデジタル記憶がデバイスをまたいでつながるようにします。';

  @override
  String get supportWishReviewViews =>
      'より豊かな表示形式：週次、月次、年次など多様な要約を取り入れ、長期的な振り返りに階層を持たせます。';

  @override
  String get supportWishCompatibility =>
      '安定性と互換性：Android バージョン、端末差、バックグラウンド制限への対応を続けます。';

  @override
  String get supportDonationMethodsTitle => '支援方法';

  @override
  String get supportVoluntaryNote =>
      '支援は完全に任意で、どの機能の利用にも影響しません。丁寧に使うこと、不具合報告、提案も ScreenMemo への大切な支援です。';

  @override
  String get supportQrMissing => '実際の支払い用 QR コードに置き換えてください';

  @override
  String get aboutOpenSourceTitle => 'オープンソース';

  @override
  String get aboutLicenseAgpl => 'ライセンス';

  @override
  String get aboutThirdPartyLicenses => 'サードパーティライセンス';

  @override
  String aboutTapVersionRemaining(Object count) {
    return 'あと $count 回タップするとガイドを開きます';
  }

  @override
  String aboutOpenLinkFailed(Object url) {
    return 'リンクを開けません：$url';
  }

  @override
  String get storageAnalysisEntryTitle => 'ストレージ分析';

  @override
  String get storageAnalysisEntryDesc => 'アプリのストレージ使用状況を詳しく確認します';

  @override
  String get actionSet => 'セット';

  @override
  String get actionEnter => '入力';

  @override
  String get actionExport => '輸出';

  @override
  String get actionImport => '輸入';

  @override
  String get actionCopyPath => 'パスをコピーする';

  @override
  String get actionOpen => '開ける';

  @override
  String get actionTrigger => 'トリガー';

  @override
  String get allPermissionsGranted => 'すべての権限が許可されました';

  @override
  String permissionsMissingCount(Object count) {
    return '未付与の権限が $count 件あります';
  }

  @override
  String get exportSuccessTitle => 'エクスポートが完了しました';

  @override
  String get exportFileExportedTo => '出力先：';

  @override
  String get pathCopiedToast => 'パスをコピーしました';

  @override
  String get exportFailedTitle => 'エクスポートに失敗しました';

  @override
  String get pleaseTryAgain => '後でもう一度お試しください';

  @override
  String get importCompleteTitle => 'インポートが完了しました';

  @override
  String get dataExtractedTo => '展開先：';

  @override
  String get importFailedTitle => 'インポートに失敗しました';

  @override
  String get importFailedCheckZip => 'ZIP ファイルを確認して、もう一度試してください。';

  @override
  String get storageAnalysisPageTitle => 'ストレージ分析';

  @override
  String get storageAnalysisLoadFailed => 'ストレージデータの取得に失敗しました';

  @override
  String get storageAnalysisEmptyMessage => '表示できるストレージデータがありません';

  @override
  String get storageAnalysisSummaryTitle => 'ストレージ概要';

  @override
  String get storageAnalysisTotalLabel => '合計';

  @override
  String get storageAnalysisAppLabel => 'アプリ';

  @override
  String get storageAnalysisDataLabel => 'アプリデータ';

  @override
  String get storageAnalysisCacheLabel => 'キャッシュ';

  @override
  String get storageAnalysisExternalLabel => '外部ログ';

  @override
  String storageAnalysisScanTimestamp(Object timestamp) {
    return 'スキャン時刻：$timestamp';
  }

  @override
  String storageAnalysisScanDurationSeconds(Object seconds) {
    return 'スキャン時間：$seconds 秒';
  }

  @override
  String storageAnalysisScanDurationMilliseconds(Object milliseconds) {
    return 'スキャン時間：$milliseconds ミリ秒';
  }

  @override
  String get storageAnalysisManualNote =>
      '使用状況アクセスが付与されていないため、ここに表示される値はローカル計測であり、システム設定と異なる場合があります。';

  @override
  String get storageAnalysisUsagePermissionMissingTitle => '使用状況アクセスが必要です';

  @override
  String get storageAnalysisUsagePermissionMissingDesc =>
      'Android 設定と同じ統計を取得するには、システム設定の「使用状況へのアクセス」を許可してください。';

  @override
  String get storageAnalysisUsagePermissionButton => '設定を開く';

  @override
  String get storageAnalysisPartialErrors => '一部の統計を取得できませんでした';

  @override
  String get storageAnalysisBreakdownTitle => '詳細内訳';

  @override
  String storageAnalysisFileCount(Object count) {
    return '$count 件のファイル';
  }

  @override
  String get storageAnalysisPathCopied => 'パスをコピーしました';

  @override
  String get storageAnalysisLabelFiles => 'files ディレクトリ';

  @override
  String get storageAnalysisLabelOutput => 'output ディレクトリ';

  @override
  String get storageAnalysisLabelScreenshots => 'スクリーンショットライブラリ';

  @override
  String get storageAnalysisLabelOutputDatabases => 'output/databases';

  @override
  String get storageAnalysisLabelReplayOutput => 'リプレイ動画';

  @override
  String get storageAnalysisReplayClearConfirmTitle => 'リプレイ動画を削除';

  @override
  String storageAnalysisReplayClearConfirmMessage(Object size, Object count) {
    return 'アプリ内部のリプレイ動画コピー（$size、$count 件のファイル）を削除します。システムギャラリーに保存済みの動画と元のスクリーンショットは削除されません。続行しますか？';
  }

  @override
  String get storageAnalysisLabelSharedPrefs => 'shared_prefs';

  @override
  String get storageAnalysisLabelNoBackup => 'no_backup';

  @override
  String get storageAnalysisLabelAppFlutter => 'app_flutter';

  @override
  String get storageAnalysisLabelDatabases => 'databases ディレクトリ';

  @override
  String get storageAnalysisLabelCacheDir => 'cache ディレクトリ';

  @override
  String get storageAnalysisLabelCodeCache => 'code_cache';

  @override
  String get storageAnalysisLabelExternalLogs => '外部ログ';

  @override
  String storageAnalysisOthersLabel(Object count) {
    return 'その他（$count 件）';
  }

  @override
  String get storageAnalysisOthersFallback => 'その他';

  @override
  String get noMediaProjectionNeeded =>
      'アクセシビリティのスクリーンショットを使用しているため、画面録画の許可は不要です';

  @override
  String get autostartPermissionMarked => '自動起動権限を許可済みとしてマークしました';

  @override
  String requestPermissionFailed(Object error) {
    return '権限の要求に失敗しました：$error';
  }

  @override
  String get expireCleanupSaved => '期限切れクリーンアップ設定が保存されました';

  @override
  String get dailyNotifyTriggered => '通知がトリガーされました';

  @override
  String get dailyNotifyTriggerFailed => '通知をトリガーできなかったか、コンテンツが空でした';

  @override
  String get refreshPermissionStatusTooltip => '権限ステータスの更新';

  @override
  String get grantedStatus => '許可済み';

  @override
  String get notGrantedStatus => '許可';

  @override
  String get privacyModeTitle => 'プライバシーモード';

  @override
  String get privacyModeDesc => '機密コンテンツを自動でぼかします';

  @override
  String get homeSortingTitle => 'ホームの並び替え';

  @override
  String get screenshotIntervalTitle => 'スクリーンショット間隔';

  @override
  String screenshotIntervalDesc(Object seconds) {
    return '現在の間隔：$seconds 秒';
  }

  @override
  String get autoAddNewAppsToCaptureTitle => '新しいアプリを自動追加';

  @override
  String get autoAddNewAppsToCaptureDesc =>
      '新しくインストールされた非システムアプリをキャプチャ一覧へ自動追加します。';

  @override
  String get windowScreenshotApiTitle => '対象ウィンドウのみ撮影';

  @override
  String get windowScreenshotApiDesc =>
      '有効にすると対象アプリのウィンドウだけを保存します。Android 14 以降ではウィンドウ API を優先し、それ以外はウィンドウ範囲で切り抜きます。';

  @override
  String get windowScreenshotApiEnabledToast => '対象ウィンドウのみ撮影を有効にしました';

  @override
  String get windowScreenshotApiDisabledToast => '対象ウィンドウのみ撮影を無効にしました';

  @override
  String get screenshotDedupeModeTitle => '画面重複除外の強度';

  @override
  String screenshotDedupeModeCurrent(Object mode) {
    return '現在：$mode';
  }

  @override
  String get screenshotDedupeModeDialogTitle => '画面重複除外の強度を選択';

  @override
  String get screenshotDedupeModeExact => 'オフ / 完全一致';

  @override
  String get screenshotDedupeModeExactDesc => '完全に同一のスクリーンショットだけをスキップします。';

  @override
  String get screenshotDedupeModeConservative => '控えめ';

  @override
  String get screenshotDedupeModeConservativeDesc =>
      'カーソルや細い線の揺れなど、ごく小さな変化だけを無視します。';

  @override
  String get screenshotDedupeModeBalanced => 'バランス';

  @override
  String get screenshotDedupeModeBalancedDesc =>
      'よくある小さなアニメーションや揺れを無視しつつ、内容の変化はできるだけ残します。';

  @override
  String get screenshotDedupeModeAggressive => '強め';

  @override
  String get screenshotDedupeModeAggressiveDesc =>
      'より多くの小範囲の変化をスキップし、保存数を減らします。';

  @override
  String screenshotDedupeModeSaved(Object mode) {
    return '画面重複除外の強度を保存しました：$mode';
  }

  @override
  String get screenshotQualityTitle => 'スクリーンショット品質';

  @override
  String get currentSizeLabel => '現在のサイズ：';

  @override
  String get clickToModifyHint => '（数字をタップして変更）';

  @override
  String get screenshotExpireTitle => 'スクリーンショットの保存期限';

  @override
  String get currentExpireDaysLabel => '現在の保存日数：';

  @override
  String expireDaysUnit(Object days) {
    return '$days 日';
  }

  @override
  String get setCompressDaysDialogTitle => '日数を設定';

  @override
  String get compressDaysLabel => '日数';

  @override
  String get compressDaysInputHint => '日数を入力してください';

  @override
  String get compressDaysInputHintAll => 'すべての履歴は 0、または日数を入力してください';

  @override
  String get compressDaysInvalidError => '1 以上の日数を入力してください。';

  @override
  String get compressDaysInvalidOrAllError => '0 または 1 以上の日数を入力してください。';

  @override
  String get compressHistoryTitle => '履歴の圧縮';

  @override
  String get compressHistoryAllDays => 'すべて';

  @override
  String get globalCompressHistoryTitle => '全アプリ履歴の圧縮';

  @override
  String globalCompressHistoryDescription(Object days, Object size) {
    return '直近 $days 日間のすべてのアプリのスクリーンショットを $size KB に圧縮し、超過分のみ処理します。';
  }

  @override
  String globalCompressHistoryDescriptionAll(Object size) {
    return 'すべてのアプリのスクリーンショットを $size KB に圧縮し、超過分のみ処理します。';
  }

  @override
  String compressHistoryDescription(Object days, Object size) {
    return '直近 $days 日間のスクリーンショットを $size KB に圧縮し、超過分のみ処理します。';
  }

  @override
  String compressHistorySetDays(Object days) {
    return '日数: $days';
  }

  @override
  String compressHistorySetTarget(Object size) {
    return '目標サイズ: $size KB';
  }

  @override
  String compressHistoryProgress(Object handled, Object total, Object saved) {
    return '$handled/$total 件処理 • 節約 $saved';
  }

  @override
  String get compressHistoryAction => '今すぐ圧縮';

  @override
  String get compressHistoryCancelling => '停止中です。開始済みの画像は完了する場合があります…';

  @override
  String get compressHistoryCancelled => '圧縮をキャンセルしました。完了済みの変更は保持されます。';

  @override
  String get compressHistoryRequireTarget => '圧縮する前に目標サイズを有効にしてください。';

  @override
  String compressHistorySuccess(int count, Object size) {
    return '$count 件を圧縮し、$size を節約しました。';
  }

  @override
  String get compressHistoryNothing => '直近のスクリーンショットは既に目標サイズを満たしています。';

  @override
  String get compressHistoryFailure => '圧縮に失敗しました。もう一度お試しください。';

  @override
  String get exportDataTitle => 'データをエクスポート';

  @override
  String get exportDataDesc => 'ZIP を Download/ScreenMemory にエクスポート';

  @override
  String get importDataTitle => 'データをインポート';

  @override
  String get importDataDesc => 'ZIP ファイルをアプリストレージに取り込み';

  @override
  String get recalculateAllTitle => 'すべてのデータを再集計';

  @override
  String get recalculateAllDesc =>
      'すべてのアプリを再スキャンして、ナビゲーションの表示（日数・アプリ・スクリーンショット・サイズ）を更新します。';

  @override
  String get recalculateAllAction => '再集計';

  @override
  String get recalculateAllProgress => '全アプリの統計を再計算しています…';

  @override
  String get recalculateAllSuccess => '統計を再集計しました。';

  @override
  String get recalculateAllFailedTitle => '再集計に失敗しました';

  @override
  String get aiAssistantTitle => 'AI アシスタント';

  @override
  String get aiAssistantDesc => 'AI インターフェースとモデルを設定し、多段の会話をテスト';

  @override
  String get segmentSampleIntervalTitle => 'サンプル間隔 (秒)';

  @override
  String segmentSampleIntervalDesc(Object seconds) {
    return '現在: $seconds秒';
  }

  @override
  String get segmentDurationTitle => 'セグメントの長さ (分)';

  @override
  String segmentDurationDesc(Object minutes) {
    return '現在: $minutes 分';
  }

  @override
  String get aiRequestIntervalTitle => 'AI リクエストの最小間隔 (秒)';

  @override
  String aiRequestIntervalDesc(Object seconds) {
    return '現在: ${seconds}s (最小 1 秒)';
  }

  @override
  String get dynamicMergeMaxSpanTitle => '動的マージ：最大スパン (分)';

  @override
  String dynamicMergeMaxSpanDesc(Object minutes) {
    return '現在: $minutes 分 (0 = 無制限)';
  }

  @override
  String get dynamicMergeMaxGapTitle => '動的マージ：最大間隔 (分)';

  @override
  String dynamicMergeMaxGapDesc(Object minutes) {
    return '現在: $minutes 分 (0 = 無制限)';
  }

  @override
  String get dynamicMergeMaxImagesTitle => '動的マージ：最大画像数';

  @override
  String dynamicMergeMaxImagesDesc(Object count) {
    return '現在: $count 枚 (0 = 無制限)';
  }

  @override
  String get dynamicMergeLimitInputHint => '0 以上の整数を入力（0 = 無制限）';

  @override
  String get dynamicMergeLimitInvalidError => '0 以上の有効な整数を入力してください';

  @override
  String get dailyReminderTimeTitle => '毎日のサマリー通知時刻';

  @override
  String get currentTimeLabel => '現在：';

  @override
  String get testNotificationTitle => '通知をテスト';

  @override
  String get testNotificationDesc => '「毎日のサマリー」通知を今すぐトリガー';

  @override
  String get enableBannerNotificationTitle => 'バナー／フローティング通知を許可';

  @override
  String get enableBannerNotificationDesc => '画面上部に通知バナーを表示できるようにする';

  @override
  String get setIntervalDialogTitle => 'スクリーンショットの間隔を設定';

  @override
  String get intervalSecondsLabel => '間隔（秒）';

  @override
  String get intervalInputHint => '1 ～ 60 の整数を入力してください';

  @override
  String get intervalInvalidError => '1～60 の有効な整数を入力してください';

  @override
  String intervalSavedSuccess(Object seconds) {
    return 'スクリーンショット間隔を $seconds 秒に設定しました';
  }

  @override
  String get setTargetSizeDialogTitle => '目標サイズ（KB）を設定';

  @override
  String get targetSizeKbLabel => '目標サイズ（KB）';

  @override
  String get targetSizeInvalidError => '50 以上の有効な整数を入力してください';

  @override
  String targetSizeSavedSuccess(Object kb) {
    return '目標サイズを $kb KB に設定しました';
  }

  @override
  String get aiImageSendFormatTitle => 'AI 送信用画像形式';

  @override
  String aiImageSendFormatCurrent(Object format) {
    return '現在：$format（送信前のみ一時変換）';
  }

  @override
  String get aiImageSendFormatDialogTitle => 'AI 送信用画像形式を選択';

  @override
  String get aiImageSendFormatOriginal => '元の形式';

  @override
  String get aiImageSendFormatOriginalDesc => 'ローカルファイルを追加変換せずそのまま送信します';

  @override
  String get aiImageSendFormatJpeg => 'JPEG（互換性優先）';

  @override
  String get aiImageSendFormatJpegDesc =>
      '送信前に一時的に JPEG へ変換します。互換性は高いですが、文字の輪郭が少しぼやける場合があります';

  @override
  String get aiImageSendFormatPng => 'PNG（ロスレス）';

  @override
  String get aiImageSendFormatPngDesc =>
      '送信前に一時的に PNG へ変換します。画質はロスレスですが、サイズが大きくなる場合があります';

  @override
  String aiImageSendFormatSaved(Object format) {
    return 'AI 送信用画像形式を $format に設定しました';
  }

  @override
  String get setExpireDaysDialogTitle => 'スクリーンショットの保存日数を設定';

  @override
  String get expireDaysLabel => '保存日数';

  @override
  String get expireDaysInputHint => '1 以上の整数を入力してください';

  @override
  String get expireDaysInvalidError => '1 以上の有効な整数を入力してください';

  @override
  String expireDaysSavedSuccess(Object days) {
    return '$days 日に設定しました';
  }

  @override
  String get sortTimeNewToOld => '時間（新→旧）';

  @override
  String get sortTimeOldToNew => '時間（旧→新）';

  @override
  String get sortSizeLargeToSmall => 'サイズ（大→小）';

  @override
  String get sortSizeSmallToLarge => 'サイズ（小→大）';

  @override
  String get sortCountManyToFew => '数（多い→少ない）';

  @override
  String get sortCountFewToMany => '数（少ない→多い）';

  @override
  String get sortFieldTime => '時間';

  @override
  String get sortFieldCount => '件数';

  @override
  String get sortFieldSize => 'サイズ';

  @override
  String get selectHomeSortingTitle => 'ホームの並び順を選択';

  @override
  String currentSortingLabel(Object sorting) {
    return '現在：$sorting';
  }

  @override
  String get privacyModeEnabledToast => 'プライバシーモードを有効にしました';

  @override
  String get privacyModeDisabledToast => 'プライバシーモードを無効にしました';

  @override
  String get screenshotQualitySettingsSaved => 'スクリーンショットの品質設定を保存しました';

  @override
  String get autoAddNewAppsToCaptureEnabledToast => '新しいアプリの自動追加を有効にしました';

  @override
  String get autoAddNewAppsToCaptureDisabledToast => '新しいアプリの自動追加を無効にしました';

  @override
  String saveFailedError(Object error) {
    return '保存に失敗しました：$error';
  }

  @override
  String get setReminderTimeTitle => 'リマインダー時刻を設定（24 時間制）';

  @override
  String get hourLabel => '時（0～23）';

  @override
  String get minuteLabel => '分（0～59）';

  @override
  String get timeInputHint => 'ヒント：数字を直接入力できます。範囲は 0～23 時、0～59 分です。';

  @override
  String get invalidHourError => '0～23 の有効な時刻を入力してください';

  @override
  String get invalidMinuteError => '0～59 の有効な分を入力してください';

  @override
  String timeSetSuccess(Object hour, Object minute) {
    return '$hour:$minute に設定しました';
  }

  @override
  String reminderScheduleSuccess(Object hour, Object minute) {
    return '毎日のリマインダーを $hour:$minute に設定しました';
  }

  @override
  String get reminderDisabledSuccess => '毎日のリマインダーを無効にしました';

  @override
  String get reminderScheduleFailed =>
      '毎日のリマインダーをスケジュールできませんでした（プラットフォームが非対応の可能性があります）';

  @override
  String saveReminderSettingsFailed(Object error) {
    return 'リマインダー設定の保存に失敗しました：$error';
  }

  @override
  String searchFailedError(Object error) {
    return '検索に失敗しました: $error';
  }

  @override
  String get searchInputHintOcr => 'キーワードを入力して OCR でスクリーンショットを検索します';

  @override
  String get noMatchingScreenshots => '一致するスクリーンショットはありません';

  @override
  String get imageMissingOrCorrupted => '画像が見つからないか破損しています';

  @override
  String get actionClear => 'クリア';

  @override
  String get actionRefresh => '更新';

  @override
  String get actionApply => '適用';

  @override
  String get noScreenshotsTitle => 'スクリーンショットはまだありません';

  @override
  String get noScreenshotsSubtitle => '監視を有効にするとここに画像が表示されます';

  @override
  String get confirmDeleteTitle => '削除の確認';

  @override
  String get confirmDeleteMessage => 'このスクリーンショットを削除しますか？この操作は元に戻せません。';

  @override
  String get actionDelete => '削除';

  @override
  String get actionContinue => '続行';

  @override
  String get linkTitle => 'リンク';

  @override
  String get actionCopy => 'コピー';

  @override
  String get imageInfoTitle => 'スクリーンショット情報';

  @override
  String get deleteImageTooltip => '画像の削除';

  @override
  String get imageLoadFailed => '画像の読み込みに失敗しました';

  @override
  String get labelAppName => 'アプリ名';

  @override
  String get labelCaptureTime => 'キャプチャ時間';

  @override
  String get labelFilePath => 'ファイルパス';

  @override
  String get labelPageLink => 'ページリンク';

  @override
  String get labelFileSize => 'ファイルサイズ';

  @override
  String get tapToContinue => 'タップして続行';

  @override
  String get appDirUninitialized => 'アプリディレクトリが初期化されていません';

  @override
  String get actionRetry => 'リトライ';

  @override
  String get appHealthLoadFailed => 'アプリ健全性の読み込みに失敗しました';

  @override
  String get appHealthRefreshStatus => '状態を更新';

  @override
  String get appHealthCustomHours => 'カスタム時間';

  @override
  String get appHealthCustomRangeTitle => 'カスタム時間範囲';

  @override
  String get appHealthRecentHoursLabel => '直近の時間数';

  @override
  String get appHealthRecentHoursHint => '例: 12';

  @override
  String get appHealthInvalidRangeHours => '時間範囲が無効です';

  @override
  String get deleteSelectedTooltip => '選択項目を削除';

  @override
  String get noMatchingResults => '一致する結果はありません';

  @override
  String dayTabToday(Object count) {
    return '今日 $count';
  }

  @override
  String dayTabYesterday(Object count) {
    return '昨日 $count';
  }

  @override
  String dayTabMonthDayCount(Object month, Object day, Object count) {
    return '$month/$day $count';
  }

  @override
  String get screenshotDeletedToast => 'スクリーンショットが削除されました';

  @override
  String get deleteFailed => '削除に失敗しました';

  @override
  String deleteFailedWithError(Object error) {
    return '削除に失敗しました: $error';
  }

  @override
  String get imageInfoTooltip => '画像情報';

  @override
  String get copySuccess => 'コピーしました';

  @override
  String get copyFailed => 'コピーに失敗しました';

  @override
  String deletedCountToast(Object count) {
    return 'スクリーンショットを $count 件削除しました';
  }

  @override
  String get invalidArguments => '無効な引数';

  @override
  String initFailedWithError(Object error) {
    return '初期化に失敗しました: $error';
  }

  @override
  String get loadMore => 'さらに読み込む';

  @override
  String loadMoreFailedWithError(Object error) {
    return 'さらにロードできませんでした: $error';
  }

  @override
  String get dateJumpTitle => '日付へ移動';

  @override
  String get dateJumpOpenTooltip => '日付へ移動';

  @override
  String get dateJumpPreviousMonth => '前の月';

  @override
  String get dateJumpNextMonth => '次の月';

  @override
  String get dateJumpLoadFailed => '日付の読み込みに失敗しました';

  @override
  String get dateJumpFailed => '日付への移動に失敗しました';

  @override
  String get dateJumpWeekdayMon => '月';

  @override
  String get dateJumpWeekdayTue => '火';

  @override
  String get dateJumpWeekdayWed => '水';

  @override
  String get dateJumpWeekdayThu => '木';

  @override
  String get dateJumpWeekdayFri => '金';

  @override
  String get dateJumpWeekdaySat => '土';

  @override
  String get dateJumpWeekdaySun => '日';

  @override
  String get confirmDeleteAllTitle => 'すべてのスクリーンショットの削除を確認する';

  @override
  String deleteAllMessage(Object count) {
    return '現在のスコープ内のすべての $count スクリーンショットを削除します。この操作は元に戻すことができません。';
  }

  @override
  String deleteSelectedMessage(Object count) {
    return '選択した $count 個のスクリーンショットを削除します。これを元に戻すことはできません。続く？';
  }

  @override
  String get deleteFailedRetry => '削除に失敗しました。再試行してください';

  @override
  String keptAndDeletedSummary(Object keep, Object deleted) {
    return '$keep を保持、$deleted を削除';
  }

  @override
  String dailySummaryTitle(Object date) {
    return '毎日の概要 $date';
  }

  @override
  String dailySummarySlotMorningTitle(Object date) {
    return '朝のブリーフィング $date';
  }

  @override
  String dailySummarySlotNoonTitle(Object date) {
    return '正午のブリーフィング $date';
  }

  @override
  String dailySummarySlotEveningTitle(Object date) {
    return '夜のブリーフィング $date';
  }

  @override
  String dailySummarySlotNightTitle(Object date) {
    return '夜のブリーフィング $date';
  }

  @override
  String get actionGenerate => '生成';

  @override
  String get actionRegenerate => '再生成';

  @override
  String get generateSuccess => '生成しました';

  @override
  String get generateFailed => '生成に失敗しました';

  @override
  String get noDailySummaryToday => '本日のサマリーはありません';

  @override
  String get generateDailySummary => '今日のサマリーを生成';

  @override
  String get dailySummaryGeneratingTitle => '今日の要約を生成しています';

  @override
  String get dailySummaryGeneratingHint => '読みやすいレイアウトを保ったまま、生成結果を順に反映します。';

  @override
  String get statisticsTitle => '統計';

  @override
  String get overviewTitle => '概要';

  @override
  String get monitoredApps => '監視対象アプリ';

  @override
  String get totalScreenshots => 'スクリーンショットの総数';

  @override
  String get todayScreenshots => '今日のスクリーンショット';

  @override
  String get storageUsage => 'ストレージの使用量';

  @override
  String get appStatisticsTitle => 'アプリの統計';

  @override
  String screenshotCountWithLast(Object count, Object last) {
    return 'スクリーンショット: $count |最後: $last';
  }

  @override
  String get none => 'なし';

  @override
  String get usageTrendsTitle => '使用傾向';

  @override
  String get trendChartTitle => 'トレンドチャート';

  @override
  String get comingSoon => '近日公開';

  @override
  String get timelineTitle => 'タイムライン';

  @override
  String get timelineReplay => 'リプレイ';

  @override
  String get timelineReplayGenerate => 'リプレイを生成';

  @override
  String get timelineReplayUseSelectedDay => '選択した日を使用';

  @override
  String get timelineReplayStartTime => '開始時刻';

  @override
  String get timelineReplayEndTime => '終了時刻';

  @override
  String get timelineReplayDuration => '目標時間';

  @override
  String get timelineReplayFps => 'FPS';

  @override
  String get timelineReplayResolution => '解像度';

  @override
  String get timelineReplayQuality => '品質';

  @override
  String get timelineReplayOverlay => '時間/アプリを重ねる';

  @override
  String get timelineReplaySaveToGallery => '生成後にギャラリーへ保存';

  @override
  String get timelineReplayAppProgressBar => 'アプリ進捗バー';

  @override
  String get timelineReplayNsfw => 'NSFW コンテンツ';

  @override
  String get timelineReplayNsfwMask => 'マスクを表示';

  @override
  String get timelineReplayNsfwShow => '完全表示';

  @override
  String get timelineReplayNsfwHide => '非表示';

  @override
  String get timelineReplayFpsInvalid => '1〜120 を入力してください';

  @override
  String timelineReplayGeneratingRange(Object range) {
    return '$rangeの動画を生成中…';
  }

  @override
  String get timelineReplayPreparing => 'リプレイを準備中…';

  @override
  String get timelineReplayEncoding => '動画を生成中…';

  @override
  String get timelineReplayNoScreenshots => 'この時間帯にスクリーンショットがありません';

  @override
  String get timelineReplayFailed => 'リプレイの生成に失敗しました';

  @override
  String get timelineReplayReady => 'リプレイを生成しました';

  @override
  String get timelineReplayNotificationHint => 'リプレイを生成中です。通知で進捗を確認できます';

  @override
  String get pressBackAgainToExit => 'もう一度戻るボタンを押して終了します';

  @override
  String get segmentStatusTitle => '活動';

  @override
  String get autoWatchingHint => 'バックグラウンドで自動視聴中…';

  @override
  String get noEvents => 'イベントはありません';

  @override
  String get noEventsSubtitle => 'イベントセグメントと AI の概要がここに表示されます';

  @override
  String get activeSegmentTitle => 'アクティブセグメント';

  @override
  String sampleEverySeconds(Object seconds) {
    return '$seconds秒ごとにサンプリング';
  }

  @override
  String get dailySummaryShort => '毎日のサマリー';

  @override
  String get weeklySummaryShort => '週間サマリー';

  @override
  String weeklySummaryTitle(Object range) {
    return '週間サマリー $range';
  }

  @override
  String get weeklySummaryEmpty => '週間サマリーはまだありません';

  @override
  String get weeklySummarySelectWeek => '週を選択';

  @override
  String get weeklySummaryOverviewTitle => '今週の概要';

  @override
  String get weeklySummaryDailyTitle => '日別ハイライト';

  @override
  String get weeklySummaryActionsTitle => '来週への提案';

  @override
  String get weeklySummaryNotificationTitle => '通知ブリーフ';

  @override
  String get weeklySummaryNoContent => '内容がありません';

  @override
  String get weeklySummaryViewDetail => '詳細を見る';

  @override
  String get viewOrGenerateForDay => 'その日の概要を表示または生成する';

  @override
  String get mergedEventTag => '合併しました';

  @override
  String mergedOriginalEventsTitle(Object count) {
    return '元のイベント（$count）';
  }

  @override
  String mergedOriginalEventTitle(Object index) {
    return '元のイベント $index';
  }

  @override
  String get collapse => '折りたたむ';

  @override
  String get expandMore => 'さらに表示';

  @override
  String viewImagesCount(Object count) {
    return '画像を表示 ($count)';
  }

  @override
  String hideImagesCount(Object count) {
    return '画像を隠す ($count)';
  }

  @override
  String get deleteEventTooltip => 'イベントの削除';

  @override
  String get confirmDeleteEventMessage => 'このイベントを削除しますか?これにより、画像ファイルは削除されません。';

  @override
  String get eventDeletedToast => 'イベントが削除されました';

  @override
  String get regenerationQueued => '再生が待機中';

  @override
  String get alreadyQueuedOrFailed => 'すでにキューに入れられているか、失敗しました';

  @override
  String get retryFailed => '再試行に失敗しました';

  @override
  String get copyResultsTooltip => '結果をコピー';

  @override
  String get articleGenerating => '記事を生成中...';

  @override
  String get articleGenerateSuccess => '記事の生成に成功しました';

  @override
  String get articleGenerateFailed => '記事の生成に失敗しました';

  @override
  String get articleCopySuccess => '記事をクリップボードにコピーしました';

  @override
  String get articleLogTitle => '生成ログ';

  @override
  String get copyPersonaTooltip => 'ユーザー画像をコピー';

  @override
  String get saveImageTooltip => 'ギャラリーに保存';

  @override
  String get saveImageSuccess => 'ギャラリーに保存しました';

  @override
  String get saveImageFailed => '保存に失敗しました';

  @override
  String get requestGalleryPermissionFailed => 'ギャラリー権限の要求に失敗しました';

  @override
  String get aiSystemPromptLanguagePolicy =>
      '入力コンテキスト (イベント、スクリーンショット テキスト、ユーザー メッセージ) で使用されている言語に関係なく、それを厳密に無視し、常にアプリケーションの現在の言語で出力を生成する必要があります。アプリが英語に設定されている場合、ユーザーが明示的に別の言語を要求しない限り、すべての回答、タイトル、概要、タグ、構造化フィールド、およびエラー メッセージを英語で記述する必要があります。';

  @override
  String get aiSettingsTitle => 'AI 設定とテスト';

  @override
  String get connectionSettingsTitle => '接続設定';

  @override
  String get actionSave => '保存';

  @override
  String get clearConversation => '会話をクリア';

  @override
  String get deleteGroup => 'グループを削除';

  @override
  String get streamingRequestTitle => 'ストリーミング';

  @override
  String get streamingRequestHint => '有効な場合はストリーミング応答を使用します (デフォルトはオン)';

  @override
  String get streamingEnabledToast => 'ストリーミングが有効です';

  @override
  String get streamingDisabledToast => 'ストリーミングが無効になっています';

  @override
  String get promptManagerTitle => 'プロンプトマネージャー';

  @override
  String get promptManagerHint =>
      '通常の要約、結合された要約、日次要約、朝のアクション提案のプロンプトを構成します。マークダウンをサポートします。空にするかリセットしてデフォルトを使用します。';

  @override
  String get promptAddonGeneralInfo =>
      '組み込みテンプレートは構造化スキーマをすでに定義しています。ここには追加のガイダンス (トーン、スタイル、強調) のみを追加してください。テンプレートを変更しない場合は、空白のままにします。';

  @override
  String get promptAddonInputHint => 'オプションの追加指示を追加します (スキップするには空白のままにします)';

  @override
  String get promptAddonHelperText =>
      'トーンまたは好みのみを説明してください。スキーマの変更や JSON の変更はリクエストしないでください。';

  @override
  String get promptAddonEmptyPlaceholder => '余分な指示はありません';

  @override
  String get promptAddonSuggestionSegment =>
      '提案されたアイデア:\n- 希望するトーンや対象読者を一文で述べます\n- 優先すべき重要な洞察や安全上の制約を強調表示します\n- JSON フィールドの追加や構造の変更を要求しないようにします。';

  @override
  String get promptAddonSuggestionMerge =>
      '提案されたアイデア:\n- マージ後のサーフェスとの比較または対照を強調します。\n- モデルに繰り返しを避け、集約された洞察に焦点を当てるよう思い出させます。\n- 出力フィールドの構造変更を要求しないでください。';

  @override
  String get promptAddonSuggestionDaily =>
      '提案されたアイデア:\n- 毎日の要約のトーンを指定します (例: アクション指向)\n- 主要な成果やリスクを強調するように依頼する\n- JSON フィールドの名前変更または追加を禁止します';

  @override
  String get promptAddonSuggestionWeekly =>
      '提案されたアイデア:\n- 週ごとのトレンドや変化点を強調する\n- 次のアクションや注意点を促す\n- JSON 出力の構造変更を要求しない';

  @override
  String get promptAddonSuggestionMorning =>
      'ヒント例:\n- ヒューマンタッチや穏やかなリズム、ささやかな癒やしを強調\n- テンプレ調やタスク駆動の口調を避けるよう指示\n- JSON フィールド変更や過度の疑問文を求めない';

  @override
  String get normalEventPromptLabel => '通常のイベントプロンプト';

  @override
  String get mergeEventPromptLabel => 'マージされたイベントプロンプト';

  @override
  String get dailySummaryPromptLabel => '毎日の概要プロンプト';

  @override
  String get weeklySummaryPromptLabel => '週間サマリープロンプト';

  @override
  String get morningInsightsPromptLabel => '朝のアクション提案プロンプト';

  @override
  String get actionEdit => '編集';

  @override
  String get savingLabel => '保存中';

  @override
  String get resetToDefault => 'デフォルトにリセット';

  @override
  String get chatTestTitle => 'チャットテスト';

  @override
  String get actionSend => '送信';

  @override
  String get sendingLabel => '送信中';

  @override
  String get baseUrlLabel => 'ベース URL';

  @override
  String get baseUrlHint => '例えばhttps://api.openai.com';

  @override
  String get apiKeyLabel => 'APIキー';

  @override
  String get apiKeyHint => '例えばsk-... またはベンダートークン';

  @override
  String get modelLabel => 'モデル';

  @override
  String get modelHint => '例えばgpt-4o-mini / gpt-4o / 互換';

  @override
  String get siteGroupsTitle => 'サイトグループ';

  @override
  String get siteGroupsHint => '複数のサイトをフォールバックとして設定し、失敗時に自動で切り替えます';

  @override
  String get rename => '名前の変更';

  @override
  String get addGroup => 'グループを追加';

  @override
  String get showGroupSelector => 'グループセレクターを表示';

  @override
  String get ungroupedSingleConfig => 'グループ化されていない (単一構成)';

  @override
  String get inputMessageHint => 'メッセージを入力';

  @override
  String get saveSuccess => '保存しました';

  @override
  String get savedCurrentGroupToast => 'グループを保存しました';

  @override
  String get savedNormalPromptToast => '通常プロンプトを保存しました';

  @override
  String get savedMergePromptToast => '結合プロンプトを保存しました';

  @override
  String get savedDailyPromptToast => '日次プロンプトを保存しました';

  @override
  String get savedWeeklyPromptToast => '週次プロンプトを保存しました';

  @override
  String get resetToDefaultPromptToast => 'デフォルトのプロンプトにリセットしました';

  @override
  String resetFailedWithError(Object error) {
    return 'リセットに失敗しました: $error';
  }

  @override
  String get clearSuccess => 'クリアしました';

  @override
  String clearFailedWithError(Object error) {
    return 'クリアに失敗しました：$error';
  }

  @override
  String get messageCannotBeEmpty => 'メッセージを入力してください';

  @override
  String sendFailedWithError(Object error) {
    return '送信に失敗しました：$error';
  }

  @override
  String get groupSwitchedToUngrouped => '未分類に切り替えました';

  @override
  String get groupSwitched => 'グループを切り替えました';

  @override
  String get groupNotSelected => 'グループが選択されていません';

  @override
  String get groupNotFound => 'グループが見つかりません';

  @override
  String get renameGroupTitle => 'グループ名を変更';

  @override
  String get groupNameLabel => 'グループ名';

  @override
  String get groupNameHint => '新しいグループ名を入力してください';

  @override
  String get nameCannotBeEmpty => '名前を入力してください';

  @override
  String get renameSuccess => '名称を変更しました';

  @override
  String renameFailedWithError(Object error) {
    return '名称変更に失敗しました：$error';
  }

  @override
  String get groupAddedToast => 'グループを追加しました';

  @override
  String addGroupFailedWithError(Object error) {
    return 'グループの追加に失敗しました：$error';
  }

  @override
  String get groupDeletedToast => 'グループを削除しました';

  @override
  String deleteGroupFailedWithError(Object error) {
    return 'グループの削除に失敗しました：$error';
  }

  @override
  String loadGroupFailedWithError(Object error) {
    return 'グループの読み込みに失敗しました：$error';
  }

  @override
  String siteGroupDefaultName(Object index) {
    return 'サイトグループ $index';
  }

  @override
  String get defaultLabel => 'デフォルト';

  @override
  String get customLabel => 'カスタム';

  @override
  String get normalShortLabel => '通常：';

  @override
  String get mergeShortLabel => '結合：';

  @override
  String get dailyShortLabel => '日次：';

  @override
  String timeRangeLabel(Object range) {
    return '時間帯：$range';
  }

  @override
  String statusLabel(Object status) {
    return 'ステータス：$status';
  }

  @override
  String samplesTitle(Object count) {
    return 'サンプル（$count）';
  }

  @override
  String get aiResultTitle => 'AIの結果';

  @override
  String get aiResultAutoRetriedHint => 'この結果は不完全なAI応答を補うために自動で1回再試行されました。';

  @override
  String get aiResultAutoRetryFailedHint => '自動再試行でも失敗しました。手動で再生成してください。';

  @override
  String modelValueLabel(Object model) {
    return 'モデル：$model';
  }

  @override
  String get tagMergedCopy => 'タグ：結合済み';

  @override
  String categoriesLabel(Object categories) {
    return 'カテゴリ：$categories';
  }

  @override
  String errorLabel(Object error) {
    return 'エラー：$error';
  }

  @override
  String summaryLabel(Object summary) {
    return '概要：$summary';
  }

  @override
  String get autostartPermissionNote =>
      '自動起動権限はメーカーによって異なり自動検出できません。実際の設定に合わせて選択してください。';

  @override
  String monthDayTime(Object month, Object day, Object hour, Object minute) {
    return '$month/$day $hour:$minute';
  }

  @override
  String yearMonthDayTime(
    Object year,
    Object month,
    Object day,
    Object hour,
    Object minute,
  ) {
    return '$year/$month/$day $hour:$minute';
  }

  @override
  String imagesCountLabel(Object count) {
    return '$count 枚';
  }

  @override
  String get apps => 'アプリ';

  @override
  String get images => '画像';

  @override
  String get days => '日';

  @override
  String get aiImageTagsTitle => '画像タグ';

  @override
  String get aiVisibleTextTitle => '表示テキスト';

  @override
  String get aiImageDescriptionsTitle => '画像説明';

  @override
  String get justNow => 'ちょうど今';

  @override
  String minutesAgo(Object minutes) {
    return '$minutes 分前';
  }

  @override
  String hoursAgo(Object hours) {
    return '$hours 時間前';
  }

  @override
  String daysAgo(Object days) {
    return '$days 日前';
  }

  @override
  String searchResultsCount(Object count) {
    return '$count 件の画像が見つかりました';
  }

  @override
  String get searchFiltersTitle => 'フィルター';

  @override
  String get filterByTime => '時間';

  @override
  String get filterByApp => 'アプリ';

  @override
  String get filterBySize => 'サイズ';

  @override
  String get filterTimeAll => 'すべて';

  @override
  String get filterTimeToday => '今日';

  @override
  String get filterTimeYesterday => '昨日';

  @override
  String get filterTimeLast7Days => '過去 7 日間';

  @override
  String get filterTimeLast30Days => '過去 30 日間';

  @override
  String get filterTimeCustomDays => 'カスタム日数';

  @override
  String get filterTimeCustomDaysHint => '1〜365日を入力';

  @override
  String get filterTimeCustomRange => 'カスタム範囲';

  @override
  String get filterAppAll => 'すべてのアプリ';

  @override
  String get filterSizeAll => 'すべてのサイズ';

  @override
  String get filterSizeSmall => '100 KB 未満';

  @override
  String get filterSizeMedium => '100 KB ～ 1 MB';

  @override
  String get filterSizeLarge => '1 MB 超';

  @override
  String get applyFilters => '適用';

  @override
  String get resetFilters => 'リセット';

  @override
  String get selectDateRange => '日付範囲を選択';

  @override
  String get startDate => '開始日';

  @override
  String get endDate => '終了日';

  @override
  String get noResultsForFilters => '現在のフィルターに一致する画像はありません';

  @override
  String get openLink => '開く';

  @override
  String get favoritePageTitle => 'お気に入り';

  @override
  String get noFavoritesTitle => 'お気に入りはありません';

  @override
  String get noFavoritesSubtitle => 'ギャラリーで長押しして複数選択モードにするとお気に入りに追加できます';

  @override
  String get noteLabel => 'メモ';

  @override
  String get updatedAt => '更新日：';

  @override
  String get clickToAddNote => 'クリックしてメモを追加...';

  @override
  String get noteUnchanged => 'メモに変更はありません';

  @override
  String get noteSaved => 'メモを保存しました';

  @override
  String get favoritesRemoved => 'お気に入りから削除しました';

  @override
  String get operationFailed => '操作に失敗しました';

  @override
  String get cannotGetAppDir => 'アプリのディレクトリを取得できません';

  @override
  String get nsfwSettingsSectionTitle => 'NSFW 設定';

  @override
  String get blockedDomainListTitle => 'ブロック対象ドメイン';

  @override
  String get addDomainPlaceholder => 'ドメインまたは *.example.com';

  @override
  String get addRuleAction => '追加';

  @override
  String get previewAction => 'プレビュー';

  @override
  String get removeAction => '削除';

  @override
  String get clearAction => 'クリア';

  @override
  String get clearAllRules => 'すべてのルールをクリア';

  @override
  String get clearAllRulesConfirmTitle => 'ルールの削除を確認';

  @override
  String get clearAllRulesMessage => 'すべてのブロック対象ドメインを削除します。この操作は元に戻せません。';

  @override
  String previewAffectsCount(Object count) {
    return '$count 枚に影響します';
  }

  @override
  String affectCountLabel(Object count) {
    return '影響：$count';
  }

  @override
  String get confirmAddRuleTitle => 'ルール追加の確認';

  @override
  String confirmAddRuleMessage(Object rule) {
    return 'ルールを追加：$rule';
  }

  @override
  String get ruleAddedToast => 'ルールを追加しました';

  @override
  String get ruleRemovedToast => 'ルールを削除しました';

  @override
  String get invalidDomainInputError => '有効なドメインを入力してください（*.example.com に対応）';

  @override
  String get manualMarkNsfw => 'NSFW としてマーク';

  @override
  String get manualUnmarkNsfw => 'NSFW マークを解除';

  @override
  String get manualMarkSuccess => 'NSFW としてマークしました';

  @override
  String get manualUnmarkSuccess => 'NSFW マークを解除しました';

  @override
  String get manualMarkFailed => '操作に失敗しました';

  @override
  String get nsfwTagLabel => 'NSFW';

  @override
  String get nsfwBlockedByRulesHint =>
      'NSFW ルールによりブロックされています。設定 > NSFW ドメインで管理してください。';

  @override
  String get providersTitle => 'プロバイダー';

  @override
  String get actionNew => '新規作成';

  @override
  String get actionAdd => '追加';

  @override
  String get noProvidersYetHint => 'まだプロバイダーがありません。「新規作成」をタップして追加してください。';

  @override
  String confirmDeleteProviderMessage(Object name) {
    return 'プロバイダー「$name」を削除しますか？この操作は元に戻せません。';
  }

  @override
  String get loadingConversations => '会話を読み込み中…';

  @override
  String get noConversations => '会話がありません';

  @override
  String get deleteConversationTitle => '会話を削除';

  @override
  String confirmDeleteConversationMessage(Object title) {
    return '会話「$title」を削除しますか？';
  }

  @override
  String get untitledConversationLabel => '無題の会話';

  @override
  String get searchProviderPlaceholder => 'プロバイダーを検索';

  @override
  String get searchModelPlaceholder => 'モデルを検索';

  @override
  String providerSelectedToast(Object name) {
    return '選択したプロバイダー：$name';
  }

  @override
  String get pleaseSelectProviderFirst => 'まずプロバイダーを選択してください';

  @override
  String get noModelsForProviderHint =>
      '利用可能なモデルがありません。「プロバイダー」ページで更新するか手動で追加してください。';

  @override
  String get noModelsDetectedHint => '利用可能なモデルが見つかりません。更新するか手動で追加してください。';

  @override
  String modelSwitchedToast(Object model) {
    return 'モデルを切り替えました：$model';
  }

  @override
  String get providerLabel => 'プロバイダー';

  @override
  String sendMessageToModelPlaceholder(Object model) {
    return '$model にメッセージを送信';
  }

  @override
  String get deepThinkingLabel => '詳細推論';

  @override
  String get thinkingInProgress => '思考中…';

  @override
  String get webSearchProcessTitle => '検索プロセス';

  @override
  String get webSearchProcessSearchingTitle => '検索プロセス · 検索中';

  @override
  String webSearchProgressSummary(int siteCount, int pageCount) {
    return '$siteCount 件のサイトを検索 · $pageCount ページを表示';
  }

  @override
  String get requestStoppedInfo => 'リクエストを停止しました';

  @override
  String get reasoningLabel => '推論:';

  @override
  String get answerLabel => '答え：';

  @override
  String get aiSelfModeEnabledToast => 'パーソナルアシスタント：会話であなたのデータコンテキストを使用します';

  @override
  String selectModelWithCounts(Object filtered, Object total) {
    return 'モデルを選択（$filtered/$total）';
  }

  @override
  String modelsCountLabel(Object count) {
    return 'モデル（$count）';
  }

  @override
  String get manualAddModelLabel => 'モデルを手動で追加';

  @override
  String get inputAndAddModelHint => '入力して追加（例：gpt-4o-mini）';

  @override
  String get fetchModelsHint => '「更新」を押すと自動取得します。失敗した場合は手動でモデル名を追加してください。';

  @override
  String get interfaceTypeLabel => 'インターフェース種別';

  @override
  String get providerTypeOpenAI => 'OpenAI';

  @override
  String get providerTypeAzureOpenAI => 'Azure OpenAI';

  @override
  String get providerTypeClaude => 'Claude';

  @override
  String get providerTypeGemini => 'Gemini';

  @override
  String currentTypeLabel(Object type) {
    return '現在：$type';
  }

  @override
  String get nameRequiredError => '名前は必須です';

  @override
  String get nameAlreadyExistsError => '同じ名前が既に存在します';

  @override
  String get apiKeyRequiredError => 'API キーは必須です';

  @override
  String get baseUrlRequiredForAzureError => 'Azure OpenAI には Base URL が必要です';

  @override
  String get atLeastOneModelRequiredError => 'モデルを少なくとも 1 つ追加してください';

  @override
  String modelsUpdatedToast(Object count) {
    return 'モデルを更新しました（$count）';
  }

  @override
  String get fetchModelsFailedHint => 'モデルの取得に失敗しました。手動で追加できます。';

  @override
  String get useResponseApiLabel =>
      'Response API を使用（公式 OpenAI のみ対応。サードパーティは推奨されません）';

  @override
  String get providerApiModeChatTitle => 'Chat';

  @override
  String get providerApiModeResponsesTitle => 'Responses';

  @override
  String get modelsPathOptionalLabel => 'モデルパス（任意）';

  @override
  String get chatPathOptionalLabel => 'チャットパス（任意）';

  @override
  String get azureApiVersionLabel => 'Azure API バージョン';

  @override
  String get azureApiVersionHint => '例：2024-02-15';

  @override
  String get baseUrlHintOpenAI => '例：https://api.openai.com（空欄で既定）';

  @override
  String get baseUrlHintClaude => '例：https://api.anthropic.com';

  @override
  String get baseUrlHintGemini => '例：https://generativelanguage.googleapis.com';

  @override
  String get geminiRegionDialogTitle => 'Gemini の利用制限';

  @override
  String get geminiRegionDialogMessage =>
      'Gemini 開発者 API は Google がサポートする国・地域からのみ利用できます。Google アカウント情報、請求情報、ネットワーク出口がサポート対象地域にあることを確認してください。条件を満たさない場合、サーバーは FAILED_PRECONDITION を返します。企業利用が必要な場合は、対象地域内の準拠したプロキシ経由でリクエストしてください。';

  @override
  String get geminiRegionToast =>
      'Gemini は対応地域でのみ利用できます。詳細はクエスチョンマークをタップしてください。';

  @override
  String baseUrlHintAzure(Object resource) {
    return '必須： https://$resource.openai.azure.com';
  }

  @override
  String get baseUrlHintCustom => 'OpenAI 互換の Base URL を入力してください';

  @override
  String get createProviderTitle => '新規プロバイダー';

  @override
  String get editProviderTitle => 'プロバイダーを編集';

  @override
  String get providerRequestHeadersTitle => 'リクエストヘッダー';

  @override
  String providerRequestHeadersDesc(
    Object apiKeyPlaceholder,
    Object uuidPlaceholder,
    Object sessionIdPlaceholder,
    Object threadIdPlaceholder,
    Object installationIdPlaceholder,
    Object windowIdPlaceholder,
    Object timestampMsPlaceholder,
  ) {
    return '任意のカスタムヘッダーは、チャット、モデル更新、Key テスト、画像生成に送信されます。$apiKeyPlaceholder、$uuidPlaceholder、$sessionIdPlaceholder、$threadIdPlaceholder、$installationIdPlaceholder、$windowIdPlaceholder、$timestampMsPlaceholder プレースホルダーを使用できます。';
  }

  @override
  String get providerRequestHeadersEmpty =>
      'カスタムリクエストヘッダーはありません。組み込みの認証ヘッダーを使用します。';

  @override
  String get providerRequestHeaderApplyTemplate => 'テンプレートを適用';

  @override
  String get providerRequestHeaderAdd => 'ヘッダーを追加';

  @override
  String get providerRequestHeaderRemove => 'ヘッダーを削除';

  @override
  String get providerRequestHeaderNameLabel => 'ヘッダー名';

  @override
  String get providerRequestHeaderValueLabel => 'ヘッダー値';

  @override
  String get providerRequestHeaderNameHint => 'Authorization';

  @override
  String providerRequestHeaderValueHint(
    Object apiKeyPlaceholder,
    Object uuidPlaceholder,
  ) {
    return 'Bearer $apiKeyPlaceholder / $uuidPlaceholder';
  }

  @override
  String providerRequestHeaderInvalid(Object name) {
    return 'Invalid request header: $name';
  }

  @override
  String get providerRequestHeaderTemplateOpenAI => 'OpenAI';

  @override
  String get providerRequestHeaderTemplateAnthropic => 'Anthropic / Claude API';

  @override
  String get providerRequestHeaderTemplateCodex => 'Codex 互換';

  @override
  String get providerRequestHeaderTemplateClaudeCode => 'Claude Code API key';

  @override
  String get deletedToast => '削除しました';

  @override
  String get providerNotFound => 'プロバイダーが見つかりません';

  @override
  String get conversationsSectionTitle => '会話';

  @override
  String get displaySectionTitle => '表示';

  @override
  String get displaySectionDesc => 'テーマモード/プライバシー/NSFW';

  @override
  String get themeModeTitle => 'テーマモード';

  @override
  String get streamRenderImagesTitle => 'ストリーミング中に画像を描画';

  @override
  String get streamRenderImagesDesc => 'スクロールに影響する場合があります';

  @override
  String get aiChatPerfOverlayTitle => 'AIChat パフォーマンスオーバーレイ';

  @override
  String get aiChatPerfOverlayDesc =>
      'AIChat ページに Perf ログウィンドウを表示（トラブルシューティング用）';

  @override
  String get themeColorTitle => 'テーマカラー';

  @override
  String get themeColorDesc => 'アプリで使用中のセマンティックカラーをカスタマイズ';

  @override
  String get chooseThemeColorTitle => 'テーマカラーを選択';

  @override
  String get themeColorsSheetTitle => 'テーマカラーをカスタマイズ';

  @override
  String get themeColorsLightBaseGroup => 'ライト基本色';

  @override
  String get themeColorsStatusGroup => '状態とアクセント色';

  @override
  String get themeColorsLightSurfaceGroup => 'ライトのサーフェス階層';

  @override
  String get themeColorsDarkBaseGroup => 'ダーク基本色';

  @override
  String get themeColorsDarkSurfaceGroup => 'ダークのサーフェス階層';

  @override
  String get themeColorsDefaultBadge => 'デフォルト';

  @override
  String get themeColorsCustomBadge => 'カスタム';

  @override
  String get themeColorHexLabel => 'Hex カラー';

  @override
  String get themeColorHexFormatHint => '#RRGGBB または #AARRGGBB を使用';

  @override
  String get themeColorInvalidHex =>
      '有効な Hex カラーを入力してください。例: #66FF66 または #FF66FF66';

  @override
  String get themeColorSaved => 'テーマカラーを保存しました';

  @override
  String get themeColorsResetSaved => 'テーマカラーをデフォルトに戻しました';

  @override
  String get themeColorsPasteTooltip => 'テーマカラーを貼り付け';

  @override
  String get themeColorsPasteEmpty => 'クリップボードが空です';

  @override
  String get themeColorsPasteInvalid => 'クリップボードに有効なテーマカラー JSON がありません';

  @override
  String get themeColorsPasteSaved => 'テーマカラーをインポートしました';

  @override
  String get themeColorsCopyTooltip => 'テーマカラー JSON をコピー';

  @override
  String get themeColorsCopySaved => 'テーマカラー JSON をコピーしました';

  @override
  String get themeColorsPresetGroup => 'カラープリセット';

  @override
  String get themeColorsPresetDefault => '既定カーキ';

  @override
  String get themeColorsPresetGreen => 'フレッシュグリーン';

  @override
  String themeColorsPresetSaved(Object name) {
    return 'カラープリセットを適用しました: $name';
  }

  @override
  String get dynamicTagPaletteTitle => '動的タグカラー';

  @override
  String get dynamicTagPaletteDescDefault => '通常タグはテキストに応じて 7 色から自動割り当て';

  @override
  String get dynamicTagPaletteDescCustom => '通常タグと結合イベントタグをカスタマイズ済み';

  @override
  String get dynamicTagPaletteSheetDesc =>
      '通常タグはテキスト hash で 7 色に固定割り当て。結合イベントタグは別色です。';

  @override
  String get dynamicTagPaletteResetSaved => '動的タグカラーをデフォルトに戻しました';

  @override
  String get dynamicTagPaletteSection => '通常の動的タグ';

  @override
  String dynamicTagPaletteColorLabel(Object index) {
    return 'タグカラー $index';
  }

  @override
  String get mergedEventTagSection => '結合イベントタグ';

  @override
  String get mergedEventTagColorTitle => '結合イベントタグカラー';

  @override
  String get dynamicTagPaletteColorSaved => '動的タグカラーを保存しました';

  @override
  String themeColorSlotLabel(String slot) {
    String _temp0 = intl.Intl.selectLogic(slot, {
      'primary': 'プライマリ',
      'primaryForeground': 'プライマリ前景',
      'secondary': 'セカンダリ',
      'secondaryForeground': 'セカンダリ前景',
      'muted': 'ミュート',
      'mutedForeground': 'ミュート前景',
      'accent': 'アクセント',
      'accentForeground': 'アクセント前景',
      'destructive': '破壊的操作',
      'destructiveForeground': '破壊的操作の前景',
      'border': 'ボーダー',
      'input': '入力背景',
      'ring': 'フォーカスリング',
      'background': 'ページ背景',
      'foreground': 'ページ前景',
      'card': 'カード背景',
      'cardForeground': 'カード前景',
      'popover': 'ポップオーバー背景',
      'popoverForeground': 'ポップオーバー前景',
      'success': '成功',
      'successForeground': '成功の前景',
      'warning': '警告',
      'warningForeground': '警告の前景',
      'info': '情報',
      'infoForeground': '情報の前景',
      'mergedEventAccent': '結合イベントアクセント',
      'lightPrimaryContainer': 'ライト主コンテナ',
      'lightSecondaryContainer': 'ライト副コンテナ',
      'lightTertiaryContainer': 'ライト第三コンテナ',
      'lightErrorContainer': 'ライトエラーコンテナ',
      'lightOutlineVariant': 'ライト弱ボーダー',
      'lightSurfaceHigh': 'ライト高サーフェス',
      'lightSurfaceHighest': 'ライト最高サーフェス',
      'lightInversePrimary': 'ライト反転プライマリ',
      'darkPrimary': 'ダークプライマリ',
      'darkPrimaryForeground': 'ダークプライマリ前景',
      'darkSecondary': 'ダークセカンダリ',
      'darkSecondaryForeground': 'ダークセカンダリ前景',
      'darkMuted': 'ダークミュート',
      'darkMutedForeground': 'ダークミュート前景',
      'darkAccent': 'ダークアクセント',
      'darkAccentForeground': 'ダークアクセント前景',
      'darkDestructive': 'ダーク破壊的操作',
      'darkDestructiveForeground': 'ダーク破壊的操作の前景',
      'darkBorder': 'ダークボーダー',
      'darkInput': 'ダーク入力背景',
      'darkRing': 'ダークフォーカスリング',
      'darkBackground': 'ダークページ背景',
      'darkForeground': 'ダークページ前景',
      'darkCard': 'ダークカード背景',
      'darkCardForeground': 'ダークカード前景',
      'darkPopover': 'ダークポップオーバー背景',
      'darkPopoverForeground': 'ダークポップオーバー前景',
      'darkSelectedAccent': 'ダーク選択アクセント',
      'darkPrimaryContainer': 'ダーク主コンテナ',
      'darkSecondaryContainer': 'ダーク副コンテナ',
      'darkTertiaryContainer': 'ダーク第三コンテナ',
      'darkErrorContainer': 'ダークエラーコンテナ',
      'darkOutlineVariant': 'ダーク弱ボーダー',
      'darkSurfaceHigh': 'ダーク高サーフェス',
      'darkSurfaceHighest': 'ダーク最高サーフェス',
      'darkSurfaceContainerLowest': 'ダーク最低サーフェス',
      'other': 'カラー',
    });
    return '$_temp0';
  }

  @override
  String themeColorUsageLabel(String slot) {
    String _temp0 = intl.Intl.selectLogic(slot, {
      'primary': '影響: 主ボタン、選択中の下部メニュー、日付タブ下線、オンのスイッチ、入力欄フォーカス枠。',
      'primaryForeground': '影響: プライマリ色ブロック上の一部文字/アイコン。スクショ設定の選択項目、補完/再構築操作など。',
      'secondary': '影響: AI コンテキストパネルのアイコン、思考カード強調、グラフ補助セグメント、結合統計補助色。',
      'secondaryForeground': '影響: セカンダリ色ブロック上の文字/アイコン。スクショ設定の淡い補助ブロックなど。',
      'muted': '影響: 一部の旧ミュート背景。例: スクショ複数選択の空状態。通常背景は入力背景/カード背景を変更。',
      'mutedForeground': '影響: 説明文、入力ヒント、未選択の下部メニュー、控えめなアイコン、空状態テキスト。',
      'accent': '予備のアクセント色。一般的なハイライトは現在プライマリに従います。',
      'accentForeground': '予備のアクセントブロック文字。一般的な強調文字はページ前景に従います。',
      'destructive': '影響: 削除/危険ボタン、エラー文字、入力欄エラー枠、スクショエラー、NSFW マーク。',
      'destructiveForeground': '影響: 危険ボタンやエラーブロック上の文字/アイコン。',
      'border': '影響: 下部メニュー上線、設定項目区切り線、カード枠、入力欄枠、ダイアログ枠。',
      'input': '影響: 入力/検索背景、下部メニュー背景、ダイアログ/ボトムシート/ドロワー背景、設定カード。',
      'ring': '予備のフォーカスリング。現在の入力欄フォーカス枠とタブ下線は主にプライマリに従います。',
      'background': '影響: ライトモードのページ背景、AppBar 背景、一部の最下層コンテナ。',
      'foreground': '影響: 本文、見出し、AppBar の文字/アイコン、標準アイコン、リスト主文字。',
      'card': '影響: グローバル Card 背景、Chip 標準背景、カスタムテーマ色グループ、一部リストカード。',
      'cardForeground': '予備のカード文字色。一般的なカード主文字はページ前景に従います。',
      'popover': '予備のポップオーバー背景。現在のダイアログ/ボトムシート/ドロワー背景は入力背景に従います。',
      'popoverForeground': '予備のポップオーバー文字。現在のダイアログ/メニュー文字はページ前景に従います。',
      'success': '影響: 権限許可、サービス正常、AI リクエスト成功、ストレージ整理の主操作、完了状態。',
      'successForeground': '影響: 成功ボタン/バッジ上の文字とアイコン。',
      'warning': '影響: モデル/キーのクールダウン、注意表示、保留状態、黄色の警告ブロック。',
      'warningForeground': '影響: 警告ブロック上の文字とアイコン。',
      'info': '影響: 情報コールアウト、補助ブロックのアイコン/文字、ライトモード検索結果タグ。',
      'infoForeground': '影響: 情報ブロック上の文字とアイコン。',
      'mergedEventAccent': '影響: 結合イベントタグ色。スクショ設定で個別に編集します。',
      'lightPrimaryContainer': '影響: ライトの選択背景。ドロワー選択、選択 Chip、選択カレンダー日など。',
      'lightSecondaryContainer':
          '影響: ライトの補助ブロック。スクショ設定の青いブロック、AI ツール/グラフ補助背景など。',
      'lightTertiaryContainer': '影響: ライトの成功バッジ背景、AI 思考/完了パネル背景。',
      'lightErrorContainer': '影響: ライトのエラー表示、インポート/動的再構築エラーコンテナ。',
      'lightOutlineVariant': '影響: ライトの弱い区切り。ダイアログ区切り、グラフカード枠、ログブロック枠など。',
      'lightSurfaceHigh': '影響: ライトの高めの面。オフのスイッチ軌道、バックアップ/統計の内側カードなど。',
      'lightSurfaceHighest': '影響: ライトの最上位面。カレンダー日セル、AI ログブロック、画像プレースホルダーなど。',
      'lightInversePrimary': '影響: ライトモードの暗い面上の反転プライマリ。使用は少なめ。',
      'darkPrimary': '影響: ダークモードの主ボタン、選択中の下部メニュー、日付タブ下線、オンのスイッチ、入力欄フォーカス枠。',
      'darkPrimaryForeground':
          '影響: ダークのプライマリ色ブロック上の一部文字/アイコン。通常のボタン文字はダークページ前景に従います。',
      'darkSecondary': '影響: ダークの AI コンテキストパネルのアイコン、思考カード強調、グラフ補助セグメント、結合統計補助色。',
      'darkSecondaryForeground': '影響: ダークのセカンダリ色ブロック上の文字/アイコン。',
      'darkMuted': '予備のミュート背景。ダークの通常パネルはダークポップオーバーまたはダークカードを変更。',
      'darkMutedForeground': '影響: ダークの説明文、入力ヒント、未選択の下部メニュー、控えめなアイコン、空状態テキスト。',
      'darkAccent': '予備のダークアクセント。一般的なハイライトは主にダークプライマリまたはダーク選択アクセントに従います。',
      'darkAccentForeground': '予備のダークアクセントブロック文字。',
      'darkDestructive': '影響: ダークの削除/危険ボタン、エラー文字、入力欄エラー枠、スクショエラー、NSFW マーク。',
      'darkDestructiveForeground': '影響: ダークの危険ボタンやエラーブロック上の文字/アイコン。',
      'darkBorder': '影響: ダークの下部メニュー上線、設定項目区切り線、カード枠、入力欄枠、ダイアログ枠。',
      'darkInput': '予備のダーク入力欄。現在の入力欄/下部メニュー/ダイアログ背景はダークポップオーバーに従います。',
      'darkRing': '予備のダークフォーカスリング。フォーカス枠とタブ下線は主にダークプライマリに従います。',
      'darkBackground': '影響: ダークのページ背景、AppBar 背景、一部の最下層コンテナ。',
      'darkForeground': '影響: ダークの本文、見出し、AppBar の文字/アイコン、標準アイコン、リスト主文字。',
      'darkCard': '影響: ダークのグローバル Card 背景、Chip 標準背景、カスタムテーマ色グループ、一部リストカード。',
      'darkCardForeground': '予備のダークカード文字。一般的なカード主文字はダークページ前景に従います。',
      'darkPopover': '影響: ダークの入力/検索背景、下部メニュー背景、ダイアログ/ボトムシート/ドロワー背景、設定カード。',
      'darkPopoverForeground': '予備のダークポップオーバー文字。現在のダイアログ/メニュー文字はダークページ前景に従います。',
      'darkSelectedAccent': '影響: ダークモードの検索結果タグの文字、枠線、淡い塗り。',
      'darkPrimaryContainer': '影響: ダークの選択背景。ドロワー選択、選択 Chip、選択カレンダー日など。',
      'darkSecondaryContainer': '影響: ダークの補助ブロック。スクショ設定の補助表示、AI ツール/グラフ補助背景など。',
      'darkTertiaryContainer': '影響: ダークの成功バッジ背景、AI 思考/完了パネル背景。',
      'darkErrorContainer': '影響: ダークのエラー表示、インポート/動的再構築エラーコンテナ。',
      'darkOutlineVariant': '影響: ダークの弱い区切り。ダイアログ区切り、グラフカード枠、ログブロック枠など。',
      'darkSurfaceHigh': '影響: ダークの高めの面。オフのスイッチ軌道、バックアップ/統計の内側カードなど。',
      'darkSurfaceHighest': '影響: ダークの最上位面。カレンダー日セル、AI ログブロック、画像プレースホルダーなど。',
      'darkSurfaceContainerLowest':
          '影響: ダークの最下層背景。クラウドバックアップ入力エリアや最深部のページ底色など。',
      'other': '影響: インポートされたカスタムカラー枠。',
    });
    return '$_temp0';
  }

  @override
  String get pageBackgroundTitle => 'ページ背景';

  @override
  String get pageBackgroundDesc => 'ライトモードのメインページ背景色';

  @override
  String get loggingTitle => 'ログ出力';

  @override
  String get loggingDesc => '集中ログを有効化（既定で有効）';

  @override
  String get loggingAiTitle => 'AI ログ';

  @override
  String get loggingScreenshotTitle => 'スクリーンショットログ';

  @override
  String get loggingAiDesc => 'AI のリクエストとレスポンスを記録';

  @override
  String get loggingScreenshotDesc => 'スクリーンショットの取得とクリーンアップを記録';

  @override
  String get logRetentionDaysTitle => 'ログ保持日数';

  @override
  String logRetentionDaysDesc(Object days) {
    return '$days 日より古いローカルログは自動的に削除されます';
  }

  @override
  String logRetentionDaysValue(Object days) {
    return '$days 日';
  }

  @override
  String get logRetentionDaysDialogMessage =>
      'この日数より古いローカルログは自動的に削除されます。最小は 1 日で、上限はありません。';

  @override
  String get logRetentionDaysLabel => '日数';

  @override
  String get logRetentionDaysInvalid => '有効な日数を入力してください。';

  @override
  String get logRetentionDaysSaved => 'ログ保持設定を保存しました。';

  @override
  String get themeModeAuto => '自動';

  @override
  String get themeModeLight => 'ライト';

  @override
  String get themeModeDark => 'ダーク';

  @override
  String get appStatsSectionTitle => 'スクリーンショット統計';

  @override
  String appStatsCountLabel(Object count) {
    return 'スクリーンショット数：$count';
  }

  @override
  String appStatsSizeLabel(String size) {
    return '合計サイズ：$size';
  }

  @override
  String get appStatsLastCaptureUnknown => '最新キャプチャ：不明';

  @override
  String appStatsLastCaptureLabel(Object time) {
    return '最新キャプチャ：$time';
  }

  @override
  String get recomputeAppStatsAction => '統計を再計算';

  @override
  String get recomputeAppStatsDescription =>
      'インポート後に枚数やサイズが正しくない場合は、統計を手動で更新できます。';

  @override
  String get recomputeAppStatsSuccess => '統計を更新しました';

  @override
  String get recomputeAppStatsConfirmTitle => '統計を再計算';

  @override
  String get recomputeAppStatsConfirmMessage =>
      'このアプリのスクリーンショット統計を再計算しますか？データ量によっては時間がかかる場合があります。';

  @override
  String get appStatsCountTitle => '枚数';

  @override
  String get appStatsSizeTitle => '合計サイズ';

  @override
  String get appStatsLastCaptureTitle => '最新キャプチャ';

  @override
  String get aiEmptySelfTitle => 'この静けさも整える時間です';

  @override
  String get aiEmptySelfSubtitle => 'ここを開くと第二の記憶をめくるみたいに、いつでも一緒に振り返れます。';

  @override
  String get homeMorningTipsTitle => '朝の提案';

  @override
  String get homeMorningTipsLoading => '前日の足跡からインスピレーションをまとめています…';

  @override
  String get homeMorningTipsPullHint => '引き下げて前日のヒントから生まれた今朝のひらめきをひらく';

  @override
  String get homeMorningTipsReleaseHint => '離して前日由来の新しいひらめきを受け取る';

  @override
  String get homeMorningTipsEmpty => 'ここで少し立ち止まることも、自分をいたわる時間です。肩の力を抜いて。';

  @override
  String get homeMorningTipsViewAll => 'デイリーサマリーを開く';

  @override
  String get homeMorningTipsDismiss => '閉じる';

  @override
  String get homeMorningTipsCooldownHint => '少し休んでからもう一度引き下げてください';

  @override
  String get homeMorningTipsCooldownMessage =>
      '何度もリフレッシュしましたね。少し画面から目を離して、現実の景色を味わいましょう。';

  @override
  String get expireCleanupConfirmTitle => 'スクリーンショット期限切れ削除を有効にしますか？';

  @override
  String expireCleanupConfirmMessage(Object days) {
    return '有効にすると、$days日以上経過したスクリーンショット画像が即座に削除されます。\n\n注意：画像ファイルのみが削除され、イベントやサマリーなどのコンテンツは保持されます。';
  }

  @override
  String get expireCleanupConfirmAction => '有効にする';

  @override
  String get desktopMergerTitle => 'データ統合ツール';

  @override
  String get desktopMergerDescription => '複数のバックアップファイルを効率的に統合';

  @override
  String get desktopMergerSteps =>
      '1. 出力ディレクトリを選択（統合データはここに保存されます）\n2. 統合するZIPバックアップファイルを追加\n3. 統合開始をクリック';

  @override
  String get desktopMergerOutputDir => '出力ディレクトリ';

  @override
  String get desktopMergerSelectOutputDir => '出力ディレクトリを選択...';

  @override
  String get desktopMergerBrowse => '参照';

  @override
  String get desktopMergerZipFiles => 'ZIPバックアップファイル';

  @override
  String desktopMergerSelectedCount(Object count) {
    return '$countファイルを選択';
  }

  @override
  String get desktopMergerAddFiles => 'ファイルを追加';

  @override
  String get desktopMergerNoFiles => 'ファイルが選択されていません';

  @override
  String get desktopMergerDragHint => '上のボタンをクリックしてZIPバックアップファイルを追加';

  @override
  String get desktopMergerResultTitle => '統合結果';

  @override
  String desktopMergerInsertedCount(Object count) {
    return '+$count枚のスクリーンショット';
  }

  @override
  String get desktopMergerClear => 'リストをクリア';

  @override
  String get desktopMergerMerging => '統合中...';

  @override
  String get desktopMergerStart => '統合を開始';

  @override
  String get desktopMergerSelectZips => 'ZIPバックアップファイルを選択';

  @override
  String get desktopMergerStageExtracting => '解凍中...';

  @override
  String get desktopMergerStageCopying => 'ファイルをコピー中...';

  @override
  String get desktopMergerStageMerging => 'データベースを統合中...';

  @override
  String get desktopMergerStageFinalizing => '完了処理中...';

  @override
  String get desktopMergerStageProcessing => '処理中...';

  @override
  String get desktopMergerStageCompleted => '統合完了';

  @override
  String get desktopMergerLiveStats => 'リアルタイム統計';

  @override
  String desktopMergerProcessingFile(Object fileName) {
    return '処理中: $fileName';
  }

  @override
  String desktopMergerFileProgress(Object current, Object total) {
    return 'ファイル進捗: $current/$total';
  }

  @override
  String get desktopMergerStatScreenshots => '新規スクリーンショット';

  @override
  String get desktopMergerStatSkipped => 'スキップした重複';

  @override
  String get desktopMergerStatFiles => 'コピーしたファイル';

  @override
  String get desktopMergerStatReused => '再利用ファイル';

  @override
  String get desktopMergerStatTags => 'メモリタグ';

  @override
  String get desktopMergerStatEvidence => 'メモリ証拠';

  @override
  String get desktopMergerSummaryTitle => '統合サマリー';

  @override
  String desktopMergerSummaryTotal(Object count) {
    return '合計 $count ファイルを処理';
  }

  @override
  String desktopMergerSummarySuccess(Object count) {
    return '成功: $count';
  }

  @override
  String desktopMergerSummaryFailed(Object count) {
    return '失敗: $count';
  }

  @override
  String desktopMergerAffectedApps(Object count) {
    return '影響を受けたアプリ ($count)';
  }

  @override
  String desktopMergerWarnings(Object count) {
    return '警告 ($count)';
  }

  @override
  String get desktopMergerDetailTitle => '詳細結果';

  @override
  String get desktopMergerFileSuccess => '成功';

  @override
  String get desktopMergerFileFailed => '失敗';

  @override
  String get desktopMergerNoData => 'データ変更なし';

  @override
  String get desktopMergerExpandAll => 'すべて展開';

  @override
  String get desktopMergerCollapseAll => 'すべて折りたたむ';

  @override
  String get desktopMergerStagePacking => 'ZIP作成中...';

  @override
  String get desktopMergerOutputZip => '出力ファイル';

  @override
  String get desktopMergerOpenFolder => 'フォルダを開く';

  @override
  String desktopMergerPackingProgress(Object percent) {
    return 'パッキング: $percent%';
  }

  @override
  String get desktopMergerMinFilesHint => '統合するには少なくとも2つのバックアップファイルを選択してください';

  @override
  String get desktopMergerExtractingHint =>
      'バックアップファイルを解凍中です。大規模なバックアップ（数万枚のスクリーンショット）は数分かかる場合があります。しばらくお待ちください...';

  @override
  String get desktopMergerCopyingHint => 'スクリーンショットファイルをコピー中、既存の画像はスキップ...';

  @override
  String get desktopMergerMergingHint => 'データベースレコードを統合中、スマート重複排除処理中...';

  @override
  String get desktopMergerPackingHint => '統合結果をZIPファイルにパッキング中...';

  @override
  String get unknownTitle => '不明';

  @override
  String get unknownTime => '不明な時間';

  @override
  String get empty => '空';

  @override
  String get evidenceTitle => '証拠';

  @override
  String get runtimeDiagnosticCopied => '診断情報をコピーしました';

  @override
  String get runtimeDiagnosticCopyFailed => '診断情報のコピーに失敗しました';

  @override
  String get runtimeDiagnosticNoFileToOpen => '開ける診断ファイルがありません';

  @override
  String get runtimeDiagnosticOpenAttempted => '診断ファイルを開こうとしました';

  @override
  String get runtimeDiagnosticOpenFallbackCopiedPath => '直接開けないため、ログパスをコピーしました';

  @override
  String get runtimeDiagnosticCopyInfoAction => '情報をコピー';

  @override
  String get runtimeDiagnosticOpenFileAction => 'このファイルを開く';

  @override
  String get runtimeDiagnosticOpenSettingsAction => '設定を開く';

  @override
  String get providerAddAtLeastOneEnabledApiKey =>
      '有効な API Key を少なくとも 1 つ追加してください。';

  @override
  String get providerSaveBeforeBatchTest => '一括テストの前にプロバイダーを保存してください。';

  @override
  String get providerKeepOneEnabledApiKey =>
      '有効で空ではない API Key を少なくとも 1 つ残してください。';

  @override
  String get providerBatchTestFailed => '一括テストに失敗しました。後でもう一度お試しください。';

  @override
  String get providerBatchTestResultTitle => '一括テスト結果';

  @override
  String get actionClose => '閉じる';

  @override
  String get providerOnlyOneApiKeyCanEdit => '一度に編集できる API Key は 1 つだけです';

  @override
  String get providerAddApiKey => 'API Key を追加';

  @override
  String get providerEditApiKey => 'API Key を編集';

  @override
  String get actionSaving => '保存中';

  @override
  String get providerFetchModelsFailedManual => 'モデルの取得に失敗しました。手動で追加できます。';

  @override
  String get providerKeyModelsUpdatedToast => 'モデル一覧を更新しました';

  @override
  String providerDeletedApiKeys(Object count) {
    return '$count 個の API Key を削除しました';
  }

  @override
  String get providerAddKeyButton => 'Key を追加';

  @override
  String get providerBatchTestButton => '一括テスト';

  @override
  String get providerDeleteAllKeys => 'すべて削除';

  @override
  String get providerNoApiKeys => 'API Key はありません。';

  @override
  String get segmentEntryLogHint => '長押しでテキストを選択するか、コピーを押してまとめてコピーします。';

  @override
  String get segmentEntryLogCopied => '動的エントリーログをコピーしました';

  @override
  String get copyLogAction => 'ログをコピー';

  @override
  String get segmentDynamicConcurrencySaveFailed => '日別並行数の保存に失敗しました';

  @override
  String get dynamicAutoRepairEnabled => '自動補修を有効にしました';

  @override
  String get dynamicAutoRepairPaused => '自動補修を一時停止しました';

  @override
  String get dynamicAutoRepairToggleFailed => '自動補修の切り替えに失敗しました';

  @override
  String get dynamicRebuildStart => '再構築を開始';

  @override
  String get dynamicRebuildContinue => '再構築を続行';

  @override
  String savedToPath(Object path) {
    return '保存先：$path';
  }

  @override
  String get dynamicRebuildNoSegments => '再構築できる動的項目はありません';

  @override
  String dynamicRebuildSwitchedModelContinue(Object model) {
    return 'モデル $model に切り替えて再構築を続行しました';
  }

  @override
  String get dynamicRebuildStartedInBackground =>
      'バックグラウンドで再構築を開始しました。通知で進捗を確認できます。';

  @override
  String get dynamicRebuildTaskResumed => 'バックグラウンド再構築タスクを再開しました';

  @override
  String get dynamicRebuildStopped => '動的再構築を停止しました';

  @override
  String get dynamicRebuildStopFailed => '動的再構築の停止に失敗しました';

  @override
  String get dynamicTaskStopping => '停止中...';

  @override
  String get dynamicTaskExitSuccess => '現在の動的タスクを終了しました';

  @override
  String get dynamicTaskExitFailed => '動的タスクの終了に失敗しました';

  @override
  String segmentTimelineNotAvailableForDate(Object date) {
    return '現在の動的タスクでは $date のタイムラインはまだ利用できません。';
  }

  @override
  String get dynamicRebuildBlockedRetry => '全体再構築中のため、単体の再生成は一時的に無効です。';

  @override
  String get dynamicRebuildBlockedForceMerge => '全体再構築中のため、手動の強制マージは一時的に無効です。';

  @override
  String get rawResponseRetentionDaysTitle => '保持日数を設定';

  @override
  String get rawResponseRetentionDaysLabel => '保持日数';

  @override
  String get rawResponseRetentionDaysHint => '0 より大きい数値を入力してください';

  @override
  String get rawResponseCleanupSaved => '生レスポンスのクリーンアップ設定を保存しました。';

  @override
  String get chatContextTitlePrefix => '会話コンテキスト（';

  @override
  String get chatContextTitleMemory => 'メモリ';

  @override
  String get chatContextTitleSuffix => '）';

  @override
  String rawResponseRetentionUpdatedDays(Object days) {
    return '保持日数を $days 日に更新しました。';
  }

  @override
  String get homeMorningTipsUpdated => '朝のヒントを更新しました';

  @override
  String get homeMorningTipsGenerateFailed => '朝のヒント生成に失敗しました';

  @override
  String eventCreateFailed(Object error) {
    return '作成に失敗しました: $error';
  }

  @override
  String eventSwitchFailed(Object error) {
    return '切り替えに失敗しました: $error';
  }

  @override
  String get eventSessionSwitched => '会話を切り替えました';

  @override
  String get eventSessionDeleted => '会話を削除しました';

  @override
  String get exclusionExcludedAppsTitle => '除外済みアプリ';

  @override
  String get exclusionSelfAppBullet => '· このアプリ（自己ループ回避）';

  @override
  String get exclusionImeAppsBullet => '· 入力方式（キーボード）アプリ:';

  @override
  String get exclusionAutoFilteredBullet => '  - （自動フィルタ済み）';

  @override
  String get exclusionUnknownIme => '不明な入力方式';

  @override
  String exclusionImeAppBullet(Object name) {
    return '  - $name';
  }

  @override
  String get imageError => '画像エラー';

  @override
  String get logDetailTitle => 'ログ詳細';

  @override
  String get logLevelAll => 'すべて';

  @override
  String get logLevelDebugVerbose => 'デバッグ/詳細';

  @override
  String get logLevelInfo => '情報';

  @override
  String get logLevelWarning => '警告';

  @override
  String get logLevelErrorSevere => 'エラー/重大';

  @override
  String get logSearchHint => 'タイトル/内容/例外/スタックを検索';

  @override
  String onboardingPermissionLoadFailed(Object error) {
    return '権限状態の読み込みに失敗しました: $error';
  }

  @override
  String get permissionGuideSettingsOpened => 'アプリ設定を開きました。ガイドに従って設定してください';

  @override
  String permissionGuideOpenSettingsFailed(Object error) {
    return '設定ページを開けませんでした: $error';
  }

  @override
  String get permissionGuideBatteryOpened => 'バッテリー最適化設定を開きました';

  @override
  String permissionGuideOpenBatteryFailed(Object error) {
    return 'バッテリー最適化設定を開けませんでした: $error';
  }

  @override
  String get permissionGuideAutostartOpened => '自動起動設定を開きました';

  @override
  String permissionGuideOpenAutostartFailed(Object error) {
    return '自動起動設定を開けませんでした: $error';
  }

  @override
  String get permissionGuideCompleted => '権限設定を完了としてマークしました';

  @override
  String permissionGuideCompleteFailed(Object error) {
    return '権限設定の完了マークに失敗しました: $error';
  }

  @override
  String get permissionGuideTitle => '権限設定ガイド';

  @override
  String get permissionGuideOpenAppSettings => 'アプリ設定を開く';

  @override
  String get permissionGuideOpenBatterySettings => 'バッテリー最適化設定を開く';

  @override
  String get permissionGuideOpenAutostartSettings => '自動起動設定を開く';

  @override
  String get permissionGuideAllDone => 'すべての設定を完了しました';

  @override
  String get galleryDeleting => '削除中...';

  @override
  String get galleryCleaningCache => 'キャッシュを整理中...';

  @override
  String get favoriteRemoved => 'お気に入りから削除しました';

  @override
  String get favoriteAdded => 'お気に入りに追加しました';

  @override
  String operationFailedWithError(Object error) {
    return '操作に失敗しました: $error';
  }

  @override
  String get searchSemantic => 'セマンティック検索';

  @override
  String get searchDynamic => '動的検索';

  @override
  String get searchMore => 'さらに検索';

  @override
  String get openDailySummary => '日次サマリーを開く';

  @override
  String get openWeeklySummary => '週次サマリーを開く';

  @override
  String get noAvailableTags => '利用可能なタグはありません';

  @override
  String get clearFilter => 'フィルターをクリア';

  @override
  String get forceMerge => '強制マージ';

  @override
  String get forceMergeNoPrevious => 'マージできる前のイベントがありません';

  @override
  String get forceMergeQueuedFailed => '強制マージのキュー投入に失敗しました';

  @override
  String get forceMergeQueued => '強制マージをキューに追加しました';

  @override
  String get forceMergeFailed => '強制マージに失敗しました';

  @override
  String get mergeCompleted => 'マージ完了';

  @override
  String get numberInputRequired => '数値を入力してください';

  @override
  String valueSaved(Object value) {
    return '保存しました: $value';
  }

  @override
  String openChannelSettingsFailed(Object error) {
    return 'チャンネル設定を開けませんでした: $error';
  }

  @override
  String openAppNotificationSettingsFailed(Object error) {
    return 'アプリ通知設定を開けませんでした: $error';
  }

  @override
  String get evidencePrefix => '[証拠: ';

  @override
  String get actionMenu => 'メニュー';

  @override
  String get actionShare => '共有';

  @override
  String get actionResetToDefault => 'デフォルトに戻す';

  @override
  String homeMorningTipNumberedTitle(Object index, Object title) {
    return '$index. $title';
  }

  @override
  String get homeMorningTipsRawTitle => '朝のヒント RAW';

  @override
  String labelWithColon(Object label) {
    return '$label: ';
  }

  @override
  String warningBullet(Object warning) {
    return '• $warning';
  }

  @override
  String resetToDefaultValue(Object value) {
    return 'デフォルトに戻しました: $value';
  }

  @override
  String get logPanelTitle => 'ログパネル';

  @override
  String get logCopiedToClipboard => 'クリップボードにコピーしました';

  @override
  String get logShareText => 'ScreenMemo ログ';

  @override
  String get logShareFailed => '共有に失敗しました';

  @override
  String get logCleared => 'ログをクリアしました';

  @override
  String get logClearFailed => 'ログのクリアに失敗しました';

  @override
  String get logNoLogs => 'ログはまだありません';

  @override
  String get logNoMatchingLogs => '一致するログはありません';

  @override
  String get logManagementTitle => 'ログ管理';

  @override
  String get logManagementSubtitle =>
      'output/logs のフォルダー階層でログを参照します。現在のディレクトリだけを読み込み、フォルダーやファイルを個別に共有・削除できます。';

  @override
  String get logManagementRefreshTooltip => 'ログを更新';

  @override
  String get logManagementShareAll => 'すべてのログを共有';

  @override
  String get logManagementShareDay => 'この日を共有';

  @override
  String get logManagementDeleteDay => 'この日のログを削除';

  @override
  String get logManagementShareFolder => 'このフォルダーを共有';

  @override
  String get logManagementDeleteFolder => 'このフォルダーを削除';

  @override
  String get logManagementShareFile => 'このファイルを共有';

  @override
  String get logManagementDeleteFile => 'このファイルを削除';

  @override
  String get logManagementLoading => 'ログを読み込み中…';

  @override
  String get logManagementExporting => 'パッケージ中…';

  @override
  String get logManagementNoLogsTitle => '保存済みログはありません';

  @override
  String get logManagementNoLogsDesc =>
      'ログを有効にしてしばらくアプリを使用すると、ここから保存済みログを共有できます。';

  @override
  String get logManagementEmptyFolderTitle => 'このフォルダーは空です';

  @override
  String get logManagementEmptyFolderDesc =>
      'ここにはログファイルやサブフォルダーがありません。親フォルダーに戻って確認してください。';

  @override
  String get logManagementParentDirectory => '親フォルダーに戻る';

  @override
  String logManagementCurrentPath(Object path) {
    return '現在の場所: $path';
  }

  @override
  String get logManagementUnknownTime => '不明な時刻';

  @override
  String logManagementSummary(Object fileCount, Object size) {
    return '$fileCount 件のファイル • $size';
  }

  @override
  String logManagementDaySubtitle(
    Object fileCount,
    Object size,
    Object modified,
  ) {
    return '$fileCount 件のファイル • $size • 更新 $modified';
  }

  @override
  String logManagementFileSubtitle(Object size, Object modified) {
    return '$size • 更新 $modified';
  }

  @override
  String logManagementFolderSubtitle(
    Object fileCount,
    Object size,
    Object modified,
  ) {
    return '$fileCount 件のファイル • $size • 更新 $modified';
  }

  @override
  String get logManagementDeleteFileTitle => 'ログファイルを削除';

  @override
  String logManagementDeleteFileMessage(Object fileName) {
    return '「$fileName」を削除しますか？この操作は元に戻せません。';
  }

  @override
  String get logManagementDeleteDayTitle => '当日のログを削除';

  @override
  String logManagementDeleteDayMessage(
    Object date,
    Object fileCount,
    Object size,
  ) {
    return '$date のログファイル $fileCount 件（$size）を削除しますか？この操作は元に戻せません。';
  }

  @override
  String get logManagementDeleteFolderTitle => 'ログフォルダーを削除';

  @override
  String logManagementDeleteFolderMessage(
    Object folderName,
    Object fileCount,
    Object size,
  ) {
    return '「$folderName」とその中のログファイル $fileCount 件（$size）を削除しますか？この操作は元に戻せません。';
  }

  @override
  String get logManagementFileDeleted => 'ログファイルを削除しました';

  @override
  String get logManagementFileMissing => 'ログファイルは存在しません';

  @override
  String logManagementFolderDeleted(Object fileCount) {
    return 'フォルダーとログファイル $fileCount 件を削除しました';
  }

  @override
  String get logManagementFolderDeletedEmpty => 'ログフォルダーを削除しました';

  @override
  String get logManagementFolderMissing => 'ログフォルダーは存在しません';

  @override
  String logManagementDayDeleted(Object fileCount) {
    return 'ログファイル $fileCount 件を削除しました';
  }

  @override
  String get logManagementDayMissing => 'この日のログは存在しません';

  @override
  String logManagementDeleteFailed(Object error) {
    return 'ログの削除に失敗しました: $error';
  }

  @override
  String get logManagementShareEmpty => '共有できるログファイルがありません';

  @override
  String logManagementShareFailed(Object error) {
    return '共有に失敗しました: $error';
  }

  @override
  String logManagementLoadFailed(Object error) {
    return 'ログの読み込みに失敗しました: $error';
  }

  @override
  String get logManagementLargeExportTitle => 'ログのエクスポートが大きいです';

  @override
  String logManagementLargeExportMessage(Object size) {
    return '選択したログは約 $size です。パッケージして共有しますか？';
  }

  @override
  String get logManagementLargeExportConfirm => '続行';

  @override
  String logManagementZipReady(Object size) {
    return 'ログ ZIP の準備ができました: $size';
  }

  @override
  String get logFilterTooltip => 'フィルター';

  @override
  String get logSortNewestFirst => '新しい順';

  @override
  String get logSortOldestFirst => '古い順';

  @override
  String get logLevelCritical => '重大';

  @override
  String get logLevelError => 'エラー';

  @override
  String get logLevelVerbose => '詳細';

  @override
  String get logLevelDebug => 'デバッグ';

  @override
  String get eventNewConversation => '新しい会話';

  @override
  String get forceMergeConfirmMessage =>
      '前のイベントと強制マージし、現在のイベント要約を上書きして前のイベントを削除します。この操作は元に戻せません。続行しますか？';

  @override
  String get forceMergeRequestedReason => '強制マージをリクエストしました（キュー内）';

  @override
  String get mergeStatusMerging => '強制マージ中…';

  @override
  String get mergeStatusMerged => 'マージ済み';

  @override
  String get mergeStatusForceRequested => '強制マージをリクエスト済み';

  @override
  String get mergeStatusNotMerged => '未マージ';

  @override
  String get mergeStatusPending => '判定待ち';

  @override
  String get semanticSearchNotStartedTitle => 'セマンティック検索は未開始です';

  @override
  String get semanticSearchNotStartedDesc =>
      '画像の AI 説明、キーワード、タグを検索します。入力中の遅延を避けるため、手動で検索を開始してください。';

  @override
  String get segmentSearchNotStartedTitle => '動的検索は未開始です';

  @override
  String get segmentSearchNotStartedDesc => '入力中の遅延を避けるため、手動で検索を開始してください。';

  @override
  String foundImagesCount(Object count) {
    return '$count 件の画像が見つかりました';
  }

  @override
  String get tagsLabel => 'タグ';

  @override
  String tagCount(Object count) {
    return '$count 個のタグ';
  }

  @override
  String get tagFilterTitle => 'タグフィルター';

  @override
  String get selectedAllLabel => 'すべて';

  @override
  String selectedTagsCount(Object count) {
    return '$count 個選択済み';
  }

  @override
  String selectedTypesCount(Object count) {
    return '$count 種類選択済み';
  }

  @override
  String confirmSelectionLabel(Object selection) {
    return 'OK（$selection）';
  }

  @override
  String get noContentParenthesized => '（空）';

  @override
  String get typeFilterTitle => '種類フィルター';

  @override
  String get rawResponseCleanupEnableTitle => '原始応答の自動クリーンアップを有効化';

  @override
  String rawResponseCleanupEnableMessage(Object days) {
    return '$days 日より古い raw_response を自動的に削除します。サマリーと structured_json には影響しません。';
  }

  @override
  String get rawResponseCleanupEnableAction => '有効化して今すぐクリーンアップ';

  @override
  String get segmentsJsonAutoRetryTitle => '自動リトライ回数';

  @override
  String get segmentsJsonAutoRetryDesc =>
      'AI の返答がアプリの要件を満たさない場合に自動再試行する回数です（0=オフ、既定 1）。';

  @override
  String get segmentsJsonAutoRetryHint => '回数（0-5）';

  @override
  String get rawResponseCleanupTitle => '原始応答の自動クリーンアップ';

  @override
  String get rawResponseCleanupKeepLabel => '保持';

  @override
  String rawResponseCleanupRetentionDays(Object days) {
    return '$days 日';
  }

  @override
  String get rawResponseCleanupDesc =>
      '古い raw_response のみ削除し、サマリーと structured_json は保持します';

  @override
  String get mergeStatusMergingReason => 'マージ中です。しばらくお待ちください…';

  @override
  String get permissionGuideLoading => '権限設定ガイドを読み込み中...';

  @override
  String get permissionGuideUnavailable => '権限設定ガイドを取得できません';

  @override
  String get permissionGuideUnknownDevice => '不明なデバイス';

  @override
  String permissionGuideLoadFailed(Object error) {
    return '権限設定ガイドの読み込みに失敗しました: $error';
  }

  @override
  String get deviceInfoTitle => 'デバイス情報';

  @override
  String get setupGuideTitle => '設定ガイド';

  @override
  String get permissionConfiguredStatus => '設定済み';

  @override
  String get permissionNeedsConfigurationStatus => '設定が必要';

  @override
  String get backgroundPermissionTitle => 'バックグラウンド実行権限';

  @override
  String get actualBatteryOptimizationStatusTitle => '実際のバッテリー最適化状態';

  @override
  String get providerSaveBeforeAddingKey => 'API Key を追加する前にプロバイダーを保存してください。';

  @override
  String get providerSaveBeforeRefreshingModels => 'モデルを更新する前にプロバイダーを保存してください。';

  @override
  String providerDefaultKeyName(Object count) {
    return 'Key $count';
  }

  @override
  String get providerKeyCurrent => '現在の Key';

  @override
  String get providerNoNewApiKeyDuplicate =>
      '新しい Key はありません。入力した API Key はすべて既に存在します。';

  @override
  String get providerKeyNameLabel => 'Key 名';

  @override
  String get providerApiKeyMultiLineLabel => 'API Key（1行に1つ）';

  @override
  String get providerApiKeySingleLineLabel => 'API Key';

  @override
  String get providerApiKeyMultiLineHint =>
      '1行に1つの API Key を入力してください。取得時は各 Key を順番に確認します。';

  @override
  String get providerKeyPriorityLabel => '優先度（100 = 動的割り当て）';

  @override
  String get providerKeyModelsLabel => '対応モデル（1行に1つ）';

  @override
  String get providerKeyProgressFetchModels => 'モデルを取得';

  @override
  String get providerKeyProgressScanKeys => 'Key をスキャン';

  @override
  String get providerKeyProgressFetchComplete => '取得完了';

  @override
  String get providerKeyProgressSaveKeys => 'Key を保存';

  @override
  String get providerKeyProgressSaveKey => 'Key を保存';

  @override
  String get providerKeyProgressSaveFailed => '保存失敗';

  @override
  String providerKeyProgressPreparingScan(Object count) {
    return '$count 個の API Key をスキャンする準備中...';
  }

  @override
  String providerKeyProgressFetchingModels(Object label) {
    return '$label のモデルを取得中...';
  }

  @override
  String providerKeyProgressModelFetchFailed(Object label, Object error) {
    return '$label のモデル取得に失敗しました：$error';
  }

  @override
  String providerKeyProgressModelsCount(Object count) {
    return '$count 個のモデル';
  }

  @override
  String get providerKeyProgressModelFailedSkipped => 'モデル取得に失敗したためスキップしました';

  @override
  String providerKeyFetchCompleteToast(
    Object modelSuccess,
    Object total,
    Object fetchedCount,
    Object failedCount,
  ) {
    return 'モデル取得完了：$modelSuccess/$total 個の Key が成功、$fetchedCount 個のモデルを統合、失敗項目 $failedCount';
  }

  @override
  String get providerKeyNoModelsFetchedToast =>
      'モデルを返した Key がありません。現在の手動モデル一覧は変更されません。';

  @override
  String providerKeyProgressFetchCompleteMessage(
    Object modelSuccess,
    Object total,
  ) {
    return 'モデル $modelSuccess/$total';
  }

  @override
  String get providerKeyProgressPreparingSave => '保存の準備中...';

  @override
  String providerKeyProgressSaving(Object label) {
    return '$label を保存中...';
  }

  @override
  String providerKeySaveSuccessNew(Object saved, Object skipped) {
    return '$saved 個の API Key を取り込みました。重複 $skipped 個をスキップ';
  }

  @override
  String get providerKeySaveSuccessEdit => 'API Key を保存しました';

  @override
  String providerKeySaveFailedToast(Object error) {
    return 'API Key の保存に失敗しました：$error';
  }

  @override
  String get dynamicSettingSampleExplanation =>
      'ダイナミック再構築のサンプリング間隔を制御します。短いほど細かく記録できますが、スクリーンショット数と AI 処理量が増えます。';

  @override
  String get dynamicSettingDurationExplanation =>
      '1つのダイナミック片がカバーする時間を制御します。長いほど一度の要約に含まれる文脈が増えます。';

  @override
  String get dynamicSettingMergeMaxSpanExplanation =>
      'マージできるダイナミック全体の時間幅を制限します。0 は無制限です。';

  @override
  String get dynamicSettingMergeMaxGapExplanation =>
      '隣接する2つのダイナミック片をマージできる最大間隔を制限します。0 は無制限です。';

  @override
  String get dynamicSettingMergeMaxImagesExplanation =>
      '1回のマージに含める最大スクリーンショット数を制限します。0 は無制限です。';

  @override
  String get dynamicSettingAiRequestIntervalExplanation =>
      'ダイナミック再構築が AI にリクエストする最小間隔を制限し、頻度が高くなりすぎるのを防ぎます。';

  @override
  String get dynamicSettingAutoRetryExplanation =>
      'AI の返答がアプリの要件を満たさない場合、アプリが自動的に再試行します。回数を増やすと安定しますが、時間と消費量も増えます。';

  @override
  String get dynamicSettingRawResponseRetentionExplanation =>
      'AI の生の返答を保持する日数を制御します。期限切れ後は生の返答のみ削除し、生成済みの要約には影響しません。';

  @override
  String get promptManagerReadOnlyBadge => '読み取り専用';

  @override
  String get promptManagerEditingBadge => '編集中';

  @override
  String get promptAddonOptionalLabel => '任意';

  @override
  String promptAddonCharCount(Object count) {
    return '$count 文字';
  }

  @override
  String promptAddonCharCountLimit(Object count, Object max) {
    return '$count / $max';
  }

  @override
  String get promptManagerSupportsPlainText => 'プレーンテキスト対応';

  @override
  String promptAddonTooLongError(Object max) {
    return '補足説明は $max 文字以内にしてください。';
  }

  @override
  String settingCurrentValue(Object value) {
    return '現在：$value';
  }

  @override
  String get savedMorningPromptToast => '朝のインサイトプロンプトを保存しました';

  @override
  String get promptAddonSectionTitle => '補足説明';

  @override
  String get aiGeneratedImageModelTitle => '画像生成モデル';

  @override
  String get aiGeneratedImagesHistoryTitle => '生成画像履歴';

  @override
  String get aiGeneratedImageModelDesc =>
      'AI 内部の generate_image ツール専用です。直接生成する UI はありません。';

  @override
  String get aiGeneratedImageModelUnconfiguredHint =>
      'このコンテキストが未設定の場合、ツールは英語のエラーを返し、チャットループは継続します。';

  @override
  String get aiGeneratedImageProviderSaved => '画像生成プロバイダーを保存しました';

  @override
  String get aiGeneratedImageModelSaved => '画像生成モデルを保存しました';

  @override
  String get aiGeneratedImageNotConfigured => '未設定';

  @override
  String get aiGeneratedHistoryLoadFailed => '生成画像の読み込みに失敗しました';

  @override
  String get aiGeneratedImageUnavailable => '画像を利用できません';

  @override
  String get aiGeneratedShareText => 'ScreenMemo 生成画像';

  @override
  String get aiGeneratedDeleteTitle => '画像を削除しますか？';

  @override
  String get aiGeneratedDeleteMessage =>
      'ローカル画像ファイルを削除し、チャットメッセージは読み取り専用のままにします。既存のチャット marker は画像を利用できない状態で表示されます。';

  @override
  String get aiGeneratedImageDeleted => '画像を削除しました';

  @override
  String get aiGeneratedHistoryEmptyTitle => '生成画像はまだありません';

  @override
  String get aiGeneratedHistoryEmptyDesc => 'AI 内部ツールで作成された画像がここに表示されます。';

  @override
  String get aiGeneratedDefaultTitle => '生成画像';

  @override
  String get aiGeneratedNoPromptStored => '保存されたプロンプトはありません';

  @override
  String get aiGeneratedCopyPrompt => 'プロンプトをコピー';

  @override
  String get modelMetaContextLabel => 'コンテキスト';

  @override
  String get modelMetaInputLabel => '入力';

  @override
  String get modelMetaOutputLabel => '出力';

  @override
  String get modelMetaFallback32k => '既定 272K';

  @override
  String get modelMetaUnknownValue => '不明';

  @override
  String get modelMetaCostLabel => '料金';

  @override
  String get modelMetaCostInputLabel => '入力';

  @override
  String get modelMetaCostOutputLabel => '出力';

  @override
  String get modelMetaCostReasoningLabel => '推論';

  @override
  String get modelMetaCostCacheReadLabel => 'キャッシュ読取';

  @override
  String get modelMetaCostCacheWriteLabel => 'キャッシュ作成';

  @override
  String get modelMetaCostAudioInputLabel => '音声入力';

  @override
  String get modelMetaCostAudioOutputLabel => '音声出力';

  @override
  String get modelMetaKnowledgeLabel => '知識期限';

  @override
  String get modelMetaReleaseLabel => 'リリース日';

  @override
  String get modelCapabilityReasoningLabel => '推論';

  @override
  String get modelCapabilityToolsLabel => 'ツール呼び出し';

  @override
  String get modelCapabilityStructuredOutputLabel => '構造化出力';

  @override
  String get modelCapabilityAttachmentsLabel => '添付';

  @override
  String get modelModalityTextLabel => 'テキスト';

  @override
  String get modelModalityImageLabel => '画像';

  @override
  String get modelModalityAudioLabel => '音声';

  @override
  String get modelModalityVideoLabel => '動画';

  @override
  String get modelModalityPdfLabel => 'PDF';

  @override
  String get modelModalityInputTooltip => '入力モダリティ';

  @override
  String get modelModalityOutputTooltip => '出力モダリティ';

  @override
  String get modelCapabilitySectionLabel => '機能';

  @override
  String get modelInputSupportSectionLabel => '入力対応';

  @override
  String get modelOutputSupportSectionLabel => '出力対応';

  @override
  String get modelStatusFlagship => '旗艦';

  @override
  String get modelStatusPreview => 'プレビュー';

  @override
  String get modelStatusBeta => 'ベータ';

  @override
  String get modelStatusDeprecated => '非推奨';

  @override
  String get modelStatusExperimental => '実験';

  @override
  String get modelStatusStable => '安定';

  @override
  String get updateCheckNowAction => 'アップデートを確認';

  @override
  String get updateChecking => 'アップデートを確認しています...';

  @override
  String get updateNoUpdate => '最新バージョンを使用しています';

  @override
  String updateCheckFailed(Object error) {
    return 'アップデート確認に失敗しました：$error';
  }

  @override
  String get updateUnknownError => '不明なエラー';

  @override
  String get updateNoCompatibleApk => 'この端末に対応する APK が見つかりません';

  @override
  String get updateNewVersionTitle => '新しいバージョンがあります';

  @override
  String get updateCurrentVersionLabel => '現在のバージョン';

  @override
  String get updateLatestVersionLabel => '最新バージョン';

  @override
  String get updatePublishedAtLabel => '公開日時';

  @override
  String get updateApkSizeLabel => 'APK サイズ';

  @override
  String get updateReleaseNotesLabel => 'リリースノート';

  @override
  String get updateDownloadAction => 'ダウンロード';

  @override
  String get updateIgnoreVersionAction => 'このバージョンを無視';

  @override
  String get updateCloseAction => '閉じる';

  @override
  String get updateIgnoredToast => 'このバージョンを無視しました';

  @override
  String get updateDownloadTitle => 'アップデートをダウンロード';

  @override
  String updateDownloadProgress(Object received, Object total) {
    return '$received / $total';
  }

  @override
  String updateDownloadProgressUnknown(Object received) {
    return '$received ダウンロード済み';
  }

  @override
  String updateDownloadFailed(Object error) {
    return 'アップデートのダウンロードに失敗しました：$error';
  }

  @override
  String get updateDownloadComplete => 'APK のダウンロードが完了しました';

  @override
  String get updateInstalling => 'インストーラーを開いています...';

  @override
  String updateInstallFailed(Object error) {
    return 'インストーラーを開けません：$error';
  }

  @override
  String get updateInstallPermissionTitle => 'インストール権限が必要です';

  @override
  String get updateInstallPermissionMessage =>
      'ScreenMemo に不明なアプリのインストールを許可し、戻ってからもう一度ダウンロードをタップしてください。';

  @override
  String get updateOpenInstallSettingsAction => '設定を開く';

  @override
  String get composerAttachImageTooltip => '画像を添付';

  @override
  String get composerDrawingModeOnTooltip => '描画モードはオンです';

  @override
  String get composerEnableDrawingModeTooltip => '描画モードを有効にする';

  @override
  String get composerDrawingModeEnabledToast => '描画モードを有効にしました';

  @override
  String get composerDrawingModeDisabledToast => '描画モードを無効にしました';

  @override
  String get composerStopTooltip => '停止';

  @override
  String get composerGenerateImageTooltip => '画像を生成';

  @override
  String get composerSendTooltip => '送信';

  @override
  String get composerGeneratingImage => '画像を生成しています';

  @override
  String get composerGeneratingWithReferences => '参照画像を使って生成しています';

  @override
  String composerImageLimitToast(Object count) {
    return '最初の $count 枚の画像のみ添付されます。';
  }

  @override
  String composerImageSelectionFailed(Object error) {
    return '画像の選択に失敗しました：$error';
  }

  @override
  String get composerImagePromptRequired => '画像生成用のプロンプトを入力してください。';

  @override
  String get composerAnalyzeImageFallbackPrompt => 'この画像を分析してください。';

  @override
  String get mcpServiceTitle => 'MCP サービス';

  @override
  String get mcpLanServerTitle => 'LAN MCP サービス';

  @override
  String mcpRunningOnPort(Object port) {
    return 'ポート $port で実行中';
  }

  @override
  String get mcpStopped => '停止中';

  @override
  String get mcpLastErrorTitle => '前回のエラー';

  @override
  String get mcpNoLanIpDetected => 'LAN IP が検出されていません';

  @override
  String get mcpResetTokenTitle => 'トークンをリセット';

  @override
  String get mcpAiInstallTitle => 'AI に渡して設定';

  @override
  String get mcpAiInstallCopyLabel => '設定手順をコピー';

  @override
  String get mcpConnectionUnavailableHint =>
      'サービスを起動し LAN IP が検出されると、ここにコピー可能な設定手順が表示されます。';

  @override
  String mcpAiInstallPrompt(Object endpoint, Object token) {
    return 'ScreenMemo を MCP サービスとして追加してください。\n\n接続情報：\n- トランスポート：Streamable HTTP MCP\n- URL：$endpoint\n- ヘッダー：Authorization: Bearer $token\n\nクライアントのフィールド名が異なる場合は、同じ URL と Authorization ヘッダーを手動で設定してください。';
  }

  @override
  String get mcpResetTokenDialogTitle => 'トークンをリセットしますか？';

  @override
  String get mcpResetTokenDialogMessage =>
      '古いトークンを使用している既存クライアントは直ちにアクセスできなくなります。';

  @override
  String get mcpResetTokenConfirm => 'リセット';

  @override
  String get mcpTokenResetToast => 'トークンをリセットしました';

  @override
  String mcpLoadStatusFailed(Object error) {
    return 'MCP 状態の読み込みに失敗しました：$error';
  }

  @override
  String mcpStartFailed(Object error) {
    return 'MCP サービスの起動に失敗しました：$error';
  }

  @override
  String mcpStopFailed(Object error) {
    return 'MCP サービスの停止に失敗しました：$error';
  }

  @override
  String mcpResetTokenFailed(Object error) {
    return 'トークンのリセットに失敗しました：$error';
  }

  @override
  String mcpCopyValueEmpty(Object label) {
    return '$label が空です';
  }

  @override
  String mcpCopiedToast(Object label) {
    return '$label をコピーしました';
  }

  @override
  String mcpCopyFailed(Object label, Object error) {
    return '$label のコピーに失敗しました：$error';
  }

  @override
  String get externalMcpAddServerTitle => '外部 MCP サーバーを追加';

  @override
  String get externalMcpEditServerTitle => '外部 MCP サーバーを編集';

  @override
  String get externalMcpNameLabel => '名前';

  @override
  String get externalMcpUrlLabel => 'URL';

  @override
  String get externalMcpTransportLabel => 'トランスポート';

  @override
  String get externalMcpTransportStreamableHttp => 'Streamable HTTP';

  @override
  String get externalMcpTransportSse => 'SSE';

  @override
  String get externalMcpHeadersJsonLabel => 'ヘッダー JSON';

  @override
  String get externalMcpHeadersJsonHint => 'Authorization: Bearer ...';

  @override
  String get externalMcpEnabledLabel => '有効';

  @override
  String get externalMcpServersTitle => '外部 MCP サーバー';

  @override
  String get externalMcpImportJsonTooltip => 'JSON をインポート';

  @override
  String get externalMcpAddServerTooltip => 'JSON からサーバーを追加';

  @override
  String get externalMcpEmptyTitle => '外部 MCP サーバーはありません';

  @override
  String get externalMcpSyncAction => '同期';

  @override
  String get settingsSkillsTitle => 'Skills';

  @override
  String get settingsSkillsAddTitle => 'Skill を追加';

  @override
  String get settingsSkillsSkillMdLabel => 'SKILL.md';

  @override
  String get settingsSkillsSkillMdHint =>
      '---\nname: my-skill\ndescription: \"...\"\n---\n\nInstructions...';

  @override
  String get settingsSkillsImportAction => 'インポート';

  @override
  String get settingsSkillsDeleteTitle => 'Skill を削除しますか？';

  @override
  String settingsSkillsDeleteMessage(Object name) {
    return '$name と skill フォルダー内のすべてのファイルを削除します。';
  }

  @override
  String settingsSkillsSavedToast(Object name) {
    return 'Skill を保存しました：$name';
  }

  @override
  String settingsSkillsSaveFailed(Object error) {
    return 'Skill の保存に失敗しました：$error';
  }

  @override
  String get settingsSkillsDeletedToast => 'Skill を削除しました。';

  @override
  String get settingsSkillsNotFoundToast => 'Skill が見つかりません。';

  @override
  String settingsSkillsDeleteFailed(Object error) {
    return 'Skill の削除に失敗しました：$error';
  }

  @override
  String get settingsSkillsEnabledToast => 'Skill を有効にしました。';

  @override
  String get settingsSkillsDisabledToast => 'Skill を無効にしました。';

  @override
  String settingsSkillsUpdateFailed(Object error) {
    return 'Skill の更新に失敗しました：$error';
  }

  @override
  String get settingsSkillsAddTooltip => 'Skill を追加';

  @override
  String get settingsSkillsEmptyTitle => 'インストール済みの Skill はありません';

  @override
  String settingsSkillsFileCount(Object count) {
    return '$count 個のファイル';
  }

  @override
  String get settingsSkillsNewFileTitle => '新しい Skill ファイル';

  @override
  String get settingsSkillsRelativePathLabel => '相対パス';

  @override
  String get settingsSkillsRelativePathHint => 'examples/basic.md';

  @override
  String get settingsSkillsContentLabel => '内容';

  @override
  String get settingsSkillsFileSavedToast => 'ファイルを保存しました。';

  @override
  String settingsSkillsFileSaveFailed(Object error) {
    return 'ファイルの保存に失敗しました：$error';
  }

  @override
  String get settingsSkillsDeleteFileTitle => 'ファイルを削除しますか？';

  @override
  String settingsSkillsDeleteFileMessage(Object path, Object name) {
    return '$name から $path を削除します。';
  }

  @override
  String get settingsSkillsFileDeletedToast => 'ファイルを削除しました。';

  @override
  String settingsSkillsFileDeleteFailed(Object error) {
    return 'ファイルの削除に失敗しました：$error';
  }

  @override
  String get settingsSkillsFileCopiedToast => 'ファイルをコピーしました。';

  @override
  String get settingsSkillsNewFileAction => '新規ファイル';

  @override
  String get settingsSkillsCopyFileTooltip => 'コピー';

  @override
  String get settingsSkillsEditFileTooltip => '編集';

  @override
  String get settingsSkillsDeleteFileTooltip => '削除';

  @override
  String settingsSkillsLoadFailed(Object error) {
    return 'Skills の読み込みに失敗しました：$error';
  }

  @override
  String externalMcpLoadServersFailed(Object error) {
    return '外部 MCP サーバーの読み込みに失敗しました：$error';
  }

  @override
  String get externalMcpSelectedFileUnavailable => '選択したファイルは利用できません。';

  @override
  String get externalMcpImportConfirmTitle => '外部 MCP サーバーをインポートしますか？';

  @override
  String externalMcpImportConfirmMessage(Object count) {
    return '$count 個のサーバーが見つかりました。有効な状態で保存され、後で同期して個別のツールを有効化できます。';
  }

  @override
  String get externalMcpConfigImportedToast => 'MCP 設定をインポートしました。';

  @override
  String externalMcpImportFailed(Object error) {
    return 'インポートに失敗しました：$error';
  }

  @override
  String externalMcpImportConfigFailed(Object error) {
    return 'MCP 設定のインポートに失敗しました：$error';
  }

  @override
  String get externalMcpHeadersJsonObjectError =>
      'ヘッダー JSON はオブジェクトである必要があります。';

  @override
  String get externalMcpServerSavedToast => 'MCP サーバーを保存しました。';

  @override
  String externalMcpSaveFailed(Object error) {
    return '保存に失敗しました：$error';
  }

  @override
  String externalMcpSaveServerFailed(Object error) {
    return 'MCP サーバーの保存に失敗しました：$error';
  }

  @override
  String externalMcpUpdateFailed(Object error) {
    return '更新に失敗しました：$error';
  }

  @override
  String get externalMcpServerUpdatedToast => 'MCP サーバーを更新しました。';

  @override
  String externalMcpUpdateServerFailed(Object error) {
    return 'MCP サーバーの更新に失敗しました：$error';
  }

  @override
  String externalMcpSyncedToast(Object count) {
    return '$count 個のツールを同期しました。';
  }

  @override
  String externalMcpSyncFailed(Object error) {
    return '同期に失敗しました：$error';
  }

  @override
  String externalMcpSyncServerFailed(Object error) {
    return 'MCP サーバーの同期に失敗しました：$error';
  }

  @override
  String get externalMcpDeleteServerTitle => '外部 MCP サーバーを削除しますか？';

  @override
  String externalMcpDeleteServerMessage(Object name) {
    return '$name と同期済みのすべてのツール設定を削除します。';
  }

  @override
  String externalMcpDeleteFailed(Object error) {
    return '削除に失敗しました：$error';
  }

  @override
  String get externalMcpServerDeletedToast => 'MCP サーバーを削除しました。';

  @override
  String externalMcpDeleteServerFailed(Object error) {
    return 'MCP サーバーの削除に失敗しました：$error';
  }

  @override
  String externalMcpToolUpdateFailed(Object error) {
    return 'ツールの更新に失敗しました：$error';
  }

  @override
  String externalMcpUpdateToolFailed(Object error) {
    return 'MCP ツールの更新に失敗しました：$error';
  }

  @override
  String get externalMcpNoToolsSynced => 'まだツールは同期されていません。';

  @override
  String get cloudBackupEntryTitle => 'Baidu Netdisk バックアップ';

  @override
  String get cloudBackupEntrySubtitle =>
      '完全 ZIP バックアップを /apps/ScreenMemo へ自動アップロードします。';

  @override
  String get cloudBackupTitle => 'Baidu Netdisk バックアップ';

  @override
  String get cloudBackupEnableTitle => '自動クラウドバックアップを有効化';

  @override
  String get cloudBackupEnableSubtitle => 'バックアップ形式は完全 ZIP です。既定ではオフです。';

  @override
  String get cloudBackupAllowMobileDataTitle => 'モバイルデータ通信を許可';

  @override
  String get cloudBackupAllowMobileDataSubtitle =>
      'オフの場合、バックグラウンドバックアップは Wi-Fi または従量課金でないネットワークを待ちます。';

  @override
  String get cloudBackupFrequencyLabel => 'バックアップ頻度（日）';

  @override
  String get cloudBackupFrequencyHelper => '最小 1 日。既定は 30 日です。';

  @override
  String get cloudBackupKeepLatestLabel => '保持する最新バックアップ数';

  @override
  String get cloudBackupKeepLatestHelper => '既定では完全バックアップを 3 個保持します。';

  @override
  String get cloudBackupBaiduPlatformSection => 'Baidu Netdisk Open Platform';

  @override
  String get cloudBackupKeyGuide =>
      'Baidu Netdisk Open Platform でアプリを作成し、アプリ詳細から AppKey と SecretKey をコピーしてください。アプリディレクトリは ScreenMemo に設定してください。';

  @override
  String get cloudBackupOpenDeveloperDocs => 'AppKey/SecretKey を取得';

  @override
  String get cloudBackupOpenDeveloperDocsShort => 'Key を取得';

  @override
  String get cloudBackupAppKeyLabel => 'AppKey';

  @override
  String get cloudBackupSecretKeyLabel => 'SecretKey';

  @override
  String get cloudBackupAuthorizationCodeLabel => '認可コード';

  @override
  String get cloudBackupAuthorizationCodeHelper =>
      '認可ページを開いて許可した後、oob code をここに貼り付けてください。';

  @override
  String get cloudBackupOpenAuthPage => '認可ページを開く';

  @override
  String get cloudBackupExchangeCode => 'コードを交換';

  @override
  String get cloudBackupTestConnection => '接続をテスト';

  @override
  String get cloudBackupDeviceId => 'デバイス ID';

  @override
  String get cloudBackupLastAttempt => '前回の試行';

  @override
  String get cloudBackupLastSuccess => '前回の成功';

  @override
  String get cloudBackupLastStatus => '最新ステータス';

  @override
  String get cloudBackupSave => '設定を保存';

  @override
  String get cloudBackupRunNow => '今すぐバックアップ';

  @override
  String get cloudBackupNotAvailable => '利用不可';

  @override
  String get cloudBackupNever => '未実行';

  @override
  String get cloudBackupFrequencyInvalid => 'バックアップ頻度は 1 日以上にしてください。';

  @override
  String get cloudBackupKeepLatestInvalid => '保持するバックアップ数は 1 以上にしてください。';

  @override
  String get cloudBackupSettingsSaved => 'クラウドバックアップ設定を保存しました。';

  @override
  String get cloudBackupAppKeyRequired => '先に AppKey を入力してください。';

  @override
  String get cloudBackupAppSecretRequired => '先に AppKey と SecretKey を入力してください。';

  @override
  String get cloudBackupAuthCodeRequired => '先に認可コードを入力してください。';

  @override
  String get cloudBackupDeveloperDocsOpenFailed =>
      'Baidu Netdisk Open Platform のドキュメントを開けませんでした。';

  @override
  String get cloudBackupAuthPageOpenFailed => '認可ページを開けませんでした。';

  @override
  String get cloudBackupAuthorizationComplete => '認可が完了しました。';

  @override
  String get cloudBackupAuthorizationFailed => '認可に失敗しました。';

  @override
  String cloudBackupAuthorizationFailedWithError(Object error) {
    return '認可に失敗しました：$error';
  }

  @override
  String get cloudBackupAuthorizationRequired => '先に認可を完了してください。';

  @override
  String get cloudBackupConnectionSuccessful => '接続に成功しました。';

  @override
  String get cloudBackupConnectionFailed => '接続に失敗しました。';

  @override
  String cloudBackupConnectionFailedWithError(Object error) {
    return '接続に失敗しました：$error';
  }

  @override
  String get cloudBackupBackupStarted => 'バックアップタスクを開始しました。';

  @override
  String get cloudBackupStartFailed => 'バックアップタスクを開始できませんでした。';

  @override
  String cloudBackupStartFailedWithError(Object error) {
    return 'バックアップタスクを開始できませんでした：$error';
  }

  @override
  String get cloudBackupStatusRunning => '実行中';

  @override
  String get cloudBackupStatusSkippedNotDue => 'まだ予定時刻ではないためスキップしました';

  @override
  String get cloudBackupStatusAuthorizationRequired => '再認可が必要です';

  @override
  String cloudBackupStatusSuccess(Object detail) {
    return '成功：$detail';
  }

  @override
  String cloudBackupStatusFailed(Object detail) {
    return '失敗：$detail';
  }

  @override
  String cloudBackupStatusUnknown(Object detail) {
    return '不明なステータス：$detail';
  }

  @override
  String get cloudBackupProgressTitle => 'バックアップ進捗';

  @override
  String cloudBackupProgressPercent(Object percent) {
    return '$percent%';
  }

  @override
  String cloudBackupProgressBytes(Object done, Object total) {
    return '$done / $total';
  }

  @override
  String get cloudBackupProgressQueued => 'バックグラウンドタスクを待機中';

  @override
  String get cloudBackupProgressChecking => 'バックアップ条件を確認中';

  @override
  String get cloudBackupProgressPreparing => 'バックアップを準備中';

  @override
  String get cloudBackupProgressZipping => 'ZIP を作成中';

  @override
  String get cloudBackupProgressRemoteFolder => 'クラウドフォルダーを準備中';

  @override
  String get cloudBackupProgressPreparingUpload => 'アップロードを準備中';

  @override
  String get cloudBackupProgressPrecreate => 'アップロードセッションを作成中';

  @override
  String get cloudBackupProgressUploading => 'アップロード中';

  @override
  String get cloudBackupProgressCreatingRemoteFile => 'クラウドファイルを作成中';

  @override
  String get cloudBackupProgressCleanup => '古いバックアップをクリーンアップ中';

  @override
  String get cloudBackupProgressFinished => 'バックアップ完了';

  @override
  String get cloudBackupProgressFailed => 'バックアップに失敗しました';

  @override
  String get cloudBackupProgressDisabled => '自動クラウドバックアップはオフです';

  @override
  String get externalMcpConfigJsonLabel => 'MCP 設定 JSON';
}
