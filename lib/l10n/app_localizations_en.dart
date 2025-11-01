// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'ScreenMemo';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get searchPlaceholder => 'Search screenshots...';

  @override
  String get homeEmptyTitle => 'No monitored apps';

  @override
  String get homeEmptySubtitle => 'Choose apps to monitor in Settings';

  @override
  String get navSelectApps => 'Select apps to monitor';

  @override
  String get dialogOk => 'OK';

  @override
  String get dialogCancel => 'Cancel';

  @override
  String get dialogDone => 'Done';

  @override
  String get permissionStatusTitle => 'Permission Status';

  @override
  String get permissionMissing => 'Permissions missing';

  @override
  String get startScreenshot => 'Start capture';

  @override
  String get stopScreenshot => 'Stop capture';

  @override
  String get screenshotEnabledToast => 'Capture enabled';

  @override
  String get screenshotDisabledToast => 'Capture disabled';

  @override
  String get intervalSettingTitle => 'Set capture interval';

  @override
  String get intervalLabel => 'Interval (seconds)';

  @override
  String get intervalHint => 'Enter an integer between 5-60';

  @override
  String intervalSavedToast(Object seconds) {
    return 'Capture interval set to ${seconds}s';
  }

  @override
  String get languageSettingTitle => 'Language';

  @override
  String get languageSystem => 'System';

  @override
  String get languageChinese => 'Chinese (Simplified)';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageJapanese => 'Japanese';

  @override
  String get languageKorean => 'Korean';

  @override
  String languageChangedToast(Object name) {
    return 'Switched to $name';
  }

  @override
  String get nsfwWarningTitle => 'Content Warning: Adult Content';

  @override
  String get nsfwWarningSubtitle =>
      'This content has been marked as adult content';

  @override
  String get show => 'Show';

  @override
  String get appSearchPlaceholder => 'Search apps...';

  @override
  String selectedCount(Object count) {
    return 'Selected $count';
  }

  @override
  String get refreshAppsTooltip => 'Refresh apps';

  @override
  String get selectAll => 'Select all';

  @override
  String get clearAll => 'Clear';

  @override
  String get noAppsFound => 'No apps found';

  @override
  String get noAppsMatched => 'No matching apps';

  @override
  String stepProgress(Object current, Object total) {
    return 'Step $current / $total';
  }

  @override
  String get onboardingWelcomeTitle => 'Welcome to ScreenMemo';

  @override
  String get onboardingWelcomeDesc =>
      'An intelligent memo and information management tool to help you capture, organize, and review important information efficiently.';

  @override
  String get onboardingKeyFeaturesTitle => 'Key features';

  @override
  String get featureSmartNotes => 'Smart information capture';

  @override
  String get featureQuickSearch => 'Fast content search';

  @override
  String get featureLocalStorage => 'Local data storage';

  @override
  String get featureUsageAnalytics => 'Usage analytics';

  @override
  String get onboardingPermissionsTitle => 'Grant required permissions';

  @override
  String get refreshPermissionStatus => 'Refresh permission status';

  @override
  String get onboardingPermissionsDesc =>
      'To provide the full experience, please grant the following permissions:';

  @override
  String get storagePermissionTitle => 'Storage permission';

  @override
  String get storagePermissionDesc => 'Save screenshot files to device storage';

  @override
  String get notificationPermissionTitle => 'Notification permission';

  @override
  String get notificationPermissionDesc => 'Show service status notifications';

  @override
  String get accessibilityPermissionTitle => 'Accessibility service';

  @override
  String get accessibilityPermissionDesc =>
      'Monitor app switching and take screenshots';

  @override
  String get usageStatsPermissionTitle => 'Usage stats permission';

  @override
  String get usageStatsPermissionDesc =>
      'Ensure accurate foreground app detection';

  @override
  String get batteryOptimizationTitle => 'Battery optimization whitelist';

  @override
  String get batteryOptimizationDesc =>
      'Keep screenshot service running stably';

  @override
  String get pleaseCompleteInSystemSettings =>
      'Please complete authorization in system settings, then return to the app';

  @override
  String get autostartPermissionTitle => 'Auto-start permission';

  @override
  String get autostartPermissionDesc => 'Allow app to restart in background';

  @override
  String get permissionsFooterNote =>
      'Permissions persist after granting and can be changed anytime in system settings';

  @override
  String get grantedLabel => 'Granted';

  @override
  String get authorizeAction => 'Authorize';

  @override
  String get onboardingSelectAppsTitle => 'Select apps to monitor';

  @override
  String get onboardingSelectAppsDesc =>
      'Please choose apps to monitor for screenshots. Select at least one to continue.';

  @override
  String get onboardingDoneTitle => 'All set!';

  @override
  String get onboardingDoneDesc =>
      'All permissions have been granted. You can now start using ScreenMemo.';

  @override
  String get nextStepTitle => 'Next step';

  @override
  String get onboardingNextStepDesc =>
      'Tap \"Start Using\" to enter the main screen and experience powerful screenshot features.';

  @override
  String get prevStep => 'Previous';

  @override
  String get startUsing => 'Start Using';

  @override
  String get finishSelection => 'Finish selection';

  @override
  String get nextStep => 'Next';

  @override
  String get confirmPermissionSettingsTitle => 'Confirm permission settings';

  @override
  String get confirmAutostartQuestion =>
      'Have you completed the \"Auto-start permission\" configuration in system settings?';

  @override
  String get notYet => 'Not yet';

  @override
  String get done => 'Done';

  @override
  String get startingScreenshotServiceInfo => 'Starting capture service...';

  @override
  String get startServiceFailedCheckPermissions =>
      'Failed to start capture service. Please check permission settings';

  @override
  String get startFailedTitle => 'Start failed';

  @override
  String get startFailedUnknown => 'Start failed: Unknown error';

  @override
  String get tipIfProblemPersists =>
      'Tip: If the issue persists, try restarting the app or reconfiguring permissions';

  @override
  String get autoDisabledDueToPermissions =>
      'Capture has been disabled due to insufficient permissions';

  @override
  String get refreshingPermissionsInfo => 'Refreshing permission status...';

  @override
  String get permissionsRefreshed => 'Permission status refreshed';

  @override
  String refreshPermissionsFailed(Object error) {
    return 'Failed to refresh permission status: $error';
  }

  @override
  String get screenRecordingPermissionTitle => 'Screen recording permission';

  @override
  String get goToSettings => 'Go to Settings';

  @override
  String get notGrantedLabel => 'Not granted';

  @override
  String get removeMonitoring => 'Remove monitoring';

  @override
  String selectedItemsCount(Object count) {
    return 'Selected $count';
  }

  @override
  String get whySomeAppsHidden => 'Why are some apps missing?';

  @override
  String get excludedAppsTitle => 'Excluded apps';

  @override
  String get excludedAppsIntro =>
      'The following apps are excluded and cannot be selected:';

  @override
  String get excludedThisApp => '· This app (to avoid self interference)';

  @override
  String get excludedImeApps => '· Input method (keyboard) apps:';

  @override
  String get excludedImeAppsFiltered =>
      '· Input method (keyboard) apps (auto filtered)';

  @override
  String currentDefaultIme(Object name, Object package) {
    return 'Current default IME: $name ($package)';
  }

  @override
  String get imeExplainText =>
      'When the keyboard pops up in another app, the system switches to the IME window. If not excluded, it may be mistaken as using the IME, causing the floating window detection to be wrong. We automatically exclude IME apps and will still move the floating window to the app before the IME pops up when an IME is detected.';

  @override
  String get gotIt => 'Got it';

  @override
  String get unknownIme => 'Unknown IME';

  @override
  String get intervalRangeNote => 'Range: 5–60 seconds, default: 5 seconds.';

  @override
  String get intervalInvalidInput =>
      'Please enter a valid integer between 5–60';

  @override
  String get removeMonitoringMessage =>
      'Only remove monitoring and do not delete images. Continue?';

  @override
  String get remove => 'Remove';

  @override
  String removedMonitoringToast(Object count) {
    return 'Removed monitoring for $count apps (images are not deleted)';
  }

  @override
  String checkPermissionStatusFailed(Object error) {
    return 'Failed to check permission status: $error';
  }

  @override
  String get accessibilityNotEnabledDetail =>
      'Accessibility service not enabled\\nPlease enable accessibility in Settings';

  @override
  String get storagePermissionNotGrantedDetail =>
      'Storage permission not granted\\nPlease grant storage permission in Settings';

  @override
  String get serviceNotRunningDetail =>
      'Service not running properly\\nPlease try restarting the app';

  @override
  String get androidVersionNotSupportedDetail =>
      'Android version not supported\\nRequires Android 11.0 or higher';

  @override
  String get permissionsSectionTitle => 'Permissions';

  @override
  String get displayAndSortSectionTitle => 'Display & Sorting';

  @override
  String get screenshotSectionTitle => 'Capture settings';

  @override
  String get segmentSummarySectionTitle => 'Segment summary';

  @override
  String get dailyReminderSectionTitle => 'Daily summary reminder';

  @override
  String get aiAssistantSectionTitle => 'AI Assistant';

  @override
  String get dataBackupSectionTitle => 'Data & backup';

  @override
  String get actionSet => 'Set';

  @override
  String get actionEnter => 'Enter';

  @override
  String get actionExport => 'Export';

  @override
  String get actionImport => 'Import';

  @override
  String get actionCopyPath => 'Copy path';

  @override
  String get actionOpen => 'Open';

  @override
  String get actionTrigger => 'Trigger';

  @override
  String get allPermissionsGranted => 'All granted';

  @override
  String permissionsMissingCount(Object count) {
    return '$count permissions not granted';
  }

  @override
  String get exportSuccessTitle => 'Export complete';

  @override
  String get exportFileExportedTo => 'File exported to:';

  @override
  String get pathCopiedToast => 'Path copied';

  @override
  String get exportFailedTitle => 'Export failed';

  @override
  String get pleaseTryAgain => 'Please try again later';

  @override
  String get importCompleteTitle => 'Import complete';

  @override
  String get dataExtractedTo => 'Data extracted to:';

  @override
  String get importFailedTitle => 'Import failed';

  @override
  String get importFailedCheckZip => 'Please check the ZIP file and try again.';

  @override
  String get noMediaProjectionNeeded =>
      'Using Accessibility screenshots, no screen recording permission needed';

  @override
  String get autostartPermissionMarked =>
      'Auto-start permission marked as granted';

  @override
  String requestPermissionFailed(Object error) {
    return 'Request permission failed: $error';
  }

  @override
  String get expireCleanupSaved => 'Expire cleanup settings saved';

  @override
  String get dailyNotifyTriggered => 'Notification triggered';

  @override
  String get dailyNotifyTriggerFailed =>
      'Failed to trigger notification or content empty';

  @override
  String get refreshPermissionStatusTooltip => 'Refresh permission status';

  @override
  String get grantedStatus => 'Granted';

  @override
  String get notGrantedStatus => 'Grant';

  @override
  String get privacyModeTitle => 'Privacy mode';

  @override
  String get privacyModeDesc => 'Automatically blur sensitive content';

  @override
  String get homeSortingTitle => 'Home sorting';

  @override
  String get screenshotIntervalTitle => 'Screenshot interval';

  @override
  String screenshotIntervalDesc(Object seconds) {
    return 'Current interval: ${seconds}s';
  }

  @override
  String get screenshotQualityTitle => 'Screenshot quality';

  @override
  String get currentSizeLabel => 'Current size: ';

  @override
  String get clickToModifyHint => '(Click number to modify)';

  @override
  String get screenshotExpireTitle => 'Screenshot expiration cleanup';

  @override
  String get currentExpireDaysLabel => 'Current expiration days: ';

  @override
  String expireDaysUnit(Object days) {
    return '$days days';
  }

  @override
  String get exportDataTitle => 'Export data';

  @override
  String get exportDataDesc => 'Export ZIP to Download/ScreenMemory';

  @override
  String get importDataTitle => 'Import data';

  @override
  String get importDataDesc => 'Import ZIP file to app storage';

  @override
  String get aiAssistantTitle => 'AI Assistant';

  @override
  String get aiAssistantDesc =>
      'Configure AI interface and models, test multi-turn conversations';

  @override
  String get segmentSampleIntervalTitle => 'Sample interval (seconds)';

  @override
  String segmentSampleIntervalDesc(Object seconds) {
    return 'Current: ${seconds}s';
  }

  @override
  String get segmentDurationTitle => 'Segment duration (minutes)';

  @override
  String segmentDurationDesc(Object minutes) {
    return 'Current: $minutes minutes';
  }

  @override
  String get aiRequestIntervalTitle => 'AI request minimum interval (seconds)';

  @override
  String aiRequestIntervalDesc(Object seconds) {
    return 'Current: ${seconds}s (minimum 1s)';
  }

  @override
  String get dailyReminderTimeTitle => 'Daily summary reminder time';

  @override
  String get currentTimeLabel => 'Current: ';

  @override
  String get testNotificationTitle => 'Test notification';

  @override
  String get testNotificationDesc =>
      'Trigger \"Daily Summary\" notification now';

  @override
  String get enableBannerNotificationTitle =>
      'Enable banner/floating notifications';

  @override
  String get enableBannerNotificationDesc =>
      'Allow notifications to pop up at the top of screen (banner/floating)';

  @override
  String get setIntervalDialogTitle => 'Set screenshot interval';

  @override
  String get intervalSecondsLabel => 'Interval (seconds)';

  @override
  String get intervalInputHint => 'Enter an integer between 5-60';

  @override
  String get intervalRangeHint => 'Range: 5-60 seconds, default: 5 seconds';

  @override
  String get intervalInvalidError =>
      'Please enter a valid integer between 5-60';

  @override
  String intervalSavedSuccess(Object seconds) {
    return 'Screenshot interval set to ${seconds}s';
  }

  @override
  String get setTargetSizeDialogTitle => 'Set target size (KB)';

  @override
  String get targetSizeKbLabel => 'Target size (KB)';

  @override
  String get targetSizeInvalidError => 'Please enter a valid integer >= 50';

  @override
  String targetSizeSavedSuccess(Object kb) {
    return 'Target size set to $kb KB';
  }

  @override
  String get setExpireDaysDialogTitle => 'Set screenshot expiration days';

  @override
  String get expireDaysLabel => 'Expiration days';

  @override
  String get expireDaysInputHint => 'Enter an integer >= 1';

  @override
  String get expireDaysInvalidError => 'Please enter a valid integer >= 1';

  @override
  String expireDaysSavedSuccess(Object days) {
    return 'Set to $days days';
  }

  @override
  String get sortTimeNewToOld => 'Time (New→Old)';

  @override
  String get sortTimeOldToNew => 'Time (Old→New)';

  @override
  String get sortSizeLargeToSmall => 'Size (Large→Small)';

  @override
  String get sortSizeSmallToLarge => 'Size (Small→Large)';

  @override
  String get sortCountManyToFew => 'Count (Many→Few)';

  @override
  String get sortCountFewToMany => 'Count (Few→Many)';

  @override
  String get sortFieldTime => 'Time';

  @override
  String get sortFieldCount => 'Count';

  @override
  String get sortFieldSize => 'Size';

  @override
  String get selectHomeSortingTitle => 'Select home sorting';

  @override
  String currentSortingLabel(Object sorting) {
    return 'Current: $sorting';
  }

  @override
  String get privacyModeEnabledToast => 'Privacy mode enabled';

  @override
  String get privacyModeDisabledToast => 'Privacy mode disabled';

  @override
  String get screenshotQualitySettingsSaved =>
      'Screenshot quality settings saved';

  @override
  String saveFailedError(Object error) {
    return 'Save failed: $error';
  }

  @override
  String get setReminderTimeTitle => 'Set reminder time (24-hour format)';

  @override
  String get hourLabel => 'Hour (0-23)';

  @override
  String get minuteLabel => 'Minute (0-59)';

  @override
  String get timeInputHint =>
      'Tip: Click numbers to input directly; range is 0-23 hours and 0-59 minutes.';

  @override
  String get invalidHourError => 'Please enter a valid hour between 0-23';

  @override
  String get invalidMinuteError => 'Please enter a valid minute between 0-59';

  @override
  String timeSetSuccess(Object hour, Object minute) {
    return 'Set to $hour:$minute';
  }

  @override
  String reminderScheduleSuccess(Object hour, Object minute) {
    return 'Daily reminder time set to $hour:$minute';
  }

  @override
  String get reminderDisabledSuccess => 'Daily reminder disabled';

  @override
  String get reminderScheduleFailed =>
      'Failed to schedule daily reminder (platform may not support)';

  @override
  String saveReminderSettingsFailed(Object error) {
    return 'Failed to save reminder settings: $error';
  }

  @override
  String searchFailedError(Object error) {
    return 'Search failed: $error';
  }

  @override
  String get searchInputHintOcr => 'Type keywords to search screenshots by OCR';

  @override
  String get noMatchingScreenshots => 'No matching screenshots';

  @override
  String get imageMissingOrCorrupted => 'Image missing or corrupted';

  @override
  String get actionClear => 'Clear';

  @override
  String get actionRefresh => 'Refresh';

  @override
  String get noScreenshotsTitle => 'No screenshots yet';

  @override
  String get noScreenshotsSubtitle =>
      'Enable screenshot monitoring to see images here';

  @override
  String get confirmDeleteTitle => 'Confirm deletion';

  @override
  String get confirmDeleteMessage =>
      'Delete this screenshot? This action cannot be undone.';

  @override
  String get actionDelete => 'Delete';

  @override
  String get actionContinue => 'Continue';

  @override
  String get linkTitle => 'Link';

  @override
  String get actionCopy => 'Copy';

  @override
  String get imageInfoTitle => 'Screenshot info';

  @override
  String get deleteImageTooltip => 'Delete image';

  @override
  String get imageLoadFailed => 'Image failed to load';

  @override
  String get labelAppName => 'App name';

  @override
  String get labelCaptureTime => 'Capture time';

  @override
  String get labelFilePath => 'File path';

  @override
  String get labelPageLink => 'Page link';

  @override
  String get labelFileSize => 'File size';

  @override
  String get tapToContinue => 'Tap to continue';

  @override
  String get appDirUninitialized => 'App directory not initialized';

  @override
  String get actionRetry => 'Retry';

  @override
  String get deleteSelectedTooltip => 'Delete selected';

  @override
  String get noMatchingResults => 'No matching results';

  @override
  String dayTabToday(Object count) {
    return 'Today $count';
  }

  @override
  String dayTabYesterday(Object count) {
    return 'Yesterday $count';
  }

  @override
  String dayTabMonthDayCount(Object month, Object day, Object count) {
    return '$month/$day $count';
  }

  @override
  String get screenshotDeletedToast => 'Screenshot deleted';

  @override
  String get deleteFailed => 'Delete failed';

  @override
  String deleteFailedWithError(Object error) {
    return 'Delete failed: $error';
  }

  @override
  String get imageInfoTooltip => 'Image info';

  @override
  String get copySuccess => 'Copied';

  @override
  String get copyFailed => 'Copy failed';

  @override
  String deletedCountToast(Object count) {
    return 'Deleted $count screenshots';
  }

  @override
  String get invalidArguments => 'Invalid arguments';

  @override
  String initFailedWithError(Object error) {
    return 'Initialization failed: $error';
  }

  @override
  String loadMoreFailedWithError(Object error) {
    return 'Failed to load more: $error';
  }

  @override
  String get confirmDeleteAllTitle => 'Confirm deleting all screenshots';

  @override
  String deleteAllMessage(Object count) {
    return 'Will delete all $count screenshots in current scope. This action cannot be undone.';
  }

  @override
  String deleteSelectedMessage(Object count) {
    return 'Will delete $count selected screenshots. This cannot be undone. Continue?';
  }

  @override
  String get deleteFailedRetry => 'Delete failed, please retry';

  @override
  String keptAndDeletedSummary(Object keep, Object deleted) {
    return 'Kept $keep, deleted $deleted';
  }

  @override
  String dailySummaryTitle(Object date) {
    return 'Daily Summary $date';
  }

  @override
  String dailySummarySlotMorningTitle(Object date) {
    return 'Morning Briefing $date';
  }

  @override
  String dailySummarySlotNoonTitle(Object date) {
    return 'Midday Briefing $date';
  }

  @override
  String dailySummarySlotEveningTitle(Object date) {
    return 'Evening Briefing $date';
  }

  @override
  String dailySummarySlotNightTitle(Object date) {
    return 'Nightly Briefing $date';
  }

  @override
  String get actionGenerate => 'Generate';

  @override
  String get actionRegenerate => 'Regenerate';

  @override
  String get generateSuccess => 'Generated';

  @override
  String get generateFailed => 'Generate failed';

  @override
  String get noDailySummaryToday => 'No summary for today';

  @override
  String get generateDailySummary => 'Generate today\'s summary';

  @override
  String get statisticsTitle => 'Statistics';

  @override
  String get overviewTitle => 'Overview';

  @override
  String get monitoredApps => 'Monitored apps';

  @override
  String get totalScreenshots => 'Total screenshots';

  @override
  String get todayScreenshots => 'Today\'s screenshots';

  @override
  String get storageUsage => 'Storage usage';

  @override
  String get appStatisticsTitle => 'App statistics';

  @override
  String screenshotCountWithLast(Object count, Object last) {
    return 'Screenshots: $count | Last: $last';
  }

  @override
  String get none => 'None';

  @override
  String get usageTrendsTitle => 'Usage trends';

  @override
  String get trendChartTitle => 'Trend chart';

  @override
  String get comingSoon => 'Coming soon';

  @override
  String get timelineTitle => 'Timeline';

  @override
  String get pressBackAgainToExit => 'Press back again to exit';

  @override
  String get segmentStatusTitle => 'Activity';

  @override
  String get autoWatchingHint => 'Auto watching in background…';

  @override
  String get noEvents => 'No events';

  @override
  String get noEventsSubtitle =>
      'Event segments and AI summaries will appear here';

  @override
  String get activeSegmentTitle => 'Active segment';

  @override
  String sampleEverySeconds(Object seconds) {
    return 'Sample every ${seconds}s';
  }

  @override
  String get dailySummaryShort => 'Daily Summary';

  @override
  String get viewOrGenerateForDay => 'View or generate the day\'s summary';

  @override
  String get mergedEventTag => 'Merged';

  @override
  String get collapse => 'Collapse';

  @override
  String get expandMore => 'Expand more';

  @override
  String viewImagesCount(Object count) {
    return 'View images ($count)';
  }

  @override
  String hideImagesCount(Object count) {
    return 'Hide images ($count)';
  }

  @override
  String get deleteEventTooltip => 'Delete event';

  @override
  String get confirmDeleteEventMessage =>
      'Delete this event? This will not delete any image files.';

  @override
  String get eventDeletedToast => 'Event deleted';

  @override
  String get regenerationQueued => 'Regeneration queued';

  @override
  String get alreadyQueuedOrFailed => 'Already queued or failed';

  @override
  String get retryFailed => 'Retry failed';

  @override
  String get copyResultsTooltip => 'Copy results';

  @override
  String get saveImageTooltip => 'Save to gallery';

  @override
  String get saveImageSuccess => 'Saved to Gallery';

  @override
  String get saveImageFailed => 'Save failed';

  @override
  String get requestGalleryPermissionFailed =>
      'Request gallery permission failed';

  @override
  String get aiSystemPromptLanguagePolicy =>
      'Regardless of the language used in the input context (events, screenshot text, or user messages), you must strictly ignore it and always produce output in the application\'s current language. If the app is set to English, all answers, titles, summaries, tags, structured fields, and error messages must be written in English unless the user explicitly requests another language.';

  @override
  String get aiSettingsTitle => 'AI Settings & Test';

  @override
  String get connectionSettingsTitle => 'Connection settings';

  @override
  String get actionSave => 'Save';

  @override
  String get clearConversation => 'Clear conversation';

  @override
  String get deleteGroup => 'Delete group';

  @override
  String get streamingRequestTitle => 'Streaming';

  @override
  String get streamingRequestHint =>
      'Use streaming responses when enabled (default on)';

  @override
  String get streamingEnabledToast => 'Streaming enabled';

  @override
  String get streamingDisabledToast => 'Streaming disabled';

  @override
  String get promptManagerTitle => 'Prompt manager';

  @override
  String get promptManagerHint =>
      'Configure prompts for normal, merged, and daily summaries; supports Markdown. Empty or reset to use defaults.';

  @override
  String get promptAddonGeneralInfo =>
      'The built-in template already defines the structured schema. Only append extra guidance here (tone, style, emphasis). Leave blank to keep the template unchanged.';

  @override
  String get promptAddonInputHint =>
      'Add optional extra instructions (leave blank to skip)';

  @override
  String get promptAddonHelperText =>
      'Describe tone or preferences only; do not request schema changes or JSON modifications.';

  @override
  String get promptAddonEmptyPlaceholder => 'No extra instructions';

  @override
  String get promptAddonSuggestionSegment =>
      'Suggested ideas:\n- State the desired tone or target audience in one sentence\n- Highlight the key insights or safety constraints to prioritize\n- Avoid asking for JSON field additions or structural changes';

  @override
  String get promptAddonSuggestionMerge =>
      'Suggested ideas:\n- Emphasize comparisons or contrasts to surface after merging\n- Remind the model to avoid repetition and focus on aggregated insights\n- Do not request structural changes to the output fields';

  @override
  String get promptAddonSuggestionDaily =>
      'Suggested ideas:\n- Specify the daily recap tone (e.g., action-oriented)\n- Ask to highlight major achievements or risks\n- Forbid renaming or adding JSON fields';

  @override
  String get normalEventPromptLabel => 'Normal event prompt';

  @override
  String get mergeEventPromptLabel => 'Merged event prompt';

  @override
  String get dailySummaryPromptLabel => 'Daily summary prompt';

  @override
  String get actionEdit => 'Edit';

  @override
  String get savingLabel => 'Saving';

  @override
  String get resetToDefault => 'Reset to default';

  @override
  String get chatTestTitle => 'Chat test';

  @override
  String get actionSend => 'Send';

  @override
  String get sendingLabel => 'Sending';

  @override
  String get baseUrlLabel => 'Base URL';

  @override
  String get baseUrlHint => 'e.g. https://api.openai.com';

  @override
  String get apiKeyLabel => 'API key';

  @override
  String get apiKeyHint => 'e.g. sk-... or vendor token';

  @override
  String get modelLabel => 'Model';

  @override
  String get modelHint => 'e.g. gpt-4o-mini / gpt-4o / compatible';

  @override
  String get siteGroupsTitle => 'Site groups';

  @override
  String get siteGroupsHint =>
      'Configure multiple sites as fallback; auto switch on failure';

  @override
  String get rename => 'Rename';

  @override
  String get addGroup => 'Add group';

  @override
  String get showGroupSelector => 'Show group selector';

  @override
  String get ungroupedSingleConfig => 'Ungrouped (single config)';

  @override
  String get inputMessageHint => 'Enter a message';

  @override
  String get saveSuccess => 'Saved';

  @override
  String get savedCurrentGroupToast => 'Group saved';

  @override
  String get savedNormalPromptToast => 'Normal prompt saved';

  @override
  String get savedMergePromptToast => 'Merged prompt saved';

  @override
  String get savedDailyPromptToast => 'Daily prompt saved';

  @override
  String get resetToDefaultPromptToast => 'Reset to default prompt';

  @override
  String resetFailedWithError(Object error) {
    return 'Reset failed: $error';
  }

  @override
  String get clearSuccess => 'Cleared';

  @override
  String clearFailedWithError(Object error) {
    return 'Clear failed: $error';
  }

  @override
  String get messageCannotBeEmpty => 'Message cannot be empty';

  @override
  String sendFailedWithError(Object error) {
    return 'Send failed: $error';
  }

  @override
  String get groupSwitchedToUngrouped => 'Switched to Ungrouped';

  @override
  String get groupSwitched => 'Group switched';

  @override
  String get groupNotSelected => 'No group selected';

  @override
  String get groupNotFound => 'Group not found';

  @override
  String get renameGroupTitle => 'Rename group';

  @override
  String get groupNameLabel => 'Group name';

  @override
  String get groupNameHint => 'Enter a new group name';

  @override
  String get nameCannotBeEmpty => 'Name cannot be empty';

  @override
  String get renameSuccess => 'Renamed';

  @override
  String renameFailedWithError(Object error) {
    return 'Rename failed: $error';
  }

  @override
  String get groupAddedToast => 'Group added';

  @override
  String addGroupFailedWithError(Object error) {
    return 'Add group failed: $error';
  }

  @override
  String get groupDeletedToast => 'Group deleted';

  @override
  String deleteGroupFailedWithError(Object error) {
    return 'Delete group failed: $error';
  }

  @override
  String loadGroupFailedWithError(Object error) {
    return 'Load group failed: $error';
  }

  @override
  String siteGroupDefaultName(Object index) {
    return 'Site Group $index';
  }

  @override
  String get defaultLabel => 'Default';

  @override
  String get customLabel => 'Custom';

  @override
  String get normalShortLabel => 'Normal:';

  @override
  String get mergeShortLabel => 'Merged:';

  @override
  String get dailyShortLabel => 'Daily:';

  @override
  String timeRangeLabel(Object range) {
    return 'Time range: $range';
  }

  @override
  String statusLabel(Object status) {
    return 'Status: $status';
  }

  @override
  String samplesTitle(Object count) {
    return 'Samples ($count)';
  }

  @override
  String get aiResultTitle => 'AI Result';

  @override
  String modelValueLabel(Object model) {
    return 'Model: $model';
  }

  @override
  String get tagMergedCopy => 'Tag: Merged';

  @override
  String categoriesLabel(Object categories) {
    return 'Categories: $categories';
  }

  @override
  String errorLabel(Object error) {
    return 'Error: $error';
  }

  @override
  String summaryLabel(Object summary) {
    return 'Summary: $summary';
  }

  @override
  String get autostartPermissionNote =>
      'Auto-start permission varies by OEM and cannot be auto-detected. Please choose based on your actual settings.';

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
    return '$count images';
  }

  @override
  String get apps => 'apps';

  @override
  String get images => 'images';

  @override
  String get days => 'days';

  @override
  String get justNow => 'Just now';

  @override
  String minutesAgo(Object minutes) {
    return '$minutes minutes ago';
  }

  @override
  String hoursAgo(Object hours) {
    return '$hours hours ago';
  }

  @override
  String daysAgo(Object days) {
    return '$days days ago';
  }

  @override
  String searchResultsCount(Object count) {
    return '$count images found';
  }

  @override
  String get searchFiltersTitle => 'Filters';

  @override
  String get filterByTime => 'Time';

  @override
  String get filterByApp => 'App';

  @override
  String get filterBySize => 'Size';

  @override
  String get filterTimeAll => 'All';

  @override
  String get filterTimeToday => 'Today';

  @override
  String get filterTimeYesterday => 'Yesterday';

  @override
  String get filterTimeLast7Days => 'Last 7 days';

  @override
  String get filterTimeLast30Days => 'Last 30 days';

  @override
  String get filterTimeCustomRange => 'Custom range';

  @override
  String get filterAppAll => 'All apps';

  @override
  String get filterSizeAll => 'All sizes';

  @override
  String get filterSizeSmall => '< 100 KB';

  @override
  String get filterSizeMedium => '100 KB - 1 MB';

  @override
  String get filterSizeLarge => '> 1 MB';

  @override
  String get applyFilters => 'Apply';

  @override
  String get resetFilters => 'Reset';

  @override
  String get selectDateRange => 'Select date range';

  @override
  String get startDate => 'Start date';

  @override
  String get endDate => 'End date';

  @override
  String get noResultsForFilters => 'No images match the current filters';

  @override
  String get openLink => 'Open';

  @override
  String get favoritePageTitle => 'Favorites';

  @override
  String get noFavoritesTitle => 'No favorites';

  @override
  String get noFavoritesSubtitle =>
      'Long-press on screenshots in the gallery to enter multi-select mode and add favorites';

  @override
  String get noteLabel => 'Note';

  @override
  String get updatedAt => 'Updated ';

  @override
  String get clickToAddNote => 'Click to add note...';

  @override
  String get noteUnchanged => 'Note unchanged';

  @override
  String get noteSaved => 'Note saved';

  @override
  String get favoritesRemoved => 'Removed from favorites';

  @override
  String get operationFailed => 'Operation failed';

  @override
  String get cannotGetAppDir => 'Cannot get app directory';

  @override
  String get nsfwSettingsSectionTitle => 'NSFW Settings';

  @override
  String get blockedDomainListTitle => 'Blocked Domain List';

  @override
  String get addDomainPlaceholder => 'Enter domain or *.example.com';

  @override
  String get addRuleAction => 'Add';

  @override
  String get previewAction => 'Preview';

  @override
  String get removeAction => 'Remove';

  @override
  String get clearAction => 'Clear';

  @override
  String get clearAllRules => 'Clear all rules';

  @override
  String get clearAllRulesConfirmTitle => 'Confirm clearing rules';

  @override
  String get clearAllRulesMessage =>
      'This will remove all blocked domain rules. This action cannot be undone.';

  @override
  String previewAffectsCount(Object count) {
    return 'Will affect $count images';
  }

  @override
  String affectCountLabel(Object count) {
    return 'Affects: $count';
  }

  @override
  String get confirmAddRuleTitle => 'Confirm add rule';

  @override
  String confirmAddRuleMessage(Object rule) {
    return 'Add rule: $rule';
  }

  @override
  String get ruleAddedToast => 'Rule added';

  @override
  String get ruleRemovedToast => 'Rule removed';

  @override
  String get invalidDomainInputError =>
      'Please enter a valid domain (supports *.example.com)';

  @override
  String get manualMarkNsfw => 'Mark as NSFW';

  @override
  String get manualUnmarkNsfw => 'Unmark NSFW';

  @override
  String get manualMarkSuccess => 'Marked as NSFW';

  @override
  String get manualUnmarkSuccess => 'NSFW mark removed';

  @override
  String get manualMarkFailed => 'Operation failed';

  @override
  String get nsfwTagLabel => 'NSFW';

  @override
  String get nsfwBlockedByRulesHint =>
      'Blocked by NSFW rules. Manage in Settings > NSFW domains.';

  @override
  String get providersTitle => 'Providers';

  @override
  String get actionNew => 'New';

  @override
  String get actionAdd => 'Add';

  @override
  String get noProvidersYetHint =>
      'No providers yet. Tap \"New\" to create one.';

  @override
  String confirmDeleteProviderMessage(Object name) {
    return 'Delete provider \"$name\"? This cannot be undone.';
  }

  @override
  String get loadingConversations => 'Loading conversations…';

  @override
  String get noConversations => 'No conversations';

  @override
  String get deleteConversationTitle => 'Delete conversation';

  @override
  String confirmDeleteConversationMessage(Object title) {
    return 'Delete conversation \"$title\"?';
  }

  @override
  String get untitledConversationLabel => 'Untitled conversation';

  @override
  String get searchProviderPlaceholder => 'Search providers';

  @override
  String get searchModelPlaceholder => 'Search models';

  @override
  String providerSelectedToast(Object name) {
    return 'Selected provider: $name';
  }

  @override
  String get pleaseSelectProviderFirst => 'Please select a provider first';

  @override
  String get noModelsForProviderHint =>
      'No models available. Refresh on Providers page or add manually.';

  @override
  String get noModelsDetectedHint =>
      'No models detected. Try Refresh or add manually.';

  @override
  String modelSwitchedToast(Object model) {
    return 'Switched model: $model';
  }

  @override
  String get providerLabel => 'Provider';

  @override
  String sendMessageToModelPlaceholder(Object model) {
    return 'Send a message to $model';
  }

  @override
  String get deepThinkingLabel => 'Deep thinking';

  @override
  String get thinkingInProgress => 'Thinking…';

  @override
  String get requestStoppedInfo => 'Request stopped';

  @override
  String get reasoningLabel => 'Reasoning:';

  @override
  String get answerLabel => 'Answer:';

  @override
  String get aiSelfModeEnabledToast =>
      'Personal assistant: conversations use your data context';

  @override
  String selectModelWithCounts(Object filtered, Object total) {
    return 'Select model ($filtered/$total)';
  }

  @override
  String modelsCountLabel(Object count) {
    return 'Models ($count)';
  }

  @override
  String get manualAddModelLabel => 'Add model manually';

  @override
  String get inputAndAddModelHint => 'Enter and add, e.g. gpt-4o-mini';

  @override
  String get fetchModelsHint =>
      'Click \"Refresh\" to fetch automatically; if it fails, add model names manually.';

  @override
  String get interfaceTypeLabel => 'Interface type';

  @override
  String currentTypeLabel(Object type) {
    return 'Current: $type';
  }

  @override
  String get nameRequiredError => 'Name is required';

  @override
  String get nameAlreadyExistsError => 'Name already exists';

  @override
  String get apiKeyRequiredError => 'API Key is required';

  @override
  String get baseUrlRequiredForAzureError =>
      'Base URL required for Azure OpenAI';

  @override
  String get atLeastOneModelRequiredError => 'At least one model is required';

  @override
  String modelsUpdatedToast(Object count) {
    return 'Models updated ($count)';
  }

  @override
  String get fetchModelsFailedHint =>
      'Fetch models failed. You may add manually.';

  @override
  String get useResponseApiLabel =>
      'Use Response API (only official OpenAI supports; third-party services are not recommended)';

  @override
  String get chatPathOptionalLabel => 'Chat Path (optional)';

  @override
  String get azureApiVersionLabel => 'Azure API Version';

  @override
  String get azureApiVersionHint => 'e.g. 2024-02-15';

  @override
  String get baseUrlHintOpenAI =>
      'e.g. https://api.openai.com (empty for default)';

  @override
  String get baseUrlHintClaude => 'e.g. https://api.anthropic.com';

  @override
  String get baseUrlHintGemini =>
      'e.g. https://generativelanguage.googleapis.com';

  @override
  String baseUrlHintAzure(Object resource) {
    return 'Required, e.g. https://$resource.openai.azure.com';
  }

  @override
  String get baseUrlHintCustom => 'Enter an OpenAI-compatible Base URL';

  @override
  String get createProviderTitle => 'New provider';

  @override
  String get editProviderTitle => 'Edit provider';

  @override
  String get deletedToast => 'Deleted';

  @override
  String get providerNotFound => 'Provider not found';

  @override
  String get conversationsSectionTitle => 'Conversations';

  @override
  String get displaySectionTitle => 'Display';

  @override
  String get streamRenderImagesTitle => 'Render images during streaming';

  @override
  String get streamRenderImagesDesc => 'May affect scrolling';

  @override
  String get themeColorTitle => 'Theme color';

  @override
  String get themeColorDesc => 'Customize the app\'s primary color';

  @override
  String get chooseThemeColorTitle => 'Choose theme color';

  @override
  String get loggingTitle => 'Logging';

  @override
  String get loggingDesc => 'Enable centralized logging (enabled by default)';

  @override
  String get loggingAiTitle => 'AI logs';

  @override
  String get loggingScreenshotTitle => 'Screenshot logs';

  @override
  String get loggingAiDesc => 'Record AI request and response logs';

  @override
  String get loggingScreenshotDesc =>
      'Record screenshot capture and cleanup logs';

  @override
  String get themeModeAuto => 'Auto';

  @override
  String get themeModeLight => 'Light';

  @override
  String get themeModeDark => 'Dark';

  @override
  String get aiEmptySelfTitle => 'Personal assistant ready';

  @override
  String get aiEmptySelfSubtitle =>
      'Ask anything. I will use your data as context.';
}
