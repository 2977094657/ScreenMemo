import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
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

  /// No description provided for @targetSizeHint.
  ///
  /// In en, this message translates to:
  /// **'To ensure OCR quality, minimum 50KB is supported; system will try to approach this size without changing resolution.'**
  String get targetSizeHint;

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

  /// No description provided for @expireDaysHint.
  ///
  /// In en, this message translates to:
  /// **'Minimum 1 day; when enabled, app will automatically clean expired files periodically after startup and each screenshot (12-hour throttle protection).'**
  String get expireDaysHint;

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
  /// **'Event Status'**
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
  /// **'Configure prompts for normal, merged, and daily summaries; supports Markdown. Empty or reset to use defaults.'**
  String get promptManagerHint;

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
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
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
