// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get appTitle => '스크린메모';

  @override
  String get settingsTitle => '설정';

  @override
  String get searchPlaceholder => '스크린샷 검색...';

  @override
  String get homeEmptyTitle => '모니터링되는 앱 없음';

  @override
  String get homeEmptySubtitle => '설정에서 모니터링할 앱을 선택하세요';

  @override
  String get navSelectApps => '모니터링할 앱 선택';

  @override
  String get dialogOk => '확인';

  @override
  String get dialogCancel => '취소';

  @override
  String get dialogDone => '완료';

  @override
  String get permissionStatusTitle => '권한 상태';

  @override
  String get permissionMissing => '권한이 부족합니다';

  @override
  String get startScreenshot => '캡처 시작';

  @override
  String get stopScreenshot => '캡처 중지';

  @override
  String get screenshotEnabledToast => '캡처를 활성화했습니다';

  @override
  String get screenshotDisabledToast => '캡처를 비활성화했습니다';

  @override
  String get intervalSettingTitle => '캡처 간격 설정';

  @override
  String get intervalLabel => '간격(초)';

  @override
  String get intervalHint => '5~60 사이의 정수를 입력하세요';

  @override
  String intervalSavedToast(Object seconds) {
    return '캡처 간격을 $seconds초로 설정했습니다';
  }

  @override
  String get languageSettingTitle => '언어';

  @override
  String get languageSystem => '시스템';

  @override
  String get languageChinese => '중국어(간체)';

  @override
  String get languageEnglish => '영어';

  @override
  String get languageJapanese => '일본어';

  @override
  String get languageKorean => '한국어';

  @override
  String languageChangedToast(Object name) {
    return '$name로 전환됨';
  }

  @override
  String get nsfwWarningTitle => '콘텐츠 경고: 성인용 콘텐츠';

  @override
  String get nsfwWarningSubtitle => '이 콘텐츠는 성인용 콘텐츠로 표시되었습니다.';

  @override
  String get show => '표시';

  @override
  String get appSearchPlaceholder => '앱 검색...';

  @override
  String selectedCount(Object count) {
    return '$count개 선택됨';
  }

  @override
  String get refreshAppsTooltip => '앱 새로 고침';

  @override
  String get selectAll => '모두 선택';

  @override
  String get clearAll => '모두 지우기';

  @override
  String get noAppsFound => '앱을 찾을 수 없습니다';

  @override
  String get noAppsMatched => '일치하는 앱이 없습니다';

  @override
  String get pinduoduoWarningTitle => '위험 알림';

  @override
  String get pinduoduoWarningMessage =>
      '핑둬둬에서 스크린샷을 촬영하면 주문이 취소될 수 있습니다. 모니터링을 활성화하지 않는 것을 권장합니다.';

  @override
  String get pinduoduoWarningCancel => '선택 취소';

  @override
  String get pinduoduoWarningKeep => '계속 선택';

  @override
  String stepProgress(Object current, Object total) {
    return '단계 $current/$total';
  }

  @override
  String get onboardingWelcomeTitle => '스크린메모에 오신 것을 환영합니다';

  @override
  String get onboardingWelcomeDesc =>
      '중요한 정보를 효율적으로 캡처, 구성 및 검토할 수 있도록 도와주는 지능형 메모 및 정보 관리 도구입니다.';

  @override
  String get onboardingKeyFeaturesTitle => '주요 기능';

  @override
  String get featureSmartNotes => '스마트 정보 캡처';

  @override
  String get featureQuickSearch => '빠른 콘텐츠 검색';

  @override
  String get featureLocalStorage => '로컬 데이터 저장';

  @override
  String get featureUsageAnalytics => '사용량 분석';

  @override
  String get onboardingPermissionsTitle => '필수 권한 부여';

  @override
  String get refreshPermissionStatus => '권한 상태 새로 고침';

  @override
  String get onboardingPermissionsDesc => '전체 경험을 제공하려면 다음 권한을 부여하십시오.';

  @override
  String get storagePermissionTitle => '저장 권한';

  @override
  String get storagePermissionDesc => '스크린샷 파일을 장치 저장소에 저장';

  @override
  String get notificationPermissionTitle => '알림 권한';

  @override
  String get notificationPermissionDesc => '서비스 상태 알림 표시';

  @override
  String get accessibilityPermissionTitle => '접근성 서비스';

  @override
  String get accessibilityPermissionDesc => '앱 전환을 모니터링하고 스크린샷을 찍습니다.';

  @override
  String get usageStatsPermissionTitle => '사용 통계 권한';

  @override
  String get usageStatsPermissionDesc => '정확한 포그라운드 앱 감지 보장';

  @override
  String get batteryOptimizationTitle => '배터리 최적화 화이트리스트';

  @override
  String get batteryOptimizationDesc => '스크린샷 서비스를 안정적으로 실행하세요';

  @override
  String get pleaseCompleteInSystemSettings => '시스템 설정에서 승인을 완료한 후 앱으로 돌아가세요.';

  @override
  String get autostartPermissionTitle => '자동 시작 권한';

  @override
  String get autostartPermissionDesc => '앱이 백그라운드에서 다시 시작되도록 허용';

  @override
  String get permissionsFooterNote =>
      '권한은 부여 후에도 유지되며 시스템 설정에서 언제든지 변경할 수 있습니다.';

  @override
  String get grantedLabel => '부여된';

  @override
  String get authorizeAction => '승인하다';

  @override
  String get onboardingSelectAppsTitle => '모니터링할 앱 선택';

  @override
  String get onboardingSelectAppsDesc =>
      '스크린샷을 모니터링할 앱을 선택하세요. 계속하려면 하나 이상을 선택하세요.';

  @override
  String get onboardingDoneTitle => '모두 설정되었습니다!';

  @override
  String get onboardingDoneDesc => '모든 권한이 부여되었습니다. 이제 ScreenMemo를 사용할 수 있습니다.';

  @override
  String get nextStepTitle => '다음 단계';

  @override
  String get onboardingNextStepDesc =>
      '\"사용 시작\"을 눌러 메인 화면으로 들어가 강력한 스크린샷 기능을 경험해 보세요.';

  @override
  String get prevStep => '이전';

  @override
  String get startUsing => '사용 시작';

  @override
  String get finishSelection => '선택 완료';

  @override
  String get nextStep => '다음';

  @override
  String get confirmPermissionSettingsTitle => '권한 설정 확인';

  @override
  String get confirmAutostartQuestion => '시스템 설정에서 \"자동 시작 권한\" 구성을 완료하셨나요?';

  @override
  String get notYet => '아직 아님';

  @override
  String get done => '완료';

  @override
  String get startingScreenshotServiceInfo => '캡처 서비스 시작 중...';

  @override
  String get startServiceFailedCheckPermissions =>
      '캡처 서비스를 시작하지 못했습니다. 권한 설정을 확인해주세요';

  @override
  String get startFailedTitle => '시작 실패';

  @override
  String get startFailedUnknown => '시작 실패: 알 수 없는 오류';

  @override
  String get tipIfProblemPersists => '팁: 문제가 지속되면 앱을 다시 시작하거나 권한을 다시 구성해 보세요.';

  @override
  String get autoDisabledDueToPermissions => '권한이 부족하여 캡처가 비활성화되었습니다.';

  @override
  String get refreshingPermissionsInfo => '권한 상태를 새로 고치는 중...';

  @override
  String get permissionsRefreshed => '권한 상태가 새로고침되었습니다.';

  @override
  String refreshPermissionsFailed(Object error) {
    return '권한 상태를 새로 고치지 못했습니다: $error';
  }

  @override
  String get screenRecordingPermissionTitle => '화면 녹화 권한';

  @override
  String get goToSettings => '설정으로 이동';

  @override
  String get notGrantedLabel => '미허용';

  @override
  String get removeMonitoring => '모니터링 해제';

  @override
  String selectedItemsCount(Object count) {
    return '$count 선택됨';
  }

  @override
  String get whySomeAppsHidden => '일부 앱이 누락된 이유는 무엇입니까?';

  @override
  String get excludedAppsTitle => '제외된 앱';

  @override
  String get excludedAppsIntro => '다음 앱은 제외되며 선택할 수 없습니다.';

  @override
  String get excludedThisApp => '· 이 앱(자기 간섭을 피하기 위해)';

  @override
  String get excludedAutomationApps => '· 자동 스킵 앱(예: GKD 등 자동 탭 도구, 오탐 방지를 위해)';

  @override
  String get excludedImeApps => '· 입력 방법(키보드) 앱:';

  @override
  String get excludedImeAppsFiltered => '· 입력 방법(키보드) 앱(자동 필터링)';

  @override
  String currentDefaultIme(Object name, Object package) {
    return '현재 기본 IME: $name($package)';
  }

  @override
  String get imeExplainText =>
      '다른 앱에서 키보드가 나타나면 시스템이 IME 창으로 전환됩니다. 제외하지 않으면 IME를 사용하는 것으로 착각하여 플로팅 창 감지가 잘못될 수 있습니다. IME 앱은 자동으로 제외되며 IME가 감지되면 IME가 팝업되기 전에 부동 창을 앱으로 이동합니다.';

  @override
  String get gotIt => '알았어요';

  @override
  String get unknownIme => '알 수 없는 IME';

  @override
  String get intervalRangeNote => '범위: 5~60초, 기본값: 5초.';

  @override
  String get intervalInvalidInput => '5~60 사이의 유효한 정수를 입력하세요.';

  @override
  String get removeMonitoringMessage => '모니터링만 해제하고 이미지는 삭제하지 않습니다. 계속할까요?';

  @override
  String get remove => '해제';

  @override
  String removedMonitoringToast(Object count) {
    return '$count개의 앱에서 모니터링을 해제했습니다(이미지는 삭제되지 않음)';
  }

  @override
  String checkPermissionStatusFailed(Object error) {
    return '권한 상태 확인 실패: $error';
  }

  @override
  String get accessibilityNotEnabledDetail =>
      '접근성 서비스가 활성화되지 않았습니다.\\n설정에서 접근성을 활성화하십시오.';

  @override
  String get storagePermissionNotGrantedDetail =>
      '저장 권한이 부여되지 않았습니다.\\n설정에서 저장 권한을 부여하세요.';

  @override
  String get serviceNotRunningDetail => '서비스가 제대로 실행되지 않습니다.\\n앱을 다시 시작해 보세요.';

  @override
  String get androidVersionNotSupportedDetail =>
      'Android 버전은 지원되지 않습니다.\\nAndroid 11.0 이상이 필요합니다.';

  @override
  String get permissionsSectionTitle => '권한';

  @override
  String get displayAndSortSectionTitle => '디스플레이 및 정렬';

  @override
  String get screenshotSectionTitle => '캡처 설정';

  @override
  String get segmentSummarySectionTitle => '세그먼트 요약';

  @override
  String get dailyReminderSectionTitle => '일일 요약 알림';

  @override
  String get aiAssistantSectionTitle => 'AI 어시스턴트';

  @override
  String get dataBackupSectionTitle => '데이터 및 백업';

  @override
  String get actionSet => '세트';

  @override
  String get actionEnter => '입력하다';

  @override
  String get actionExport => '내보내다';

  @override
  String get actionImport => '수입';

  @override
  String get actionCopyPath => '경로 복사';

  @override
  String get actionOpen => '열려 있는';

  @override
  String get actionTrigger => '방아쇠';

  @override
  String get allPermissionsGranted => '모든 권한이 허용되었습니다';

  @override
  String permissionsMissingCount(Object count) {
    return '허용되지 않은 권한 $count개';
  }

  @override
  String get exportSuccessTitle => '내보내기가 완료되었습니다';

  @override
  String get exportFileExportedTo => '내보낸 위치:';

  @override
  String get pathCopiedToast => '경로를 복사했습니다';

  @override
  String get exportFailedTitle => '내보내기에 실패했습니다';

  @override
  String get pleaseTryAgain => '나중에 다시 시도해 주세요';

  @override
  String get importCompleteTitle => '가져오기가 완료되었습니다';

  @override
  String get dataExtractedTo => '데이터 추출 위치:';

  @override
  String get importFailedTitle => '가져오기에 실패했습니다';

  @override
  String get importFailedCheckZip => 'ZIP 파일을 확인하고 다시 시도해 주세요.';

  @override
  String get noMediaProjectionNeeded => '접근성 캡처를 사용 중이므로 화면 녹화 권한이 필요 없습니다';

  @override
  String get autostartPermissionMarked => '자동 시작 권한이 허용된 것으로 표시되었습니다';

  @override
  String requestPermissionFailed(Object error) {
    return '권한 요청에 실패했습니다: $error';
  }

  @override
  String get expireCleanupSaved => '만료 정리 설정이 저장되었습니다.';

  @override
  String get dailyNotifyTriggered => '알림이 실행됨';

  @override
  String get dailyNotifyTriggerFailed => '알림을 트리거하지 못했거나 콘텐츠가 비어 있습니다.';

  @override
  String get refreshPermissionStatusTooltip => '권한 상태 새로 고침';

  @override
  String get grantedStatus => '허용됨';

  @override
  String get notGrantedStatus => '허용';

  @override
  String get privacyModeTitle => '개인 정보 보호 모드';

  @override
  String get privacyModeDesc => '민감한 콘텐츠를 자동으로 블러 처리합니다';

  @override
  String get homeSortingTitle => '홈 정렬';

  @override
  String get screenshotIntervalTitle => '스크린샷 간격';

  @override
  String screenshotIntervalDesc(Object seconds) {
    return '현재 간격: $seconds초';
  }

  @override
  String get screenshotQualityTitle => '스크린샷 품질';

  @override
  String get currentSizeLabel => '현재 크기:';

  @override
  String get clickToModifyHint => '(숫자를 탭하면 수정 가능)';

  @override
  String get screenshotExpireTitle => '스크린샷 저장 기간';

  @override
  String get currentExpireDaysLabel => '현재 저장 일수:';

  @override
  String expireDaysUnit(Object days) {
    return '$days일';
  }

  @override
  String get exportDataTitle => '데이터 내보내기';

  @override
  String get exportDataDesc => 'ZIP을 Download/ScreenMemory에 내보내기';

  @override
  String get importDataTitle => '데이터 가져오기';

  @override
  String get importDataDesc => 'ZIP 파일을 앱 저장소로 가져오기';

  @override
  String get aiAssistantTitle => 'AI 어시스턴트';

  @override
  String get aiAssistantDesc => 'AI 인터페이스와 모델을 구성하고 다중 회차 대화를 테스트합니다';

  @override
  String get segmentSampleIntervalTitle => '샘플 간격(초)';

  @override
  String segmentSampleIntervalDesc(Object seconds) {
    return '현재: $seconds초';
  }

  @override
  String get segmentDurationTitle => '세그먼트 기간(분)';

  @override
  String segmentDurationDesc(Object minutes) {
    return '현재: $minutes분';
  }

  @override
  String get aiRequestIntervalTitle => 'AI 요청 최소 간격(초)';

  @override
  String aiRequestIntervalDesc(Object seconds) {
    return '현재: ${seconds}s(최소 1초)';
  }

  @override
  String get dailyReminderTimeTitle => '일일 요약 알림 시간';

  @override
  String get currentTimeLabel => '현재:';

  @override
  String get testNotificationTitle => '알림 테스트';

  @override
  String get testNotificationDesc => '\"일일 요약\" 알림을 지금 트리거합니다';

  @override
  String get enableBannerNotificationTitle => '배너/플로팅 알림 허용';

  @override
  String get enableBannerNotificationDesc => '화면 상단에 배너 알림이 표시되도록 허용합니다';

  @override
  String get setIntervalDialogTitle => '스크린샷 간격 설정';

  @override
  String get intervalSecondsLabel => '간격(초)';

  @override
  String get intervalInputHint => '5~60 사이의 정수를 입력하세요.';

  @override
  String get intervalRangeHint => '범위: 5~60초 (기본값: 5초)';

  @override
  String get intervalInvalidError => '5~60 사이의 유효한 정수를 입력하세요';

  @override
  String intervalSavedSuccess(Object seconds) {
    return '스크린샷 간격을 $seconds초로 설정했습니다';
  }

  @override
  String get setTargetSizeDialogTitle => '목표 크기(KB) 설정';

  @override
  String get targetSizeKbLabel => '목표 크기(KB)';

  @override
  String get targetSizeInvalidError => '50 이상의 유효한 정수를 입력하세요';

  @override
  String targetSizeSavedSuccess(Object kb) {
    return '목표 크기를 ${kb}KB로 설정했습니다';
  }

  @override
  String get setExpireDaysDialogTitle => '스크린샷 저장 일수 설정';

  @override
  String get expireDaysLabel => '저장 일수';

  @override
  String get expireDaysInputHint => '1 이상의 정수를 입력하세요';

  @override
  String get expireDaysInvalidError => '1 이상의 유효한 정수를 입력하세요';

  @override
  String expireDaysSavedSuccess(Object days) {
    return '$days일로 설정했습니다';
  }

  @override
  String get sortTimeNewToOld => '시간(신규→기존)';

  @override
  String get sortTimeOldToNew => '시간(구→신)';

  @override
  String get sortSizeLargeToSmall => '사이즈(대→소)';

  @override
  String get sortSizeSmallToLarge => '사이즈(소→대)';

  @override
  String get sortCountManyToFew => '개수(많은 순)';

  @override
  String get sortCountFewToMany => '개수(적은 순)';

  @override
  String get sortFieldTime => '시간';

  @override
  String get sortFieldCount => '개수';

  @override
  String get sortFieldSize => '크기';

  @override
  String get selectHomeSortingTitle => '홈 정렬 선택';

  @override
  String currentSortingLabel(Object sorting) {
    return '현재: $sorting';
  }

  @override
  String get privacyModeEnabledToast => '프라이버시 모드를 켰습니다';

  @override
  String get privacyModeDisabledToast => '프라이버시 모드를 껐습니다';

  @override
  String get screenshotQualitySettingsSaved => '스크린샷 품질 설정을 저장했습니다';

  @override
  String saveFailedError(Object error) {
    return '저장에 실패했습니다: $error';
  }

  @override
  String get setReminderTimeTitle => '알림 시간 설정(24시간제)';

  @override
  String get hourLabel => '시(0~23)';

  @override
  String get minuteLabel => '분(0~59)';

  @override
  String get timeInputHint => '팁: 숫자를 직접 입력할 수 있습니다. 범위는 0~23시, 0~59분입니다.';

  @override
  String get invalidHourError => '0~23 사이의 유효한 시를 입력하세요';

  @override
  String get invalidMinuteError => '0~59 사이의 유효한 분을 입력하세요';

  @override
  String timeSetSuccess(Object hour, Object minute) {
    return '$hour:$minute로 설정했습니다';
  }

  @override
  String reminderScheduleSuccess(Object hour, Object minute) {
    return '일일 알림 시간을 $hour:$minute로 설정했습니다';
  }

  @override
  String get reminderDisabledSuccess => '일일 알림을 비활성화했습니다';

  @override
  String get reminderScheduleFailed => '일일 알림을 예약하지 못했습니다(플랫폼에서 지원하지 않을 수 있음)';

  @override
  String saveReminderSettingsFailed(Object error) {
    return '알림 설정 저장 실패: $error';
  }

  @override
  String searchFailedError(Object error) {
    return '검색 실패: $error';
  }

  @override
  String get searchInputHintOcr => 'OCR로 스크린샷을 검색하려면 키워드를 입력하세요.';

  @override
  String get noMatchingScreenshots => '일치하는 스크린샷이 없습니다.';

  @override
  String get imageMissingOrCorrupted => '이미지가 없거나 손상되었습니다.';

  @override
  String get actionClear => '지우기';

  @override
  String get actionRefresh => '새로 고침';

  @override
  String get noScreenshotsTitle => '스크린샷이 없습니다';

  @override
  String get noScreenshotsSubtitle => '모니터링을 활성화하면 여기에 이미지가 표시됩니다';

  @override
  String get confirmDeleteTitle => '삭제 확인';

  @override
  String get confirmDeleteMessage => '이 스크린샷을 삭제할까요? 이 작업은 되돌릴 수 없습니다.';

  @override
  String get actionDelete => '삭제';

  @override
  String get actionContinue => '계속';

  @override
  String get linkTitle => '링크';

  @override
  String get actionCopy => '복사';

  @override
  String get imageInfoTitle => '스크린샷 정보';

  @override
  String get deleteImageTooltip => '이미지 삭제';

  @override
  String get imageLoadFailed => '이미지를 로드하지 못했습니다.';

  @override
  String get labelAppName => '앱 이름';

  @override
  String get labelCaptureTime => '캡처 시간';

  @override
  String get labelFilePath => '파일 경로';

  @override
  String get labelPageLink => '페이지 링크';

  @override
  String get labelFileSize => '파일 크기';

  @override
  String get tapToContinue => '탭하여 계속';

  @override
  String get appDirUninitialized => '앱 디렉토리가 초기화되지 않았습니다.';

  @override
  String get actionRetry => '다시 해 보다';

  @override
  String get deleteSelectedTooltip => '선택 항목 삭제';

  @override
  String get noMatchingResults => '일치하는 결과가 없습니다';

  @override
  String dayTabToday(Object count) {
    return '오늘 $count';
  }

  @override
  String dayTabYesterday(Object count) {
    return '어제 $count';
  }

  @override
  String dayTabMonthDayCount(Object month, Object day, Object count) {
    return '$month/$day $count';
  }

  @override
  String get screenshotDeletedToast => '스크린샷이 삭제되었습니다.';

  @override
  String get deleteFailed => '삭제 실패';

  @override
  String deleteFailedWithError(Object error) {
    return '삭제 실패: $error';
  }

  @override
  String get imageInfoTooltip => '이미지 정보';

  @override
  String get copySuccess => '복사했습니다';

  @override
  String get copyFailed => '복사에 실패했습니다';

  @override
  String deletedCountToast(Object count) {
    return '스크린샷 $count개를 삭제했습니다';
  }

  @override
  String get invalidArguments => '잘못된 인수';

  @override
  String initFailedWithError(Object error) {
    return '초기화 실패: $error';
  }

  @override
  String loadMoreFailedWithError(Object error) {
    return '추가 로드 실패: $error';
  }

  @override
  String get confirmDeleteAllTitle => '모든 스크린샷 삭제 확인';

  @override
  String deleteAllMessage(Object count) {
    return '현재 범위의 모든 $count 스크린샷을 삭제합니다. 이 작업은 취소할 수 없습니다.';
  }

  @override
  String deleteSelectedMessage(Object count) {
    return '$count 선택한 스크린샷을 삭제합니다. 이 작업은 취소할 수 없습니다. 계속하다?';
  }

  @override
  String get deleteFailedRetry => '삭제하지 못했습니다. 다시 시도해 주세요.';

  @override
  String keptAndDeletedSummary(Object keep, Object deleted) {
    return '$keep 보관, $deleted 삭제';
  }

  @override
  String dailySummaryTitle(Object date) {
    return '일일 요약 $date';
  }

  @override
  String dailySummarySlotMorningTitle(Object date) {
    return '아침 브리핑 $date';
  }

  @override
  String dailySummarySlotNoonTitle(Object date) {
    return '정오 브리핑 $date';
  }

  @override
  String dailySummarySlotEveningTitle(Object date) {
    return '저녁 브리핑 $date';
  }

  @override
  String dailySummarySlotNightTitle(Object date) {
    return '야간 브리핑 $date';
  }

  @override
  String get actionGenerate => '생성';

  @override
  String get actionRegenerate => '다시 생성';

  @override
  String get generateSuccess => '생성했습니다';

  @override
  String get generateFailed => '생성에 실패했습니다';

  @override
  String get noDailySummaryToday => '오늘 요약이 없습니다';

  @override
  String get generateDailySummary => '오늘 요약 생성';

  @override
  String get statisticsTitle => '통계';

  @override
  String get overviewTitle => '개요';

  @override
  String get monitoredApps => '모니터링되는 앱';

  @override
  String get totalScreenshots => '총 스크린샷';

  @override
  String get todayScreenshots => '오늘의 스크린샷';

  @override
  String get storageUsage => '스토리지 사용량';

  @override
  String get appStatisticsTitle => '앱 통계';

  @override
  String screenshotCountWithLast(Object count, Object last) {
    return '스크린샷: $count | 마지막: $last';
  }

  @override
  String get none => '없음';

  @override
  String get usageTrendsTitle => '사용 동향';

  @override
  String get trendChartTitle => '추세 차트';

  @override
  String get comingSoon => '곧 출시 예정';

  @override
  String get timelineTitle => '타임라인';

  @override
  String get pressBackAgainToExit => '종료하려면 뒤로를 다시 누르세요.';

  @override
  String get segmentStatusTitle => '활동';

  @override
  String get autoWatchingHint => '백그라운드에서 자동 시청 중…';

  @override
  String get noEvents => '이벤트 없음';

  @override
  String get noEventsSubtitle => '이벤트 세그먼트 및 AI 요약이 여기에 표시됩니다.';

  @override
  String get activeSegmentTitle => '활성 세그먼트';

  @override
  String sampleEverySeconds(Object seconds) {
    return '$seconds초마다 샘플링';
  }

  @override
  String get dailySummaryShort => '일일 요약';

  @override
  String get weeklySummaryShort => '주간 요약';

  @override
  String weeklySummaryTitle(Object range) {
    return '주간 요약 $range';
  }

  @override
  String get weeklySummaryEmpty => '주간 요약이 아직 없습니다';

  @override
  String get weeklySummarySelectWeek => '주 선택';

  @override
  String get weeklySummaryOverviewTitle => '이번 주 개요';

  @override
  String get weeklySummaryDailyTitle => '요일별 정리';

  @override
  String get weeklySummaryActionsTitle => '다음 주 실행 제안';

  @override
  String get weeklySummaryNotificationTitle => '알림 요약';

  @override
  String get weeklySummaryNoContent => '내용이 없습니다';

  @override
  String get weeklySummaryViewDetail => '자세히 보기';

  @override
  String get viewOrGenerateForDay => '오늘의 요약 보기 또는 생성';

  @override
  String get mergedEventTag => '병합됨';

  @override
  String get collapse => '접기';

  @override
  String get expandMore => '더 보기';

  @override
  String viewImagesCount(Object count) {
    return '이미지 보기 ($count)';
  }

  @override
  String hideImagesCount(Object count) {
    return '이미지 숨기기 ($count)';
  }

  @override
  String get deleteEventTooltip => '일정 삭제';

  @override
  String get confirmDeleteEventMessage => '이 일정을 삭제하시겠습니까? 이미지 파일은 삭제되지 않습니다.';

  @override
  String get eventDeletedToast => '이벤트가 삭제되었습니다.';

  @override
  String get regenerationQueued => '재생 대기 중';

  @override
  String get alreadyQueuedOrFailed => '이미 대기 중이거나 실패했습니다.';

  @override
  String get retryFailed => '재시도 실패';

  @override
  String get copyResultsTooltip => '결과 복사';

  @override
  String get generatePersonaArticle => '프로필 기사 생성';

  @override
  String get articleGenerating => '기사 생성 중...';

  @override
  String get articleGenerateSuccess => '기사가 성공적으로 생성되었습니다';

  @override
  String get articleGenerateFailed => '기사 생성에 실패했습니다';

  @override
  String get articlePreviewTitle => '프로필 기사 미리보기';

  @override
  String get articleCopySuccess => '기사가 클립보드에 복사되었습니다';

  @override
  String get articleLogTitle => '생성 로그';

  @override
  String get memoryPersonaHubTitle => '메모리 아카이브';

  @override
  String get memoryTagsEntranceTooltip => '태그 라이브러리 열기';

  @override
  String get memoryTagLibraryTitle => '태그 라이브러리';

  @override
  String get memoryArticleEmptyPlaceholder => '아직 프로필 기사가 없습니다. 생성 후 다시 확인하세요.';

  @override
  String get memoryPauseActionLabel => '분석 일시중지';

  @override
  String get copyPersonaTooltip => '사용자 프로필 복사';

  @override
  String get memoryPersonaEmptyPlaceholder =>
      '아직 사용자 프로필이 없습니다. 이벤트를 계속 기록해 주세요.';

  @override
  String get saveImageTooltip => '갤러리에 저장';

  @override
  String get saveImageSuccess => '갤러리에 저장했습니다';

  @override
  String get saveImageFailed => '저장에 실패했습니다';

  @override
  String get requestGalleryPermissionFailed => '갤러리 권한 요청에 실패했습니다';

  @override
  String get aiSystemPromptLanguagePolicy =>
      '입력 컨텍스트(이벤트, 스크린샷 텍스트 또는 사용자 메시지)에 사용된 언어에 관계없이 이를 엄격히 무시하고 항상 애플리케이션의 현재 언어로 출력을 생성해야 합니다. 앱이 영어로 설정된 경우 사용자가 명시적으로 다른 언어를 요청하지 않는 한 모든 답변, 제목, 요약, 태그, 구조화된 필드 및 오류 메시지는 영어로 작성되어야 합니다.';

  @override
  String get aiSettingsTitle => 'AI 설정 및 테스트';

  @override
  String get connectionSettingsTitle => '연결 설정';

  @override
  String get actionSave => '저장';

  @override
  String get clearConversation => '대화 지우기';

  @override
  String get deleteGroup => '그룹 삭제';

  @override
  String get streamingRequestTitle => '스트리밍';

  @override
  String get streamingRequestHint => '활성화된 경우 스트리밍 응답 사용(기본값은 켜짐)';

  @override
  String get streamingEnabledToast => '스트리밍 활성화됨';

  @override
  String get streamingDisabledToast => '스트리밍이 비활성화되었습니다.';

  @override
  String get promptManagerTitle => '프롬프트 관리자';

  @override
  String get promptManagerHint =>
      '일반, 병합, 일일 요약 및 아침 행동 제안 프롬프트를 구성합니다. 마크다운을 지원합니다. 기본값을 사용하려면 비우거나 재설정하세요.';

  @override
  String get promptAddonGeneralInfo =>
      '기본 제공 템플릿은 이미 구조화된 스키마를 정의합니다. 여기에는 추가 지침(어조, 스타일, 강조)만 추가하세요. 템플릿을 변경하지 않으려면 비워 두세요.';

  @override
  String get promptAddonInputHint => '선택적 추가 지침 추가(건너뛰려면 비워 두세요)';

  @override
  String get promptAddonHelperText =>
      '어조나 선호 사항만 설명하세요. 스키마 변경이나 JSON 수정을 요청하지 마세요.';

  @override
  String get promptAddonEmptyPlaceholder => '추가 지침 없음';

  @override
  String get promptAddonSuggestionSegment =>
      '제안된 아이디어:\n- 원하는 어조나 타겟 청중을 한 문장으로 표현하세요.\n- 우선순위를 정할 핵심 통찰력이나 안전 제약 사항을 강조하세요.\n- JSON 필드 추가 또는 구조적 변경을 요청하지 마세요.';

  @override
  String get promptAddonSuggestionMerge =>
      '제안된 아이디어:\n- 병합 후 표면과의 비교 또는 대조를 강조합니다.\n- 반복을 피하고 집계된 통찰력에 집중하도록 모델에 상기시킵니다.\n- 출력 필드에 구조적 변경을 요청하지 마십시오.';

  @override
  String get promptAddonSuggestionDaily =>
      '제안된 아이디어:\n- 일일 요약 톤을 지정합니다(예: 행동 중심).\n- 주요 성과나 리스크를 강조하도록 요청\n- JSON 필드 이름 변경 또는 추가 금지';

  @override
  String get promptAddonSuggestionWeekly =>
      'Suggested ideas:\n- Emphasize week-over-week trends or pivots to highlight\n- Ask for actionable follow-ups or attention points\n- Avoid requesting structural changes to the JSON output';

  @override
  String get promptAddonSuggestionMorning =>
      '권장 사항:\n- 인간적인 온기, 여유로운 리듬, 소소한 위로를 강조\n- 템플릿/업무 지향 어조를 피하도록 안내\n- JSON 필드 변경이나 잦은 질문 사용을 요구하지 않기';

  @override
  String get normalEventPromptLabel => '일반 이벤트 프롬프트';

  @override
  String get mergeEventPromptLabel => '병합된 이벤트 프롬프트';

  @override
  String get dailySummaryPromptLabel => '일일 요약 프롬프트';

  @override
  String get weeklySummaryPromptLabel => 'Weekly summary prompt';

  @override
  String get morningInsightsPromptLabel => '아침 행동 제안 프롬프트';

  @override
  String get actionEdit => '편집하다';

  @override
  String get savingLabel => '저장 중';

  @override
  String get resetToDefault => '기본값으로 재설정';

  @override
  String get chatTestTitle => '채팅 테스트';

  @override
  String get actionSend => '전송';

  @override
  String get sendingLabel => '전송 중';

  @override
  String get baseUrlLabel => '기본 URL';

  @override
  String get baseUrlHint => '예를 들어 https://api.openai.com';

  @override
  String get apiKeyLabel => 'API 키';

  @override
  String get apiKeyHint => '예를 들어 sk-... 또는 공급업체 토큰';

  @override
  String get modelLabel => '모델';

  @override
  String get modelHint => '예를 들어 gpt-4o-mini / gpt-4o / 호환 가능';

  @override
  String get siteGroupsTitle => '사이트 그룹';

  @override
  String get siteGroupsHint => '여러 사이트를 백업으로 구성하고 실패 시 자동으로 전환합니다';

  @override
  String get rename => '이름 바꾸기';

  @override
  String get addGroup => '그룹 추가';

  @override
  String get showGroupSelector => '그룹 선택기 표시';

  @override
  String get ungroupedSingleConfig => '그룹 해제됨(단일 구성)';

  @override
  String get inputMessageHint => '메시지를 입력하세요';

  @override
  String get saveSuccess => '저장했습니다';

  @override
  String get savedCurrentGroupToast => '그룹을 저장했습니다';

  @override
  String get savedNormalPromptToast => '일반 프롬프트를 저장했습니다';

  @override
  String get savedMergePromptToast => '병합 프롬프트를 저장했습니다';

  @override
  String get savedDailyPromptToast => '일일 프롬프트를 저장했습니다';

  @override
  String get savedWeeklyPromptToast => 'Weekly prompt saved';

  @override
  String get resetToDefaultPromptToast => '기본 프롬프트로 재설정했습니다';

  @override
  String resetFailedWithError(Object error) {
    return '재설정 실패: $error';
  }

  @override
  String get clearSuccess => '지웠습니다';

  @override
  String clearFailedWithError(Object error) {
    return '지우기에 실패했습니다: $error';
  }

  @override
  String get messageCannotBeEmpty => '메시지를 입력하세요';

  @override
  String sendFailedWithError(Object error) {
    return '전송에 실패했습니다: $error';
  }

  @override
  String get groupSwitchedToUngrouped => '미분류로 전환했습니다';

  @override
  String get groupSwitched => '그룹을 전환했습니다';

  @override
  String get groupNotSelected => '선택된 그룹이 없습니다';

  @override
  String get groupNotFound => '그룹을 찾을 수 없습니다';

  @override
  String get renameGroupTitle => '그룹 이름 변경';

  @override
  String get groupNameLabel => '그룹 이름';

  @override
  String get groupNameHint => '새 그룹 이름을 입력하세요';

  @override
  String get nameCannotBeEmpty => '이름을 입력하세요';

  @override
  String get renameSuccess => '이름을 변경했습니다';

  @override
  String renameFailedWithError(Object error) {
    return '이름 변경 실패: $error';
  }

  @override
  String get groupAddedToast => '그룹을 추가했습니다';

  @override
  String addGroupFailedWithError(Object error) {
    return '그룹 추가 실패: $error';
  }

  @override
  String get groupDeletedToast => '그룹을 삭제했습니다';

  @override
  String deleteGroupFailedWithError(Object error) {
    return '그룹 삭제 실패: $error';
  }

  @override
  String loadGroupFailedWithError(Object error) {
    return '그룹 로드 실패: $error';
  }

  @override
  String siteGroupDefaultName(Object index) {
    return '사이트 그룹 $index';
  }

  @override
  String get defaultLabel => '기본값';

  @override
  String get customLabel => '사용자 지정';

  @override
  String get normalShortLabel => '일반:';

  @override
  String get mergeShortLabel => '병합:';

  @override
  String get dailyShortLabel => '일일:';

  @override
  String timeRangeLabel(Object range) {
    return '시간 범위: $range';
  }

  @override
  String statusLabel(Object status) {
    return '상태: $status';
  }

  @override
  String samplesTitle(Object count) {
    return '샘플($count)';
  }

  @override
  String get aiResultTitle => 'AI 결과';

  @override
  String modelValueLabel(Object model) {
    return '모델: $model';
  }

  @override
  String get tagMergedCopy => '태그: 병합됨';

  @override
  String categoriesLabel(Object categories) {
    return '카테고리: $categories';
  }

  @override
  String errorLabel(Object error) {
    return '오류: $error';
  }

  @override
  String summaryLabel(Object summary) {
    return '요약: $summary';
  }

  @override
  String get autostartPermissionNote =>
      '자동 시작 권한은 제조사에 따라 달라 자동 감지할 수 없습니다. 실제 설정에 맞게 선택하세요.';

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
    return '$count장';
  }

  @override
  String get apps => '앱';

  @override
  String get images => '이미지';

  @override
  String get days => '날';

  @override
  String get justNow => '방금';

  @override
  String minutesAgo(Object minutes) {
    return '$minutes분 전';
  }

  @override
  String hoursAgo(Object hours) {
    return '$hours시간 전';
  }

  @override
  String daysAgo(Object days) {
    return '$days일 전';
  }

  @override
  String searchResultsCount(Object count) {
    return '$count개의 이미지를 찾았습니다';
  }

  @override
  String get searchFiltersTitle => '필터';

  @override
  String get filterByTime => '시간';

  @override
  String get filterByApp => '앱';

  @override
  String get filterBySize => '크기';

  @override
  String get filterTimeAll => '전체';

  @override
  String get filterTimeToday => '오늘';

  @override
  String get filterTimeYesterday => '어제';

  @override
  String get filterTimeLast7Days => '지난 7일';

  @override
  String get filterTimeLast30Days => '지난 30일';

  @override
  String get filterTimeCustomRange => '맞춤 범위';

  @override
  String get filterAppAll => '모든 앱';

  @override
  String get filterSizeAll => '모든 크기';

  @override
  String get filterSizeSmall => '100KB 미만';

  @override
  String get filterSizeMedium => '100KB ~ 1MB';

  @override
  String get filterSizeLarge => '1MB 초과';

  @override
  String get applyFilters => '적용';

  @override
  String get resetFilters => '초기화';

  @override
  String get selectDateRange => '날짜 범위 선택';

  @override
  String get startDate => '시작 날짜';

  @override
  String get endDate => '종료 날짜';

  @override
  String get noResultsForFilters => '현재 필터와 일치하는 이미지가 없습니다';

  @override
  String get openLink => '열기';

  @override
  String get favoritePageTitle => '즐겨찾기';

  @override
  String get noFavoritesTitle => '즐겨찾기가 없습니다';

  @override
  String get noFavoritesSubtitle => '갤러리에서 길게 눌러 여러 항목을 선택한 뒤 즐겨찾기에 추가하세요';

  @override
  String get noteLabel => '메모';

  @override
  String get updatedAt => '업데이트: ';

  @override
  String get clickToAddNote => '메모 추가...';

  @override
  String get noteUnchanged => '메모가 변경되지 않았습니다';

  @override
  String get noteSaved => '메모를 저장했습니다';

  @override
  String get favoritesRemoved => '즐겨찾기에서 제거했습니다';

  @override
  String get operationFailed => '작업에 실패했습니다';

  @override
  String get cannotGetAppDir => '앱 디렉터리를 가져올 수 없습니다';

  @override
  String get nsfwSettingsSectionTitle => 'NSFW 설정';

  @override
  String get blockedDomainListTitle => '차단 도메인 목록';

  @override
  String get addDomainPlaceholder => '도메인 또는 *.example.com 입력';

  @override
  String get addRuleAction => '추가';

  @override
  String get previewAction => '미리보기';

  @override
  String get removeAction => '삭제';

  @override
  String get clearAction => '지우기';

  @override
  String get clearAllRules => '모든 규칙 지우기';

  @override
  String get clearAllRulesConfirmTitle => '규칙 삭제 확인';

  @override
  String get clearAllRulesMessage => '모든 차단 도메인 규칙을 삭제합니다. 이 작업은 되돌릴 수 없습니다.';

  @override
  String previewAffectsCount(Object count) {
    return '$count개의 이미지에 영향을 줍니다';
  }

  @override
  String affectCountLabel(Object count) {
    return '영향: $count';
  }

  @override
  String get confirmAddRuleTitle => '규칙 추가 확인';

  @override
  String confirmAddRuleMessage(Object rule) {
    return '규칙 추가: $rule';
  }

  @override
  String get ruleAddedToast => '규칙을 추가했습니다';

  @override
  String get ruleRemovedToast => '규칙을 삭제했습니다';

  @override
  String get invalidDomainInputError => '유효한 도메인을 입력하세요 (*.example.com 지원)';

  @override
  String get manualMarkNsfw => 'NSFW로 표시';

  @override
  String get manualUnmarkNsfw => 'NSFW 표시 해제';

  @override
  String get manualMarkSuccess => 'NSFW로 표시했습니다';

  @override
  String get manualUnmarkSuccess => 'NSFW 표시를 해제했습니다';

  @override
  String get manualMarkFailed => '작업에 실패했습니다';

  @override
  String get nsfwTagLabel => 'NSFW';

  @override
  String get nsfwBlockedByRulesHint =>
      'NSFW 규칙으로 인해 차단되었습니다. 설정 > NSFW 도메인에서 관리하세요.';

  @override
  String get providersTitle => '공급자';

  @override
  String get actionNew => '새로 만들기';

  @override
  String get actionAdd => '추가';

  @override
  String get noProvidersYetHint => '프로바이더가 없습니다. \"새로 만들기\"를 눌러 생성하세요.';

  @override
  String confirmDeleteProviderMessage(Object name) {
    return '\"$name\" 프로바이더를 삭제할까요? 이 작업은 되돌릴 수 없습니다.';
  }

  @override
  String get loadingConversations => '대화를 불러오는 중…';

  @override
  String get noConversations => '대화가 없습니다';

  @override
  String get deleteConversationTitle => '대화 삭제';

  @override
  String confirmDeleteConversationMessage(Object title) {
    return '\"$title\" 대화를 삭제할까요?';
  }

  @override
  String get untitledConversationLabel => '제목 없음 대화';

  @override
  String get searchProviderPlaceholder => '프로바이더 검색';

  @override
  String get searchModelPlaceholder => '모델 검색';

  @override
  String providerSelectedToast(Object name) {
    return '선택한 프로바이더: $name';
  }

  @override
  String get pleaseSelectProviderFirst => '먼저 프로바이더를 선택하세요';

  @override
  String get noModelsForProviderHint =>
      '사용 가능한 모델이 없습니다. 프로바이더 페이지에서 새로 고치거나 직접 추가하세요.';

  @override
  String get noModelsDetectedHint => '모델을 찾을 수 없습니다. 새로 고침하거나 직접 추가하세요.';

  @override
  String modelSwitchedToast(Object model) {
    return '모델을 변경했습니다: $model';
  }

  @override
  String get providerLabel => '프로바이더';

  @override
  String sendMessageToModelPlaceholder(Object model) {
    return '$model에게 메시지 보내기';
  }

  @override
  String get deepThinkingLabel => '심층 추론';

  @override
  String get thinkingInProgress => '생각 중…';

  @override
  String get requestStoppedInfo => '요청이 중지되었습니다';

  @override
  String get reasoningLabel => '추리:';

  @override
  String get answerLabel => '답변:';

  @override
  String get aiSelfModeEnabledToast => '개인 비서: 대화에 사용자 데이터 컨텍스트를 사용합니다';

  @override
  String selectModelWithCounts(Object filtered, Object total) {
    return '모델 선택($filtered/$total)';
  }

  @override
  String modelsCountLabel(Object count) {
    return '모델($count)';
  }

  @override
  String get manualAddModelLabel => '모델 수동 추가';

  @override
  String get inputAndAddModelHint => '모델을 입력 후 추가 (예: gpt-4o-mini)';

  @override
  String get fetchModelsHint =>
      '\"새로 고침\"을 눌러 자동으로 가져옵니다. 실패하면 모델 이름을 직접 추가하세요.';

  @override
  String get interfaceTypeLabel => '인터페이스 유형';

  @override
  String currentTypeLabel(Object type) {
    return '현재: $type';
  }

  @override
  String get nameRequiredError => '이름은 필수입니다';

  @override
  String get nameAlreadyExistsError => '같은 이름이 이미 존재합니다';

  @override
  String get apiKeyRequiredError => 'API 키가 필요합니다';

  @override
  String get baseUrlRequiredForAzureError => 'Azure OpenAI에는 Base URL이 필요합니다';

  @override
  String get atLeastOneModelRequiredError => '모델을 최소 1개 추가하세요';

  @override
  String modelsUpdatedToast(Object count) {
    return '모델을 업데이트했습니다($count)';
  }

  @override
  String get fetchModelsFailedHint => '모델을 가져오지 못했습니다. 직접 추가하세요.';

  @override
  String get useResponseApiLabel => 'Response API 사용(공식 OpenAI만 지원, 서드파티 권장 X)';

  @override
  String get chatPathOptionalLabel => '채팅 경로(선택 사항)';

  @override
  String get azureApiVersionLabel => 'Azure API 버전';

  @override
  String get azureApiVersionHint => '예: 2024-02-15';

  @override
  String get baseUrlHintOpenAI => '예: https://api.openai.com (기본값)';

  @override
  String get baseUrlHintClaude => '예: https://api.anthropic.com';

  @override
  String get baseUrlHintGemini =>
      '예: https://generativelanguage.googleapis.com';

  @override
  String get geminiRegionDialogTitle => 'Gemini 사용 제한';

  @override
  String get geminiRegionDialogMessage =>
      'Gemini 개발자 API 는 Google 이 지원하는 국가/지역에서만 사용할 수 있습니다. Google 계정 정보, 결제 정보, 네트워크 출구가 지원 지역에 있는지 확인하세요. 조건을 충족하지 않으면 서버가 FAILED_PRECONDITION 을 반환합니다. 기업 환경이 필요한 경우 지원 지역 내의 준수 프록시를 통해 요청을 전달하세요.';

  @override
  String get geminiRegionToast =>
      'Gemini 는 지원되는 지역에서만 사용할 수 있습니다. 자세한 내용은 물음표를 눌러 확인하세요.';

  @override
  String baseUrlHintAzure(Object resource) {
    return '필수: https://$resource.openai.azure.com';
  }

  @override
  String get baseUrlHintCustom => 'OpenAI 호환 Base URL을 입력하세요';

  @override
  String get createProviderTitle => '새 프로바이더';

  @override
  String get editProviderTitle => '프로바이더 편집';

  @override
  String get deletedToast => '삭제했습니다';

  @override
  String get providerNotFound => '프로바이더를 찾을 수 없습니다';

  @override
  String get memoryMenuEntry => '메모리 아카이브';

  @override
  String get memoryCenterTitle => '메모리 아카이브';

  @override
  String get memoryClearAllTooltip => '기억 저장소 비우기';

  @override
  String get memoryClearAllConfirmTitle => '기억 저장소 비우기';

  @override
  String get memoryClearAllConfirmMessage =>
      '모든 기억 태그, 이벤트, 증거가 삭제됩니다. 이 작업은 되돌릴 수 없습니다. 계속하시겠습니까?';

  @override
  String get memoryImportSampleTooltip => '테스트용으로 30개 가져오기';

  @override
  String memoryImportSampleSuccess(Object count) {
    return '테스트용으로 $count개의 이벤트를 가져왔습니다';
  }

  @override
  String get memoryImportSampleEmpty => '가져올 기억 이벤트가 없습니다';

  @override
  String memoryImportSampleFailed(Object error) {
    return '가져오기에 실패했습니다: $error';
  }

  @override
  String get memoryPauseTooltip => '처리 일시중지';

  @override
  String get memoryPauseSuccess => '분석을 일시중지했습니다';

  @override
  String memoryPauseFailed(Object error) {
    return '일시중지 실패: $error';
  }

  @override
  String get memoryPendingSectionTitle => '확인 대기 태그';

  @override
  String get memoryConfirmedSectionTitle => '확인된 태그';

  @override
  String get memoryRecentEventsSectionTitle => '최근 이벤트';

  @override
  String get memoryNoPending => '확인 대기 태그가 없습니다';

  @override
  String get memoryNoConfirmed => '확인된 태그가 아직 없습니다';

  @override
  String get memoryNoEvents => '관련 이벤트가 아직 없습니다';

  @override
  String get memoryConfirmAction => '확인됨으로 표시';

  @override
  String get memoryStatusPending => '확인 대기';

  @override
  String get memoryStatusConfirmed => '확인됨';

  @override
  String get memoryCategoryIdentity => '신원';

  @override
  String get memoryCategoryRelationship => '관계';

  @override
  String get memoryCategoryInterest => '관심사';

  @override
  String get memoryCategoryBehavior => '행동';

  @override
  String get memoryCategoryPreference => '선호';

  @override
  String get memoryCategoryOther => '기타';

  @override
  String memoryConfidenceLabel(Object value) {
    return '신뢰도: $value%';
  }

  @override
  String memoryOccurrencesLabel(Object count) {
    return '발생 횟수: $count';
  }

  @override
  String memoryFirstSeenLabel(Object date) {
    return '처음 발견: $date';
  }

  @override
  String memoryLastSeenLabel(Object date) {
    return '최근 발견: $date';
  }

  @override
  String memoryEvidenceCountLabel(Object count) {
    return '증거: $count건';
  }

  @override
  String get memoryEventContainsContext => '사용자 관련 정보 포함';

  @override
  String get memoryEventNoContext => '사용자 관련 정보가 감지되지 않았습니다';

  @override
  String memoryEventTimeLabel(Object date) {
    return '시간: $date';
  }

  @override
  String memoryEventSourceLabel(Object source) {
    return '출처: $source';
  }

  @override
  String memoryEventTypeLabel(Object type) {
    return '유형: $type';
  }

  @override
  String get memoryProgressIdle => '과거 이벤트 처리를 대기 중';

  @override
  String get memoryProgressRunning => '과거 이벤트 분석 중';

  @override
  String memoryProgressRunningDetail(
    Object processed,
    Object total,
    Object percent,
  ) {
    return '$processed/$total일 처리됨 ($percent%)';
  }

  @override
  String memoryProgressNewTagsDetail(Object count) {
    return '새 태그: $count';
  }

  @override
  String memoryProgressCompleted(Object total, Object seconds) {
    return '과거 이벤트 분석 완료: 총 $total일, 소요 $seconds초';
  }

  @override
  String memoryProgressFailed(Object message) {
    return '분석 실패: $message';
  }

  @override
  String memoryProgressFailedEvent(Object event) {
    return '실패한 이벤트: $event';
  }

  @override
  String memoryProgressPreparing(Object stage) {
    return '준비 중: $stage';
  }

  @override
  String get memoryProgressStageSyncSegments => '스크린샷 이벤트 동기화';

  @override
  String get memoryProgressStageSyncChats => '대화 기록 동기화';

  @override
  String get memoryProgressStageDispatch => '히스토리 분석 시작';

  @override
  String get memoryRefreshTooltip => '새로고침';

  @override
  String memoryConfirmSuccessToast(Object label) {
    return '\"$label\" 태그가 확인되었습니다';
  }

  @override
  String memoryConfirmFailedToast(Object message) {
    return '실패: $message';
  }

  @override
  String get memorySnapshotUpdated => '메모리 스냅샷이 업데이트되었습니다';

  @override
  String get memoryStartProcessingAction => '과거 이벤트 분석 시작';

  @override
  String get memoryStartProcessingActionShort => '분석 시작';

  @override
  String get memoryMalformedResponseTitle => '비정상 응답이 감지되어 분석이 일시 중지되었습니다';

  @override
  String memoryMalformedResponseSubtitle(Object eventId) {
    return '이벤트 $eventId의 응답에 \"当前用户描述：\" 표시가 없습니다. 확인 후 다시 시작하세요.';
  }

  @override
  String get memoryMalformedResponseSubtitleNoId =>
      '최근 응답에 \"当前用户描述：\" 표시가 없습니다. 확인 후 다시 시작하세요.';

  @override
  String get memoryMalformedResponseRawLabel => '원본 응답:';

  @override
  String get memoryDeleteTagAction => '태그 삭제';

  @override
  String get memoryDeleteTagConfirmTitle => '태그 삭제';

  @override
  String memoryDeleteTagConfirmMessage(Object tagLabel) {
    return '\"$tagLabel\" 태그를 삭제할까요? 관련 증거도 제거됩니다.';
  }

  @override
  String get memoryDeleteTagSuccess => '태그가 삭제되었습니다';

  @override
  String memoryDeleteTagFailed(Object error) {
    return '삭제 실패: $error';
  }

  @override
  String get memoryStatusPendingIndicator => '확인 대기';

  @override
  String get memoryStatusConfirmedIndicator => '확인됨';

  @override
  String get memoryReprocessAction => '모든 과거 이벤트 재분석';

  @override
  String get memoryStartProcessingToast => '과거 이벤트 분석을 시작했습니다';

  @override
  String get memoryLoadMore => '더 보기';

  @override
  String get memoryCenterHeroTitle => '캐릭터 프로필';

  @override
  String get memoryCenterHeroSubtitle => '이벤트에서 추출한 RPG 스타일의 사용자 기록';

  @override
  String memoryCenterPendingCountLabel(Object count) {
    return '보류: $count';
  }

  @override
  String memoryCenterConfirmedCountLabel(Object count) {
    return '확정: $count';
  }

  @override
  String memoryCenterEventCountLabel(Object count) {
    return '관련 이벤트: $count';
  }

  @override
  String get memoryTagDetailTitle => '태그 상세';

  @override
  String get memoryTagDetailRefresh => '새로고침';

  @override
  String get memoryTagDetailInfoTitle => '프로필';

  @override
  String get memoryTagDetailStatisticsTitle => '속성';

  @override
  String memoryTagDetailOccurrences(Object count) {
    return '등장 횟수: $count';
  }

  @override
  String memoryTagDetailConfidence(Object confidence) {
    return '신뢰도: $confidence';
  }

  @override
  String memoryTagDetailFirstSeen(Object date) {
    return '첫 등장: $date';
  }

  @override
  String memoryTagDetailLastSeen(Object date) {
    return '마지막 등장: $date';
  }

  @override
  String get memoryTagDetailEvidenceTitle => '증거 목록';

  @override
  String memoryTagDetailEvidenceCount(Object count) {
    return '총 증거 수: $count';
  }

  @override
  String get memoryTagDetailNoEvidence => '증거가 아직 없습니다';

  @override
  String get memoryTagDetailLoadFailed => '태그 데이터를 불러오지 못했습니다';

  @override
  String get memoryEvidenceInferenceLabel => '추론 설명';

  @override
  String get memoryEvidenceNotesLabel => '메모';

  @override
  String get memoryEvidenceNoNotes => '메모 없음';

  @override
  String get memoryEvidenceEventHeading => '출처 이벤트';

  @override
  String get memoryEvidenceUserEditedBadge => '사용자 편집';

  @override
  String get conversationsSectionTitle => '대화';

  @override
  String get displaySectionTitle => '디스플레이';

  @override
  String get streamRenderImagesTitle => '스트리밍 중 이미지 렌더링';

  @override
  String get streamRenderImagesDesc => '스크롤에 영향을 줄 수 있습니다';

  @override
  String get themeColorTitle => '테마 색상';

  @override
  String get themeColorDesc => '앱의 기본 색상을 사용자 지정하세요';

  @override
  String get chooseThemeColorTitle => '테마 색상 선택';

  @override
  String get loggingTitle => '로그';

  @override
  String get loggingDesc => '중앙 집중식 로그 활성화(기본값)';

  @override
  String get loggingAiTitle => 'AI 로그';

  @override
  String get loggingScreenshotTitle => '스크린샷 로그';

  @override
  String get loggingAiDesc => 'AI 요청과 응답을 기록합니다';

  @override
  String get loggingScreenshotDesc => '스크린샷 캡처 및 정리를 기록합니다';

  @override
  String get themeModeAuto => '자동';

  @override
  String get themeModeLight => '라이트';

  @override
  String get themeModeDark => '다크';

  @override
  String get appStatsSectionTitle => '스크린샷 통계';

  @override
  String appStatsCountLabel(Object count) {
    return '스크린샷 수: $count';
  }

  @override
  String appStatsSizeLabel(String size) {
    return '총 용량: $size';
  }

  @override
  String get appStatsLastCaptureUnknown => '마지막 캡처: 알 수 없음';

  @override
  String appStatsLastCaptureLabel(Object time) {
    return '마지막 캡처: $time';
  }

  @override
  String get recomputeAppStatsAction => '통계 재계산';

  @override
  String get recomputeAppStatsDescription =>
      '가져오기 후 수량이나 용량이 맞지 않을 때 수동으로 새로 고칠 수 있습니다.';

  @override
  String get recomputeAppStatsSuccess => '통계를 새로 고쳤습니다';

  @override
  String get recomputeAppStatsConfirmTitle => '통계 재계산';

  @override
  String get recomputeAppStatsConfirmMessage =>
      '이 앱의 스크린샷 통계를 다시 계산할까요? 데이터가 많으면 시간이 걸릴 수 있습니다.';

  @override
  String get appStatsCountTitle => '스크린샷';

  @override
  String get appStatsSizeTitle => '총 용량';

  @override
  String get appStatsLastCaptureTitle => '마지막 캡처';

  @override
  String get aiEmptySelfTitle => '개인 비서 준비 완료';

  @override
  String get aiEmptySelfSubtitle => '무엇이든 질문하세요. 데이터 컨텍스트를 활용해 답변합니다.';
}
