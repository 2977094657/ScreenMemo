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
  String get navSelectApps => '監視するアプリを選択';

  @override
  String get dialogOk => 'OK';

  @override
  String get dialogCancel => 'キャンセル';

  @override
  String get dialogDone => '完了';

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
  String get intervalHint => '5～60 の整数を入力してください';

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
  String get intervalRangeNote => '範囲: 5 ～ 60 秒、デフォルト: 5 秒。';

  @override
  String get intervalInvalidInput => '5 ～ 60 の有効な整数を入力してください';

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
  String get displayAndSortSectionTitle => '表示と並べ替え';

  @override
  String get screenshotSectionTitle => 'キャプチャ設定';

  @override
  String get segmentSummarySectionTitle => 'セグメントの概要';

  @override
  String get dailyReminderSectionTitle => '毎日の概要リマインダー';

  @override
  String get aiAssistantSectionTitle => 'AIアシスタント';

  @override
  String get dataBackupSectionTitle => 'データとバックアップ';

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
  String get compressDaysInvalidError => '1 以上の日数を入力してください。';

  @override
  String get compressHistoryTitle => '履歴の圧縮';

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
  String get importModeTitle => 'インポート方法を選択';

  @override
  String get importModeOverwriteTitle => '上書きインポート';

  @override
  String get importModeOverwriteDesc =>
      '現在のデータディレクトリを置き換えます。バックアップの完全復元に使用します。';

  @override
  String get importModeMergeTitle => 'マージインポート';

  @override
  String get importModeMergeDesc => '既存データを保持し、アーカイブ内容を重複排除してマージします。';

  @override
  String get mergeProgressCopying => 'スクリーンショットファイルをコピーしています…';

  @override
  String get mergeProgressCopyingGeneric => 'その他のリソースをコピーしています…';

  @override
  String get mergeProgressMergingDb => 'データベースをマージしています…';

  @override
  String get mergeProgressMemoryDb => 'メモリーデータベースをマージしています…';

  @override
  String get mergeProgressFinalizing => 'マージを完了しています…';

  @override
  String get mergeCompleteTitle => 'マージが完了しました';

  @override
  String mergeReportInserted(int count) {
    return '追加されたスクリーンショット: $count';
  }

  @override
  String mergeReportSkipped(int count) {
    return 'スキップした重複: $count';
  }

  @override
  String mergeReportCopied(int count) {
    return 'コピーしたファイル: $count';
  }

  @override
  String mergeReportMemoryEvents(int count) {
    return '追加された記憶イベント: $count';
  }

  @override
  String mergeReportMemoryTags(int count) {
    return '追加された記憶タグ: $count';
  }

  @override
  String mergeReportMemoryEvidence(int count) {
    return '追加されたタグ証拠: $count';
  }

  @override
  String mergeReportAffectedPackages(String packages) {
    return '影響を受けたアプリパッケージ: $packages';
  }

  @override
  String get mergeReportWarnings => '確認が必要な警告：';

  @override
  String get mergeReportNoWarnings => '警告はありません。';

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
  String get intervalInputHint => '5 ～ 60 の整数を入力してください';

  @override
  String get intervalInvalidError => '5～60 の有効な整数を入力してください';

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
  String loadMoreFailedWithError(Object error) {
    return 'さらにロードできませんでした: $error';
  }

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
  String get generatePersonaArticle => 'プロフィール記事を生成';

  @override
  String get articleGenerating => '記事を生成中...';

  @override
  String get articleGenerateSuccess => '記事の生成に成功しました';

  @override
  String get articleGenerateFailed => '記事の生成に失敗しました';

  @override
  String get articlePreviewTitle => 'プロフィール記事プレビュー';

  @override
  String get articleCopySuccess => '記事をクリップボードにコピーしました';

  @override
  String get articleLogTitle => '生成ログ';

  @override
  String get memoryPersonaHubTitle => 'メモリーアーカイブ';

  @override
  String get memoryTagsEntranceTooltip => 'タグライブラリを開く';

  @override
  String get memoryTagLibraryTitle => 'タグライブラリ';

  @override
  String get memoryArticleEmptyPlaceholder => 'まだプロフィール記事がありません。生成後にご確認ください。';

  @override
  String get memoryPauseActionLabel => '解析を一時停止';

  @override
  String get copyPersonaTooltip => 'ユーザー画像をコピー';

  @override
  String get memoryPersonaEmptyPlaceholder =>
      'まだユーザー画像がありません。イベントを記録して内容を充実させてください。';

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
      'Suggested ideas:\n- Emphasize week-over-week trends or pivots to highlight\n- Ask for actionable follow-ups or attention points\n- Avoid requesting structural changes to the JSON output';

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
  String get weeklySummaryPromptLabel => 'Weekly summary prompt';

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
  String get savedWeeklyPromptToast => 'Weekly prompt saved';

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
  String get deletedToast => '削除しました';

  @override
  String get providerNotFound => 'プロバイダーが見つかりません';

  @override
  String get memoryMenuEntry => 'メモリーアーカイブ';

  @override
  String get memoryCenterTitle => 'メモリーアーカイブ';

  @override
  String get memoryClearAllTooltip => '記憶庫を空にする';

  @override
  String get memoryClearAllConfirmTitle => '記憶庫を空にする';

  @override
  String get memoryClearAllConfirmMessage =>
      '記憶庫のタグ・イベント・証拠をすべて削除します。この操作は元に戻せません。続行しますか？';

  @override
  String get memoryImportSampleTooltip => 'テスト用に30件取り込み';

  @override
  String memoryImportSampleSuccess(Object count) {
    return 'テスト用に $count 件のイベントを取り込みました';
  }

  @override
  String get memoryImportSampleEmpty => '取り込める記憶イベントがありません';

  @override
  String memoryImportSampleFailed(Object error) {
    return '取り込みに失敗しました: $error';
  }

  @override
  String get memoryPauseTooltip => '処理を一時停止';

  @override
  String get memoryPauseSuccess => '解析を一時停止しました';

  @override
  String memoryPauseFailed(Object error) {
    return '一時停止に失敗しました: $error';
  }

  @override
  String get memoryPendingSectionTitle => '確認待ちのタグ';

  @override
  String get memoryConfirmedSectionTitle => '確認済みタグ';

  @override
  String get memoryRecentEventsSectionTitle => '最近のイベント';

  @override
  String get memoryNoPending => '確認待ちのタグはありません';

  @override
  String get memoryNoConfirmed => '確認済みのタグはまだありません';

  @override
  String get memoryNoEvents => '関連するイベントはまだありません';

  @override
  String get memoryConfirmAction => '確認済みにする';

  @override
  String get memoryStatusPending => '確認待ち';

  @override
  String get memoryStatusConfirmed => '確認済み';

  @override
  String get memoryCategoryIdentity => '本人情報';

  @override
  String get memoryCategoryRelationship => '関係';

  @override
  String get memoryCategoryInterest => '興味';

  @override
  String get memoryCategoryBehavior => '行動';

  @override
  String get memoryCategoryPreference => '嗜好';

  @override
  String get memoryCategoryOther => 'その他';

  @override
  String memoryConfidenceLabel(Object value) {
    return '確信度：$value%';
  }

  @override
  String memoryOccurrencesLabel(Object count) {
    return '出現回数：$count';
  }

  @override
  String memoryFirstSeenLabel(Object date) {
    return '初検出：$date';
  }

  @override
  String memoryLastSeenLabel(Object date) {
    return '最新検出：$date';
  }

  @override
  String memoryEvidenceCountLabel(Object count) {
    return '証拠：$count 件';
  }

  @override
  String get memoryEventContainsContext => 'ユーザー関連の情報を含みます';

  @override
  String get memoryEventNoContext => 'ユーザー関連の情報は検出されませんでした';

  @override
  String memoryEventTimeLabel(Object date) {
    return '時刻：$date';
  }

  @override
  String memoryEventSourceLabel(Object source) {
    return 'ソース：$source';
  }

  @override
  String memoryEventTypeLabel(Object type) {
    return 'タイプ：$type';
  }

  @override
  String get memoryProgressIdle => '歴史イベントの処理待ち';

  @override
  String get memoryProgressRunning => '歴史イベントを解析中';

  @override
  String memoryProgressRunningDetail(
    Object processed,
    Object total,
    Object percent,
  ) {
    return '$processed/$total 日を処理済み（$percent%）';
  }

  @override
  String memoryProgressNewTagsDetail(Object count) {
    return '新しいタグ：$count';
  }

  @override
  String memoryProgressCompleted(Object total, Object seconds) {
    return '歴史イベントの解析完了：合計 $total 日、$seconds 秒';
  }

  @override
  String memoryProgressFailed(Object message) {
    return '解析に失敗しました：$message';
  }

  @override
  String memoryProgressFailedEvent(Object event) {
    return '失敗イベント：$event';
  }

  @override
  String memoryProgressPreparing(Object stage) {
    return '準備中：$stage';
  }

  @override
  String get memoryProgressStageSyncSegments => 'スクリーンショットイベントを同期中';

  @override
  String get memoryProgressStageSyncChats => '会話ログを同期中';

  @override
  String get memoryProgressStageDispatch => '履歴解析を起動中';

  @override
  String get memoryRefreshTooltip => '更新';

  @override
  String memoryConfirmSuccessToast(Object label) {
    return '「$label」を確認済みにしました';
  }

  @override
  String memoryConfirmFailedToast(Object message) {
    return '操作に失敗しました：$message';
  }

  @override
  String get memorySnapshotUpdated => '記憶スナップショットを更新しました';

  @override
  String get memoryStartProcessingAction => '履歴イベント解析を開始';

  @override
  String get memoryStartProcessingActionShort => '解析を開始';

  @override
  String get memoryMalformedResponseTitle => '異常な応答を検出したため解析を一時停止しました';

  @override
  String memoryMalformedResponseSubtitle(Object eventId) {
    return 'イベント $eventId の応答に「当前用户描述：」マーカーが含まれていません。確認後に再開してください。';
  }

  @override
  String get memoryMalformedResponseSubtitleNoId =>
      '最新の応答に「当前用户描述：」マーカーが含まれていません。確認後に再開してください。';

  @override
  String get memoryMalformedResponseRawLabel => '生データ:';

  @override
  String get memoryDeleteTagAction => 'タグを削除';

  @override
  String get memoryDeleteTagConfirmTitle => 'タグを削除';

  @override
  String memoryDeleteTagConfirmMessage(Object tagLabel) {
    return 'タグ「$tagLabel」を削除しますか？関連する証拠も削除されます。';
  }

  @override
  String get memoryDeleteTagSuccess => 'タグを削除しました';

  @override
  String memoryDeleteTagFailed(Object error) {
    return '削除に失敗しました: $error';
  }

  @override
  String get memoryStatusPendingIndicator => '確認待ち';

  @override
  String get memoryStatusConfirmedIndicator => '確認済み';

  @override
  String get memoryReprocessAction => '履歴イベントを再解析';

  @override
  String get memoryStartProcessingToast => '履歴イベント解析を開始しました';

  @override
  String get memoryLoadMore => 'さらに読み込む';

  @override
  String get memoryCenterHeroTitle => 'キャラクタープロフィール';

  @override
  String get memoryCenterHeroSubtitle => 'イベントから抽出したRPG風の個人情報カード';

  @override
  String memoryCenterPendingCountLabel(Object count) {
    return '保留: $count';
  }

  @override
  String memoryCenterConfirmedCountLabel(Object count) {
    return '確定: $count';
  }

  @override
  String memoryCenterEventCountLabel(Object count) {
    return '関連イベント: $count';
  }

  @override
  String get memoryTagDetailTitle => 'タグ詳細';

  @override
  String get memoryTagDetailRefresh => '再読み込み';

  @override
  String get memoryTagDetailInfoTitle => 'プロフィール';

  @override
  String get memoryTagDetailStatisticsTitle => '属性';

  @override
  String memoryTagDetailOccurrences(Object count) {
    return '出現回数: $count';
  }

  @override
  String memoryTagDetailConfidence(Object confidence) {
    return '確信度: $confidence';
  }

  @override
  String memoryTagDetailFirstSeen(Object date) {
    return '初登場: $date';
  }

  @override
  String memoryTagDetailLastSeen(Object date) {
    return '最終登場: $date';
  }

  @override
  String get memoryTagDetailEvidenceTitle => '証拠一覧';

  @override
  String memoryTagDetailEvidenceCount(Object count) {
    return '証拠総数: $count';
  }

  @override
  String get memoryTagDetailNoEvidence => '証拠がまだありません';

  @override
  String get memoryTagDetailLoadFailed => 'タグデータの読み込みに失敗しました';

  @override
  String get memoryEvidenceInferenceLabel => '推論メモ';

  @override
  String get memoryEvidenceNotesLabel => 'メモ';

  @override
  String get memoryEvidenceNoNotes => 'メモなし';

  @override
  String get memoryEvidenceEventHeading => '関連イベント';

  @override
  String get memoryEvidenceUserEditedBadge => 'ユーザー編集済み';

  @override
  String get conversationsSectionTitle => '会話';

  @override
  String get displaySectionTitle => '表示';

  @override
  String get streamRenderImagesTitle => 'ストリーミング中に画像を描画';

  @override
  String get streamRenderImagesDesc => 'スクロールに影響する場合があります';

  @override
  String get themeColorTitle => 'テーマカラー';

  @override
  String get themeColorDesc => 'アプリのキーカラーをカスタマイズ';

  @override
  String get chooseThemeColorTitle => 'テーマカラーを選択';

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
}
