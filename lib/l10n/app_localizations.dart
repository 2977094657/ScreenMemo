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
  /// **'Select apps to monitor'**
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
  /// **'Clear'**
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

  /// No description provided for @segmentSummarySectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Segment summary'**
  String get segmentSummarySectionTitle;

  /// No description provided for @dailyReminderSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Daily summary reminder'**
  String get dailyReminderSectionTitle;

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

  /// No description provided for @intervalRangeHint.
  ///
  /// In en, this message translates to:
  /// **'Range: 5-60 seconds, default: 5 seconds'**
  String get intervalRangeHint;

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

  /// No description provided for @generatePersonaArticle.
  ///
  /// In en, this message translates to:
  /// **'Generate persona article'**
  String get generatePersonaArticle;

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

  /// No description provided for @articlePreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Persona Article Preview'**
  String get articlePreviewTitle;

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

  /// No description provided for @memoryPersonaHubTitle.
  ///
  /// In en, this message translates to:
  /// **'Memory Archive'**
  String get memoryPersonaHubTitle;

  /// No description provided for @memoryTagsEntranceTooltip.
  ///
  /// In en, this message translates to:
  /// **'Open tag library'**
  String get memoryTagsEntranceTooltip;

  /// No description provided for @memoryTagLibraryTitle.
  ///
  /// In en, this message translates to:
  /// **'Tag Library'**
  String get memoryTagLibraryTitle;

  /// No description provided for @memoryArticleEmptyPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'No persona article yet. Generate one to see full insights.'**
  String get memoryArticleEmptyPlaceholder;

  /// No description provided for @memoryPauseActionLabel.
  ///
  /// In en, this message translates to:
  /// **'Pause processing'**
  String get memoryPauseActionLabel;

  /// No description provided for @copyPersonaTooltip.
  ///
  /// In en, this message translates to:
  /// **'Copy persona summary'**
  String get copyPersonaTooltip;

  /// No description provided for @memoryPersonaEmptyPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'No persona summary yet. Keep recording events to enrich it.'**
  String get memoryPersonaEmptyPlaceholder;

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
  /// **'Configure prompts for normal, merged, daily, weekly summaries, and morning insights; supports Markdown. Empty or reset to use defaults.'**
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
  /// **'Deep thinking'**
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

  /// No description provided for @memoryMenuEntry.
  ///
  /// In en, this message translates to:
  /// **'Memory Archive'**
  String get memoryMenuEntry;

  /// No description provided for @memoryCenterTitle.
  ///
  /// In en, this message translates to:
  /// **'Memory Archive'**
  String get memoryCenterTitle;

  /// No description provided for @memoryClearAllTooltip.
  ///
  /// In en, this message translates to:
  /// **'Clear memory vault'**
  String get memoryClearAllTooltip;

  /// No description provided for @memoryClearAllConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear Memory Vault'**
  String get memoryClearAllConfirmTitle;

  /// No description provided for @memoryClearAllConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'This will delete all memory tags, events, and evidence. This action cannot be undone. Continue?'**
  String get memoryClearAllConfirmMessage;

  /// No description provided for @memoryImportSampleTooltip.
  ///
  /// In en, this message translates to:
  /// **'Import 30 items for testing'**
  String get memoryImportSampleTooltip;

  /// No description provided for @memoryImportSampleSuccess.
  ///
  /// In en, this message translates to:
  /// **'Imported {count} events for testing'**
  String memoryImportSampleSuccess(Object count);

  /// No description provided for @memoryImportSampleEmpty.
  ///
  /// In en, this message translates to:
  /// **'No memory events available to import'**
  String get memoryImportSampleEmpty;

  /// No description provided for @memoryImportSampleFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed: {error}'**
  String memoryImportSampleFailed(Object error);

  /// No description provided for @memoryPauseTooltip.
  ///
  /// In en, this message translates to:
  /// **'Pause processing'**
  String get memoryPauseTooltip;

  /// No description provided for @memoryPauseSuccess.
  ///
  /// In en, this message translates to:
  /// **'Processing paused'**
  String get memoryPauseSuccess;

  /// No description provided for @memoryPauseFailed.
  ///
  /// In en, this message translates to:
  /// **'Pause failed: {error}'**
  String memoryPauseFailed(Object error);

  /// No description provided for @memoryPendingSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Pending Tags'**
  String get memoryPendingSectionTitle;

  /// No description provided for @memoryConfirmedSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirmed Tags'**
  String get memoryConfirmedSectionTitle;

  /// No description provided for @memoryRecentEventsSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Recent Events'**
  String get memoryRecentEventsSectionTitle;

  /// No description provided for @memoryNoPending.
  ///
  /// In en, this message translates to:
  /// **'No pending tags yet'**
  String get memoryNoPending;

  /// No description provided for @memoryNoConfirmed.
  ///
  /// In en, this message translates to:
  /// **'No confirmed tags yet'**
  String get memoryNoConfirmed;

  /// No description provided for @memoryNoEvents.
  ///
  /// In en, this message translates to:
  /// **'No related events yet'**
  String get memoryNoEvents;

  /// No description provided for @memoryConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Mark as confirmed'**
  String get memoryConfirmAction;

  /// No description provided for @memoryStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get memoryStatusPending;

  /// No description provided for @memoryStatusConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirmed'**
  String get memoryStatusConfirmed;

  /// No description provided for @memoryCategoryIdentity.
  ///
  /// In en, this message translates to:
  /// **'Identity'**
  String get memoryCategoryIdentity;

  /// No description provided for @memoryCategoryRelationship.
  ///
  /// In en, this message translates to:
  /// **'Relationship'**
  String get memoryCategoryRelationship;

  /// No description provided for @memoryCategoryInterest.
  ///
  /// In en, this message translates to:
  /// **'Interest'**
  String get memoryCategoryInterest;

  /// No description provided for @memoryCategoryBehavior.
  ///
  /// In en, this message translates to:
  /// **'Behavior'**
  String get memoryCategoryBehavior;

  /// No description provided for @memoryCategoryPreference.
  ///
  /// In en, this message translates to:
  /// **'Preference'**
  String get memoryCategoryPreference;

  /// No description provided for @memoryCategoryOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get memoryCategoryOther;

  /// No description provided for @memoryConfidenceLabel.
  ///
  /// In en, this message translates to:
  /// **'Confidence: {value}%'**
  String memoryConfidenceLabel(Object value);

  /// No description provided for @memoryOccurrencesLabel.
  ///
  /// In en, this message translates to:
  /// **'Occurrences: {count}'**
  String memoryOccurrencesLabel(Object count);

  /// No description provided for @memoryFirstSeenLabel.
  ///
  /// In en, this message translates to:
  /// **'First seen: {date}'**
  String memoryFirstSeenLabel(Object date);

  /// No description provided for @memoryLastSeenLabel.
  ///
  /// In en, this message translates to:
  /// **'Last seen: {date}'**
  String memoryLastSeenLabel(Object date);

  /// No description provided for @memoryEvidenceCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Evidence: {count}'**
  String memoryEvidenceCountLabel(Object count);

  /// No description provided for @memoryEventContainsContext.
  ///
  /// In en, this message translates to:
  /// **'Contains user-related info'**
  String get memoryEventContainsContext;

  /// No description provided for @memoryEventNoContext.
  ///
  /// In en, this message translates to:
  /// **'No user-related info detected'**
  String get memoryEventNoContext;

  /// No description provided for @memoryEventTimeLabel.
  ///
  /// In en, this message translates to:
  /// **'Time: {date}'**
  String memoryEventTimeLabel(Object date);

  /// No description provided for @memoryEventSourceLabel.
  ///
  /// In en, this message translates to:
  /// **'Source: {source}'**
  String memoryEventSourceLabel(Object source);

  /// No description provided for @memoryEventTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Type: {type}'**
  String memoryEventTypeLabel(Object type);

  /// No description provided for @memoryProgressIdle.
  ///
  /// In en, this message translates to:
  /// **'Waiting for historical events'**
  String get memoryProgressIdle;

  /// No description provided for @memoryProgressRunning.
  ///
  /// In en, this message translates to:
  /// **'Processing historical events'**
  String get memoryProgressRunning;

  /// No description provided for @memoryProgressRunningDetail.
  ///
  /// In en, this message translates to:
  /// **'{processed}/{total} days processed ({percent}%)'**
  String memoryProgressRunningDetail(
    Object processed,
    Object total,
    Object percent,
  );

  /// No description provided for @memoryProgressNewTagsDetail.
  ///
  /// In en, this message translates to:
  /// **'New tags discovered: {count}'**
  String memoryProgressNewTagsDetail(Object count);

  /// No description provided for @memoryProgressCompleted.
  ///
  /// In en, this message translates to:
  /// **'Historical days processed: {total} days in {seconds} seconds'**
  String memoryProgressCompleted(Object total, Object seconds);

  /// No description provided for @memoryProgressFailed.
  ///
  /// In en, this message translates to:
  /// **'Processing failed: {message}'**
  String memoryProgressFailed(Object message);

  /// No description provided for @memoryProgressFailedEvent.
  ///
  /// In en, this message translates to:
  /// **'Failed event: {event}'**
  String memoryProgressFailedEvent(Object event);

  /// No description provided for @memoryProgressPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing: {stage}'**
  String memoryProgressPreparing(Object stage);

  /// No description provided for @memoryProgressStageSyncSegments.
  ///
  /// In en, this message translates to:
  /// **'Syncing screenshot events'**
  String get memoryProgressStageSyncSegments;

  /// No description provided for @memoryProgressStageSyncChats.
  ///
  /// In en, this message translates to:
  /// **'Syncing conversations'**
  String get memoryProgressStageSyncChats;

  /// No description provided for @memoryProgressStageDispatch.
  ///
  /// In en, this message translates to:
  /// **'Starting historical processing'**
  String get memoryProgressStageDispatch;

  /// No description provided for @memoryRefreshTooltip.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get memoryRefreshTooltip;

  /// No description provided for @memoryConfirmSuccessToast.
  ///
  /// In en, this message translates to:
  /// **'Confirmed tag \"{label}\"'**
  String memoryConfirmSuccessToast(Object label);

  /// No description provided for @memoryConfirmFailedToast.
  ///
  /// In en, this message translates to:
  /// **'Failed: {message}'**
  String memoryConfirmFailedToast(Object message);

  /// No description provided for @memorySnapshotUpdated.
  ///
  /// In en, this message translates to:
  /// **'Memory snapshot updated'**
  String get memorySnapshotUpdated;

  /// No description provided for @memoryStartProcessingAction.
  ///
  /// In en, this message translates to:
  /// **'Start processing history'**
  String get memoryStartProcessingAction;

  /// No description provided for @memoryStartProcessingActionShort.
  ///
  /// In en, this message translates to:
  /// **'Start processing'**
  String get memoryStartProcessingActionShort;

  /// No description provided for @memoryMalformedResponseTitle.
  ///
  /// In en, this message translates to:
  /// **'Malformed response detected, processing paused'**
  String get memoryMalformedResponseTitle;

  /// No description provided for @memoryMalformedResponseSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Response for event {eventId} is missing the \"Current User Summary:\" marker. Review it before resuming.'**
  String memoryMalformedResponseSubtitle(Object eventId);

  /// No description provided for @memoryMalformedResponseSubtitleNoId.
  ///
  /// In en, this message translates to:
  /// **'The latest response is missing the \"Current User Summary:\" marker. Review it before resuming.'**
  String get memoryMalformedResponseSubtitleNoId;

  /// No description provided for @memoryMalformedResponseRawLabel.
  ///
  /// In en, this message translates to:
  /// **'Raw response:'**
  String get memoryMalformedResponseRawLabel;

  /// No description provided for @memoryDeleteTagAction.
  ///
  /// In en, this message translates to:
  /// **'Delete tag'**
  String get memoryDeleteTagAction;

  /// No description provided for @memoryDeleteTagConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete tag'**
  String get memoryDeleteTagConfirmTitle;

  /// No description provided for @memoryDeleteTagConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete tag \"{tagLabel}\"? Associated evidence will be removed.'**
  String memoryDeleteTagConfirmMessage(Object tagLabel);

  /// No description provided for @memoryDeleteTagSuccess.
  ///
  /// In en, this message translates to:
  /// **'Tag deleted'**
  String get memoryDeleteTagSuccess;

  /// No description provided for @memoryDeleteTagFailed.
  ///
  /// In en, this message translates to:
  /// **'Delete failed: {error}'**
  String memoryDeleteTagFailed(Object error);

  /// No description provided for @memoryStatusPendingIndicator.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get memoryStatusPendingIndicator;

  /// No description provided for @memoryStatusConfirmedIndicator.
  ///
  /// In en, this message translates to:
  /// **'Confirmed'**
  String get memoryStatusConfirmedIndicator;

  /// No description provided for @memoryReprocessAction.
  ///
  /// In en, this message translates to:
  /// **'Reprocess entire history'**
  String get memoryReprocessAction;

  /// No description provided for @memoryStartProcessingToast.
  ///
  /// In en, this message translates to:
  /// **'Historical processing started'**
  String get memoryStartProcessingToast;

  /// No description provided for @memoryLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get memoryLoadMore;

  /// No description provided for @memoryCenterHeroTitle.
  ///
  /// In en, this message translates to:
  /// **'Character dossier'**
  String get memoryCenterHeroTitle;

  /// No description provided for @memoryCenterHeroSubtitle.
  ///
  /// In en, this message translates to:
  /// **'An RPG-style card distilled from your personal events'**
  String get memoryCenterHeroSubtitle;

  /// No description provided for @memoryCenterPendingCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Pending: {count}'**
  String memoryCenterPendingCountLabel(Object count);

  /// No description provided for @memoryCenterConfirmedCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirmed: {count}'**
  String memoryCenterConfirmedCountLabel(Object count);

  /// No description provided for @memoryCenterEventCountLabel.
  ///
  /// In en, this message translates to:
  /// **'User-related events: {count}'**
  String memoryCenterEventCountLabel(Object count);

  /// No description provided for @memoryTagDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Tag Detail'**
  String get memoryTagDetailTitle;

  /// No description provided for @memoryTagDetailRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get memoryTagDetailRefresh;

  /// No description provided for @memoryTagDetailInfoTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get memoryTagDetailInfoTitle;

  /// No description provided for @memoryTagDetailStatisticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Attributes'**
  String get memoryTagDetailStatisticsTitle;

  /// No description provided for @memoryTagDetailOccurrences.
  ///
  /// In en, this message translates to:
  /// **'Occurrences: {count}'**
  String memoryTagDetailOccurrences(Object count);

  /// No description provided for @memoryTagDetailConfidence.
  ///
  /// In en, this message translates to:
  /// **'Confidence: {confidence}'**
  String memoryTagDetailConfidence(Object confidence);

  /// No description provided for @memoryTagDetailFirstSeen.
  ///
  /// In en, this message translates to:
  /// **'First seen: {date}'**
  String memoryTagDetailFirstSeen(Object date);

  /// No description provided for @memoryTagDetailLastSeen.
  ///
  /// In en, this message translates to:
  /// **'Last seen: {date}'**
  String memoryTagDetailLastSeen(Object date);

  /// No description provided for @memoryTagDetailEvidenceTitle.
  ///
  /// In en, this message translates to:
  /// **'Supporting evidence'**
  String get memoryTagDetailEvidenceTitle;

  /// No description provided for @memoryTagDetailEvidenceCount.
  ///
  /// In en, this message translates to:
  /// **'Total evidence: {count}'**
  String memoryTagDetailEvidenceCount(Object count);

  /// No description provided for @memoryTagDetailNoEvidence.
  ///
  /// In en, this message translates to:
  /// **'No evidence recorded yet'**
  String get memoryTagDetailNoEvidence;

  /// No description provided for @memoryTagDetailLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load tag data'**
  String get memoryTagDetailLoadFailed;

  /// No description provided for @memoryEvidenceInferenceLabel.
  ///
  /// In en, this message translates to:
  /// **'Inference'**
  String get memoryEvidenceInferenceLabel;

  /// No description provided for @memoryEvidenceNotesLabel.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get memoryEvidenceNotesLabel;

  /// No description provided for @memoryEvidenceNoNotes.
  ///
  /// In en, this message translates to:
  /// **'No notes'**
  String get memoryEvidenceNoNotes;

  /// No description provided for @memoryEvidenceEventHeading.
  ///
  /// In en, this message translates to:
  /// **'Source event'**
  String get memoryEvidenceEventHeading;

  /// No description provided for @memoryEvidenceUserEditedBadge.
  ///
  /// In en, this message translates to:
  /// **'Edited by user'**
  String get memoryEvidenceUserEditedBadge;

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
  /// **'Personal assistant ready'**
  String get aiEmptySelfTitle;

  /// No description provided for @aiEmptySelfSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Ask anything. I will use your data as context.'**
  String get aiEmptySelfSubtitle;
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
