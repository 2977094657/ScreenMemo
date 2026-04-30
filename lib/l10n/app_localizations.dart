import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_ko.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('zh'),
    Locale('en'),
    Locale('ja'),
    Locale('ko'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'ScreenMemo'**
  String get appTitle;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @searchPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search screenshots...'**
  String get searchPlaceholder;

  /// No description provided for @homeEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No monitored apps'**
  String get homeEmptyTitle;

  /// No description provided for @homeEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose apps to monitor in Settings'**
  String get homeEmptySubtitle;

  /// No description provided for @navSelectApps.
  ///
  /// In en, this message translates to:
  /// **'Select screenshot apps'**
  String get navSelectApps;

  /// No description provided for @dialogOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get dialogOk;

  /// No description provided for @dialogCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get dialogCancel;

  /// No description provided for @dialogDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get dialogDone;

  /// No description provided for @permissionStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'Permission Status'**
  String get permissionStatusTitle;

  /// No description provided for @permissionMissing.
  ///
  /// In en, this message translates to:
  /// **'Permissions missing'**
  String get permissionMissing;

  /// No description provided for @startScreenshot.
  ///
  /// In en, this message translates to:
  /// **'Start capture'**
  String get startScreenshot;

  /// No description provided for @stopScreenshot.
  ///
  /// In en, this message translates to:
  /// **'Stop capture'**
  String get stopScreenshot;

  /// No description provided for @screenshotEnabledToast.
  ///
  /// In en, this message translates to:
  /// **'Capture enabled'**
  String get screenshotEnabledToast;

  /// No description provided for @screenshotDisabledToast.
  ///
  /// In en, this message translates to:
  /// **'Capture disabled'**
  String get screenshotDisabledToast;

  /// No description provided for @intervalSettingTitle.
  ///
  /// In en, this message translates to:
  /// **'Set capture interval'**
  String get intervalSettingTitle;

  /// No description provided for @intervalLabel.
  ///
  /// In en, this message translates to:
  /// **'Interval (seconds)'**
  String get intervalLabel;

  /// No description provided for @intervalHint.
  ///
  /// In en, this message translates to:
  /// **'Enter an integer between 5-60'**
  String get intervalHint;

  /// Prompt after saving capture interval in seconds
  ///
  /// In en, this message translates to:
  /// **'Capture interval set to {seconds}s'**
  String intervalSavedToast(Object seconds);

  /// No description provided for @languageSettingTitle.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageSettingTitle;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get languageSystem;

  /// No description provided for @languageChinese.
  ///
  /// In en, this message translates to:
  /// **'Chinese (Simplified)'**
  String get languageChinese;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageJapanese.
  ///
  /// In en, this message translates to:
  /// **'Japanese'**
  String get languageJapanese;

  /// No description provided for @languageKorean.
  ///
  /// In en, this message translates to:
  /// **'Korean'**
  String get languageKorean;

  /// Toast after changing language
  ///
  /// In en, this message translates to:
  /// **'Switched to {name}'**
  String languageChangedToast(Object name);

  /// No description provided for @nsfwWarningTitle.
  ///
  /// In en, this message translates to:
  /// **'Content Warning: Adult Content'**
  String get nsfwWarningTitle;

  /// No description provided for @nsfwWarningSubtitle.
  ///
  /// In en, this message translates to:
  /// **'This content has been marked as adult content'**
  String get nsfwWarningSubtitle;

  /// No description provided for @show.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get show;

  /// No description provided for @appSearchPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search apps...'**
  String get appSearchPlaceholder;

  /// Number of selected apps
  ///
  /// In en, this message translates to:
  /// **'Selected {count}'**
  String selectedCount(Object count);

  /// No description provided for @refreshAppsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Refresh apps'**
  String get refreshAppsTooltip;

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get selectAll;

  /// No description provided for @clearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get clearAll;

  /// No description provided for @noAppsFound.
  ///
  /// In en, this message translates to:
  /// **'No apps found'**
  String get noAppsFound;

  /// No description provided for @noAppsMatched.
  ///
  /// In en, this message translates to:
  /// **'No matching apps'**
  String get noAppsMatched;

  /// No description provided for @pinduoduoWarningTitle.
  ///
  /// In en, this message translates to:
  /// **'Risk Reminder'**
  String get pinduoduoWarningTitle;

  /// No description provided for @pinduoduoWarningMessage.
  ///
  /// In en, this message translates to:
  /// **'Taking screenshots in Pinduoduo may lead to order cancellations. We do not recommend enabling monitoring.'**
  String get pinduoduoWarningMessage;

  /// No description provided for @pinduoduoWarningCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get pinduoduoWarningCancel;

  /// No description provided for @pinduoduoWarningKeep.
  ///
  /// In en, this message translates to:
  /// **'Keep Anyway'**
  String get pinduoduoWarningKeep;

  /// No description provided for @stepProgress.
  ///
  /// In en, this message translates to:
  /// **'Step {current} / {total}'**
  String stepProgress(Object current, Object total);

  /// No description provided for @onboardingWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to ScreenMemo'**
  String get onboardingWelcomeTitle;

  /// No description provided for @onboardingWelcomeDesc.
  ///
  /// In en, this message translates to:
  /// **'An intelligent memo and information management tool to help you capture, organize, and review important information efficiently.'**
  String get onboardingWelcomeDesc;

  /// No description provided for @onboardingKeyFeaturesTitle.
  ///
  /// In en, this message translates to:
  /// **'Key features'**
  String get onboardingKeyFeaturesTitle;

  /// No description provided for @featureSmartNotes.
  ///
  /// In en, this message translates to:
  /// **'Smart information capture'**
  String get featureSmartNotes;

  /// No description provided for @featureQuickSearch.
  ///
  /// In en, this message translates to:
  /// **'Fast content search'**
  String get featureQuickSearch;

  /// No description provided for @featureLocalStorage.
  ///
  /// In en, this message translates to:
  /// **'Local data storage'**
  String get featureLocalStorage;

  /// No description provided for @featureUsageAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Usage analytics'**
  String get featureUsageAnalytics;

  /// No description provided for @onboardingPermissionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Grant required permissions'**
  String get onboardingPermissionsTitle;

  /// No description provided for @refreshPermissionStatus.
  ///
  /// In en, this message translates to:
  /// **'Refresh permission status'**
  String get refreshPermissionStatus;

  /// No description provided for @onboardingPermissionsDesc.
  ///
  /// In en, this message translates to:
  /// **'To provide the full experience, please grant the following permissions:'**
  String get onboardingPermissionsDesc;

  /// No description provided for @storagePermissionTitle.
  ///
  /// In en, this message translates to:
  /// **'Storage permission'**
  String get storagePermissionTitle;

  /// No description provided for @storagePermissionDesc.
  ///
  /// In en, this message translates to:
  /// **'Save screenshot files to device storage'**
  String get storagePermissionDesc;

  /// No description provided for @notificationPermissionTitle.
  ///
  /// In en, this message translates to:
  /// **'Notification permission'**
  String get notificationPermissionTitle;

  /// No description provided for @notificationPermissionDesc.
  ///
  /// In en, this message translates to:
  /// **'Show service status notifications'**
  String get notificationPermissionDesc;

  /// No description provided for @accessibilityPermissionTitle.
  ///
  /// In en, this message translates to:
  /// **'Accessibility service'**
  String get accessibilityPermissionTitle;

  /// No description provided for @accessibilityPermissionDesc.
  ///
  /// In en, this message translates to:
  /// **'Monitor app switching and take screenshots'**
  String get accessibilityPermissionDesc;

  /// No description provided for @usageStatsPermissionTitle.
  ///
  /// In en, this message translates to:
  /// **'Usage stats permission'**
  String get usageStatsPermissionTitle;

  /// No description provided for @usageStatsPermissionDesc.
  ///
  /// In en, this message translates to:
  /// **'Ensure accurate foreground app detection'**
  String get usageStatsPermissionDesc;

  /// No description provided for @batteryOptimizationTitle.
  ///
  /// In en, this message translates to:
  /// **'Battery optimization whitelist'**
  String get batteryOptimizationTitle;

  /// No description provided for @batteryOptimizationDesc.
  ///
  /// In en, this message translates to:
  /// **'Keep screenshot service running stably'**
  String get batteryOptimizationDesc;

  /// No description provided for @pleaseCompleteInSystemSettings.
  ///
  /// In en, this message translates to:
  /// **'Please complete authorization in system settings, then return to the app'**
  String get pleaseCompleteInSystemSettings;

  /// No description provided for @autostartPermissionTitle.
  ///
  /// In en, this message translates to:
  /// **'Auto-start permission'**
  String get autostartPermissionTitle;

  /// No description provided for @autostartPermissionDesc.
  ///
  /// In en, this message translates to:
  /// **'Allow app to restart in background'**
  String get autostartPermissionDesc;

  /// No description provided for @permissionsFooterNote.
  ///
  /// In en, this message translates to:
  /// **'Permissions persist after granting and can be changed anytime in system settings'**
  String get permissionsFooterNote;

  /// No description provided for @grantedLabel.
  ///
  /// In en, this message translates to:
  /// **'Granted'**
  String get grantedLabel;

  /// No description provided for @authorizeAction.
  ///
  /// In en, this message translates to:
  /// **'Authorize'**
  String get authorizeAction;

  /// No description provided for @onboardingSelectAppsTitle.
  ///
  /// In en, this message translates to:
  /// **'Select apps to monitor'**
  String get onboardingSelectAppsTitle;

  /// No description provided for @onboardingSelectAppsDesc.
  ///
  /// In en, this message translates to:
  /// **'Please choose apps to monitor for screenshots. Select at least one to continue.'**
  String get onboardingSelectAppsDesc;

  /// No description provided for @onboardingDoneTitle.
  ///
  /// In en, this message translates to:
  /// **'All set!'**
  String get onboardingDoneTitle;

  /// No description provided for @onboardingDoneDesc.
  ///
  /// In en, this message translates to:
  /// **'All permissions have been granted. You can now start using ScreenMemo.'**
  String get onboardingDoneDesc;

  /// No description provided for @nextStepTitle.
  ///
  /// In en, this message translates to:
  /// **'Next step'**
  String get nextStepTitle;

  /// No description provided for @onboardingNextStepDesc.
  ///
  /// In en, this message translates to:
  /// **'Tap \"Start Using\" to enter the main screen and experience powerful screenshot features.'**
  String get onboardingNextStepDesc;

  /// No description provided for @prevStep.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get prevStep;

  /// No description provided for @startUsing.
  ///
  /// In en, this message translates to:
  /// **'Start Using'**
  String get startUsing;

  /// No description provided for @finishSelection.
  ///
  /// In en, this message translates to:
  /// **'Finish selection'**
  String get finishSelection;

  /// No description provided for @nextStep.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get nextStep;

  /// No description provided for @confirmPermissionSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm permission settings'**
  String get confirmPermissionSettingsTitle;

  /// No description provided for @confirmAutostartQuestion.
  ///
  /// In en, this message translates to:
  /// **'Have you completed the \"Auto-start permission\" configuration in system settings?'**
  String get confirmAutostartQuestion;

  /// No description provided for @notYet.
  ///
  /// In en, this message translates to:
  /// **'Not yet'**
  String get notYet;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @startingScreenshotServiceInfo.
  ///
  /// In en, this message translates to:
  /// **'Starting capture service...'**
  String get startingScreenshotServiceInfo;

  /// No description provided for @startServiceFailedCheckPermissions.
  ///
  /// In en, this message translates to:
  /// **'Failed to start capture service. Please check permission settings'**
  String get startServiceFailedCheckPermissions;

  /// No description provided for @startFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Start failed'**
  String get startFailedTitle;

  /// No description provided for @startFailedUnknown.
  ///
  /// In en, this message translates to:
  /// **'Start failed: Unknown error'**
  String get startFailedUnknown;

  /// No description provided for @tipIfProblemPersists.
  ///
  /// In en, this message translates to:
  /// **'Tip: If the issue persists, try restarting the app or reconfiguring permissions'**
  String get tipIfProblemPersists;

  /// No description provided for @autoDisabledDueToPermissions.
  ///
  /// In en, this message translates to:
  /// **'Capture has been disabled due to insufficient permissions'**
  String get autoDisabledDueToPermissions;

  /// No description provided for @refreshingPermissionsInfo.
  ///
  /// In en, this message translates to:
  /// **'Refreshing permission status...'**
  String get refreshingPermissionsInfo;

  /// No description provided for @permissionsRefreshed.
  ///
  /// In en, this message translates to:
  /// **'Permission status refreshed'**
  String get permissionsRefreshed;

  /// No description provided for @refreshPermissionsFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to refresh permission status: {error}'**
  String refreshPermissionsFailed(Object error);

  /// No description provided for @screenRecordingPermissionTitle.
  ///
  /// In en, this message translates to:
  /// **'Screen recording permission'**
  String get screenRecordingPermissionTitle;

  /// No description provided for @goToSettings.
  ///
  /// In en, this message translates to:
  /// **'Go to Settings'**
  String get goToSettings;

  /// No description provided for @notGrantedLabel.
  ///
  /// In en, this message translates to:
  /// **'Not granted'**
  String get notGrantedLabel;

  /// No description provided for @removeMonitoring.
  ///
  /// In en, this message translates to:
  /// **'Remove monitoring'**
  String get removeMonitoring;

  /// No description provided for @selectedItemsCount.
  ///
  /// In en, this message translates to:
  /// **'Selected {count}'**
  String selectedItemsCount(Object count);

  /// No description provided for @whySomeAppsHidden.
  ///
  /// In en, this message translates to:
  /// **'Why are some apps missing?'**
  String get whySomeAppsHidden;

  /// No description provided for @excludedAppsTitle.
  ///
  /// In en, this message translates to:
  /// **'Excluded apps'**
  String get excludedAppsTitle;

  /// No description provided for @excludedAppsIntro.
  ///
  /// In en, this message translates to:
  /// **'The following apps are excluded and cannot be selected:'**
  String get excludedAppsIntro;

  /// No description provided for @excludedThisApp.
  ///
  /// In en, this message translates to:
  /// **'· This app (to avoid self interference)'**
  String get excludedThisApp;

  /// No description provided for @excludedAutomationApps.
  ///
  /// In en, this message translates to:
  /// **'· Automation skipping apps (e.g., GKD auto tapper, to avoid misattribution)'**
  String get excludedAutomationApps;

  /// No description provided for @excludedImeApps.
  ///
  /// In en, this message translates to:
  /// **'· Input method (keyboard) apps:'**
  String get excludedImeApps;

  /// No description provided for @excludedImeAppsFiltered.
  ///
  /// In en, this message translates to:
  /// **'· Input method (keyboard) apps (auto filtered)'**
  String get excludedImeAppsFiltered;

  /// No description provided for @currentDefaultIme.
  ///
  /// In en, this message translates to:
  /// **'Current default IME: {name} ({package})'**
  String currentDefaultIme(Object name, Object package);

  /// No description provided for @imeExplainText.
  ///
  /// In en, this message translates to:
  /// **'When the keyboard pops up in another app, the system switches to the IME window. If not excluded, it may be mistaken as using the IME, causing the floating window detection to be wrong. We automatically exclude IME apps and will still move the floating window to the app before the IME pops up when an IME is detected.'**
  String get imeExplainText;

  /// No description provided for @gotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get gotIt;

  /// No description provided for @unknownIme.
  ///
  /// In en, this message translates to:
  /// **'Unknown IME'**
  String get unknownIme;

  /// No description provided for @intervalRangeNote.
  ///
  /// In en, this message translates to:
  /// **'Range: 5–60 seconds, default: 5 seconds.'**
  String get intervalRangeNote;

  /// No description provided for @intervalInvalidInput.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid integer between 5–60'**
  String get intervalInvalidInput;

  /// No description provided for @removeMonitoringMessage.
  ///
  /// In en, this message translates to:
  /// **'Only remove monitoring and do not delete images. Continue?'**
  String get removeMonitoringMessage;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @removedMonitoringToast.
  ///
  /// In en, this message translates to:
  /// **'Removed monitoring for {count} apps (images are not deleted)'**
  String removedMonitoringToast(Object count);

  /// No description provided for @checkPermissionStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to check permission status: {error}'**
  String checkPermissionStatusFailed(Object error);

  /// No description provided for @accessibilityNotEnabledDetail.
  ///
  /// In en, this message translates to:
  /// **'Accessibility service not enabled\\nPlease enable accessibility in Settings'**
  String get accessibilityNotEnabledDetail;

  /// No description provided for @storagePermissionNotGrantedDetail.
  ///
  /// In en, this message translates to:
  /// **'Storage permission not granted\\nPlease grant storage permission in Settings'**
  String get storagePermissionNotGrantedDetail;

  /// No description provided for @serviceNotRunningDetail.
  ///
  /// In en, this message translates to:
  /// **'Service not running properly\\nPlease try restarting the app'**
  String get serviceNotRunningDetail;

  /// No description provided for @androidVersionNotSupportedDetail.
  ///
  /// In en, this message translates to:
  /// **'Android version not supported\\nRequires Android 11.0 or higher'**
  String get androidVersionNotSupportedDetail;

  /// No description provided for @permissionsSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Permissions'**
  String get permissionsSectionTitle;

  /// No description provided for @permissionsSectionDesc.
  ///
  /// In en, this message translates to:
  /// **'Storage, notifications, accessibility, keep-alive'**
  String get permissionsSectionDesc;

  /// No description provided for @displayAndSortSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Display & Sorting'**
  String get displayAndSortSectionTitle;

  /// No description provided for @screenshotSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Capture settings'**
  String get screenshotSectionTitle;

  /// No description provided for @screenshotSectionDesc.
  ///
  /// In en, this message translates to:
  /// **'Interval, quality, expiration'**
  String get screenshotSectionDesc;

  /// No description provided for @segmentSummarySectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Dynamic settings'**
  String get segmentSummarySectionTitle;

  /// No description provided for @segmentSummarySectionDesc.
  ///
  /// In en, this message translates to:
  /// **'Sampling / duration / merging / AI request interval'**
  String get segmentSummarySectionDesc;

  /// No description provided for @dailyReminderSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Daily summary reminder'**
  String get dailyReminderSectionTitle;

  /// No description provided for @dailyReminderSectionDesc.
  ///
  /// In en, this message translates to:
  /// **'Time, banner permission, test'**
  String get dailyReminderSectionDesc;

  /// No description provided for @aiAssistantSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Assistant'**
  String get aiAssistantSectionTitle;

  /// No description provided for @dataBackupSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Data & backup'**
  String get dataBackupSectionTitle;

  /// No description provided for @dataBackupSectionDesc.
  ///
  /// In en, this message translates to:
  /// **'Storage, import/export, recalc stats'**
  String get dataBackupSectionDesc;

  /// No description provided for @advancedSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get advancedSectionTitle;

  /// No description provided for @advancedSectionDesc.
  ///
  /// In en, this message translates to:
  /// **'Logs and performance options'**
  String get advancedSectionDesc;

  /// No description provided for @storageAnalysisEntryTitle.
  ///
  /// In en, this message translates to:
  /// **'Storage analysis'**
  String get storageAnalysisEntryTitle;

  /// No description provided for @storageAnalysisEntryDesc.
  ///
  /// In en, this message translates to:
  /// **'Inspect detailed storage usage for this app'**
  String get storageAnalysisEntryDesc;

  /// No description provided for @actionSet.
  ///
  /// In en, this message translates to:
  /// **'Set'**
  String get actionSet;

  /// No description provided for @actionEnter.
  ///
  /// In en, this message translates to:
  /// **'Enter'**
  String get actionEnter;

  /// No description provided for @actionExport.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get actionExport;

  /// No description provided for @actionImport.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get actionImport;

  /// No description provided for @actionCopyPath.
  ///
  /// In en, this message translates to:
  /// **'Copy path'**
  String get actionCopyPath;

  /// No description provided for @actionOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get actionOpen;

  /// No description provided for @actionTrigger.
  ///
  /// In en, this message translates to:
  /// **'Trigger'**
  String get actionTrigger;

  /// No description provided for @allPermissionsGranted.
  ///
  /// In en, this message translates to:
  /// **'All granted'**
  String get allPermissionsGranted;

  /// No description provided for @permissionsMissingCount.
  ///
  /// In en, this message translates to:
  /// **'{count} permissions not granted'**
  String permissionsMissingCount(Object count);

  /// No description provided for @exportSuccessTitle.
  ///
  /// In en, this message translates to:
  /// **'Export complete'**
  String get exportSuccessTitle;

  /// No description provided for @exportFileExportedTo.
  ///
  /// In en, this message translates to:
  /// **'File exported to:'**
  String get exportFileExportedTo;

  /// No description provided for @pathCopiedToast.
  ///
  /// In en, this message translates to:
  /// **'Path copied'**
  String get pathCopiedToast;

  /// No description provided for @exportFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Export failed'**
  String get exportFailedTitle;

  /// No description provided for @pleaseTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Please try again later'**
  String get pleaseTryAgain;

  /// No description provided for @importCompleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Import complete'**
  String get importCompleteTitle;

  /// No description provided for @dataExtractedTo.
  ///
  /// In en, this message translates to:
  /// **'Data extracted to:'**
  String get dataExtractedTo;

  /// No description provided for @importFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Import failed'**
  String get importFailedTitle;

  /// No description provided for @importFailedCheckZip.
  ///
  /// In en, this message translates to:
  /// **'Please check the ZIP file and try again.'**
  String get importFailedCheckZip;

  /// No description provided for @storageAnalysisPageTitle.
  ///
  /// In en, this message translates to:
  /// **'Storage Analysis'**
  String get storageAnalysisPageTitle;

  /// No description provided for @storageAnalysisLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load storage data'**
  String get storageAnalysisLoadFailed;

  /// No description provided for @storageAnalysisEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'No storage data available'**
  String get storageAnalysisEmptyMessage;

  /// No description provided for @storageAnalysisSummaryTitle.
  ///
  /// In en, this message translates to:
  /// **'Storage Overview'**
  String get storageAnalysisSummaryTitle;

  /// No description provided for @storageAnalysisTotalLabel.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get storageAnalysisTotalLabel;

  /// No description provided for @storageAnalysisAppLabel.
  ///
  /// In en, this message translates to:
  /// **'App'**
  String get storageAnalysisAppLabel;

  /// No description provided for @storageAnalysisDataLabel.
  ///
  /// In en, this message translates to:
  /// **'App data'**
  String get storageAnalysisDataLabel;

  /// No description provided for @storageAnalysisCacheLabel.
  ///
  /// In en, this message translates to:
  /// **'Cache'**
  String get storageAnalysisCacheLabel;

  /// No description provided for @storageAnalysisExternalLabel.
  ///
  /// In en, this message translates to:
  /// **'External logs'**
  String get storageAnalysisExternalLabel;

  /// No description provided for @storageAnalysisScanTimestamp.
  ///
  /// In en, this message translates to:
  /// **'Scanned at: {timestamp}'**
  String storageAnalysisScanTimestamp(Object timestamp);

  /// No description provided for @storageAnalysisScanDurationSeconds.
  ///
  /// In en, this message translates to:
  /// **'Scan duration: {seconds}s'**
  String storageAnalysisScanDurationSeconds(Object seconds);

  /// No description provided for @storageAnalysisScanDurationMilliseconds.
  ///
  /// In en, this message translates to:
  /// **'Scan duration: {milliseconds} ms'**
  String storageAnalysisScanDurationMilliseconds(Object milliseconds);

  /// No description provided for @storageAnalysisManualNote.
  ///
  /// In en, this message translates to:
  /// **'Usage Access is not granted. The data shown here is calculated locally and may differ from system settings.'**
  String get storageAnalysisManualNote;

  /// No description provided for @storageAnalysisUsagePermissionMissingTitle.
  ///
  /// In en, this message translates to:
  /// **'Usage access required'**
  String get storageAnalysisUsagePermissionMissingTitle;

  /// No description provided for @storageAnalysisUsagePermissionMissingDesc.
  ///
  /// In en, this message translates to:
  /// **'Grant Usage Access in system settings to retrieve the same storage stats shown in Android settings.'**
  String get storageAnalysisUsagePermissionMissingDesc;

  /// No description provided for @storageAnalysisUsagePermissionButton.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get storageAnalysisUsagePermissionButton;

  /// No description provided for @storageAnalysisPartialErrors.
  ///
  /// In en, this message translates to:
  /// **'Some metrics failed to load'**
  String get storageAnalysisPartialErrors;

  /// No description provided for @storageAnalysisBreakdownTitle.
  ///
  /// In en, this message translates to:
  /// **'Detailed breakdown'**
  String get storageAnalysisBreakdownTitle;

  /// No description provided for @storageAnalysisFileCount.
  ///
  /// In en, this message translates to:
  /// **'{count} files'**
  String storageAnalysisFileCount(Object count);

  /// No description provided for @storageAnalysisPathCopied.
  ///
  /// In en, this message translates to:
  /// **'Path copied'**
  String get storageAnalysisPathCopied;

  /// No description provided for @storageAnalysisLabelFiles.
  ///
  /// In en, this message translates to:
  /// **'files directory'**
  String get storageAnalysisLabelFiles;

  /// No description provided for @storageAnalysisLabelOutput.
  ///
  /// In en, this message translates to:
  /// **'output directory'**
  String get storageAnalysisLabelOutput;

  /// No description provided for @storageAnalysisLabelScreenshots.
  ///
  /// In en, this message translates to:
  /// **'Screenshot library'**
  String get storageAnalysisLabelScreenshots;

  /// No description provided for @storageAnalysisLabelOutputDatabases.
  ///
  /// In en, this message translates to:
  /// **'output/databases'**
  String get storageAnalysisLabelOutputDatabases;

  /// No description provided for @storageAnalysisLabelSharedPrefs.
  ///
  /// In en, this message translates to:
  /// **'shared_prefs'**
  String get storageAnalysisLabelSharedPrefs;

  /// No description provided for @storageAnalysisLabelNoBackup.
  ///
  /// In en, this message translates to:
  /// **'no_backup'**
  String get storageAnalysisLabelNoBackup;

  /// No description provided for @storageAnalysisLabelAppFlutter.
  ///
  /// In en, this message translates to:
  /// **'app_flutter'**
  String get storageAnalysisLabelAppFlutter;

  /// No description provided for @storageAnalysisLabelDatabases.
  ///
  /// In en, this message translates to:
  /// **'databases directory'**
  String get storageAnalysisLabelDatabases;

  /// No description provided for @storageAnalysisLabelCacheDir.
  ///
  /// In en, this message translates to:
  /// **'cache directory'**
  String get storageAnalysisLabelCacheDir;

  /// No description provided for @storageAnalysisLabelCodeCache.
  ///
  /// In en, this message translates to:
  /// **'code_cache'**
  String get storageAnalysisLabelCodeCache;

  /// No description provided for @storageAnalysisLabelExternalLogs.
  ///
  /// In en, this message translates to:
  /// **'External logs'**
  String get storageAnalysisLabelExternalLogs;

  /// No description provided for @storageAnalysisOthersLabel.
  ///
  /// In en, this message translates to:
  /// **'Others ({count})'**
  String storageAnalysisOthersLabel(Object count);

  /// No description provided for @storageAnalysisOthersFallback.
  ///
  /// In en, this message translates to:
  /// **'Others'**
  String get storageAnalysisOthersFallback;

  /// No description provided for @noMediaProjectionNeeded.
  ///
  /// In en, this message translates to:
  /// **'Using Accessibility screenshots, no screen recording permission needed'**
  String get noMediaProjectionNeeded;

  /// No description provided for @autostartPermissionMarked.
  ///
  /// In en, this message translates to:
  /// **'Auto-start permission marked as granted'**
  String get autostartPermissionMarked;

  /// No description provided for @requestPermissionFailed.
  ///
  /// In en, this message translates to:
  /// **'Request permission failed: {error}'**
  String requestPermissionFailed(Object error);

  /// No description provided for @expireCleanupSaved.
  ///
  /// In en, this message translates to:
  /// **'Expire cleanup settings saved'**
  String get expireCleanupSaved;

  /// No description provided for @dailyNotifyTriggered.
  ///
  /// In en, this message translates to:
  /// **'Notification triggered'**
  String get dailyNotifyTriggered;

  /// No description provided for @dailyNotifyTriggerFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to trigger notification or content empty'**
  String get dailyNotifyTriggerFailed;

  /// No description provided for @refreshPermissionStatusTooltip.
  ///
  /// In en, this message translates to:
  /// **'Refresh permission status'**
  String get refreshPermissionStatusTooltip;

  /// No description provided for @grantedStatus.
  ///
  /// In en, this message translates to:
  /// **'Granted'**
  String get grantedStatus;

  /// No description provided for @notGrantedStatus.
  ///
  /// In en, this message translates to:
  /// **'Grant'**
  String get notGrantedStatus;

  /// No description provided for @privacyModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy mode'**
  String get privacyModeTitle;

  /// No description provided for @privacyModeDesc.
  ///
  /// In en, this message translates to:
  /// **'Automatically blur sensitive content'**
  String get privacyModeDesc;

  /// No description provided for @homeSortingTitle.
  ///
  /// In en, this message translates to:
  /// **'Home sorting'**
  String get homeSortingTitle;

  /// No description provided for @screenshotIntervalTitle.
  ///
  /// In en, this message translates to:
  /// **'Screenshot interval'**
  String get screenshotIntervalTitle;

  /// No description provided for @screenshotIntervalDesc.
  ///
  /// In en, this message translates to:
  /// **'Current interval: {seconds}s'**
  String screenshotIntervalDesc(Object seconds);

  /// No description provided for @screenshotQualityTitle.
  ///
  /// In en, this message translates to:
  /// **'Screenshot quality'**
  String get screenshotQualityTitle;

  /// No description provided for @currentSizeLabel.
  ///
  /// In en, this message translates to:
  /// **'Current size: '**
  String get currentSizeLabel;

  /// No description provided for @clickToModifyHint.
  ///
  /// In en, this message translates to:
  /// **'(Click number to modify)'**
  String get clickToModifyHint;

  /// No description provided for @screenshotExpireTitle.
  ///
  /// In en, this message translates to:
  /// **'Screenshot expiration cleanup'**
  String get screenshotExpireTitle;

  /// No description provided for @currentExpireDaysLabel.
  ///
  /// In en, this message translates to:
  /// **'Current expiration days: '**
  String get currentExpireDaysLabel;

  /// No description provided for @expireDaysUnit.
  ///
  /// In en, this message translates to:
  /// **'{days} days'**
  String expireDaysUnit(Object days);

  /// No description provided for @setCompressDaysDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Set days'**
  String get setCompressDaysDialogTitle;

  /// No description provided for @compressDaysLabel.
  ///
  /// In en, this message translates to:
  /// **'Days'**
  String get compressDaysLabel;

  /// No description provided for @compressDaysInputHint.
  ///
  /// In en, this message translates to:
  /// **'Enter number of days'**
  String get compressDaysInputHint;

  /// No description provided for @compressDaysInvalidError.
  ///
  /// In en, this message translates to:
  /// **'Please enter a positive number of days.'**
  String get compressDaysInvalidError;

  /// No description provided for @compressHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Compress history'**
  String get compressHistoryTitle;

  /// No description provided for @compressHistoryDescription.
  ///
  /// In en, this message translates to:
  /// **'Compress screenshots from the last {days} days to {size} KB if they exceed the target.'**
  String compressHistoryDescription(Object days, Object size);

  /// No description provided for @compressHistorySetDays.
  ///
  /// In en, this message translates to:
  /// **'Days: {days}'**
  String compressHistorySetDays(Object days);

  /// No description provided for @compressHistorySetTarget.
  ///
  /// In en, this message translates to:
  /// **'Target size: {size} KB'**
  String compressHistorySetTarget(Object size);

  /// No description provided for @compressHistoryProgress.
  ///
  /// In en, this message translates to:
  /// **'{handled}/{total} processed • Saved {saved}'**
  String compressHistoryProgress(Object handled, Object total, Object saved);

  /// No description provided for @compressHistoryAction.
  ///
  /// In en, this message translates to:
  /// **'Compress now'**
  String get compressHistoryAction;

  /// No description provided for @compressHistoryRequireTarget.
  ///
  /// In en, this message translates to:
  /// **'Enable target size before compressing.'**
  String get compressHistoryRequireTarget;

  /// No description provided for @compressHistorySuccess.
  ///
  /// In en, this message translates to:
  /// **'Compressed {count} screenshots, saved {size}.'**
  String compressHistorySuccess(int count, Object size);

  /// No description provided for @compressHistoryNothing.
  ///
  /// In en, this message translates to:
  /// **'All screenshots already meet the target size.'**
  String get compressHistoryNothing;

  /// No description provided for @compressHistoryFailure.
  ///
  /// In en, this message translates to:
  /// **'Failed to compress screenshots. Please try again.'**
  String get compressHistoryFailure;

  /// No description provided for @exportDataTitle.
  ///
  /// In en, this message translates to:
  /// **'Export data'**
  String get exportDataTitle;

  /// No description provided for @exportDataDesc.
  ///
  /// In en, this message translates to:
  /// **'Export ZIP to Download/ScreenMemory'**
  String get exportDataDesc;

  /// No description provided for @importDataTitle.
  ///
  /// In en, this message translates to:
  /// **'Import data'**
  String get importDataTitle;

  /// No description provided for @importDataDesc.
  ///
  /// In en, this message translates to:
  /// **'Import ZIP file to app storage'**
  String get importDataDesc;

  /// No description provided for @importModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Select import strategy'**
  String get importModeTitle;

  /// No description provided for @importModeOverwriteTitle.
  ///
  /// In en, this message translates to:
  /// **'Overwrite import'**
  String get importModeOverwriteTitle;

  /// No description provided for @importModeOverwriteDesc.
  ///
  /// In en, this message translates to:
  /// **'Replace the current data directory. Use when fully restoring from backups.'**
  String get importModeOverwriteDesc;

  /// No description provided for @importModeMergeTitle.
  ///
  /// In en, this message translates to:
  /// **'Merge import'**
  String get importModeMergeTitle;

  /// No description provided for @importModeMergeDesc.
  ///
  /// In en, this message translates to:
  /// **'Keep current data and merge archive contents with deduplication.'**
  String get importModeMergeDesc;

  /// No description provided for @mergeProgressCopying.
  ///
  /// In en, this message translates to:
  /// **'Copying screenshot files...'**
  String get mergeProgressCopying;

  /// No description provided for @mergeProgressCopyingGeneric.
  ///
  /// In en, this message translates to:
  /// **'Copying additional assets...'**
  String get mergeProgressCopyingGeneric;

  /// No description provided for @mergeProgressMergingDb.
  ///
  /// In en, this message translates to:
  /// **'Merging database shards...'**
  String get mergeProgressMergingDb;

  /// No description provided for @mergeProgressFinalizing.
  ///
  /// In en, this message translates to:
  /// **'Finalizing merge...'**
  String get mergeProgressFinalizing;

  /// No description provided for @mergeCompleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Merge complete'**
  String get mergeCompleteTitle;

  /// No description provided for @mergeReportInserted.
  ///
  /// In en, this message translates to:
  /// **'New screenshots: {count}'**
  String mergeReportInserted(int count);

  /// No description provided for @mergeReportSkipped.
  ///
  /// In en, this message translates to:
  /// **'Skipped duplicates: {count}'**
  String mergeReportSkipped(int count);

  /// No description provided for @mergeReportCopied.
  ///
  /// In en, this message translates to:
  /// **'Files copied: {count}'**
  String mergeReportCopied(int count);

  /// No description provided for @mergeReportMemoryEvidence.
  ///
  /// In en, this message translates to:
  /// **'New tag evidence: {count}'**
  String mergeReportMemoryEvidence(int count);

  /// No description provided for @mergeReportAffectedPackages.
  ///
  /// In en, this message translates to:
  /// **'Affected app packages: {packages}'**
  String mergeReportAffectedPackages(String packages);

  /// No description provided for @mergeReportWarnings.
  ///
  /// In en, this message translates to:
  /// **'Warnings to review:'**
  String get mergeReportWarnings;

  /// No description provided for @mergeReportNoWarnings.
  ///
  /// In en, this message translates to:
  /// **'No warnings detected.'**
  String get mergeReportNoWarnings;

  /// No description provided for @recalculateAllTitle.
  ///
  /// In en, this message translates to:
  /// **'Recalculate all data'**
  String get recalculateAllTitle;

  /// No description provided for @recalculateAllDesc.
  ///
  /// In en, this message translates to:
  /// **'Rescan every app to refresh navigation totals for days, apps, screenshots, and size.'**
  String get recalculateAllDesc;

  /// No description provided for @recalculateAllAction.
  ///
  /// In en, this message translates to:
  /// **'Recalculate'**
  String get recalculateAllAction;

  /// No description provided for @recalculateAllProgress.
  ///
  /// In en, this message translates to:
  /// **'Recomputing statistics for all apps...'**
  String get recalculateAllProgress;

  /// No description provided for @recalculateAllSuccess.
  ///
  /// In en, this message translates to:
  /// **'All statistics have been refreshed.'**
  String get recalculateAllSuccess;

  /// No description provided for @recalculateAllFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Recalculation failed'**
  String get recalculateAllFailedTitle;

  /// No description provided for @aiAssistantTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Assistant'**
  String get aiAssistantTitle;

  /// No description provided for @aiAssistantDesc.
  ///
  /// In en, this message translates to:
  /// **'Configure AI interface and models, test multi-turn conversations'**
  String get aiAssistantDesc;

  /// No description provided for @segmentSampleIntervalTitle.
  ///
  /// In en, this message translates to:
  /// **'Sample interval (seconds)'**
  String get segmentSampleIntervalTitle;

  /// No description provided for @segmentSampleIntervalDesc.
  ///
  /// In en, this message translates to:
  /// **'Current: {seconds}s'**
  String segmentSampleIntervalDesc(Object seconds);

  /// No description provided for @segmentDurationTitle.
  ///
  /// In en, this message translates to:
  /// **'Segment duration (minutes)'**
  String get segmentDurationTitle;

  /// No description provided for @segmentDurationDesc.
  ///
  /// In en, this message translates to:
  /// **'Current: {minutes} minutes'**
  String segmentDurationDesc(Object minutes);

  /// No description provided for @aiRequestIntervalTitle.
  ///
  /// In en, this message translates to:
  /// **'AI request minimum interval (seconds)'**
  String get aiRequestIntervalTitle;

  /// No description provided for @aiRequestIntervalDesc.
  ///
  /// In en, this message translates to:
  /// **'Current: {seconds}s (minimum 1s)'**
  String aiRequestIntervalDesc(Object seconds);

  /// No description provided for @dynamicMergeMaxSpanTitle.
  ///
  /// In en, this message translates to:
  /// **'Dynamic merge: max span (minutes)'**
  String get dynamicMergeMaxSpanTitle;

  /// No description provided for @dynamicMergeMaxSpanDesc.
  ///
  /// In en, this message translates to:
  /// **'Current: {minutes} minutes (0 = unlimited)'**
  String dynamicMergeMaxSpanDesc(Object minutes);

  /// No description provided for @dynamicMergeMaxGapTitle.
  ///
  /// In en, this message translates to:
  /// **'Dynamic merge: max gap (minutes)'**
  String get dynamicMergeMaxGapTitle;

  /// No description provided for @dynamicMergeMaxGapDesc.
  ///
  /// In en, this message translates to:
  /// **'Current: {minutes} minutes (0 = unlimited)'**
  String dynamicMergeMaxGapDesc(Object minutes);

  /// No description provided for @dynamicMergeMaxImagesTitle.
  ///
  /// In en, this message translates to:
  /// **'Dynamic merge: max images'**
  String get dynamicMergeMaxImagesTitle;

  /// No description provided for @dynamicMergeMaxImagesDesc.
  ///
  /// In en, this message translates to:
  /// **'Current: {count} images (0 = unlimited)'**
  String dynamicMergeMaxImagesDesc(Object count);

  /// No description provided for @dynamicMergeLimitInputHint.
  ///
  /// In en, this message translates to:
  /// **'Enter an integer >= 0 (0 = unlimited)'**
  String get dynamicMergeLimitInputHint;

  /// No description provided for @dynamicMergeLimitInvalidError.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid integer >= 0'**
  String get dynamicMergeLimitInvalidError;

  /// No description provided for @dailyReminderTimeTitle.
  ///
  /// In en, this message translates to:
  /// **'Daily summary reminder time'**
  String get dailyReminderTimeTitle;

  /// No description provided for @currentTimeLabel.
  ///
  /// In en, this message translates to:
  /// **'Current: '**
  String get currentTimeLabel;

  /// No description provided for @testNotificationTitle.
  ///
  /// In en, this message translates to:
  /// **'Test notification'**
  String get testNotificationTitle;

  /// No description provided for @testNotificationDesc.
  ///
  /// In en, this message translates to:
  /// **'Trigger \"Daily Summary\" notification now'**
  String get testNotificationDesc;

  /// No description provided for @enableBannerNotificationTitle.
  ///
  /// In en, this message translates to:
  /// **'Enable banner/floating notifications'**
  String get enableBannerNotificationTitle;

  /// No description provided for @enableBannerNotificationDesc.
  ///
  /// In en, this message translates to:
  /// **'Allow notifications to pop up at the top of screen (banner/floating)'**
  String get enableBannerNotificationDesc;

  /// No description provided for @setIntervalDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Set screenshot interval'**
  String get setIntervalDialogTitle;

  /// No description provided for @intervalSecondsLabel.
  ///
  /// In en, this message translates to:
  /// **'Interval (seconds)'**
  String get intervalSecondsLabel;

  /// No description provided for @intervalInputHint.
  ///
  /// In en, this message translates to:
  /// **'Enter an integer between 5-60'**
  String get intervalInputHint;

  /// No description provided for @intervalInvalidError.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid integer between 5-60'**
  String get intervalInvalidError;

  /// No description provided for @intervalSavedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Screenshot interval set to {seconds}s'**
  String intervalSavedSuccess(Object seconds);

  /// No description provided for @setTargetSizeDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Set target size (KB)'**
  String get setTargetSizeDialogTitle;

  /// No description provided for @targetSizeKbLabel.
  ///
  /// In en, this message translates to:
  /// **'Target size (KB)'**
  String get targetSizeKbLabel;

  /// No description provided for @targetSizeInvalidError.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid integer >= 50'**
  String get targetSizeInvalidError;

  /// No description provided for @targetSizeSavedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Target size set to {kb} KB'**
  String targetSizeSavedSuccess(Object kb);

  /// No description provided for @setExpireDaysDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Set screenshot expiration days'**
  String get setExpireDaysDialogTitle;

  /// No description provided for @expireDaysLabel.
  ///
  /// In en, this message translates to:
  /// **'Expiration days'**
  String get expireDaysLabel;

  /// No description provided for @expireDaysInputHint.
  ///
  /// In en, this message translates to:
  /// **'Enter an integer >= 1'**
  String get expireDaysInputHint;

  /// No description provided for @expireDaysInvalidError.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid integer >= 1'**
  String get expireDaysInvalidError;

  /// No description provided for @expireDaysSavedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Set to {days} days'**
  String expireDaysSavedSuccess(Object days);

  /// No description provided for @sortTimeNewToOld.
  ///
  /// In en, this message translates to:
  /// **'Time (New→Old)'**
  String get sortTimeNewToOld;

  /// No description provided for @sortTimeOldToNew.
  ///
  /// In en, this message translates to:
  /// **'Time (Old→New)'**
  String get sortTimeOldToNew;

  /// No description provided for @sortSizeLargeToSmall.
  ///
  /// In en, this message translates to:
  /// **'Size (Large→Small)'**
  String get sortSizeLargeToSmall;

  /// No description provided for @sortSizeSmallToLarge.
  ///
  /// In en, this message translates to:
  /// **'Size (Small→Large)'**
  String get sortSizeSmallToLarge;

  /// No description provided for @sortCountManyToFew.
  ///
  /// In en, this message translates to:
  /// **'Count (Many→Few)'**
  String get sortCountManyToFew;

  /// No description provided for @sortCountFewToMany.
  ///
  /// In en, this message translates to:
  /// **'Count (Few→Many)'**
  String get sortCountFewToMany;

  /// No description provided for @sortFieldTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get sortFieldTime;

  /// No description provided for @sortFieldCount.
  ///
  /// In en, this message translates to:
  /// **'Count'**
  String get sortFieldCount;

  /// No description provided for @sortFieldSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get sortFieldSize;

  /// No description provided for @selectHomeSortingTitle.
  ///
  /// In en, this message translates to:
  /// **'Select home sorting'**
  String get selectHomeSortingTitle;

  /// No description provided for @currentSortingLabel.
  ///
  /// In en, this message translates to:
  /// **'Current: {sorting}'**
  String currentSortingLabel(Object sorting);

  /// No description provided for @privacyModeEnabledToast.
  ///
  /// In en, this message translates to:
  /// **'Privacy mode enabled'**
  String get privacyModeEnabledToast;

  /// No description provided for @privacyModeDisabledToast.
  ///
  /// In en, this message translates to:
  /// **'Privacy mode disabled'**
  String get privacyModeDisabledToast;

  /// No description provided for @screenshotQualitySettingsSaved.
  ///
  /// In en, this message translates to:
  /// **'Screenshot quality settings saved'**
  String get screenshotQualitySettingsSaved;

  /// No description provided for @saveFailedError.
  ///
  /// In en, this message translates to:
  /// **'Save failed: {error}'**
  String saveFailedError(Object error);

  /// No description provided for @setReminderTimeTitle.
  ///
  /// In en, this message translates to:
  /// **'Set reminder time (24-hour format)'**
  String get setReminderTimeTitle;

  /// No description provided for @hourLabel.
  ///
  /// In en, this message translates to:
  /// **'Hour (0-23)'**
  String get hourLabel;

  /// No description provided for @minuteLabel.
  ///
  /// In en, this message translates to:
  /// **'Minute (0-59)'**
  String get minuteLabel;

  /// No description provided for @timeInputHint.
  ///
  /// In en, this message translates to:
  /// **'Tip: Click numbers to input directly; range is 0-23 hours and 0-59 minutes.'**
  String get timeInputHint;

  /// No description provided for @invalidHourError.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid hour between 0-23'**
  String get invalidHourError;

  /// No description provided for @invalidMinuteError.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid minute between 0-59'**
  String get invalidMinuteError;

  /// No description provided for @timeSetSuccess.
  ///
  /// In en, this message translates to:
  /// **'Set to {hour}:{minute}'**
  String timeSetSuccess(Object hour, Object minute);

  /// No description provided for @reminderScheduleSuccess.
  ///
  /// In en, this message translates to:
  /// **'Daily reminder time set to {hour}:{minute}'**
  String reminderScheduleSuccess(Object hour, Object minute);

  /// No description provided for @reminderDisabledSuccess.
  ///
  /// In en, this message translates to:
  /// **'Daily reminder disabled'**
  String get reminderDisabledSuccess;

  /// No description provided for @reminderScheduleFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to schedule daily reminder (platform may not support)'**
  String get reminderScheduleFailed;

  /// No description provided for @saveReminderSettingsFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to save reminder settings: {error}'**
  String saveReminderSettingsFailed(Object error);

  /// No description provided for @searchFailedError.
  ///
  /// In en, this message translates to:
  /// **'Search failed: {error}'**
  String searchFailedError(Object error);

  /// No description provided for @searchInputHintOcr.
  ///
  /// In en, this message translates to:
  /// **'Type keywords to search screenshots by OCR'**
  String get searchInputHintOcr;

  /// No description provided for @noMatchingScreenshots.
  ///
  /// In en, this message translates to:
  /// **'No matching screenshots'**
  String get noMatchingScreenshots;

  /// No description provided for @imageMissingOrCorrupted.
  ///
  /// In en, this message translates to:
  /// **'Image missing or corrupted'**
  String get imageMissingOrCorrupted;

  /// No description provided for @actionClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get actionClear;

  /// No description provided for @actionRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get actionRefresh;

  /// No description provided for @noScreenshotsTitle.
  ///
  /// In en, this message translates to:
  /// **'No screenshots yet'**
  String get noScreenshotsTitle;

  /// No description provided for @noScreenshotsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enable screenshot monitoring to see images here'**
  String get noScreenshotsSubtitle;

  /// No description provided for @confirmDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm deletion'**
  String get confirmDeleteTitle;

  /// No description provided for @confirmDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete this screenshot? This action cannot be undone.'**
  String get confirmDeleteMessage;

  /// No description provided for @actionDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get actionDelete;

  /// No description provided for @actionContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get actionContinue;

  /// No description provided for @linkTitle.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get linkTitle;

  /// No description provided for @actionCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get actionCopy;

  /// No description provided for @imageInfoTitle.
  ///
  /// In en, this message translates to:
  /// **'Screenshot info'**
  String get imageInfoTitle;

  /// No description provided for @deleteImageTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete image'**
  String get deleteImageTooltip;

  /// No description provided for @imageLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Image failed to load'**
  String get imageLoadFailed;

  /// No description provided for @labelAppName.
  ///
  /// In en, this message translates to:
  /// **'App name'**
  String get labelAppName;

  /// No description provided for @labelCaptureTime.
  ///
  /// In en, this message translates to:
  /// **'Capture time'**
  String get labelCaptureTime;

  /// No description provided for @labelFilePath.
  ///
  /// In en, this message translates to:
  /// **'File path'**
  String get labelFilePath;

  /// No description provided for @labelPageLink.
  ///
  /// In en, this message translates to:
  /// **'Page link'**
  String get labelPageLink;

  /// No description provided for @labelFileSize.
  ///
  /// In en, this message translates to:
  /// **'File size'**
  String get labelFileSize;

  /// No description provided for @tapToContinue.
  ///
  /// In en, this message translates to:
  /// **'Tap to continue'**
  String get tapToContinue;

  /// No description provided for @appDirUninitialized.
  ///
  /// In en, this message translates to:
  /// **'App directory not initialized'**
  String get appDirUninitialized;

  /// No description provided for @actionRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get actionRetry;

  /// No description provided for @deleteSelectedTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete selected'**
  String get deleteSelectedTooltip;

  /// No description provided for @noMatchingResults.
  ///
  /// In en, this message translates to:
  /// **'No matching results'**
  String get noMatchingResults;

  /// No description provided for @dayTabToday.
  ///
  /// In en, this message translates to:
  /// **'Today {count}'**
  String dayTabToday(Object count);

  /// No description provided for @dayTabYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday {count}'**
  String dayTabYesterday(Object count);

  /// No description provided for @dayTabMonthDayCount.
  ///
  /// In en, this message translates to:
  /// **'{month}/{day} {count}'**
  String dayTabMonthDayCount(Object month, Object day, Object count);

  /// No description provided for @screenshotDeletedToast.
  ///
  /// In en, this message translates to:
  /// **'Screenshot deleted'**
  String get screenshotDeletedToast;

  /// No description provided for @deleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Delete failed'**
  String get deleteFailed;

  /// No description provided for @deleteFailedWithError.
  ///
  /// In en, this message translates to:
  /// **'Delete failed: {error}'**
  String deleteFailedWithError(Object error);

  /// No description provided for @imageInfoTooltip.
  ///
  /// In en, this message translates to:
  /// **'Image info'**
  String get imageInfoTooltip;

  /// No description provided for @copySuccess.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copySuccess;

  /// No description provided for @copyFailed.
  ///
  /// In en, this message translates to:
  /// **'Copy failed'**
  String get copyFailed;

  /// No description provided for @deletedCountToast.
  ///
  /// In en, this message translates to:
  /// **'Deleted {count} screenshots'**
  String deletedCountToast(Object count);

  /// No description provided for @invalidArguments.
  ///
  /// In en, this message translates to:
  /// **'Invalid arguments'**
  String get invalidArguments;

  /// No description provided for @initFailedWithError.
  ///
  /// In en, this message translates to:
  /// **'Initialization failed: {error}'**
  String initFailedWithError(Object error);

  /// No description provided for @loadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get loadMore;

  /// No description provided for @loadMoreFailedWithError.
  ///
  /// In en, this message translates to:
  /// **'Failed to load more: {error}'**
  String loadMoreFailedWithError(Object error);

  /// No description provided for @confirmDeleteAllTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm deleting all screenshots'**
  String get confirmDeleteAllTitle;

  /// No description provided for @deleteAllMessage.
  ///
  /// In en, this message translates to:
  /// **'Will delete all {count} screenshots in current scope. This action cannot be undone.'**
  String deleteAllMessage(Object count);

  /// No description provided for @deleteSelectedMessage.
  ///
  /// In en, this message translates to:
  /// **'Will delete {count} selected screenshots. This cannot be undone. Continue?'**
  String deleteSelectedMessage(Object count);

  /// No description provided for @deleteFailedRetry.
  ///
  /// In en, this message translates to:
  /// **'Delete failed, please retry'**
  String get deleteFailedRetry;

  /// No description provided for @keptAndDeletedSummary.
  ///
  /// In en, this message translates to:
  /// **'Kept {keep}, deleted {deleted}'**
  String keptAndDeletedSummary(Object keep, Object deleted);

  /// No description provided for @dailySummaryTitle.
  ///
  /// In en, this message translates to:
  /// **'Daily Summary {date}'**
  String dailySummaryTitle(Object date);

  /// No description provided for @dailySummarySlotMorningTitle.
  ///
  /// In en, this message translates to:
  /// **'Morning Briefing {date}'**
  String dailySummarySlotMorningTitle(Object date);

  /// No description provided for @dailySummarySlotNoonTitle.
  ///
  /// In en, this message translates to:
  /// **'Midday Briefing {date}'**
  String dailySummarySlotNoonTitle(Object date);

  /// No description provided for @dailySummarySlotEveningTitle.
  ///
  /// In en, this message translates to:
  /// **'Evening Briefing {date}'**
  String dailySummarySlotEveningTitle(Object date);

  /// No description provided for @dailySummarySlotNightTitle.
  ///
  /// In en, this message translates to:
  /// **'Nightly Briefing {date}'**
  String dailySummarySlotNightTitle(Object date);

  /// No description provided for @actionGenerate.
  ///
  /// In en, this message translates to:
  /// **'Generate'**
  String get actionGenerate;

  /// No description provided for @actionRegenerate.
  ///
  /// In en, this message translates to:
  /// **'Regenerate'**
  String get actionRegenerate;

  /// No description provided for @generateSuccess.
  ///
  /// In en, this message translates to:
  /// **'Generated'**
  String get generateSuccess;

  /// No description provided for @generateFailed.
  ///
  /// In en, this message translates to:
  /// **'Generate failed'**
  String get generateFailed;

  /// No description provided for @noDailySummaryToday.
  ///
  /// In en, this message translates to:
  /// **'No summary for today'**
  String get noDailySummaryToday;

  /// No description provided for @generateDailySummary.
  ///
  /// In en, this message translates to:
  /// **'Generate today\'s summary'**
  String get generateDailySummary;

  /// No description provided for @dailySummaryGeneratingTitle.
  ///
  /// In en, this message translates to:
  /// **'Generating today\'s summary'**
  String get dailySummaryGeneratingTitle;

  /// No description provided for @dailySummaryGeneratingHint.
  ///
  /// In en, this message translates to:
  /// **'The page stays in reading mode while the summary stream arrives.'**
  String get dailySummaryGeneratingHint;

  /// No description provided for @statisticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get statisticsTitle;

  /// No description provided for @overviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get overviewTitle;

  /// No description provided for @monitoredApps.
  ///
  /// In en, this message translates to:
  /// **'Monitored apps'**
  String get monitoredApps;

  /// No description provided for @totalScreenshots.
  ///
  /// In en, this message translates to:
  /// **'Total screenshots'**
  String get totalScreenshots;

  /// No description provided for @todayScreenshots.
  ///
  /// In en, this message translates to:
  /// **'Today\'s screenshots'**
  String get todayScreenshots;

  /// No description provided for @storageUsage.
  ///
  /// In en, this message translates to:
  /// **'Storage usage'**
  String get storageUsage;

  /// No description provided for @appStatisticsTitle.
  ///
  /// In en, this message translates to:
  /// **'App statistics'**
  String get appStatisticsTitle;

  /// No description provided for @screenshotCountWithLast.
  ///
  /// In en, this message translates to:
  /// **'Screenshots: {count} | Last: {last}'**
  String screenshotCountWithLast(Object count, Object last);

  /// No description provided for @none.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get none;

  /// No description provided for @usageTrendsTitle.
  ///
  /// In en, this message translates to:
  /// **'Usage trends'**
  String get usageTrendsTitle;

  /// No description provided for @trendChartTitle.
  ///
  /// In en, this message translates to:
  /// **'Trend chart'**
  String get trendChartTitle;

  /// No description provided for @comingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get comingSoon;

  /// No description provided for @timelineTitle.
  ///
  /// In en, this message translates to:
  /// **'Timeline'**
  String get timelineTitle;

  /// No description provided for @timelineReplay.
  ///
  /// In en, this message translates to:
  /// **'Replay'**
  String get timelineReplay;

  /// No description provided for @timelineReplayGenerate.
  ///
  /// In en, this message translates to:
  /// **'Generate replay'**
  String get timelineReplayGenerate;

  /// No description provided for @timelineReplayUseSelectedDay.
  ///
  /// In en, this message translates to:
  /// **'Use selected day'**
  String get timelineReplayUseSelectedDay;

  /// No description provided for @timelineReplayStartTime.
  ///
  /// In en, this message translates to:
  /// **'Start time'**
  String get timelineReplayStartTime;

  /// No description provided for @timelineReplayEndTime.
  ///
  /// In en, this message translates to:
  /// **'End time'**
  String get timelineReplayEndTime;

  /// No description provided for @timelineReplayDuration.
  ///
  /// In en, this message translates to:
  /// **'Target duration'**
  String get timelineReplayDuration;

  /// No description provided for @timelineReplayFps.
  ///
  /// In en, this message translates to:
  /// **'FPS'**
  String get timelineReplayFps;

  /// No description provided for @timelineReplayResolution.
  ///
  /// In en, this message translates to:
  /// **'Resolution'**
  String get timelineReplayResolution;

  /// No description provided for @timelineReplayQuality.
  ///
  /// In en, this message translates to:
  /// **'Quality'**
  String get timelineReplayQuality;

  /// No description provided for @timelineReplayOverlay.
  ///
  /// In en, this message translates to:
  /// **'Overlay time/app'**
  String get timelineReplayOverlay;

  /// No description provided for @timelineReplaySaveToGallery.
  ///
  /// In en, this message translates to:
  /// **'Save to gallery after generating'**
  String get timelineReplaySaveToGallery;

  /// No description provided for @timelineReplayAppProgressBar.
  ///
  /// In en, this message translates to:
  /// **'App progress bar'**
  String get timelineReplayAppProgressBar;

  /// No description provided for @timelineReplayNsfw.
  ///
  /// In en, this message translates to:
  /// **'NSFW content'**
  String get timelineReplayNsfw;

  /// No description provided for @timelineReplayNsfwMask.
  ///
  /// In en, this message translates to:
  /// **'Show mask'**
  String get timelineReplayNsfwMask;

  /// No description provided for @timelineReplayNsfwShow.
  ///
  /// In en, this message translates to:
  /// **'Show all'**
  String get timelineReplayNsfwShow;

  /// No description provided for @timelineReplayNsfwHide.
  ///
  /// In en, this message translates to:
  /// **'Hide NSFW'**
  String get timelineReplayNsfwHide;

  /// No description provided for @timelineReplayFpsInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter 1–120'**
  String get timelineReplayFpsInvalid;

  /// No description provided for @timelineReplayGeneratingRange.
  ///
  /// In en, this message translates to:
  /// **'Generating {range} video…'**
  String timelineReplayGeneratingRange(Object range);

  /// No description provided for @timelineReplayPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing replay…'**
  String get timelineReplayPreparing;

  /// No description provided for @timelineReplayEncoding.
  ///
  /// In en, this message translates to:
  /// **'Encoding video…'**
  String get timelineReplayEncoding;

  /// No description provided for @timelineReplayNoScreenshots.
  ///
  /// In en, this message translates to:
  /// **'No screenshots in this time range'**
  String get timelineReplayNoScreenshots;

  /// No description provided for @timelineReplayFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to generate replay'**
  String get timelineReplayFailed;

  /// No description provided for @timelineReplayReady.
  ///
  /// In en, this message translates to:
  /// **'Replay generated'**
  String get timelineReplayReady;

  /// No description provided for @timelineReplayNotificationHint.
  ///
  /// In en, this message translates to:
  /// **'Replay is generating; check progress in notifications'**
  String get timelineReplayNotificationHint;

  /// No description provided for @pressBackAgainToExit.
  ///
  /// In en, this message translates to:
  /// **'Press back again to exit'**
  String get pressBackAgainToExit;

  /// No description provided for @segmentStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get segmentStatusTitle;

  /// No description provided for @autoWatchingHint.
  ///
  /// In en, this message translates to:
  /// **'Auto watching in background…'**
  String get autoWatchingHint;

  /// No description provided for @noEvents.
  ///
  /// In en, this message translates to:
  /// **'No events'**
  String get noEvents;

  /// No description provided for @noEventsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Event segments and AI summaries will appear here'**
  String get noEventsSubtitle;

  /// No description provided for @activeSegmentTitle.
  ///
  /// In en, this message translates to:
  /// **'Active segment'**
  String get activeSegmentTitle;

  /// No description provided for @sampleEverySeconds.
  ///
  /// In en, this message translates to:
  /// **'Sample every {seconds}s'**
  String sampleEverySeconds(Object seconds);

  /// No description provided for @dailySummaryShort.
  ///
  /// In en, this message translates to:
  /// **'Daily Summary'**
  String get dailySummaryShort;

  /// No description provided for @weeklySummaryShort.
  ///
  /// In en, this message translates to:
  /// **'Weekly Summary'**
  String get weeklySummaryShort;

  /// Weekly summary page title with date range
  ///
  /// In en, this message translates to:
  /// **'Weekly Summary {range}'**
  String weeklySummaryTitle(Object range);

  /// No description provided for @weeklySummaryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No weekly summaries yet'**
  String get weeklySummaryEmpty;

  /// No description provided for @weeklySummarySelectWeek.
  ///
  /// In en, this message translates to:
  /// **'Select Week'**
  String get weeklySummarySelectWeek;

  /// No description provided for @weeklySummaryOverviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Weekly Overview'**
  String get weeklySummaryOverviewTitle;

  /// No description provided for @weeklySummaryDailyTitle.
  ///
  /// In en, this message translates to:
  /// **'Daily Breakdown'**
  String get weeklySummaryDailyTitle;

  /// No description provided for @weeklySummaryActionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Next Week Actions'**
  String get weeklySummaryActionsTitle;

  /// No description provided for @weeklySummaryNotificationTitle.
  ///
  /// In en, this message translates to:
  /// **'Notification Brief'**
  String get weeklySummaryNotificationTitle;

  /// No description provided for @weeklySummaryNoContent.
  ///
  /// In en, this message translates to:
  /// **'No content'**
  String get weeklySummaryNoContent;

  /// No description provided for @weeklySummaryViewDetail.
  ///
  /// In en, this message translates to:
  /// **'View details'**
  String get weeklySummaryViewDetail;

  /// No description provided for @viewOrGenerateForDay.
  ///
  /// In en, this message translates to:
  /// **'View or generate the day\'s summary'**
  String get viewOrGenerateForDay;

  /// No description provided for @mergedEventTag.
  ///
  /// In en, this message translates to:
  /// **'Merged'**
  String get mergedEventTag;

  /// Title for the expandable section that contains original events merged into the current event.
  ///
  /// In en, this message translates to:
  /// **'Original events ({count})'**
  String mergedOriginalEventsTitle(Object count);

  /// Header title for each original event entry inside a merged event.
  ///
  /// In en, this message translates to:
  /// **'Original event {index}'**
  String mergedOriginalEventTitle(Object index);

  /// No description provided for @collapse.
  ///
  /// In en, this message translates to:
  /// **'Collapse'**
  String get collapse;

  /// No description provided for @expandMore.
  ///
  /// In en, this message translates to:
  /// **'Expand more'**
  String get expandMore;

  /// No description provided for @viewImagesCount.
  ///
  /// In en, this message translates to:
  /// **'View images ({count})'**
  String viewImagesCount(Object count);

  /// No description provided for @hideImagesCount.
  ///
  /// In en, this message translates to:
  /// **'Hide images ({count})'**
  String hideImagesCount(Object count);

  /// No description provided for @deleteEventTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete event'**
  String get deleteEventTooltip;

  /// No description provided for @confirmDeleteEventMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete this event? This will not delete any image files.'**
  String get confirmDeleteEventMessage;

  /// No description provided for @eventDeletedToast.
  ///
  /// In en, this message translates to:
  /// **'Event deleted'**
  String get eventDeletedToast;

  /// No description provided for @regenerationQueued.
  ///
  /// In en, this message translates to:
  /// **'Regeneration queued'**
  String get regenerationQueued;

  /// No description provided for @alreadyQueuedOrFailed.
  ///
  /// In en, this message translates to:
  /// **'Already queued or failed'**
  String get alreadyQueuedOrFailed;

  /// No description provided for @retryFailed.
  ///
  /// In en, this message translates to:
  /// **'Retry failed'**
  String get retryFailed;

  /// No description provided for @copyResultsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Copy results'**
  String get copyResultsTooltip;

  /// No description provided for @articleGenerating.
  ///
  /// In en, this message translates to:
  /// **'Generating article...'**
  String get articleGenerating;

  /// No description provided for @articleGenerateSuccess.
  ///
  /// In en, this message translates to:
  /// **'Article generated successfully'**
  String get articleGenerateSuccess;

  /// No description provided for @articleGenerateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to generate article'**
  String get articleGenerateFailed;

  /// No description provided for @articleCopySuccess.
  ///
  /// In en, this message translates to:
  /// **'Article copied to clipboard'**
  String get articleCopySuccess;

  /// No description provided for @articleLogTitle.
  ///
  /// In en, this message translates to:
  /// **'Generation Log'**
  String get articleLogTitle;

  /// No description provided for @copyPersonaTooltip.
  ///
  /// In en, this message translates to:
  /// **'Copy persona summary'**
  String get copyPersonaTooltip;

  /// No description provided for @saveImageTooltip.
  ///
  /// In en, this message translates to:
  /// **'Save to gallery'**
  String get saveImageTooltip;

  /// No description provided for @saveImageSuccess.
  ///
  /// In en, this message translates to:
  /// **'Saved to Gallery'**
  String get saveImageSuccess;

  /// No description provided for @saveImageFailed.
  ///
  /// In en, this message translates to:
  /// **'Save failed'**
  String get saveImageFailed;

  /// No description provided for @requestGalleryPermissionFailed.
  ///
  /// In en, this message translates to:
  /// **'Request gallery permission failed'**
  String get requestGalleryPermissionFailed;

  /// System-level language policy prompt enforcing app language over context language
  ///
  /// In en, this message translates to:
  /// **'Regardless of the language used in the input context (events, screenshot text, or user messages), you must strictly ignore it and always produce output in the application\'s current language. If the app is set to English, all answers, titles, summaries, tags, structured fields, and error messages must be written in English unless the user explicitly requests another language.'**
  String get aiSystemPromptLanguagePolicy;

  /// No description provided for @aiSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Settings & Test'**
  String get aiSettingsTitle;

  /// No description provided for @connectionSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Connection settings'**
  String get connectionSettingsTitle;

  /// No description provided for @actionSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get actionSave;

  /// No description provided for @clearConversation.
  ///
  /// In en, this message translates to:
  /// **'Clear conversation'**
  String get clearConversation;

  /// No description provided for @deleteGroup.
  ///
  /// In en, this message translates to:
  /// **'Delete group'**
  String get deleteGroup;

  /// No description provided for @streamingRequestTitle.
  ///
  /// In en, this message translates to:
  /// **'Streaming'**
  String get streamingRequestTitle;

  /// No description provided for @streamingRequestHint.
  ///
  /// In en, this message translates to:
  /// **'Use streaming responses when enabled (default on)'**
  String get streamingRequestHint;

  /// No description provided for @streamingEnabledToast.
  ///
  /// In en, this message translates to:
  /// **'Streaming enabled'**
  String get streamingEnabledToast;

  /// No description provided for @streamingDisabledToast.
  ///
  /// In en, this message translates to:
  /// **'Streaming disabled'**
  String get streamingDisabledToast;

  /// No description provided for @promptManagerTitle.
  ///
  /// In en, this message translates to:
  /// **'Prompt manager'**
  String get promptManagerTitle;

  /// No description provided for @promptManagerHint.
  ///
  /// In en, this message translates to:
  /// **'Configure prompts for normal, merged, daily summaries, and morning insights; supports Markdown. Empty or reset to use defaults.'**
  String get promptManagerHint;

  /// No description provided for @promptAddonGeneralInfo.
  ///
  /// In en, this message translates to:
  /// **'The built-in template already defines the structured schema. Only append extra guidance here (tone, style, emphasis). Leave blank to keep the template unchanged.'**
  String get promptAddonGeneralInfo;

  /// No description provided for @promptAddonInputHint.
  ///
  /// In en, this message translates to:
  /// **'Add optional extra instructions (leave blank to skip)'**
  String get promptAddonInputHint;

  /// No description provided for @promptAddonHelperText.
  ///
  /// In en, this message translates to:
  /// **'Describe tone or preferences only; do not request schema changes or JSON modifications.'**
  String get promptAddonHelperText;

  /// No description provided for @promptAddonEmptyPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'No extra instructions'**
  String get promptAddonEmptyPlaceholder;

  /// No description provided for @promptAddonSuggestionSegment.
  ///
  /// In en, this message translates to:
  /// **'Suggested ideas:\n- State the desired tone or target audience in one sentence\n- Highlight the key insights or safety constraints to prioritize\n- Avoid asking for JSON field additions or structural changes'**
  String get promptAddonSuggestionSegment;

  /// No description provided for @promptAddonSuggestionMerge.
  ///
  /// In en, this message translates to:
  /// **'Suggested ideas:\n- Emphasize comparisons or contrasts to surface after merging\n- Remind the model to avoid repetition and focus on aggregated insights\n- Do not request structural changes to the output fields'**
  String get promptAddonSuggestionMerge;

  /// No description provided for @promptAddonSuggestionDaily.
  ///
  /// In en, this message translates to:
  /// **'Suggested ideas:\n- Specify the daily recap tone (e.g., action-oriented)\n- Ask to highlight major achievements or risks\n- Forbid renaming or adding JSON fields'**
  String get promptAddonSuggestionDaily;

  /// No description provided for @promptAddonSuggestionWeekly.
  ///
  /// In en, this message translates to:
  /// **'Suggested ideas:\n- Emphasize week-over-week trends or pivots to highlight\n- Ask for actionable follow-ups or attention points\n- Avoid requesting structural changes to the JSON output'**
  String get promptAddonSuggestionWeekly;

  /// No description provided for @promptAddonSuggestionMorning.
  ///
  /// In en, this message translates to:
  /// **'Suggested ideas:\n- Emphasize warmth, gentle pacing, or small comforts\n- Remind the model to avoid templated or task-driven tone\n- Do not request JSON field changes or rely heavily on questions'**
  String get promptAddonSuggestionMorning;

  /// No description provided for @normalEventPromptLabel.
  ///
  /// In en, this message translates to:
  /// **'Normal event prompt'**
  String get normalEventPromptLabel;

  /// No description provided for @mergeEventPromptLabel.
  ///
  /// In en, this message translates to:
  /// **'Merged event prompt'**
  String get mergeEventPromptLabel;

  /// No description provided for @dailySummaryPromptLabel.
  ///
  /// In en, this message translates to:
  /// **'Daily summary prompt'**
  String get dailySummaryPromptLabel;

  /// No description provided for @weeklySummaryPromptLabel.
  ///
  /// In en, this message translates to:
  /// **'Weekly summary prompt'**
  String get weeklySummaryPromptLabel;

  /// No description provided for @morningInsightsPromptLabel.
  ///
  /// In en, this message translates to:
  /// **'Morning insights prompt'**
  String get morningInsightsPromptLabel;

  /// No description provided for @actionEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get actionEdit;

  /// No description provided for @savingLabel.
  ///
  /// In en, this message translates to:
  /// **'Saving'**
  String get savingLabel;

  /// No description provided for @resetToDefault.
  ///
  /// In en, this message translates to:
  /// **'Reset to default'**
  String get resetToDefault;

  /// No description provided for @chatTestTitle.
  ///
  /// In en, this message translates to:
  /// **'Chat test'**
  String get chatTestTitle;

  /// No description provided for @actionSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get actionSend;

  /// No description provided for @sendingLabel.
  ///
  /// In en, this message translates to:
  /// **'Sending'**
  String get sendingLabel;

  /// No description provided for @baseUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'Base URL'**
  String get baseUrlLabel;

  /// No description provided for @baseUrlHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. https://api.openai.com'**
  String get baseUrlHint;

  /// No description provided for @apiKeyLabel.
  ///
  /// In en, this message translates to:
  /// **'API key'**
  String get apiKeyLabel;

  /// No description provided for @apiKeyHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. sk-... or vendor token'**
  String get apiKeyHint;

  /// No description provided for @modelLabel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get modelLabel;

  /// No description provided for @modelHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. gpt-4o-mini / gpt-4o / compatible'**
  String get modelHint;

  /// No description provided for @siteGroupsTitle.
  ///
  /// In en, this message translates to:
  /// **'Site groups'**
  String get siteGroupsTitle;

  /// No description provided for @siteGroupsHint.
  ///
  /// In en, this message translates to:
  /// **'Configure multiple sites as fallback; auto switch on failure'**
  String get siteGroupsHint;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @addGroup.
  ///
  /// In en, this message translates to:
  /// **'Add group'**
  String get addGroup;

  /// No description provided for @showGroupSelector.
  ///
  /// In en, this message translates to:
  /// **'Show group selector'**
  String get showGroupSelector;

  /// No description provided for @ungroupedSingleConfig.
  ///
  /// In en, this message translates to:
  /// **'Ungrouped (single config)'**
  String get ungroupedSingleConfig;

  /// No description provided for @inputMessageHint.
  ///
  /// In en, this message translates to:
  /// **'Enter a message'**
  String get inputMessageHint;

  /// No description provided for @saveSuccess.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get saveSuccess;

  /// No description provided for @savedCurrentGroupToast.
  ///
  /// In en, this message translates to:
  /// **'Group saved'**
  String get savedCurrentGroupToast;

  /// No description provided for @savedNormalPromptToast.
  ///
  /// In en, this message translates to:
  /// **'Normal prompt saved'**
  String get savedNormalPromptToast;

  /// No description provided for @savedMergePromptToast.
  ///
  /// In en, this message translates to:
  /// **'Merged prompt saved'**
  String get savedMergePromptToast;

  /// No description provided for @savedDailyPromptToast.
  ///
  /// In en, this message translates to:
  /// **'Daily prompt saved'**
  String get savedDailyPromptToast;

  /// No description provided for @savedWeeklyPromptToast.
  ///
  /// In en, this message translates to:
  /// **'Weekly prompt saved'**
  String get savedWeeklyPromptToast;

  /// No description provided for @resetToDefaultPromptToast.
  ///
  /// In en, this message translates to:
  /// **'Reset to default prompt'**
  String get resetToDefaultPromptToast;

  /// No description provided for @resetFailedWithError.
  ///
  /// In en, this message translates to:
  /// **'Reset failed: {error}'**
  String resetFailedWithError(Object error);

  /// No description provided for @clearSuccess.
  ///
  /// In en, this message translates to:
  /// **'Cleared'**
  String get clearSuccess;

  /// No description provided for @clearFailedWithError.
  ///
  /// In en, this message translates to:
  /// **'Clear failed: {error}'**
  String clearFailedWithError(Object error);

  /// No description provided for @messageCannotBeEmpty.
  ///
  /// In en, this message translates to:
  /// **'Message cannot be empty'**
  String get messageCannotBeEmpty;

  /// No description provided for @sendFailedWithError.
  ///
  /// In en, this message translates to:
  /// **'Send failed: {error}'**
  String sendFailedWithError(Object error);

  /// No description provided for @groupSwitchedToUngrouped.
  ///
  /// In en, this message translates to:
  /// **'Switched to Ungrouped'**
  String get groupSwitchedToUngrouped;

  /// No description provided for @groupSwitched.
  ///
  /// In en, this message translates to:
  /// **'Group switched'**
  String get groupSwitched;

  /// No description provided for @groupNotSelected.
  ///
  /// In en, this message translates to:
  /// **'No group selected'**
  String get groupNotSelected;

  /// No description provided for @groupNotFound.
  ///
  /// In en, this message translates to:
  /// **'Group not found'**
  String get groupNotFound;

  /// No description provided for @renameGroupTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename group'**
  String get renameGroupTitle;

  /// No description provided for @groupNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Group name'**
  String get groupNameLabel;

  /// No description provided for @groupNameHint.
  ///
  /// In en, this message translates to:
  /// **'Enter a new group name'**
  String get groupNameHint;

  /// No description provided for @nameCannotBeEmpty.
  ///
  /// In en, this message translates to:
  /// **'Name cannot be empty'**
  String get nameCannotBeEmpty;

  /// No description provided for @renameSuccess.
  ///
  /// In en, this message translates to:
  /// **'Renamed'**
  String get renameSuccess;

  /// No description provided for @renameFailedWithError.
  ///
  /// In en, this message translates to:
  /// **'Rename failed: {error}'**
  String renameFailedWithError(Object error);

  /// No description provided for @groupAddedToast.
  ///
  /// In en, this message translates to:
  /// **'Group added'**
  String get groupAddedToast;

  /// No description provided for @addGroupFailedWithError.
  ///
  /// In en, this message translates to:
  /// **'Add group failed: {error}'**
  String addGroupFailedWithError(Object error);

  /// No description provided for @groupDeletedToast.
  ///
  /// In en, this message translates to:
  /// **'Group deleted'**
  String get groupDeletedToast;

  /// No description provided for @deleteGroupFailedWithError.
  ///
  /// In en, this message translates to:
  /// **'Delete group failed: {error}'**
  String deleteGroupFailedWithError(Object error);

  /// No description provided for @loadGroupFailedWithError.
  ///
  /// In en, this message translates to:
  /// **'Load group failed: {error}'**
  String loadGroupFailedWithError(Object error);

  /// No description provided for @siteGroupDefaultName.
  ///
  /// In en, this message translates to:
  /// **'Site Group {index}'**
  String siteGroupDefaultName(Object index);

  /// No description provided for @defaultLabel.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get defaultLabel;

  /// No description provided for @customLabel.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get customLabel;

  /// No description provided for @normalShortLabel.
  ///
  /// In en, this message translates to:
  /// **'Normal:'**
  String get normalShortLabel;

  /// No description provided for @mergeShortLabel.
  ///
  /// In en, this message translates to:
  /// **'Merged:'**
  String get mergeShortLabel;

  /// No description provided for @dailyShortLabel.
  ///
  /// In en, this message translates to:
  /// **'Daily:'**
  String get dailyShortLabel;

  /// No description provided for @timeRangeLabel.
  ///
  /// In en, this message translates to:
  /// **'Time range: {range}'**
  String timeRangeLabel(Object range);

  /// No description provided for @statusLabel.
  ///
  /// In en, this message translates to:
  /// **'Status: {status}'**
  String statusLabel(Object status);

  /// No description provided for @samplesTitle.
  ///
  /// In en, this message translates to:
  /// **'Samples ({count})'**
  String samplesTitle(Object count);

  /// No description provided for @aiResultTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Result'**
  String get aiResultTitle;

  /// No description provided for @aiResultAutoRetriedHint.
  ///
  /// In en, this message translates to:
  /// **'This result was automatically retried once to recover an incomplete AI response.'**
  String get aiResultAutoRetriedHint;

  /// No description provided for @aiResultAutoRetryFailedHint.
  ///
  /// In en, this message translates to:
  /// **'Automatic retry still failed. Please tap regenerate to retry manually.'**
  String get aiResultAutoRetryFailedHint;

  /// No description provided for @modelValueLabel.
  ///
  /// In en, this message translates to:
  /// **'Model: {model}'**
  String modelValueLabel(Object model);

  /// No description provided for @tagMergedCopy.
  ///
  /// In en, this message translates to:
  /// **'Tag: Merged'**
  String get tagMergedCopy;

  /// No description provided for @categoriesLabel.
  ///
  /// In en, this message translates to:
  /// **'Categories: {categories}'**
  String categoriesLabel(Object categories);

  /// No description provided for @errorLabel.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String errorLabel(Object error);

  /// No description provided for @summaryLabel.
  ///
  /// In en, this message translates to:
  /// **'Summary: {summary}'**
  String summaryLabel(Object summary);

  /// No description provided for @autostartPermissionNote.
  ///
  /// In en, this message translates to:
  /// **'Auto-start permission varies by OEM and cannot be auto-detected. Please choose based on your actual settings.'**
  String get autostartPermissionNote;

  /// No description provided for @monthDayTime.
  ///
  /// In en, this message translates to:
  /// **'{month}/{day} {hour}:{minute}'**
  String monthDayTime(Object month, Object day, Object hour, Object minute);

  /// No description provided for @yearMonthDayTime.
  ///
  /// In en, this message translates to:
  /// **'{year}/{month}/{day} {hour}:{minute}'**
  String yearMonthDayTime(
    Object year,
    Object month,
    Object day,
    Object hour,
    Object minute,
  );

  /// No description provided for @imagesCountLabel.
  ///
  /// In en, this message translates to:
  /// **'{count} images'**
  String imagesCountLabel(Object count);

  /// No description provided for @apps.
  ///
  /// In en, this message translates to:
  /// **'apps'**
  String get apps;

  /// No description provided for @images.
  ///
  /// In en, this message translates to:
  /// **'images'**
  String get images;

  /// No description provided for @days.
  ///
  /// In en, this message translates to:
  /// **'days'**
  String get days;

  /// No description provided for @aiImageTagsTitle.
  ///
  /// In en, this message translates to:
  /// **'Image tags'**
  String get aiImageTagsTitle;

  /// No description provided for @aiVisibleTextTitle.
  ///
  /// In en, this message translates to:
  /// **'Visible text'**
  String get aiVisibleTextTitle;

  /// No description provided for @aiImageDescriptionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Image descriptions'**
  String get aiImageDescriptionsTitle;

  /// No description provided for @justNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get justNow;

  /// No description provided for @minutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{minutes} minutes ago'**
  String minutesAgo(Object minutes);

  /// No description provided for @hoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{hours} hours ago'**
  String hoursAgo(Object hours);

  /// No description provided for @daysAgo.
  ///
  /// In en, this message translates to:
  /// **'{days} days ago'**
  String daysAgo(Object days);

  /// Search results count display
  ///
  /// In en, this message translates to:
  /// **'{count} images found'**
  String searchResultsCount(Object count);

  /// No description provided for @searchFiltersTitle.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get searchFiltersTitle;

  /// No description provided for @filterByTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get filterByTime;

  /// No description provided for @filterByApp.
  ///
  /// In en, this message translates to:
  /// **'App'**
  String get filterByApp;

  /// No description provided for @filterBySize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get filterBySize;

  /// No description provided for @filterTimeAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get filterTimeAll;

  /// No description provided for @filterTimeToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get filterTimeToday;

  /// No description provided for @filterTimeYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get filterTimeYesterday;

  /// No description provided for @filterTimeLast7Days.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get filterTimeLast7Days;

  /// No description provided for @filterTimeLast30Days.
  ///
  /// In en, this message translates to:
  /// **'Last 30 days'**
  String get filterTimeLast30Days;

  /// No description provided for @filterTimeCustomDays.
  ///
  /// In en, this message translates to:
  /// **'Custom days'**
  String get filterTimeCustomDays;

  /// No description provided for @filterTimeCustomDaysHint.
  ///
  /// In en, this message translates to:
  /// **'Enter 1-365 days'**
  String get filterTimeCustomDaysHint;

  /// No description provided for @filterTimeCustomRange.
  ///
  /// In en, this message translates to:
  /// **'Custom range'**
  String get filterTimeCustomRange;

  /// No description provided for @filterAppAll.
  ///
  /// In en, this message translates to:
  /// **'All apps'**
  String get filterAppAll;

  /// No description provided for @filterSizeAll.
  ///
  /// In en, this message translates to:
  /// **'All sizes'**
  String get filterSizeAll;

  /// No description provided for @filterSizeSmall.
  ///
  /// In en, this message translates to:
  /// **'< 100 KB'**
  String get filterSizeSmall;

  /// No description provided for @filterSizeMedium.
  ///
  /// In en, this message translates to:
  /// **'100 KB - 1 MB'**
  String get filterSizeMedium;

  /// No description provided for @filterSizeLarge.
  ///
  /// In en, this message translates to:
  /// **'> 1 MB'**
  String get filterSizeLarge;

  /// No description provided for @applyFilters.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get applyFilters;

  /// No description provided for @resetFilters.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get resetFilters;

  /// No description provided for @selectDateRange.
  ///
  /// In en, this message translates to:
  /// **'Select date range'**
  String get selectDateRange;

  /// No description provided for @startDate.
  ///
  /// In en, this message translates to:
  /// **'Start date'**
  String get startDate;

  /// No description provided for @endDate.
  ///
  /// In en, this message translates to:
  /// **'End date'**
  String get endDate;

  /// No description provided for @noResultsForFilters.
  ///
  /// In en, this message translates to:
  /// **'No images match the current filters'**
  String get noResultsForFilters;

  /// No description provided for @openLink.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get openLink;

  /// No description provided for @favoritePageTitle.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get favoritePageTitle;

  /// No description provided for @noFavoritesTitle.
  ///
  /// In en, this message translates to:
  /// **'No favorites'**
  String get noFavoritesTitle;

  /// No description provided for @noFavoritesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Long-press on screenshots in the gallery to enter multi-select mode and add favorites'**
  String get noFavoritesSubtitle;

  /// No description provided for @noteLabel.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get noteLabel;

  /// No description provided for @updatedAt.
  ///
  /// In en, this message translates to:
  /// **'Updated '**
  String get updatedAt;

  /// No description provided for @clickToAddNote.
  ///
  /// In en, this message translates to:
  /// **'Click to add note...'**
  String get clickToAddNote;

  /// No description provided for @noteUnchanged.
  ///
  /// In en, this message translates to:
  /// **'Note unchanged'**
  String get noteUnchanged;

  /// No description provided for @noteSaved.
  ///
  /// In en, this message translates to:
  /// **'Note saved'**
  String get noteSaved;

  /// No description provided for @favoritesRemoved.
  ///
  /// In en, this message translates to:
  /// **'Removed from favorites'**
  String get favoritesRemoved;

  /// No description provided for @operationFailed.
  ///
  /// In en, this message translates to:
  /// **'Operation failed'**
  String get operationFailed;

  /// No description provided for @cannotGetAppDir.
  ///
  /// In en, this message translates to:
  /// **'Cannot get app directory'**
  String get cannotGetAppDir;

  /// No description provided for @nsfwSettingsSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'NSFW Settings'**
  String get nsfwSettingsSectionTitle;

  /// No description provided for @blockedDomainListTitle.
  ///
  /// In en, this message translates to:
  /// **'Blocked Domain List'**
  String get blockedDomainListTitle;

  /// No description provided for @addDomainPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Enter domain or *.example.com'**
  String get addDomainPlaceholder;

  /// No description provided for @addRuleAction.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get addRuleAction;

  /// No description provided for @previewAction.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get previewAction;

  /// No description provided for @removeAction.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removeAction;

  /// No description provided for @clearAction.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clearAction;

  /// No description provided for @clearAllRules.
  ///
  /// In en, this message translates to:
  /// **'Clear all rules'**
  String get clearAllRules;

  /// No description provided for @clearAllRulesConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm clearing rules'**
  String get clearAllRulesConfirmTitle;

  /// No description provided for @clearAllRulesMessage.
  ///
  /// In en, this message translates to:
  /// **'This will remove all blocked domain rules. This action cannot be undone.'**
  String get clearAllRulesMessage;

  /// No description provided for @previewAffectsCount.
  ///
  /// In en, this message translates to:
  /// **'Will affect {count} images'**
  String previewAffectsCount(Object count);

  /// No description provided for @affectCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Affects: {count}'**
  String affectCountLabel(Object count);

  /// No description provided for @confirmAddRuleTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm add rule'**
  String get confirmAddRuleTitle;

  /// No description provided for @confirmAddRuleMessage.
  ///
  /// In en, this message translates to:
  /// **'Add rule: {rule}'**
  String confirmAddRuleMessage(Object rule);

  /// No description provided for @ruleAddedToast.
  ///
  /// In en, this message translates to:
  /// **'Rule added'**
  String get ruleAddedToast;

  /// No description provided for @ruleRemovedToast.
  ///
  /// In en, this message translates to:
  /// **'Rule removed'**
  String get ruleRemovedToast;

  /// No description provided for @invalidDomainInputError.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid domain (supports *.example.com)'**
  String get invalidDomainInputError;

  /// No description provided for @manualMarkNsfw.
  ///
  /// In en, this message translates to:
  /// **'Mark as NSFW'**
  String get manualMarkNsfw;

  /// No description provided for @manualUnmarkNsfw.
  ///
  /// In en, this message translates to:
  /// **'Unmark NSFW'**
  String get manualUnmarkNsfw;

  /// No description provided for @manualMarkSuccess.
  ///
  /// In en, this message translates to:
  /// **'Marked as NSFW'**
  String get manualMarkSuccess;

  /// No description provided for @manualUnmarkSuccess.
  ///
  /// In en, this message translates to:
  /// **'NSFW mark removed'**
  String get manualUnmarkSuccess;

  /// No description provided for @manualMarkFailed.
  ///
  /// In en, this message translates to:
  /// **'Operation failed'**
  String get manualMarkFailed;

  /// No description provided for @nsfwTagLabel.
  ///
  /// In en, this message translates to:
  /// **'NSFW'**
  String get nsfwTagLabel;

  /// No description provided for @nsfwBlockedByRulesHint.
  ///
  /// In en, this message translates to:
  /// **'Blocked by NSFW rules. Manage in Settings > NSFW domains.'**
  String get nsfwBlockedByRulesHint;

  /// No description provided for @providersTitle.
  ///
  /// In en, this message translates to:
  /// **'Providers'**
  String get providersTitle;

  /// No description provided for @actionNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get actionNew;

  /// No description provided for @actionAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get actionAdd;

  /// No description provided for @noProvidersYetHint.
  ///
  /// In en, this message translates to:
  /// **'No providers yet. Tap \"New\" to create one.'**
  String get noProvidersYetHint;

  /// No description provided for @confirmDeleteProviderMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete provider \"{name}\"? This cannot be undone.'**
  String confirmDeleteProviderMessage(Object name);

  /// No description provided for @loadingConversations.
  ///
  /// In en, this message translates to:
  /// **'Loading conversations…'**
  String get loadingConversations;

  /// No description provided for @noConversations.
  ///
  /// In en, this message translates to:
  /// **'No conversations'**
  String get noConversations;

  /// No description provided for @deleteConversationTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete conversation'**
  String get deleteConversationTitle;

  /// No description provided for @confirmDeleteConversationMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete conversation \"{title}\"?'**
  String confirmDeleteConversationMessage(Object title);

  /// No description provided for @untitledConversationLabel.
  ///
  /// In en, this message translates to:
  /// **'Untitled conversation'**
  String get untitledConversationLabel;

  /// No description provided for @searchProviderPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search providers'**
  String get searchProviderPlaceholder;

  /// No description provided for @searchModelPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search models'**
  String get searchModelPlaceholder;

  /// No description provided for @providerSelectedToast.
  ///
  /// In en, this message translates to:
  /// **'Selected provider: {name}'**
  String providerSelectedToast(Object name);

  /// No description provided for @pleaseSelectProviderFirst.
  ///
  /// In en, this message translates to:
  /// **'Please select a provider first'**
  String get pleaseSelectProviderFirst;

  /// No description provided for @noModelsForProviderHint.
  ///
  /// In en, this message translates to:
  /// **'No models available. Refresh on Providers page or add manually.'**
  String get noModelsForProviderHint;

  /// No description provided for @noModelsDetectedHint.
  ///
  /// In en, this message translates to:
  /// **'No models detected. Try Refresh or add manually.'**
  String get noModelsDetectedHint;

  /// No description provided for @modelSwitchedToast.
  ///
  /// In en, this message translates to:
  /// **'Switched model: {model}'**
  String modelSwitchedToast(Object model);

  /// No description provided for @providerLabel.
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get providerLabel;

  /// No description provided for @sendMessageToModelPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Send a message to {model}'**
  String sendMessageToModelPlaceholder(Object model);

  /// No description provided for @deepThinkingLabel.
  ///
  /// In en, this message translates to:
  /// **'Thinking'**
  String get deepThinkingLabel;

  /// No description provided for @thinkingInProgress.
  ///
  /// In en, this message translates to:
  /// **'Thinking…'**
  String get thinkingInProgress;

  /// No description provided for @requestStoppedInfo.
  ///
  /// In en, this message translates to:
  /// **'Request stopped'**
  String get requestStoppedInfo;

  /// No description provided for @reasoningLabel.
  ///
  /// In en, this message translates to:
  /// **'Reasoning:'**
  String get reasoningLabel;

  /// No description provided for @answerLabel.
  ///
  /// In en, this message translates to:
  /// **'Answer:'**
  String get answerLabel;

  /// No description provided for @aiSelfModeEnabledToast.
  ///
  /// In en, this message translates to:
  /// **'Personal assistant: conversations use your data context'**
  String get aiSelfModeEnabledToast;

  /// No description provided for @selectModelWithCounts.
  ///
  /// In en, this message translates to:
  /// **'Select model ({filtered}/{total})'**
  String selectModelWithCounts(Object filtered, Object total);

  /// No description provided for @modelsCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Models ({count})'**
  String modelsCountLabel(Object count);

  /// No description provided for @manualAddModelLabel.
  ///
  /// In en, this message translates to:
  /// **'Add model manually'**
  String get manualAddModelLabel;

  /// No description provided for @inputAndAddModelHint.
  ///
  /// In en, this message translates to:
  /// **'Enter and add, e.g. gpt-4o-mini'**
  String get inputAndAddModelHint;

  /// No description provided for @fetchModelsHint.
  ///
  /// In en, this message translates to:
  /// **'Click \"Refresh\" to fetch automatically; if it fails, add model names manually.'**
  String get fetchModelsHint;

  /// No description provided for @interfaceTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Interface type'**
  String get interfaceTypeLabel;

  /// No description provided for @currentTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Current: {type}'**
  String currentTypeLabel(Object type);

  /// No description provided for @nameRequiredError.
  ///
  /// In en, this message translates to:
  /// **'Name is required'**
  String get nameRequiredError;

  /// No description provided for @nameAlreadyExistsError.
  ///
  /// In en, this message translates to:
  /// **'Name already exists'**
  String get nameAlreadyExistsError;

  /// No description provided for @apiKeyRequiredError.
  ///
  /// In en, this message translates to:
  /// **'API Key is required'**
  String get apiKeyRequiredError;

  /// No description provided for @baseUrlRequiredForAzureError.
  ///
  /// In en, this message translates to:
  /// **'Base URL required for Azure OpenAI'**
  String get baseUrlRequiredForAzureError;

  /// No description provided for @atLeastOneModelRequiredError.
  ///
  /// In en, this message translates to:
  /// **'At least one model is required'**
  String get atLeastOneModelRequiredError;

  /// No description provided for @modelsUpdatedToast.
  ///
  /// In en, this message translates to:
  /// **'Models updated ({count})'**
  String modelsUpdatedToast(Object count);

  /// No description provided for @fetchModelsFailedHint.
  ///
  /// In en, this message translates to:
  /// **'Fetch models failed. You may add manually.'**
  String get fetchModelsFailedHint;

  /// No description provided for @useResponseApiLabel.
  ///
  /// In en, this message translates to:
  /// **'Use Response API (only official OpenAI supports; third-party services are not recommended)'**
  String get useResponseApiLabel;

  /// No description provided for @modelsPathOptionalLabel.
  ///
  /// In en, this message translates to:
  /// **'Models Path (optional)'**
  String get modelsPathOptionalLabel;

  /// No description provided for @chatPathOptionalLabel.
  ///
  /// In en, this message translates to:
  /// **'Chat Path (optional)'**
  String get chatPathOptionalLabel;

  /// No description provided for @azureApiVersionLabel.
  ///
  /// In en, this message translates to:
  /// **'Azure API Version'**
  String get azureApiVersionLabel;

  /// No description provided for @azureApiVersionHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 2024-02-15'**
  String get azureApiVersionHint;

  /// No description provided for @baseUrlHintOpenAI.
  ///
  /// In en, this message translates to:
  /// **'e.g. https://api.openai.com (empty for default)'**
  String get baseUrlHintOpenAI;

  /// No description provided for @baseUrlHintClaude.
  ///
  /// In en, this message translates to:
  /// **'e.g. https://api.anthropic.com'**
  String get baseUrlHintClaude;

  /// No description provided for @baseUrlHintGemini.
  ///
  /// In en, this message translates to:
  /// **'e.g. https://generativelanguage.googleapis.com'**
  String get baseUrlHintGemini;

  /// No description provided for @geminiRegionDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Gemini Usage Restriction'**
  String get geminiRegionDialogTitle;

  /// No description provided for @geminiRegionDialogMessage.
  ///
  /// In en, this message translates to:
  /// **'Gemini Developer API requests are only available from Google-supported countries or regions. Ensure your Google account profile, billing information, and network egress are located in supported regions; otherwise the server returns FAILED_PRECONDITION. For enterprise scenarios, route traffic through a compliant proxy within a supported region.'**
  String get geminiRegionDialogMessage;

  /// No description provided for @geminiRegionToast.
  ///
  /// In en, this message translates to:
  /// **'Gemini works only in supported regions. Tap the question mark for details.'**
  String get geminiRegionToast;

  /// No description provided for @baseUrlHintAzure.
  ///
  /// In en, this message translates to:
  /// **'Required, e.g. https://{resource}.openai.azure.com'**
  String baseUrlHintAzure(Object resource);

  /// No description provided for @baseUrlHintCustom.
  ///
  /// In en, this message translates to:
  /// **'Enter an OpenAI-compatible Base URL'**
  String get baseUrlHintCustom;

  /// No description provided for @createProviderTitle.
  ///
  /// In en, this message translates to:
  /// **'New provider'**
  String get createProviderTitle;

  /// No description provided for @editProviderTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit provider'**
  String get editProviderTitle;

  /// No description provided for @deletedToast.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get deletedToast;

  /// No description provided for @providerNotFound.
  ///
  /// In en, this message translates to:
  /// **'Provider not found'**
  String get providerNotFound;

  /// No description provided for @conversationsSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Conversations'**
  String get conversationsSectionTitle;

  /// No description provided for @displaySectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Display'**
  String get displaySectionTitle;

  /// No description provided for @displaySectionDesc.
  ///
  /// In en, this message translates to:
  /// **'Theme mode, privacy mode, NSFW'**
  String get displaySectionDesc;

  /// No description provided for @themeModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Theme mode'**
  String get themeModeTitle;

  /// No description provided for @streamRenderImagesTitle.
  ///
  /// In en, this message translates to:
  /// **'Render images during streaming'**
  String get streamRenderImagesTitle;

  /// No description provided for @streamRenderImagesDesc.
  ///
  /// In en, this message translates to:
  /// **'May affect scrolling'**
  String get streamRenderImagesDesc;

  /// No description provided for @aiChatPerfOverlayTitle.
  ///
  /// In en, this message translates to:
  /// **'AIChat perf overlay'**
  String get aiChatPerfOverlayTitle;

  /// No description provided for @aiChatPerfOverlayDesc.
  ///
  /// In en, this message translates to:
  /// **'Show the Perf log window on AI chat page (for troubleshooting)'**
  String get aiChatPerfOverlayDesc;

  /// No description provided for @themeColorTitle.
  ///
  /// In en, this message translates to:
  /// **'Theme color'**
  String get themeColorTitle;

  /// No description provided for @themeColorDesc.
  ///
  /// In en, this message translates to:
  /// **'Customize the app\'s primary color'**
  String get themeColorDesc;

  /// No description provided for @chooseThemeColorTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose theme color'**
  String get chooseThemeColorTitle;

  /// No description provided for @pageBackgroundTitle.
  ///
  /// In en, this message translates to:
  /// **'Page background'**
  String get pageBackgroundTitle;

  /// No description provided for @pageBackgroundDesc.
  ///
  /// In en, this message translates to:
  /// **'Background color for main pages (light mode)'**
  String get pageBackgroundDesc;

  /// No description provided for @loggingTitle.
  ///
  /// In en, this message translates to:
  /// **'Logging'**
  String get loggingTitle;

  /// No description provided for @loggingDesc.
  ///
  /// In en, this message translates to:
  /// **'Enable centralized logging (enabled by default)'**
  String get loggingDesc;

  /// No description provided for @loggingAiTitle.
  ///
  /// In en, this message translates to:
  /// **'AI logs'**
  String get loggingAiTitle;

  /// No description provided for @loggingScreenshotTitle.
  ///
  /// In en, this message translates to:
  /// **'Screenshot logs'**
  String get loggingScreenshotTitle;

  /// No description provided for @loggingAiDesc.
  ///
  /// In en, this message translates to:
  /// **'Record AI request and response logs'**
  String get loggingAiDesc;

  /// No description provided for @loggingScreenshotDesc.
  ///
  /// In en, this message translates to:
  /// **'Record screenshot capture and cleanup logs'**
  String get loggingScreenshotDesc;

  /// No description provided for @themeModeAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get themeModeAuto;

  /// No description provided for @themeModeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeModeLight;

  /// No description provided for @themeModeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeModeDark;

  /// No description provided for @appStatsSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Screenshot statistics'**
  String get appStatsSectionTitle;

  /// No description provided for @appStatsCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Screenshots: {count}'**
  String appStatsCountLabel(Object count);

  /// No description provided for @appStatsSizeLabel.
  ///
  /// In en, this message translates to:
  /// **'Total size: {size}'**
  String appStatsSizeLabel(String size);

  /// No description provided for @appStatsLastCaptureUnknown.
  ///
  /// In en, this message translates to:
  /// **'Last captured: Unknown'**
  String get appStatsLastCaptureUnknown;

  /// No description provided for @appStatsLastCaptureLabel.
  ///
  /// In en, this message translates to:
  /// **'Last captured: {time}'**
  String appStatsLastCaptureLabel(Object time);

  /// No description provided for @recomputeAppStatsAction.
  ///
  /// In en, this message translates to:
  /// **'Recompute statistics'**
  String get recomputeAppStatsAction;

  /// No description provided for @recomputeAppStatsDescription.
  ///
  /// In en, this message translates to:
  /// **'Fix screenshot count and size mismatch caused by imports.'**
  String get recomputeAppStatsDescription;

  /// No description provided for @recomputeAppStatsSuccess.
  ///
  /// In en, this message translates to:
  /// **'Statistics refreshed'**
  String get recomputeAppStatsSuccess;

  /// No description provided for @recomputeAppStatsConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Recompute statistics'**
  String get recomputeAppStatsConfirmTitle;

  /// No description provided for @recomputeAppStatsConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Recompute the screenshot statistics for this app? This may take a while for large libraries.'**
  String get recomputeAppStatsConfirmMessage;

  /// No description provided for @appStatsCountTitle.
  ///
  /// In en, this message translates to:
  /// **'Screenshots'**
  String get appStatsCountTitle;

  /// No description provided for @appStatsSizeTitle.
  ///
  /// In en, this message translates to:
  /// **'Total size'**
  String get appStatsSizeTitle;

  /// No description provided for @appStatsLastCaptureTitle.
  ///
  /// In en, this message translates to:
  /// **'Last captured'**
  String get appStatsLastCaptureTitle;

  /// No description provided for @aiEmptySelfTitle.
  ///
  /// In en, this message translates to:
  /// **'This quiet moment is its own reset'**
  String get aiEmptySelfTitle;

  /// No description provided for @aiEmptySelfSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Open this space like leafing through your second memory—I\'m here to replay it with you.'**
  String get aiEmptySelfSubtitle;

  /// No description provided for @homeMorningTipsTitle.
  ///
  /// In en, this message translates to:
  /// **'Morning insights'**
  String get homeMorningTipsTitle;

  /// No description provided for @homeMorningTipsLoading.
  ///
  /// In en, this message translates to:
  /// **'Gathering ideas from yesterday’s trail…'**
  String get homeMorningTipsLoading;

  /// No description provided for @homeMorningTipsPullHint.
  ///
  /// In en, this message translates to:
  /// **'Pull to unveil today’s spark from yesterday'**
  String get homeMorningTipsPullHint;

  /// No description provided for @homeMorningTipsReleaseHint.
  ///
  /// In en, this message translates to:
  /// **'Release for another spark from yesterday'**
  String get homeMorningTipsReleaseHint;

  /// No description provided for @homeMorningTipsEmpty.
  ///
  /// In en, this message translates to:
  /// **'This brief pause is a way to care for yourself—take it easy.'**
  String get homeMorningTipsEmpty;

  /// No description provided for @homeMorningTipsViewAll.
  ///
  /// In en, this message translates to:
  /// **'Open daily summary'**
  String get homeMorningTipsViewAll;

  /// No description provided for @homeMorningTipsDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss card'**
  String get homeMorningTipsDismiss;

  /// No description provided for @homeMorningTipsCooldownHint.
  ///
  /// In en, this message translates to:
  /// **'Take a short pause before pulling again'**
  String get homeMorningTipsCooldownHint;

  /// No description provided for @homeMorningTipsCooldownMessage.
  ///
  /// In en, this message translates to:
  /// **'You’ve refreshed quite a lot—take a breath and look up from the screen for a moment.'**
  String get homeMorningTipsCooldownMessage;

  /// No description provided for @expireCleanupConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm enabling screenshot cleanup'**
  String get expireCleanupConfirmTitle;

  /// No description provided for @expireCleanupConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Once enabled, screenshots older than {days} days will be cleaned up immediately.\n\nNote: Only image files will be deleted; events, summaries, and other content will be preserved.'**
  String expireCleanupConfirmMessage(Object days);

  /// No description provided for @expireCleanupConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get expireCleanupConfirmAction;

  /// No description provided for @desktopMergerTitle.
  ///
  /// In en, this message translates to:
  /// **'Data Merger Tool'**
  String get desktopMergerTitle;

  /// No description provided for @desktopMergerDescription.
  ///
  /// In en, this message translates to:
  /// **'Efficiently merge multiple backup files'**
  String get desktopMergerDescription;

  /// No description provided for @desktopMergerSteps.
  ///
  /// In en, this message translates to:
  /// **'1. Select output directory (merged data will be saved here)\n2. Add ZIP backup files to merge\n3. Click Start Merge'**
  String get desktopMergerSteps;

  /// No description provided for @desktopMergerOutputDir.
  ///
  /// In en, this message translates to:
  /// **'Output Directory'**
  String get desktopMergerOutputDir;

  /// No description provided for @desktopMergerSelectOutputDir.
  ///
  /// In en, this message translates to:
  /// **'Select output directory...'**
  String get desktopMergerSelectOutputDir;

  /// No description provided for @desktopMergerBrowse.
  ///
  /// In en, this message translates to:
  /// **'Browse'**
  String get desktopMergerBrowse;

  /// No description provided for @desktopMergerZipFiles.
  ///
  /// In en, this message translates to:
  /// **'ZIP Backup Files'**
  String get desktopMergerZipFiles;

  /// No description provided for @desktopMergerSelectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} files selected'**
  String desktopMergerSelectedCount(Object count);

  /// No description provided for @desktopMergerAddFiles.
  ///
  /// In en, this message translates to:
  /// **'Add Files'**
  String get desktopMergerAddFiles;

  /// No description provided for @desktopMergerNoFiles.
  ///
  /// In en, this message translates to:
  /// **'No files selected'**
  String get desktopMergerNoFiles;

  /// No description provided for @desktopMergerDragHint.
  ///
  /// In en, this message translates to:
  /// **'Click the button above to add ZIP backup files'**
  String get desktopMergerDragHint;

  /// No description provided for @desktopMergerResultTitle.
  ///
  /// In en, this message translates to:
  /// **'Merge Results'**
  String get desktopMergerResultTitle;

  /// No description provided for @desktopMergerInsertedCount.
  ///
  /// In en, this message translates to:
  /// **'+{count} screenshots'**
  String desktopMergerInsertedCount(Object count);

  /// No description provided for @desktopMergerClear.
  ///
  /// In en, this message translates to:
  /// **'Clear List'**
  String get desktopMergerClear;

  /// No description provided for @desktopMergerMerging.
  ///
  /// In en, this message translates to:
  /// **'Merging...'**
  String get desktopMergerMerging;

  /// No description provided for @desktopMergerStart.
  ///
  /// In en, this message translates to:
  /// **'Start Merge'**
  String get desktopMergerStart;

  /// No description provided for @desktopMergerSelectZips.
  ///
  /// In en, this message translates to:
  /// **'Select ZIP backup files'**
  String get desktopMergerSelectZips;

  /// No description provided for @desktopMergerStageExtracting.
  ///
  /// In en, this message translates to:
  /// **'Extracting...'**
  String get desktopMergerStageExtracting;

  /// No description provided for @desktopMergerStageCopying.
  ///
  /// In en, this message translates to:
  /// **'Copying files...'**
  String get desktopMergerStageCopying;

  /// No description provided for @desktopMergerStageMerging.
  ///
  /// In en, this message translates to:
  /// **'Merging databases...'**
  String get desktopMergerStageMerging;

  /// No description provided for @desktopMergerStageFinalizing.
  ///
  /// In en, this message translates to:
  /// **'Finalizing...'**
  String get desktopMergerStageFinalizing;

  /// No description provided for @desktopMergerStageProcessing.
  ///
  /// In en, this message translates to:
  /// **'Processing...'**
  String get desktopMergerStageProcessing;

  /// No description provided for @desktopMergerStageCompleted.
  ///
  /// In en, this message translates to:
  /// **'Merge completed'**
  String get desktopMergerStageCompleted;

  /// No description provided for @desktopMergerLiveStats.
  ///
  /// In en, this message translates to:
  /// **'Live Statistics'**
  String get desktopMergerLiveStats;

  /// No description provided for @desktopMergerProcessingFile.
  ///
  /// In en, this message translates to:
  /// **'Processing: {fileName}'**
  String desktopMergerProcessingFile(Object fileName);

  /// No description provided for @desktopMergerFileProgress.
  ///
  /// In en, this message translates to:
  /// **'File Progress: {current}/{total}'**
  String desktopMergerFileProgress(Object current, Object total);

  /// No description provided for @desktopMergerStatScreenshots.
  ///
  /// In en, this message translates to:
  /// **'New Screenshots'**
  String get desktopMergerStatScreenshots;

  /// No description provided for @desktopMergerStatSkipped.
  ///
  /// In en, this message translates to:
  /// **'Skipped Duplicates'**
  String get desktopMergerStatSkipped;

  /// No description provided for @desktopMergerStatFiles.
  ///
  /// In en, this message translates to:
  /// **'Copied Files'**
  String get desktopMergerStatFiles;

  /// No description provided for @desktopMergerStatReused.
  ///
  /// In en, this message translates to:
  /// **'Reused Files'**
  String get desktopMergerStatReused;

  /// No description provided for @desktopMergerStatTags.
  ///
  /// In en, this message translates to:
  /// **'Memory Tags'**
  String get desktopMergerStatTags;

  /// No description provided for @desktopMergerStatEvidence.
  ///
  /// In en, this message translates to:
  /// **'Memory Evidence'**
  String get desktopMergerStatEvidence;

  /// No description provided for @desktopMergerSummaryTitle.
  ///
  /// In en, this message translates to:
  /// **'Merge Summary'**
  String get desktopMergerSummaryTitle;

  /// No description provided for @desktopMergerSummaryTotal.
  ///
  /// In en, this message translates to:
  /// **'Processed {count} files in total'**
  String desktopMergerSummaryTotal(Object count);

  /// No description provided for @desktopMergerSummarySuccess.
  ///
  /// In en, this message translates to:
  /// **'Success: {count}'**
  String desktopMergerSummarySuccess(Object count);

  /// No description provided for @desktopMergerSummaryFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed: {count}'**
  String desktopMergerSummaryFailed(Object count);

  /// No description provided for @desktopMergerAffectedApps.
  ///
  /// In en, this message translates to:
  /// **'Affected Apps ({count})'**
  String desktopMergerAffectedApps(Object count);

  /// No description provided for @desktopMergerWarnings.
  ///
  /// In en, this message translates to:
  /// **'Warnings ({count})'**
  String desktopMergerWarnings(Object count);

  /// No description provided for @desktopMergerDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Detailed Results'**
  String get desktopMergerDetailTitle;

  /// No description provided for @desktopMergerFileSuccess.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get desktopMergerFileSuccess;

  /// No description provided for @desktopMergerFileFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get desktopMergerFileFailed;

  /// No description provided for @desktopMergerNoData.
  ///
  /// In en, this message translates to:
  /// **'No data changes'**
  String get desktopMergerNoData;

  /// No description provided for @desktopMergerExpandAll.
  ///
  /// In en, this message translates to:
  /// **'Expand All'**
  String get desktopMergerExpandAll;

  /// No description provided for @desktopMergerCollapseAll.
  ///
  /// In en, this message translates to:
  /// **'Collapse All'**
  String get desktopMergerCollapseAll;

  /// No description provided for @desktopMergerStagePacking.
  ///
  /// In en, this message translates to:
  /// **'Packing ZIP...'**
  String get desktopMergerStagePacking;

  /// No description provided for @desktopMergerOutputZip.
  ///
  /// In en, this message translates to:
  /// **'Output File'**
  String get desktopMergerOutputZip;

  /// No description provided for @desktopMergerOpenFolder.
  ///
  /// In en, this message translates to:
  /// **'Open Folder'**
  String get desktopMergerOpenFolder;

  /// No description provided for @desktopMergerPackingProgress.
  ///
  /// In en, this message translates to:
  /// **'Packing: {percent}%'**
  String desktopMergerPackingProgress(Object percent);

  /// No description provided for @desktopMergerMinFilesHint.
  ///
  /// In en, this message translates to:
  /// **'Please select at least 2 backup files to merge'**
  String get desktopMergerMinFilesHint;

  /// No description provided for @desktopMergerExtractingHint.
  ///
  /// In en, this message translates to:
  /// **'Extracting backup file. Large backups (tens of thousands of screenshots) may take several minutes, please be patient...'**
  String get desktopMergerExtractingHint;

  /// No description provided for @desktopMergerCopyingHint.
  ///
  /// In en, this message translates to:
  /// **'Copying screenshot files, skipping existing images...'**
  String get desktopMergerCopyingHint;

  /// No description provided for @desktopMergerMergingHint.
  ///
  /// In en, this message translates to:
  /// **'Merging database records with smart deduplication...'**
  String get desktopMergerMergingHint;

  /// No description provided for @desktopMergerPackingHint.
  ///
  /// In en, this message translates to:
  /// **'Packing merged results into ZIP file...'**
  String get desktopMergerPackingHint;

  /// No description provided for @unknownTitle.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknownTitle;

  /// No description provided for @unknownTime.
  ///
  /// In en, this message translates to:
  /// **'Unknown time'**
  String get unknownTime;

  /// No description provided for @empty.
  ///
  /// In en, this message translates to:
  /// **'Empty'**
  String get empty;

  /// No description provided for @evidenceTitle.
  ///
  /// In en, this message translates to:
  /// **'Evidence'**
  String get evidenceTitle;

  /// No description provided for @runtimeDiagnosticCopied.
  ///
  /// In en, this message translates to:
  /// **'Diagnostic info copied'**
  String get runtimeDiagnosticCopied;

  /// No description provided for @runtimeDiagnosticCopyFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to copy diagnostic info'**
  String get runtimeDiagnosticCopyFailed;

  /// No description provided for @runtimeDiagnosticNoFileToOpen.
  ///
  /// In en, this message translates to:
  /// **'No diagnostic file available to open'**
  String get runtimeDiagnosticNoFileToOpen;

  /// No description provided for @runtimeDiagnosticOpenAttempted.
  ///
  /// In en, this message translates to:
  /// **'Tried to open diagnostic file'**
  String get runtimeDiagnosticOpenAttempted;

  /// No description provided for @runtimeDiagnosticOpenFallbackCopiedPath.
  ///
  /// In en, this message translates to:
  /// **'Could not open directly; log path copied'**
  String get runtimeDiagnosticOpenFallbackCopiedPath;

  /// No description provided for @runtimeDiagnosticCopyInfoAction.
  ///
  /// In en, this message translates to:
  /// **'Copy info'**
  String get runtimeDiagnosticCopyInfoAction;

  /// No description provided for @runtimeDiagnosticOpenFileAction.
  ///
  /// In en, this message translates to:
  /// **'Open this file'**
  String get runtimeDiagnosticOpenFileAction;

  /// No description provided for @runtimeDiagnosticOpenSettingsAction.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get runtimeDiagnosticOpenSettingsAction;

  /// No description provided for @importDiagnosticsReportCopied.
  ///
  /// In en, this message translates to:
  /// **'Diagnostic report copied'**
  String get importDiagnosticsReportCopied;

  /// No description provided for @importDiagnosticsNoRepairableOcr.
  ///
  /// In en, this message translates to:
  /// **'No OCR text needs repair; diagnostics refreshed'**
  String get importDiagnosticsNoRepairableOcr;

  /// No description provided for @importDiagnosticsOcrRepairStarted.
  ///
  /// In en, this message translates to:
  /// **'Repair started in the background. Check notification progress.'**
  String get importDiagnosticsOcrRepairStarted;

  /// No description provided for @importDiagnosticsOcrRepairResumed.
  ///
  /// In en, this message translates to:
  /// **'Background repair resumed. Check notification progress.'**
  String get importDiagnosticsOcrRepairResumed;

  /// No description provided for @importDiagnosticsOcrRepairStopped.
  ///
  /// In en, this message translates to:
  /// **'OCR text repair stopped'**
  String get importDiagnosticsOcrRepairStopped;

  /// No description provided for @importDiagnosticsStopRepairFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to stop repair'**
  String get importDiagnosticsStopRepairFailed;

  /// No description provided for @importDiagnosticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Import diagnostics'**
  String get importDiagnosticsTitle;

  /// No description provided for @importDiagnosticsFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics failed'**
  String get importDiagnosticsFailedTitle;

  /// No description provided for @importDiagnosticsDurationMs.
  ///
  /// In en, this message translates to:
  /// **'Duration: {durationMs}ms'**
  String importDiagnosticsDurationMs(Object durationMs);

  /// No description provided for @importDiagnosticsBackgroundRepairTask.
  ///
  /// In en, this message translates to:
  /// **'Background repair task'**
  String get importDiagnosticsBackgroundRepairTask;

  /// No description provided for @importDiagnosticsStopRepair.
  ///
  /// In en, this message translates to:
  /// **'Stop repair'**
  String get importDiagnosticsStopRepair;

  /// No description provided for @importDiagnosticsRepairIndex.
  ///
  /// In en, this message translates to:
  /// **'Repair index'**
  String get importDiagnosticsRepairIndex;

  /// No description provided for @memoryTabView.
  ///
  /// In en, this message translates to:
  /// **'View memory'**
  String get memoryTabView;

  /// No description provided for @memoryTabRebuild.
  ///
  /// In en, this message translates to:
  /// **'One-tap rebuild'**
  String get memoryTabRebuild;

  /// No description provided for @memorySignalStatusChip.
  ///
  /// In en, this message translates to:
  /// **'{label} {count}'**
  String memorySignalStatusChip(Object label, Object count);

  /// No description provided for @memoryForceCreate.
  ///
  /// In en, this message translates to:
  /// **'Force create'**
  String get memoryForceCreate;

  /// No description provided for @actionIgnore.
  ///
  /// In en, this message translates to:
  /// **'Ignore'**
  String get actionIgnore;

  /// No description provided for @memoryGenerateSuggestions.
  ///
  /// In en, this message translates to:
  /// **'Generate suggestions'**
  String get memoryGenerateSuggestions;

  /// No description provided for @memoryApplyAllSuggestions.
  ///
  /// In en, this message translates to:
  /// **'Apply all'**
  String get memoryApplyAllSuggestions;

  /// No description provided for @memoryApplyThisSuggestion.
  ///
  /// In en, this message translates to:
  /// **'Apply this'**
  String get memoryApplyThisSuggestion;

  /// No description provided for @memoryDontApplySuggestion.
  ///
  /// In en, this message translates to:
  /// **'Do not apply'**
  String get memoryDontApplySuggestion;

  /// No description provided for @memoryCopyError.
  ///
  /// In en, this message translates to:
  /// **'Copy error'**
  String get memoryCopyError;

  /// No description provided for @actionDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get actionDescription;

  /// No description provided for @memoryRebuildAction.
  ///
  /// In en, this message translates to:
  /// **'One-tap rebuild'**
  String get memoryRebuildAction;

  /// No description provided for @actionStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get actionStop;

  /// No description provided for @memoryUriInputHint.
  ///
  /// In en, this message translates to:
  /// **'Enter URI (e.g. core://my_user)'**
  String get memoryUriInputHint;

  /// No description provided for @memorySearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search memory content/path…'**
  String get memorySearchHint;

  /// No description provided for @memoryRoot.
  ///
  /// In en, this message translates to:
  /// **'Root'**
  String get memoryRoot;

  /// No description provided for @memoryParent.
  ///
  /// In en, this message translates to:
  /// **'Parent'**
  String get memoryParent;

  /// No description provided for @memoryBoot.
  ///
  /// In en, this message translates to:
  /// **'Boot'**
  String get memoryBoot;

  /// No description provided for @memoryRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get memoryRecent;

  /// No description provided for @memoryIndex.
  ///
  /// In en, this message translates to:
  /// **'Index'**
  String get memoryIndex;

  /// No description provided for @providerAddAtLeastOneEnabledApiKey.
  ///
  /// In en, this message translates to:
  /// **'Please add at least one enabled API Key.'**
  String get providerAddAtLeastOneEnabledApiKey;

  /// No description provided for @providerSaveBeforeBatchTest.
  ///
  /// In en, this message translates to:
  /// **'Please save the provider before running batch test.'**
  String get providerSaveBeforeBatchTest;

  /// No description provided for @providerKeepOneEnabledApiKey.
  ///
  /// In en, this message translates to:
  /// **'Please keep at least one enabled and non-empty API Key.'**
  String get providerKeepOneEnabledApiKey;

  /// No description provided for @providerBatchTestFailed.
  ///
  /// In en, this message translates to:
  /// **'Batch test failed. Please try again later.'**
  String get providerBatchTestFailed;

  /// No description provided for @providerBatchTestResultTitle.
  ///
  /// In en, this message translates to:
  /// **'Batch test results'**
  String get providerBatchTestResultTitle;

  /// No description provided for @actionClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get actionClose;

  /// No description provided for @providerOnlyOneApiKeyCanEdit.
  ///
  /// In en, this message translates to:
  /// **'Only one API Key can be edited at a time'**
  String get providerOnlyOneApiKeyCanEdit;

  /// No description provided for @providerAddApiKey.
  ///
  /// In en, this message translates to:
  /// **'Add API Key'**
  String get providerAddApiKey;

  /// No description provided for @providerEditApiKey.
  ///
  /// In en, this message translates to:
  /// **'Edit API Key'**
  String get providerEditApiKey;

  /// No description provided for @providerFetchModelsAndBalance.
  ///
  /// In en, this message translates to:
  /// **'Fetch models and balance'**
  String get providerFetchModelsAndBalance;

  /// No description provided for @actionSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving'**
  String get actionSaving;

  /// No description provided for @providerFetchModelsFailedManual.
  ///
  /// In en, this message translates to:
  /// **'Failed to fetch models. You can add them manually.'**
  String get providerFetchModelsFailedManual;

  /// No description provided for @providerDeletedApiKeys.
  ///
  /// In en, this message translates to:
  /// **'Deleted {count} API Keys'**
  String providerDeletedApiKeys(Object count);

  /// No description provided for @providerAddKeyButton.
  ///
  /// In en, this message translates to:
  /// **'Add Key'**
  String get providerAddKeyButton;

  /// No description provided for @providerBatchTestButton.
  ///
  /// In en, this message translates to:
  /// **'Batch test'**
  String get providerBatchTestButton;

  /// No description provided for @providerDeleteAllKeys.
  ///
  /// In en, this message translates to:
  /// **'Delete all'**
  String get providerDeleteAllKeys;

  /// No description provided for @providerNoApiKeys.
  ///
  /// In en, this message translates to:
  /// **'No API Keys.'**
  String get providerNoApiKeys;

  /// No description provided for @balanceEndpointNone.
  ///
  /// In en, this message translates to:
  /// **'Do not query'**
  String get balanceEndpointNone;

  /// No description provided for @balanceEndpointNewApi.
  ///
  /// In en, this message translates to:
  /// **'new-api (/dashboard/billing)'**
  String get balanceEndpointNewApi;

  /// No description provided for @balanceEndpointSub2api.
  ///
  /// In en, this message translates to:
  /// **'sub2api (/v1/usage)'**
  String get balanceEndpointSub2api;

  /// No description provided for @segmentEntryLogHint.
  ///
  /// In en, this message translates to:
  /// **'Long-press to select text, or tap Copy to copy everything.'**
  String get segmentEntryLogHint;

  /// No description provided for @segmentEntryLogCopied.
  ///
  /// In en, this message translates to:
  /// **'Dynamic entry log copied'**
  String get segmentEntryLogCopied;

  /// No description provided for @copyLogAction.
  ///
  /// In en, this message translates to:
  /// **'Copy log'**
  String get copyLogAction;

  /// No description provided for @segmentDynamicConcurrencySaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to save day concurrency'**
  String get segmentDynamicConcurrencySaveFailed;

  /// No description provided for @dynamicAutoRepairEnabled.
  ///
  /// In en, this message translates to:
  /// **'Auto repair enabled'**
  String get dynamicAutoRepairEnabled;

  /// No description provided for @dynamicAutoRepairPaused.
  ///
  /// In en, this message translates to:
  /// **'Auto repair paused'**
  String get dynamicAutoRepairPaused;

  /// No description provided for @dynamicAutoRepairToggleFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to toggle auto repair'**
  String get dynamicAutoRepairToggleFailed;

  /// No description provided for @dynamicRebuildStart.
  ///
  /// In en, this message translates to:
  /// **'Start rebuild'**
  String get dynamicRebuildStart;

  /// No description provided for @dynamicRebuildContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue rebuild'**
  String get dynamicRebuildContinue;

  /// No description provided for @savedToPath.
  ///
  /// In en, this message translates to:
  /// **'Saved to: {path}'**
  String savedToPath(Object path);

  /// No description provided for @dynamicRebuildNoSegments.
  ///
  /// In en, this message translates to:
  /// **'No dynamics to rebuild'**
  String get dynamicRebuildNoSegments;

  /// No description provided for @dynamicRebuildSwitchedModelContinue.
  ///
  /// In en, this message translates to:
  /// **'Switched to model {model} and continued rebuild'**
  String dynamicRebuildSwitchedModelContinue(Object model);

  /// No description provided for @dynamicRebuildStartedInBackground.
  ///
  /// In en, this message translates to:
  /// **'Rebuild started in the background. Check notification progress.'**
  String get dynamicRebuildStartedInBackground;

  /// No description provided for @dynamicRebuildTaskResumed.
  ///
  /// In en, this message translates to:
  /// **'Background rebuild task resumed'**
  String get dynamicRebuildTaskResumed;

  /// No description provided for @dynamicRebuildStopped.
  ///
  /// In en, this message translates to:
  /// **'Dynamic rebuild stopped'**
  String get dynamicRebuildStopped;

  /// No description provided for @dynamicRebuildStopFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to stop dynamic rebuild'**
  String get dynamicRebuildStopFailed;

  /// No description provided for @dynamicRebuildBlockedRetry.
  ///
  /// In en, this message translates to:
  /// **'Full rebuild is running. Single-item regeneration is temporarily disabled.'**
  String get dynamicRebuildBlockedRetry;

  /// No description provided for @dynamicRebuildBlockedForceMerge.
  ///
  /// In en, this message translates to:
  /// **'Full rebuild is running. Manual force merge is temporarily disabled.'**
  String get dynamicRebuildBlockedForceMerge;

  /// No description provided for @rawResponseRetentionDaysTitle.
  ///
  /// In en, this message translates to:
  /// **'Set retention days'**
  String get rawResponseRetentionDaysTitle;

  /// No description provided for @rawResponseRetentionDaysLabel.
  ///
  /// In en, this message translates to:
  /// **'Retention days'**
  String get rawResponseRetentionDaysLabel;

  /// No description provided for @rawResponseRetentionDaysHint.
  ///
  /// In en, this message translates to:
  /// **'Enter a number > 0'**
  String get rawResponseRetentionDaysHint;

  /// No description provided for @rawResponseCleanupSaved.
  ///
  /// In en, this message translates to:
  /// **'Raw response cleanup settings saved.'**
  String get rawResponseCleanupSaved;

  /// No description provided for @chatContextTitlePrefix.
  ///
  /// In en, this message translates to:
  /// **'Conversation Context ('**
  String get chatContextTitlePrefix;

  /// No description provided for @chatContextTitleMemory.
  ///
  /// In en, this message translates to:
  /// **'Memory'**
  String get chatContextTitleMemory;

  /// No description provided for @chatContextTitleSuffix.
  ///
  /// In en, this message translates to:
  /// **')'**
  String get chatContextTitleSuffix;

  /// No description provided for @rawResponseRetentionUpdatedDays.
  ///
  /// In en, this message translates to:
  /// **'Retention updated to {days} days.'**
  String rawResponseRetentionUpdatedDays(Object days);

  /// No description provided for @homeMorningTipsUpdated.
  ///
  /// In en, this message translates to:
  /// **'Morning tips updated'**
  String get homeMorningTipsUpdated;

  /// No description provided for @homeMorningTipsGenerateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to generate morning tips'**
  String get homeMorningTipsGenerateFailed;

  /// No description provided for @eventCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Create failed: {error}'**
  String eventCreateFailed(Object error);

  /// No description provided for @eventSwitchFailed.
  ///
  /// In en, this message translates to:
  /// **'Switch failed: {error}'**
  String eventSwitchFailed(Object error);

  /// No description provided for @eventSessionSwitched.
  ///
  /// In en, this message translates to:
  /// **'Conversation switched'**
  String get eventSessionSwitched;

  /// No description provided for @eventSessionDeleted.
  ///
  /// In en, this message translates to:
  /// **'Conversation deleted'**
  String get eventSessionDeleted;

  /// No description provided for @exclusionExcludedAppsTitle.
  ///
  /// In en, this message translates to:
  /// **'Excluded apps'**
  String get exclusionExcludedAppsTitle;

  /// No description provided for @exclusionSelfAppBullet.
  ///
  /// In en, this message translates to:
  /// **'· This app (avoid self-loop)'**
  String get exclusionSelfAppBullet;

  /// No description provided for @exclusionImeAppsBullet.
  ///
  /// In en, this message translates to:
  /// **'· Input method (keyboard) apps:'**
  String get exclusionImeAppsBullet;

  /// No description provided for @exclusionAutoFilteredBullet.
  ///
  /// In en, this message translates to:
  /// **'  - (automatically filtered)'**
  String get exclusionAutoFilteredBullet;

  /// No description provided for @exclusionUnknownIme.
  ///
  /// In en, this message translates to:
  /// **'Unknown input method'**
  String get exclusionUnknownIme;

  /// No description provided for @exclusionImeAppBullet.
  ///
  /// In en, this message translates to:
  /// **'  - {name}'**
  String exclusionImeAppBullet(Object name);

  /// No description provided for @imageError.
  ///
  /// In en, this message translates to:
  /// **'Image Error'**
  String get imageError;

  /// No description provided for @logDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Log detail'**
  String get logDetailTitle;

  /// No description provided for @logLevelAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get logLevelAll;

  /// No description provided for @logLevelDebugVerbose.
  ///
  /// In en, this message translates to:
  /// **'Debug/Verbose'**
  String get logLevelDebugVerbose;

  /// No description provided for @logLevelInfo.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get logLevelInfo;

  /// No description provided for @logLevelWarning.
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get logLevelWarning;

  /// No description provided for @logLevelErrorSevere.
  ///
  /// In en, this message translates to:
  /// **'Error/Severe'**
  String get logLevelErrorSevere;

  /// No description provided for @logSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search title/content/exception/stack'**
  String get logSearchHint;

  /// No description provided for @onboardingPermissionLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load permission status: {error}'**
  String onboardingPermissionLoadFailed(Object error);

  /// No description provided for @permissionGuideSettingsOpened.
  ///
  /// In en, this message translates to:
  /// **'App settings opened. Please follow the guide.'**
  String get permissionGuideSettingsOpened;

  /// No description provided for @permissionGuideOpenSettingsFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to open settings page: {error}'**
  String permissionGuideOpenSettingsFailed(Object error);

  /// No description provided for @permissionGuideBatteryOpened.
  ///
  /// In en, this message translates to:
  /// **'Battery optimization settings opened'**
  String get permissionGuideBatteryOpened;

  /// No description provided for @permissionGuideOpenBatteryFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to open battery optimization settings: {error}'**
  String permissionGuideOpenBatteryFailed(Object error);

  /// No description provided for @permissionGuideAutostartOpened.
  ///
  /// In en, this message translates to:
  /// **'Autostart settings opened'**
  String get permissionGuideAutostartOpened;

  /// No description provided for @permissionGuideOpenAutostartFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to open autostart settings: {error}'**
  String permissionGuideOpenAutostartFailed(Object error);

  /// No description provided for @permissionGuideCompleted.
  ///
  /// In en, this message translates to:
  /// **'Permission setup marked as complete'**
  String get permissionGuideCompleted;

  /// No description provided for @permissionGuideCompleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to mark permission setup: {error}'**
  String permissionGuideCompleteFailed(Object error);

  /// No description provided for @permissionGuideTitle.
  ///
  /// In en, this message translates to:
  /// **'Permission setup guide'**
  String get permissionGuideTitle;

  /// No description provided for @permissionGuideOpenAppSettings.
  ///
  /// In en, this message translates to:
  /// **'Open app settings'**
  String get permissionGuideOpenAppSettings;

  /// No description provided for @permissionGuideOpenBatterySettings.
  ///
  /// In en, this message translates to:
  /// **'Open battery optimization settings'**
  String get permissionGuideOpenBatterySettings;

  /// No description provided for @permissionGuideOpenAutostartSettings.
  ///
  /// In en, this message translates to:
  /// **'Open autostart settings'**
  String get permissionGuideOpenAutostartSettings;

  /// No description provided for @permissionGuideAllDone.
  ///
  /// In en, this message translates to:
  /// **'I have completed all settings'**
  String get permissionGuideAllDone;

  /// No description provided for @galleryDeleting.
  ///
  /// In en, this message translates to:
  /// **'Deleting...'**
  String get galleryDeleting;

  /// No description provided for @galleryCleaningCache.
  ///
  /// In en, this message translates to:
  /// **'Cleaning cache...'**
  String get galleryCleaningCache;

  /// No description provided for @favoriteRemoved.
  ///
  /// In en, this message translates to:
  /// **'Removed from favorites'**
  String get favoriteRemoved;

  /// No description provided for @favoriteAdded.
  ///
  /// In en, this message translates to:
  /// **'Added to favorites'**
  String get favoriteAdded;

  /// No description provided for @operationFailedWithError.
  ///
  /// In en, this message translates to:
  /// **'Operation failed: {error}'**
  String operationFailedWithError(Object error);

  /// No description provided for @searchSemantic.
  ///
  /// In en, this message translates to:
  /// **'Semantic search'**
  String get searchSemantic;

  /// No description provided for @searchDynamic.
  ///
  /// In en, this message translates to:
  /// **'Search dynamics'**
  String get searchDynamic;

  /// No description provided for @searchMore.
  ///
  /// In en, this message translates to:
  /// **'Search more'**
  String get searchMore;

  /// No description provided for @openDailySummary.
  ///
  /// In en, this message translates to:
  /// **'Open daily summary'**
  String get openDailySummary;

  /// No description provided for @openWeeklySummary.
  ///
  /// In en, this message translates to:
  /// **'Open weekly summary'**
  String get openWeeklySummary;

  /// No description provided for @noAvailableTags.
  ///
  /// In en, this message translates to:
  /// **'No available tags'**
  String get noAvailableTags;

  /// No description provided for @clearFilter.
  ///
  /// In en, this message translates to:
  /// **'Clear filter'**
  String get clearFilter;

  /// No description provided for @forceMerge.
  ///
  /// In en, this message translates to:
  /// **'Force merge'**
  String get forceMerge;

  /// No description provided for @forceMergeNoPrevious.
  ///
  /// In en, this message translates to:
  /// **'No previous event to merge'**
  String get forceMergeNoPrevious;

  /// No description provided for @forceMergeQueuedFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to queue force merge'**
  String get forceMergeQueuedFailed;

  /// No description provided for @forceMergeQueued.
  ///
  /// In en, this message translates to:
  /// **'Force merge queued'**
  String get forceMergeQueued;

  /// No description provided for @forceMergeFailed.
  ///
  /// In en, this message translates to:
  /// **'Force merge failed'**
  String get forceMergeFailed;

  /// No description provided for @mergeCompleted.
  ///
  /// In en, this message translates to:
  /// **'Merge completed'**
  String get mergeCompleted;

  /// No description provided for @numberInputRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter a number.'**
  String get numberInputRequired;

  /// No description provided for @valueSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved: {value}'**
  String valueSaved(Object value);

  /// No description provided for @openChannelSettingsFailed.
  ///
  /// In en, this message translates to:
  /// **'Open channel settings failed: {error}'**
  String openChannelSettingsFailed(Object error);

  /// No description provided for @openAppNotificationSettingsFailed.
  ///
  /// In en, this message translates to:
  /// **'Open app notification settings failed: {error}'**
  String openAppNotificationSettingsFailed(Object error);

  /// No description provided for @evidencePrefix.
  ///
  /// In en, this message translates to:
  /// **'[evidence: '**
  String get evidencePrefix;

  /// No description provided for @actionMenu.
  ///
  /// In en, this message translates to:
  /// **'Menu'**
  String get actionMenu;

  /// No description provided for @actionShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get actionShare;

  /// No description provided for @actionResetToDefault.
  ///
  /// In en, this message translates to:
  /// **'Reset to default'**
  String get actionResetToDefault;

  /// No description provided for @homeMorningTipNumberedTitle.
  ///
  /// In en, this message translates to:
  /// **'{index}. {title}'**
  String homeMorningTipNumberedTitle(Object index, Object title);

  /// No description provided for @homeMorningTipsRawTitle.
  ///
  /// In en, this message translates to:
  /// **'Morning tips RAW'**
  String get homeMorningTipsRawTitle;

  /// No description provided for @labelWithColon.
  ///
  /// In en, this message translates to:
  /// **'{label}: '**
  String labelWithColon(Object label);

  /// No description provided for @warningBullet.
  ///
  /// In en, this message translates to:
  /// **'• {warning}'**
  String warningBullet(Object warning);

  /// No description provided for @resetToDefaultValue.
  ///
  /// In en, this message translates to:
  /// **'Reset to default: {value}'**
  String resetToDefaultValue(Object value);

  /// No description provided for @logPanelTitle.
  ///
  /// In en, this message translates to:
  /// **'Log panel'**
  String get logPanelTitle;

  /// No description provided for @logCopiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get logCopiedToClipboard;

  /// No description provided for @logShareText.
  ///
  /// In en, this message translates to:
  /// **'ScreenMemo logs'**
  String get logShareText;

  /// No description provided for @logShareFailed.
  ///
  /// In en, this message translates to:
  /// **'Share failed'**
  String get logShareFailed;

  /// No description provided for @logCleared.
  ///
  /// In en, this message translates to:
  /// **'Logs cleared'**
  String get logCleared;

  /// No description provided for @logClearFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to clear logs'**
  String get logClearFailed;

  /// No description provided for @logNoLogs.
  ///
  /// In en, this message translates to:
  /// **'No logs yet'**
  String get logNoLogs;

  /// No description provided for @logNoMatchingLogs.
  ///
  /// In en, this message translates to:
  /// **'No matching logs'**
  String get logNoMatchingLogs;

  /// No description provided for @logFilterTooltip.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get logFilterTooltip;

  /// No description provided for @logSortNewestFirst.
  ///
  /// In en, this message translates to:
  /// **'Newest first'**
  String get logSortNewestFirst;

  /// No description provided for @logSortOldestFirst.
  ///
  /// In en, this message translates to:
  /// **'Oldest first'**
  String get logSortOldestFirst;

  /// No description provided for @logLevelCritical.
  ///
  /// In en, this message translates to:
  /// **'Critical'**
  String get logLevelCritical;

  /// No description provided for @logLevelError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get logLevelError;

  /// No description provided for @logLevelVerbose.
  ///
  /// In en, this message translates to:
  /// **'Verbose'**
  String get logLevelVerbose;

  /// No description provided for @logLevelDebug.
  ///
  /// In en, this message translates to:
  /// **'Debug'**
  String get logLevelDebug;

  /// No description provided for @eventNewConversation.
  ///
  /// In en, this message translates to:
  /// **'New conversation'**
  String get eventNewConversation;

  /// No description provided for @forceMergeConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Force merge with the previous event, overwrite the current event summary, and delete the previous event. This cannot be undone. Continue?'**
  String get forceMergeConfirmMessage;

  /// No description provided for @forceMergeRequestedReason.
  ///
  /// In en, this message translates to:
  /// **'Force merge requested (queued)'**
  String get forceMergeRequestedReason;

  /// No description provided for @mergeStatusMerging.
  ///
  /// In en, this message translates to:
  /// **'Force merging…'**
  String get mergeStatusMerging;

  /// No description provided for @mergeStatusMerged.
  ///
  /// In en, this message translates to:
  /// **'Merged'**
  String get mergeStatusMerged;

  /// No description provided for @mergeStatusForceRequested.
  ///
  /// In en, this message translates to:
  /// **'Force merge requested'**
  String get mergeStatusForceRequested;

  /// No description provided for @mergeStatusNotMerged.
  ///
  /// In en, this message translates to:
  /// **'Not merged'**
  String get mergeStatusNotMerged;

  /// No description provided for @mergeStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get mergeStatusPending;

  /// No description provided for @semanticSearchNotStartedTitle.
  ///
  /// In en, this message translates to:
  /// **'Semantic search not started'**
  String get semanticSearchNotStartedTitle;

  /// No description provided for @semanticSearchNotStartedDesc.
  ///
  /// In en, this message translates to:
  /// **'This searches AI descriptions, keywords, and tags for images. To avoid lag while typing, start the search manually.'**
  String get semanticSearchNotStartedDesc;

  /// No description provided for @segmentSearchNotStartedTitle.
  ///
  /// In en, this message translates to:
  /// **'Dynamic search not started'**
  String get segmentSearchNotStartedTitle;

  /// No description provided for @segmentSearchNotStartedDesc.
  ///
  /// In en, this message translates to:
  /// **'To avoid lag while typing, start the search manually.'**
  String get segmentSearchNotStartedDesc;

  /// No description provided for @foundImagesCount.
  ///
  /// In en, this message translates to:
  /// **'Found {count} images'**
  String foundImagesCount(Object count);

  /// No description provided for @tagsLabel.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get tagsLabel;

  /// No description provided for @tagCount.
  ///
  /// In en, this message translates to:
  /// **'{count} tags'**
  String tagCount(Object count);

  /// No description provided for @tagFilterTitle.
  ///
  /// In en, this message translates to:
  /// **'Tag filters'**
  String get tagFilterTitle;

  /// No description provided for @selectedAllLabel.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get selectedAllLabel;

  /// No description provided for @selectedTagsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String selectedTagsCount(Object count);

  /// No description provided for @selectedTypesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String selectedTypesCount(Object count);

  /// No description provided for @confirmSelectionLabel.
  ///
  /// In en, this message translates to:
  /// **'OK ({selection})'**
  String confirmSelectionLabel(Object selection);

  /// No description provided for @noContentParenthesized.
  ///
  /// In en, this message translates to:
  /// **'(empty)'**
  String get noContentParenthesized;

  /// No description provided for @typeFilterTitle.
  ///
  /// In en, this message translates to:
  /// **'Type filters'**
  String get typeFilterTitle;

  /// No description provided for @rawResponseCleanupEnableTitle.
  ///
  /// In en, this message translates to:
  /// **'Enable Raw Response Cleanup'**
  String get rawResponseCleanupEnableTitle;

  /// No description provided for @rawResponseCleanupEnableMessage.
  ///
  /// In en, this message translates to:
  /// **'This will automatically clear raw_response older than {days} days. Summaries and structured_json are not affected.'**
  String rawResponseCleanupEnableMessage(Object days);

  /// No description provided for @rawResponseCleanupEnableAction.
  ///
  /// In en, this message translates to:
  /// **'Enable & Clean Now'**
  String get rawResponseCleanupEnableAction;

  /// No description provided for @segmentsJsonAutoRetryHint.
  ///
  /// In en, this message translates to:
  /// **'Times (0-5)'**
  String get segmentsJsonAutoRetryHint;

  /// No description provided for @rawResponseCleanupTitle.
  ///
  /// In en, this message translates to:
  /// **'Auto Clean Raw Responses'**
  String get rawResponseCleanupTitle;

  /// No description provided for @rawResponseCleanupKeepLabel.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get rawResponseCleanupKeepLabel;

  /// No description provided for @rawResponseCleanupRetentionDays.
  ///
  /// In en, this message translates to:
  /// **'{days} days'**
  String rawResponseCleanupRetentionDays(Object days);

  /// No description provided for @rawResponseCleanupDesc.
  ///
  /// In en, this message translates to:
  /// **'Only clears old raw_response; summaries and structured_json stay untouched'**
  String get rawResponseCleanupDesc;

  /// No description provided for @mergeStatusMergingReason.
  ///
  /// In en, this message translates to:
  /// **'Merging, please wait…'**
  String get mergeStatusMergingReason;

  /// No description provided for @permissionGuideLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading permission setup guide...'**
  String get permissionGuideLoading;

  /// No description provided for @permissionGuideUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unable to get permission setup guide'**
  String get permissionGuideUnavailable;

  /// No description provided for @permissionGuideUnknownDevice.
  ///
  /// In en, this message translates to:
  /// **'Unknown device'**
  String get permissionGuideUnknownDevice;

  /// No description provided for @permissionGuideLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load permission setup guide: {error}'**
  String permissionGuideLoadFailed(Object error);

  /// No description provided for @deviceInfoTitle.
  ///
  /// In en, this message translates to:
  /// **'Device info'**
  String get deviceInfoTitle;

  /// No description provided for @setupGuideTitle.
  ///
  /// In en, this message translates to:
  /// **'Setup guide'**
  String get setupGuideTitle;

  /// No description provided for @permissionConfiguredStatus.
  ///
  /// In en, this message translates to:
  /// **'Configured'**
  String get permissionConfiguredStatus;

  /// No description provided for @permissionNeedsConfigurationStatus.
  ///
  /// In en, this message translates to:
  /// **'Needs configuration'**
  String get permissionNeedsConfigurationStatus;

  /// No description provided for @backgroundPermissionTitle.
  ///
  /// In en, this message translates to:
  /// **'Background run permission'**
  String get backgroundPermissionTitle;

  /// No description provided for @actualBatteryOptimizationStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'Actual battery optimization status'**
  String get actualBatteryOptimizationStatusTitle;

  /// No description provided for @keyDialogProviderNotSavedHint.
  ///
  /// In en, this message translates to:
  /// **'Please save the provider before adding API keys.'**
  String get keyDialogProviderNotSavedHint;

  /// No description provided for @keyDialogNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Key name'**
  String get keyDialogNameLabel;

  /// No description provided for @keyDialogApiKeyLabel.
  ///
  /// In en, this message translates to:
  /// **'API Key'**
  String get keyDialogApiKeyLabel;

  /// No description provided for @keyDialogApiKeyLabelMulti.
  ///
  /// In en, this message translates to:
  /// **'API Key (one per line)'**
  String get keyDialogApiKeyLabelMulti;

  /// No description provided for @keyDialogApiKeyHintMulti.
  ///
  /// In en, this message translates to:
  /// **'One API Key per line. Fetch scans every key.'**
  String get keyDialogApiKeyHintMulti;

  /// No description provided for @keyDialogPriorityLabel.
  ///
  /// In en, this message translates to:
  /// **'Priority (100 = dynamic allocation)'**
  String get keyDialogPriorityLabel;

  /// No description provided for @keyDialogModelsLabel.
  ///
  /// In en, this message translates to:
  /// **'Supported models (one per line)'**
  String get keyDialogModelsLabel;

  /// No description provided for @keyDialogPhaseFetchModels.
  ///
  /// In en, this message translates to:
  /// **'Fetch models'**
  String get keyDialogPhaseFetchModels;

  /// No description provided for @keyDialogPhaseFetchBalance.
  ///
  /// In en, this message translates to:
  /// **'Fetch balance'**
  String get keyDialogPhaseFetchBalance;

  /// No description provided for @keyDialogPhaseScanKeys.
  ///
  /// In en, this message translates to:
  /// **'Scan keys'**
  String get keyDialogPhaseScanKeys;

  /// No description provided for @keyDialogPhaseSaveKeys.
  ///
  /// In en, this message translates to:
  /// **'Save keys'**
  String get keyDialogPhaseSaveKeys;

  /// No description provided for @keyDialogPhaseSaveKey.
  ///
  /// In en, this message translates to:
  /// **'Save key'**
  String get keyDialogPhaseSaveKey;

  /// No description provided for @keyDialogPhaseSaveBalance.
  ///
  /// In en, this message translates to:
  /// **'Save balance'**
  String get keyDialogPhaseSaveBalance;

  /// No description provided for @keyDialogPhaseFetchComplete.
  ///
  /// In en, this message translates to:
  /// **'Fetch complete'**
  String get keyDialogPhaseFetchComplete;

  /// No description provided for @keyDialogPhaseSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Save failed'**
  String get keyDialogPhaseSaveFailed;

  /// No description provided for @keyDialogFallbackKeyName.
  ///
  /// In en, this message translates to:
  /// **'Current key'**
  String get keyDialogFallbackKeyName;

  /// No description provided for @keyDialogPreparingScan.
  ///
  /// In en, this message translates to:
  /// **'Preparing to scan {count} API keys...'**
  String keyDialogPreparingScan(int count);

  /// No description provided for @keyDialogFetchingModelsFor.
  ///
  /// In en, this message translates to:
  /// **'Fetching models for {label}...'**
  String keyDialogFetchingModelsFor(String label);

  /// No description provided for @keyDialogFetchingBalanceFor.
  ///
  /// In en, this message translates to:
  /// **'Fetching balance for {label}...'**
  String keyDialogFetchingBalanceFor(String label);

  /// No description provided for @keyDialogModelFetchFailed.
  ///
  /// In en, this message translates to:
  /// **'{label} model fetch failed: {error}'**
  String keyDialogModelFetchFailed(String label, String error);

  /// No description provided for @keyDialogBalanceFetchFailed.
  ///
  /// In en, this message translates to:
  /// **'{label} balance fetch failed: {error}'**
  String keyDialogBalanceFetchFailed(String label, String error);

  /// No description provided for @keyDialogModelsCountText.
  ///
  /// In en, this message translates to:
  /// **'{count} models'**
  String keyDialogModelsCountText(int count);

  /// No description provided for @keyDialogModelFetchSkipped.
  ///
  /// In en, this message translates to:
  /// **'model fetch failed, skipped'**
  String get keyDialogModelFetchSkipped;

  /// No description provided for @keyDialogBalanceSuffixSuccess.
  ///
  /// In en, this message translates to:
  /// **', balance: {value}'**
  String keyDialogBalanceSuffixSuccess(String value);

  /// No description provided for @keyDialogBalanceSuffixFailed.
  ///
  /// In en, this message translates to:
  /// **', balance failed'**
  String get keyDialogBalanceSuffixFailed;

  /// No description provided for @keyDialogScanLine.
  ///
  /// In en, this message translates to:
  /// **'{label}: {modelMessage}{balanceMessage}'**
  String keyDialogScanLine(
    String label,
    String modelMessage,
    String balanceMessage,
  );

  /// No description provided for @keyDialogModelFetchSummarySuccess.
  ///
  /// In en, this message translates to:
  /// **'Model fetch complete: {ok}/{total} keys succeeded, {merged} models merged{balanceHint}{failedHint}'**
  String keyDialogModelFetchSummarySuccess(
    int ok,
    int total,
    int merged,
    String balanceHint,
    String failedHint,
  );

  /// No description provided for @keyDialogModelFetchSummaryNone.
  ///
  /// In en, this message translates to:
  /// **'No key returned models. The current manual model list is unchanged.'**
  String get keyDialogModelFetchSummaryNone;

  /// No description provided for @keyDialogPreparingSave.
  ///
  /// In en, this message translates to:
  /// **'Preparing to save...'**
  String get keyDialogPreparingSave;

  /// No description provided for @keyDialogSavingItem.
  ///
  /// In en, this message translates to:
  /// **'Saving {label}...'**
  String keyDialogSavingItem(String label);

  /// No description provided for @keyDialogSavingBalanceItem.
  ///
  /// In en, this message translates to:
  /// **'Saving balance for {label}...'**
  String keyDialogSavingBalanceItem(String label);

  /// No description provided for @keyDialogImportedKeys.
  ///
  /// In en, this message translates to:
  /// **'Imported {count} API keys{balanceHint}{skippedHint}'**
  String keyDialogImportedKeys(
    int count,
    String balanceHint,
    String skippedHint,
  );

  /// No description provided for @keyDialogApiKeySaved.
  ///
  /// In en, this message translates to:
  /// **'API Key saved{balanceHint}'**
  String keyDialogApiKeySaved(String balanceHint);

  /// No description provided for @keyDialogNoNewKey.
  ///
  /// In en, this message translates to:
  /// **'No new key: all entered API keys already exist.'**
  String get keyDialogNoNewKey;

  /// No description provided for @keyDialogSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to save API Key: {error}'**
  String keyDialogSaveFailed(String error);

  /// No description provided for @keyDialogBalanceHintFraction.
  ///
  /// In en, this message translates to:
  /// **', balance {ok}/{total}'**
  String keyDialogBalanceHintFraction(int ok, int total);

  /// No description provided for @keyDialogSkippedDuplicates.
  ///
  /// In en, this message translates to:
  /// **', skipped {count} duplicate keys'**
  String keyDialogSkippedDuplicates(int count);

  /// No description provided for @keyDialogFailedItemsHint.
  ///
  /// In en, this message translates to:
  /// **', {count} failed items'**
  String keyDialogFailedItemsHint(int count);

  /// No description provided for @keyDialogFinalSummary.
  ///
  /// In en, this message translates to:
  /// **'Models {modelOk}/{modelTotal}, balances {balanceOk}/{balanceTotal}'**
  String keyDialogFinalSummary(
    int modelOk,
    int modelTotal,
    int balanceOk,
    int balanceTotal,
  );

  /// No description provided for @segmentSampleIntervalExplain.
  ///
  /// In en, this message translates to:
  /// **'How often a screenshot is sampled within a single segment when generating a summary. Smaller values capture more detail but use more tokens; larger values are cheaper but may miss short-lived events.'**
  String get segmentSampleIntervalExplain;

  /// No description provided for @segmentDurationExplain.
  ///
  /// In en, this message translates to:
  /// **'Maximum duration of a single dynamic segment. After this length, a new segment is started even if the activity continues. Shorter segments produce more granular summaries; longer ones provide broader context.'**
  String get segmentDurationExplain;

  /// No description provided for @dynamicMergeMaxSpanExplain.
  ///
  /// In en, this message translates to:
  /// **'Upper bound on the time span across which adjacent dynamic segments may be merged into one summary. Set to 0 to disable the limit.'**
  String get dynamicMergeMaxSpanExplain;

  /// No description provided for @dynamicMergeMaxGapExplain.
  ///
  /// In en, this message translates to:
  /// **'Maximum allowed gap between two adjacent dynamic segments for them to be considered mergeable. Set to 0 to disable the limit.'**
  String get dynamicMergeMaxGapExplain;

  /// No description provided for @dynamicMergeMaxImagesExplain.
  ///
  /// In en, this message translates to:
  /// **'Maximum number of screenshots fed into a merged summary in one go. Higher values give the model more context but increase cost and latency. Set to 0 for no limit.'**
  String get dynamicMergeMaxImagesExplain;

  /// No description provided for @aiRequestIntervalExplain.
  ///
  /// In en, this message translates to:
  /// **'Minimum interval between two AI requests sent by the app. Increase this if your provider rate-limits you, or to reduce overall consumption.'**
  String get aiRequestIntervalExplain;

  /// No description provided for @segmentsJsonAutoRetryTitle.
  ///
  /// In en, this message translates to:
  /// **'Auto retry count'**
  String get segmentsJsonAutoRetryTitle;

  /// No description provided for @segmentsJsonAutoRetryDesc.
  ///
  /// In en, this message translates to:
  /// **'When the AI response does not match the expected format, automatically retry the request this many times (0 = off, default 1). Current: {count}'**
  String segmentsJsonAutoRetryDesc(int count);

  /// No description provided for @segmentsJsonAutoRetryExplain.
  ///
  /// In en, this message translates to:
  /// **'The AI sometimes returns content that cannot be parsed or does not match the required structure. When this happens, the app will automatically resend the request up to this many times. Higher values improve success rate but cost more time and tokens.'**
  String get segmentsJsonAutoRetryExplain;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ja', 'ko', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ja':
      return AppLocalizationsJa();
    case 'ko':
      return AppLocalizationsKo();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
