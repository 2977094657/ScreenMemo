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
  String get navSelectApps => '스크린샷 앱 선택';

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
  String get permissionsSectionDesc => '저장소/알림/접근성/상주';

  @override
  String get displayAndSortSectionTitle => '디스플레이 및 정렬';

  @override
  String get screenshotSectionTitle => '캡처 설정';

  @override
  String get screenshotSectionDesc => '간격/품질/만료 정리';

  @override
  String get segmentSummarySectionTitle => '다이내믹 설정';

  @override
  String get segmentSummarySectionDesc => '샘플링 / 길이 / 병합 / AI 요청 간격';

  @override
  String get dailyReminderSectionTitle => '일일 요약 알림';

  @override
  String get dailyReminderSectionDesc => '시간/배너 권한/테스트';

  @override
  String get aiAssistantSectionTitle => 'AI 어시스턴트';

  @override
  String get dataBackupSectionTitle => '데이터 및 백업';

  @override
  String get dataBackupSectionDesc => '저장소/가져오기/내보내기/재계산';

  @override
  String get advancedSectionTitle => '고급';

  @override
  String get advancedSectionDesc => '로그 및 성능 옵션';

  @override
  String get storageAnalysisEntryTitle => '저장소 분석';

  @override
  String get storageAnalysisEntryDesc => '앱의 저장소 사용량을 자세히 확인합니다';

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
  String get storageAnalysisPageTitle => '저장소 분석';

  @override
  String get storageAnalysisLoadFailed => '저장소 데이터를 불러오지 못했습니다';

  @override
  String get storageAnalysisEmptyMessage => '표시할 저장소 데이터가 없습니다';

  @override
  String get storageAnalysisSummaryTitle => '저장소 요약';

  @override
  String get storageAnalysisTotalLabel => '전체';

  @override
  String get storageAnalysisAppLabel => '앱';

  @override
  String get storageAnalysisDataLabel => '앱 데이터';

  @override
  String get storageAnalysisCacheLabel => '캐시';

  @override
  String get storageAnalysisExternalLabel => '외부 로그';

  @override
  String storageAnalysisScanTimestamp(Object timestamp) {
    return '스캔 시각: $timestamp';
  }

  @override
  String storageAnalysisScanDurationSeconds(Object seconds) {
    return '스캔 시간: $seconds초';
  }

  @override
  String storageAnalysisScanDurationMilliseconds(Object milliseconds) {
    return '스캔 시간: $milliseconds밀리초';
  }

  @override
  String get storageAnalysisManualNote =>
      '사용량 접근 권한이 없어 로컬 측정값을 표시합니다. 시스템 설정과 다를 수 있습니다.';

  @override
  String get storageAnalysisUsagePermissionMissingTitle => '사용량 접근 권한 필요';

  @override
  String get storageAnalysisUsagePermissionMissingDesc =>
      'Android 설정과 동일한 저장소 통계를 가져오려면 시스템 설정에서 \'사용량 접근\'을 허용하세요.';

  @override
  String get storageAnalysisUsagePermissionButton => '설정 열기';

  @override
  String get storageAnalysisPartialErrors => '일부 통계를 불러오지 못했습니다';

  @override
  String get storageAnalysisBreakdownTitle => '상세 분포';

  @override
  String storageAnalysisFileCount(Object count) {
    return '파일 $count개';
  }

  @override
  String get storageAnalysisPathCopied => '경로를 복사했습니다';

  @override
  String get storageAnalysisLabelFiles => 'files 디렉터리';

  @override
  String get storageAnalysisLabelOutput => 'output 디렉터리';

  @override
  String get storageAnalysisLabelScreenshots => '스크린샷 라이브러리';

  @override
  String get storageAnalysisLabelOutputDatabases => 'output/databases';

  @override
  String get storageAnalysisLabelSharedPrefs => 'shared_prefs';

  @override
  String get storageAnalysisLabelNoBackup => 'no_backup';

  @override
  String get storageAnalysisLabelAppFlutter => 'app_flutter';

  @override
  String get storageAnalysisLabelDatabases => 'databases 디렉터리';

  @override
  String get storageAnalysisLabelCacheDir => 'cache 디렉터리';

  @override
  String get storageAnalysisLabelCodeCache => 'code_cache';

  @override
  String get storageAnalysisLabelExternalLogs => '외부 로그';

  @override
  String storageAnalysisOthersLabel(Object count) {
    return '기타 ($count개)';
  }

  @override
  String get storageAnalysisOthersFallback => '기타';

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
  String get setCompressDaysDialogTitle => '일수 설정';

  @override
  String get compressDaysLabel => '일수';

  @override
  String get compressDaysInputHint => '일수를 입력하세요';

  @override
  String get compressDaysInvalidError => '1 이상의 일수를 입력하세요.';

  @override
  String get compressHistoryTitle => '과거 압축';

  @override
  String compressHistoryDescription(Object days, Object size) {
    return '최근 $days일 동안의 스크린샷을 $size KB 목표로 압축하며, 초과한 파일만 처리합니다.';
  }

  @override
  String compressHistorySetDays(Object days) {
    return '일수: $days';
  }

  @override
  String compressHistorySetTarget(Object size) {
    return '목표 크기: ${size}KB';
  }

  @override
  String compressHistoryProgress(Object handled, Object total, Object saved) {
    return '$handled/$total 처리 • 절약 $saved';
  }

  @override
  String get compressHistoryAction => '지금 압축';

  @override
  String get compressHistoryRequireTarget => '압축 전에 목표 크기를 먼저 활성화하세요.';

  @override
  String compressHistorySuccess(int count, Object size) {
    return '$count개의 이미지를 압축했고 $size를 절약했습니다.';
  }

  @override
  String get compressHistoryNothing => '최근 스크린샷은 이미 목표 크기를 만족합니다.';

  @override
  String get compressHistoryFailure => '압축에 실패했습니다. 다시 시도해 주세요.';

  @override
  String get exportDataTitle => '데이터 내보내기';

  @override
  String get exportDataDesc => 'ZIP을 Download/ScreenMemory에 내보내기';

  @override
  String get importDataTitle => '데이터 가져오기';

  @override
  String get importDataDesc => 'ZIP 파일을 앱 저장소로 가져오기';

  @override
  String get importModeTitle => '가져오기 방식을 선택하세요';

  @override
  String get importModeOverwriteTitle => '덮어쓰기 가져오기';

  @override
  String get importModeOverwriteDesc => '현재 데이터 디렉터리를 교체합니다. 전체 백업 복원에 사용하세요.';

  @override
  String get importModeMergeTitle => '병합 가져오기';

  @override
  String get importModeMergeDesc => '기존 데이터를 유지하고 압축 파일 내용을 중복 제거 후 병합합니다.';

  @override
  String get mergeProgressCopying => '스크린샷 파일을 복사하는 중…';

  @override
  String get mergeProgressCopyingGeneric => '추가 리소스를 복사하는 중…';

  @override
  String get mergeProgressMergingDb => '데이터베이스를 병합하는 중…';

  @override
  String get mergeProgressFinalizing => '병합을 마무리하는 중…';

  @override
  String get mergeCompleteTitle => '병합이 완료되었습니다';

  @override
  String mergeReportInserted(int count) {
    return '새 스크린샷: $count';
  }

  @override
  String mergeReportSkipped(int count) {
    return '중복 건수 건너뜀: $count';
  }

  @override
  String mergeReportCopied(int count) {
    return '복사한 파일: $count';
  }

  @override
  String mergeReportMemoryEvidence(int count) {
    return '추가된 태그 증거: $count';
  }

  @override
  String mergeReportAffectedPackages(String packages) {
    return '영향받은 앱 패키지: $packages';
  }

  @override
  String get mergeReportWarnings => '확인해야 할 경고:';

  @override
  String get mergeReportNoWarnings => '경고가 없습니다.';

  @override
  String get recalculateAllTitle => '전체 데이터 다시 집계';

  @override
  String get recalculateAllDesc =>
      '모든 앱을 다시 스캔하여 내비게이션의 일수·앱·스크린샷·용량 통계를 새로 고칩니다.';

  @override
  String get recalculateAllAction => '다시 집계';

  @override
  String get recalculateAllProgress => '모든 앱의 통계를 다시 계산하는 중…';

  @override
  String get recalculateAllSuccess => '전체 통계를 새로 고쳤습니다.';

  @override
  String get recalculateAllFailedTitle => '다시 집계에 실패했습니다';

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
  String get dynamicMergeMaxSpanTitle => '동적 병합: 전체 범위 상한(분)';

  @override
  String dynamicMergeMaxSpanDesc(Object minutes) {
    return '현재: $minutes분(0 = 제한 없음)';
  }

  @override
  String get dynamicMergeMaxGapTitle => '동적 병합: 이벤트 간 최대 간격(분)';

  @override
  String dynamicMergeMaxGapDesc(Object minutes) {
    return '현재: $minutes분(0 = 제한 없음)';
  }

  @override
  String get dynamicMergeMaxImagesTitle => '동적 병합: 이미지 수 상한(장)';

  @override
  String dynamicMergeMaxImagesDesc(Object count) {
    return '현재: $count장(0 = 제한 없음)';
  }

  @override
  String get dynamicMergeLimitInputHint => '0 이상의 정수를 입력하세요(0 = 제한 없음)';

  @override
  String get dynamicMergeLimitInvalidError => '0 이상의 유효한 정수를 입력하세요';

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
  String get loadMore => '더 보기';

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
  String get dailySummaryGeneratingTitle => '오늘 요약을 생성하는 중입니다';

  @override
  String get dailySummaryGeneratingHint => '읽기 레이아웃을 유지한 채 생성 결과가 순차적으로 반영됩니다.';

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
  String get timelineReplay => '리플레이';

  @override
  String get timelineReplayGenerate => '리플레이 생성';

  @override
  String get timelineReplayUseSelectedDay => '선택한 날짜 사용';

  @override
  String get timelineReplayStartTime => '시작 시간';

  @override
  String get timelineReplayEndTime => '종료 시간';

  @override
  String get timelineReplayDuration => '목표 길이';

  @override
  String get timelineReplayFps => 'FPS';

  @override
  String get timelineReplayResolution => '해상도';

  @override
  String get timelineReplayQuality => '품질';

  @override
  String get timelineReplayOverlay => '시간/앱 오버레이';

  @override
  String get timelineReplaySaveToGallery => '생성 후 갤러리에 저장';

  @override
  String get timelineReplayAppProgressBar => '앱 진행 바';

  @override
  String get timelineReplayNsfw => 'NSFW 콘텐츠';

  @override
  String get timelineReplayNsfwMask => '마스크 표시';

  @override
  String get timelineReplayNsfwShow => '완전히 표시';

  @override
  String get timelineReplayNsfwHide => '표시 안 함';

  @override
  String get timelineReplayFpsInvalid => '1~120을 입력하세요';

  @override
  String timelineReplayGeneratingRange(Object range) {
    return '$range 동영상을 생성 중…';
  }

  @override
  String get timelineReplayPreparing => '리플레이 준비 중…';

  @override
  String get timelineReplayEncoding => '동영상 생성 중…';

  @override
  String get timelineReplayNoScreenshots => '이 시간 범위에 스크린샷이 없습니다';

  @override
  String get timelineReplayFailed => '리플레이 생성에 실패했습니다';

  @override
  String get timelineReplayReady => '리플레이가 생성되었습니다';

  @override
  String get timelineReplayNotificationHint =>
      '리플레이를 생성 중입니다. 알림에서 진행 상황을 확인할 수 있습니다.';

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
  String mergedOriginalEventsTitle(Object count) {
    return '원본 이벤트($count)';
  }

  @override
  String mergedOriginalEventTitle(Object index) {
    return '원본 이벤트 $index';
  }

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
  String get articleGenerating => '기사 생성 중...';

  @override
  String get articleGenerateSuccess => '기사가 성공적으로 생성되었습니다';

  @override
  String get articleGenerateFailed => '기사 생성에 실패했습니다';

  @override
  String get articleCopySuccess => '기사가 클립보드에 복사되었습니다';

  @override
  String get articleLogTitle => '생성 로그';

  @override
  String get copyPersonaTooltip => '사용자 프로필 복사';

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
      '제안된 아이디어:\n- 주간 추세나 변화 포인트를 강조\n- 실행 가능한 후속 조치나 주의할 점을 요청\n- JSON 출력 구조 변경을 요청하지 마세요.';

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
  String get weeklySummaryPromptLabel => '주간 요약 프롬프트';

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
  String get savedWeeklyPromptToast => '주간 프롬프트를 저장했습니다';

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
  String get aiResultAutoRetriedHint =>
      '불완전한 AI 응답을 복구하기 위해 이 결과는 자동으로 1회 재시도되었습니다.';

  @override
  String get aiResultAutoRetryFailedHint => '자동 재시도에도 실패했습니다. 수동으로 다시 생성해 주세요.';

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
  String get aiImageTagsTitle => '이미지 태그';

  @override
  String get aiVisibleTextTitle => '표시된 텍스트';

  @override
  String get aiImageDescriptionsTitle => '이미지 설명';

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
  String get filterTimeCustomDays => '사용자 지정 일수';

  @override
  String get filterTimeCustomDaysHint => '1-365일 입력';

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
  String get modelsPathOptionalLabel => '모델 경로(선택 사항)';

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
  String get conversationsSectionTitle => '대화';

  @override
  String get displaySectionTitle => '디스플레이';

  @override
  String get displaySectionDesc => '테마 모드/개인정보/NSFW';

  @override
  String get themeModeTitle => '테마 모드';

  @override
  String get streamRenderImagesTitle => '스트리밍 중 이미지 렌더링';

  @override
  String get streamRenderImagesDesc => '스크롤에 영향을 줄 수 있습니다';

  @override
  String get aiChatPerfOverlayTitle => 'AIChat 성능 로그 오버레이';

  @override
  String get aiChatPerfOverlayDesc => 'AIChat 페이지에 Perf 로그 창을 표시합니다(문제 해결용)';

  @override
  String get themeColorTitle => '테마 색상';

  @override
  String get themeColorDesc => '앱의 기본 색상을 사용자 지정하세요';

  @override
  String get chooseThemeColorTitle => '테마 색상 선택';

  @override
  String get pageBackgroundTitle => '페이지 배경';

  @override
  String get pageBackgroundDesc => '라이트 모드 메인 페이지 배경색';

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
  String get aiEmptySelfTitle => '지금의 고요도 정리의 한 순간이에요';

  @override
  String get aiEmptySelfSubtitle => '이 공간을 열면 두 번째 기억을 넘기듯, 언제든 함께 돌아볼 수 있어요.';

  @override
  String get homeMorningTipsTitle => '아침 제안';

  @override
  String get homeMorningTipsLoading => '어제의 흔적에서 영감을 정리하는 중…';

  @override
  String get homeMorningTipsPullHint => '당겨서 어제의 단서로 빚은 오늘의 영감을 펼쳐보세요';

  @override
  String get homeMorningTipsReleaseHint => '놓으면 어제에서 온 새로운 영감이 찾아와요';

  @override
  String get homeMorningTipsEmpty => '여기 잠시 머무는 순간도 자신을 돌보는 시간이니, 천천히 숨을 고르세요.';

  @override
  String get homeMorningTipsViewAll => '데일리 요약 열기';

  @override
  String get homeMorningTipsDismiss => '카드 닫기';

  @override
  String get homeMorningTipsCooldownHint => '잠시 쉬었다가 다시 당겨주세요';

  @override
  String get homeMorningTipsCooldownMessage =>
      '많이 새로고침했어요. 잠시 휴대폰을 내려놓고 현실의 풍경을 바라보세요.';

  @override
  String get expireCleanupConfirmTitle => '스크린샷 만료 정리를 활성화하시겠습니까?';

  @override
  String expireCleanupConfirmMessage(Object days) {
    return '활성화하면 $days일이 지난 스크린샷 이미지가 즉시 삭제됩니다.\n\n참고: 이미지 파일만 삭제되며, 이벤트, 요약 등의 콘텐츠는 유지됩니다.';
  }

  @override
  String get expireCleanupConfirmAction => '활성화';

  @override
  String get desktopMergerTitle => '데이터 병합 도구';

  @override
  String get desktopMergerDescription => '여러 백업 파일을 효율적으로 병합';

  @override
  String get desktopMergerSteps =>
      '1. 출력 디렉토리 선택 (병합된 데이터가 여기에 저장됩니다)\n2. 병합할 ZIP 백업 파일 추가\n3. 병합 시작 클릭';

  @override
  String get desktopMergerOutputDir => '출력 디렉토리';

  @override
  String get desktopMergerSelectOutputDir => '출력 디렉토리 선택...';

  @override
  String get desktopMergerBrowse => '찾아보기';

  @override
  String get desktopMergerZipFiles => 'ZIP 백업 파일';

  @override
  String desktopMergerSelectedCount(Object count) {
    return '$count개 파일 선택됨';
  }

  @override
  String get desktopMergerAddFiles => '파일 추가';

  @override
  String get desktopMergerNoFiles => '선택된 파일 없음';

  @override
  String get desktopMergerDragHint => '위 버튼을 클릭하여 ZIP 백업 파일 추가';

  @override
  String get desktopMergerResultTitle => '병합 결과';

  @override
  String desktopMergerInsertedCount(Object count) {
    return '+$count개 스크린샷';
  }

  @override
  String get desktopMergerClear => '목록 지우기';

  @override
  String get desktopMergerMerging => '병합 중...';

  @override
  String get desktopMergerStart => '병합 시작';

  @override
  String get desktopMergerSelectZips => 'ZIP 백업 파일 선택';

  @override
  String get desktopMergerStageExtracting => '압축 해제 중...';

  @override
  String get desktopMergerStageCopying => '파일 복사 중...';

  @override
  String get desktopMergerStageMerging => '데이터베이스 병합 중...';

  @override
  String get desktopMergerStageFinalizing => '완료 중...';

  @override
  String get desktopMergerStageProcessing => '처리 중...';

  @override
  String get desktopMergerStageCompleted => '병합 완료';

  @override
  String get desktopMergerLiveStats => '실시간 통계';

  @override
  String desktopMergerProcessingFile(Object fileName) {
    return '처리 중: $fileName';
  }

  @override
  String desktopMergerFileProgress(Object current, Object total) {
    return '파일 진행: $current/$total';
  }

  @override
  String get desktopMergerStatScreenshots => '새 스크린샷';

  @override
  String get desktopMergerStatSkipped => '건너뛴 중복';

  @override
  String get desktopMergerStatFiles => '복사된 파일';

  @override
  String get desktopMergerStatReused => '재사용 파일';

  @override
  String get desktopMergerStatTags => '메모리 태그';

  @override
  String get desktopMergerStatEvidence => '메모리 증거';

  @override
  String get desktopMergerSummaryTitle => '병합 요약';

  @override
  String desktopMergerSummaryTotal(Object count) {
    return '총 $count개 파일 처리됨';
  }

  @override
  String desktopMergerSummarySuccess(Object count) {
    return '성공: $count';
  }

  @override
  String desktopMergerSummaryFailed(Object count) {
    return '실패: $count';
  }

  @override
  String desktopMergerAffectedApps(Object count) {
    return '영향받은 앱 ($count)';
  }

  @override
  String desktopMergerWarnings(Object count) {
    return '경고 ($count)';
  }

  @override
  String get desktopMergerDetailTitle => '상세 결과';

  @override
  String get desktopMergerFileSuccess => '성공';

  @override
  String get desktopMergerFileFailed => '실패';

  @override
  String get desktopMergerNoData => '데이터 변경 없음';

  @override
  String get desktopMergerExpandAll => '모두 펼치기';

  @override
  String get desktopMergerCollapseAll => '모두 접기';

  @override
  String get desktopMergerStagePacking => 'ZIP 압축 중...';

  @override
  String get desktopMergerOutputZip => '출력 파일';

  @override
  String get desktopMergerOpenFolder => '폴더 열기';

  @override
  String desktopMergerPackingProgress(Object percent) {
    return '압축 중: $percent%';
  }

  @override
  String get desktopMergerMinFilesHint => '병합하려면 최소 2개의 백업 파일을 선택하세요';

  @override
  String get desktopMergerExtractingHint =>
      '백업 파일 압축 해제 중입니다. 대용량 백업(수만 장의 스크린샷)은 몇 분 정도 걸릴 수 있습니다. 잠시만 기다려 주세요...';

  @override
  String get desktopMergerCopyingHint => '스크린샷 파일 복사 중, 기존 이미지 건너뛰기...';

  @override
  String get desktopMergerMergingHint => '스마트 중복 제거로 데이터베이스 레코드 병합 중...';

  @override
  String get desktopMergerPackingHint => '병합된 결과를 ZIP 파일로 압축 중...';

  @override
  String get unknownTitle => '알 수 없음';

  @override
  String get unknownTime => '알 수 없는 시간';

  @override
  String get empty => '비어 있음';

  @override
  String get evidenceTitle => '증거';

  @override
  String get runtimeDiagnosticCopied => '진단 정보를 복사했습니다';

  @override
  String get runtimeDiagnosticCopyFailed => '진단 정보 복사에 실패했습니다';

  @override
  String get runtimeDiagnosticNoFileToOpen => '열 수 있는 진단 파일이 없습니다';

  @override
  String get runtimeDiagnosticOpenAttempted => '진단 파일 열기를 시도했습니다';

  @override
  String get runtimeDiagnosticOpenFallbackCopiedPath =>
      '직접 열 수 없어 로그 경로를 복사했습니다';

  @override
  String get runtimeDiagnosticCopyInfoAction => '정보 복사';

  @override
  String get runtimeDiagnosticOpenFileAction => '이 파일 열기';

  @override
  String get runtimeDiagnosticOpenSettingsAction => '설정 열기';

  @override
  String get importDiagnosticsReportCopied => '진단 보고서를 복사했습니다';

  @override
  String get importDiagnosticsNoRepairableOcr => '수리할 OCR 텍스트가 없어 진단을 새로고침했습니다';

  @override
  String get importDiagnosticsOcrRepairStarted =>
      '백그라운드에서 수리를 시작했습니다. 알림에서 진행 상황을 확인하세요.';

  @override
  String get importDiagnosticsOcrRepairResumed =>
      '백그라운드 수리 작업을 재개했습니다. 알림에서 진행 상황을 확인하세요.';

  @override
  String get importDiagnosticsOcrRepairStopped => 'OCR 텍스트 수리가 중지되었습니다';

  @override
  String get importDiagnosticsStopRepairFailed => '수리 중지에 실패했습니다';

  @override
  String get importDiagnosticsTitle => '가져오기 진단';

  @override
  String get importDiagnosticsFailedTitle => '진단 실패';

  @override
  String importDiagnosticsDurationMs(Object durationMs) {
    return '소요 시간: ${durationMs}ms';
  }

  @override
  String get importDiagnosticsBackgroundRepairTask => '백그라운드 수리 작업';

  @override
  String get importDiagnosticsStopRepair => '수리 중지';

  @override
  String get importDiagnosticsRepairIndex => '인덱스 수리';

  @override
  String get memoryTabView => '메모리 보기';

  @override
  String get memoryTabRebuild => '한 번에 재구축';

  @override
  String memorySignalStatusChip(Object label, Object count) {
    return '$label $count';
  }

  @override
  String get memoryForceCreate => '강제 새로 만들기';

  @override
  String get actionIgnore => '무시';

  @override
  String get memoryGenerateSuggestions => '제안 생성';

  @override
  String get memoryApplyAllSuggestions => '모두 적용';

  @override
  String get memoryApplyThisSuggestion => '이 항목 적용';

  @override
  String get memoryDontApplySuggestion => '적용 안 함';

  @override
  String get memoryCopyError => '오류 복사';

  @override
  String get actionDescription => '설명';

  @override
  String get memoryRebuildAction => '한 번에 재구축';

  @override
  String get actionStop => '중지';

  @override
  String get memoryUriInputHint => 'URI 입력(예: core://my_user)';

  @override
  String get memorySearchHint => '메모리 내용/경로 검색…';

  @override
  String get memoryRoot => '루트';

  @override
  String get memoryParent => '상위';

  @override
  String get memoryBoot => 'boot';

  @override
  String get memoryRecent => 'recent';

  @override
  String get memoryIndex => 'index';

  @override
  String get providerAddAtLeastOneEnabledApiKey => '활성화된 API Key를 하나 이상 추가하세요.';

  @override
  String get providerSaveBeforeBatchTest => '일괄 테스트 전에 제공업체를 먼저 저장하세요.';

  @override
  String get providerKeepOneEnabledApiKey =>
      '활성화되어 있고 비어 있지 않은 API Key를 하나 이상 유지하세요.';

  @override
  String get providerBatchTestFailed => '일괄 테스트에 실패했습니다. 나중에 다시 시도하세요.';

  @override
  String get providerBatchTestResultTitle => '일괄 테스트 결과';

  @override
  String get actionClose => '닫기';

  @override
  String get providerOnlyOneApiKeyCanEdit => '한 번에 하나의 API Key만 편집할 수 있습니다';

  @override
  String get providerAddApiKey => 'API Key 추가';

  @override
  String get providerEditApiKey => 'API Key 편집';

  @override
  String get providerFetchModelsAndBalance => '모델과 잔액 가져오기';

  @override
  String get actionSaving => '저장 중';

  @override
  String get providerFetchModelsFailedManual =>
      '모델을 가져오지 못했습니다. 수동으로 추가할 수 있습니다.';

  @override
  String providerDeletedApiKeys(Object count) {
    return 'API Key $count개를 삭제했습니다';
  }

  @override
  String get providerAddKeyButton => 'Key 추가';

  @override
  String get providerBatchTestButton => '일괄 테스트';

  @override
  String get providerDeleteAllKeys => '모두 삭제';

  @override
  String get providerNoApiKeys => 'API Key가 없습니다.';

  @override
  String get balanceEndpointNone => '조회 안 함';

  @override
  String get balanceEndpointNewApi => 'new-api（/dashboard/billing）';

  @override
  String get balanceEndpointSub2api => 'sub2api（/v1/usage）';

  @override
  String get segmentEntryLogHint => '길게 눌러 텍스트를 선택하거나 복사 버튼을 눌러 한 번에 복사하세요.';

  @override
  String get segmentEntryLogCopied => '동적 진입 로그를 복사했습니다';

  @override
  String get copyLogAction => '로그 복사';

  @override
  String get segmentDynamicConcurrencySaveFailed => '일별 동시 처리 수 저장 실패';

  @override
  String get dynamicAutoRepairEnabled => '자동 보수가 켜졌습니다';

  @override
  String get dynamicAutoRepairPaused => '자동 보수가 일시 중지되었습니다';

  @override
  String get dynamicAutoRepairToggleFailed => '자동 보수 전환 실패';

  @override
  String get dynamicRebuildStart => '재구축 시작';

  @override
  String get dynamicRebuildContinue => '재구축 계속';

  @override
  String savedToPath(Object path) {
    return '저장 위치: $path';
  }

  @override
  String get dynamicRebuildNoSegments => '재구축할 동적 항목이 없습니다';

  @override
  String dynamicRebuildSwitchedModelContinue(Object model) {
    return '$model 모델로 전환하여 재구축을 계속합니다';
  }

  @override
  String get dynamicRebuildStartedInBackground =>
      '백그라운드에서 재구축을 시작했습니다. 알림에서 진행 상황을 확인하세요.';

  @override
  String get dynamicRebuildTaskResumed => '백그라운드 재구축 작업이 재개되었습니다';

  @override
  String get dynamicRebuildStopped => '동적 재구축이 중지되었습니다';

  @override
  String get dynamicRebuildStopFailed => '동적 재구축 중지 실패';

  @override
  String get dynamicRebuildBlockedRetry =>
      '전체 재구축 중이라 단일 항목 재생성을 일시적으로 사용할 수 없습니다.';

  @override
  String get dynamicRebuildBlockedForceMerge =>
      '전체 재구축 중이라 수동 강제 병합을 일시적으로 사용할 수 없습니다.';

  @override
  String get rawResponseRetentionDaysTitle => '보관 일수 설정';

  @override
  String get rawResponseRetentionDaysLabel => '보관 일수';

  @override
  String get rawResponseRetentionDaysHint => '0보다 큰 숫자를 입력하세요';

  @override
  String get rawResponseCleanupSaved => '원본 응답 정리 설정이 저장되었습니다.';

  @override
  String get chatContextTitlePrefix => '대화 컨텍스트(';

  @override
  String get chatContextTitleMemory => '메모리';

  @override
  String get chatContextTitleSuffix => ')';

  @override
  String rawResponseRetentionUpdatedDays(Object days) {
    return '보관 기간을 $days일로 업데이트했습니다.';
  }

  @override
  String get homeMorningTipsUpdated => '아침 힌트가 업데이트되었습니다';

  @override
  String get homeMorningTipsGenerateFailed => '아침 힌트 생성에 실패했습니다';

  @override
  String eventCreateFailed(Object error) {
    return '생성 실패: $error';
  }

  @override
  String eventSwitchFailed(Object error) {
    return '전환 실패: $error';
  }

  @override
  String get eventSessionSwitched => '대화가 전환되었습니다';

  @override
  String get eventSessionDeleted => '대화가 삭제되었습니다';

  @override
  String get exclusionExcludedAppsTitle => '제외된 앱';

  @override
  String get exclusionSelfAppBullet => '· 이 앱(자기 순환 방지)';

  @override
  String get exclusionImeAppsBullet => '· 입력기(키보드) 앱:';

  @override
  String get exclusionAutoFilteredBullet => '  - (자동 필터링됨)';

  @override
  String get exclusionUnknownIme => '알 수 없는 입력기';

  @override
  String exclusionImeAppBullet(Object name) {
    return '  - $name';
  }

  @override
  String get imageError => '이미지 오류';

  @override
  String get logDetailTitle => '로그 상세';

  @override
  String get logLevelAll => '전체';

  @override
  String get logLevelDebugVerbose => '디버그/상세';

  @override
  String get logLevelInfo => '정보';

  @override
  String get logLevelWarning => '경고';

  @override
  String get logLevelErrorSevere => '오류/심각';

  @override
  String get logSearchHint => '제목/내용/예외/스택 검색';

  @override
  String onboardingPermissionLoadFailed(Object error) {
    return '권한 상태 로드 실패: $error';
  }

  @override
  String get permissionGuideSettingsOpened => '앱 설정 페이지를 열었습니다. 안내에 따라 설정하세요';

  @override
  String permissionGuideOpenSettingsFailed(Object error) {
    return '설정 페이지 열기 실패: $error';
  }

  @override
  String get permissionGuideBatteryOpened => '배터리 최적화 설정 페이지를 열었습니다';

  @override
  String permissionGuideOpenBatteryFailed(Object error) {
    return '배터리 최적화 설정 열기 실패: $error';
  }

  @override
  String get permissionGuideAutostartOpened => '자동 시작 설정 페이지를 열었습니다';

  @override
  String permissionGuideOpenAutostartFailed(Object error) {
    return '자동 시작 설정 열기 실패: $error';
  }

  @override
  String get permissionGuideCompleted => '권한 설정을 완료로 표시했습니다';

  @override
  String permissionGuideCompleteFailed(Object error) {
    return '권한 설정 완료 표시 실패: $error';
  }

  @override
  String get permissionGuideTitle => '권한 설정 가이드';

  @override
  String get permissionGuideOpenAppSettings => '앱 설정 페이지 열기';

  @override
  String get permissionGuideOpenBatterySettings => '배터리 최적화 설정 열기';

  @override
  String get permissionGuideOpenAutostartSettings => '자동 시작 설정 열기';

  @override
  String get permissionGuideAllDone => '모든 설정을 완료했습니다';

  @override
  String get galleryDeleting => '삭제 중...';

  @override
  String get galleryCleaningCache => '캐시 정리 중...';

  @override
  String get favoriteRemoved => '즐겨찾기에서 제거했습니다';

  @override
  String get favoriteAdded => '즐겨찾기에 추가했습니다';

  @override
  String operationFailedWithError(Object error) {
    return '작업 실패: $error';
  }

  @override
  String get searchSemantic => '의미 검색';

  @override
  String get searchDynamic => '동적 검색';

  @override
  String get searchMore => '더 검색';

  @override
  String get openDailySummary => '일일 요약 열기';

  @override
  String get openWeeklySummary => '주간 요약 열기';

  @override
  String get noAvailableTags => '사용 가능한 태그 없음';

  @override
  String get clearFilter => '필터 지우기';

  @override
  String get forceMerge => '강제 병합';

  @override
  String get forceMergeNoPrevious => '병합할 이전 이벤트가 없습니다';

  @override
  String get forceMergeQueuedFailed => '강제 병합 대기열 추가 실패';

  @override
  String get forceMergeQueued => '강제 병합이 대기열에 추가되었습니다';

  @override
  String get forceMergeFailed => '강제 병합 실패';

  @override
  String get mergeCompleted => '병합 완료';

  @override
  String get numberInputRequired => '숫자를 입력하세요';

  @override
  String valueSaved(Object value) {
    return '저장됨: $value';
  }

  @override
  String openChannelSettingsFailed(Object error) {
    return '채널 설정 열기 실패: $error';
  }

  @override
  String openAppNotificationSettingsFailed(Object error) {
    return '앱 알림 설정 열기 실패: $error';
  }

  @override
  String get evidencePrefix => '[증거: ';

  @override
  String get actionMenu => '메뉴';

  @override
  String get actionShare => '공유';

  @override
  String get actionResetToDefault => '기본값으로 재설정';

  @override
  String homeMorningTipNumberedTitle(Object index, Object title) {
    return '$index. $title';
  }

  @override
  String get homeMorningTipsRawTitle => '아침 힌트 RAW';

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
    return '기본값으로 재설정됨: $value';
  }

  @override
  String get logPanelTitle => '로그 패널';

  @override
  String get logCopiedToClipboard => '클립보드에 복사했습니다';

  @override
  String get logShareText => 'ScreenMemo 로그';

  @override
  String get logShareFailed => '공유 실패';

  @override
  String get logCleared => '로그를 지웠습니다';

  @override
  String get logClearFailed => '로그 지우기 실패';

  @override
  String get logNoLogs => '아직 로그가 없습니다';

  @override
  String get logNoMatchingLogs => '일치하는 로그가 없습니다';

  @override
  String get logFilterTooltip => '필터';

  @override
  String get logSortNewestFirst => '최신순';

  @override
  String get logSortOldestFirst => '오래된순';

  @override
  String get logLevelCritical => '심각';

  @override
  String get logLevelError => '오류';

  @override
  String get logLevelVerbose => '상세';

  @override
  String get logLevelDebug => '디버그';

  @override
  String get eventNewConversation => '새 대화';

  @override
  String get forceMergeConfirmMessage =>
      '이전 이벤트와 강제로 병합하고 현재 이벤트 요약을 덮어쓰며 이전 이벤트를 삭제합니다. 이 작업은 되돌릴 수 없습니다. 계속할까요?';

  @override
  String get forceMergeRequestedReason => '강제 병합 요청됨(대기열)';

  @override
  String get mergeStatusMerging => '강제 병합 중…';

  @override
  String get mergeStatusMerged => '병합됨';

  @override
  String get mergeStatusForceRequested => '강제 병합 요청됨';

  @override
  String get mergeStatusNotMerged => '병합되지 않음';

  @override
  String get mergeStatusPending => '판정 대기';

  @override
  String get semanticSearchNotStartedTitle => '의미 검색이 시작되지 않았습니다';

  @override
  String get semanticSearchNotStartedDesc =>
      '이미지의 AI 설명, 키워드, 태그를 검색합니다. 입력 중 지연을 피하려면 수동으로 검색을 시작하세요.';

  @override
  String get segmentSearchNotStartedTitle => '동적 검색이 시작되지 않았습니다';

  @override
  String get segmentSearchNotStartedDesc => '입력 중 지연을 피하려면 수동으로 검색을 시작하세요.';

  @override
  String foundImagesCount(Object count) {
    return '이미지 $count장을 찾았습니다';
  }

  @override
  String get tagsLabel => '태그';

  @override
  String tagCount(Object count) {
    return '태그 $count개';
  }

  @override
  String get tagFilterTitle => '태그 필터';

  @override
  String get selectedAllLabel => '전체';

  @override
  String selectedTagsCount(Object count) {
    return '$count개 선택됨';
  }

  @override
  String selectedTypesCount(Object count) {
    return '$count종 선택됨';
  }

  @override
  String confirmSelectionLabel(Object selection) {
    return '확인 ($selection)';
  }

  @override
  String get noContentParenthesized => '(비어 있음)';

  @override
  String get typeFilterTitle => '유형 필터';

  @override
  String get rawResponseCleanupEnableTitle => '원본 응답 자동 정리 사용';

  @override
  String rawResponseCleanupEnableMessage(Object days) {
    return '$days일보다 오래된 raw_response를 자동으로 정리합니다. 요약과 structured_json에는 영향을 주지 않습니다.';
  }

  @override
  String get rawResponseCleanupEnableAction => '사용하고 지금 정리';

  @override
  String get segmentsJsonAutoRetryHint => '횟수(0-5)';

  @override
  String get rawResponseCleanupTitle => '원본 응답 자동 정리';

  @override
  String get rawResponseCleanupKeepLabel => '보관';

  @override
  String rawResponseCleanupRetentionDays(Object days) {
    return '$days일';
  }

  @override
  String get rawResponseCleanupDesc =>
      '오래된 raw_response만 정리하며 요약과 structured_json은 유지됩니다';

  @override
  String get mergeStatusMergingReason => '병합 중입니다. 잠시만 기다려 주세요…';

  @override
  String get permissionGuideLoading => '권한 설정 가이드를 불러오는 중...';

  @override
  String get permissionGuideUnavailable => '권한 설정 가이드를 가져올 수 없습니다';

  @override
  String get permissionGuideUnknownDevice => '알 수 없는 기기';

  @override
  String permissionGuideLoadFailed(Object error) {
    return '권한 설정 가이드 로드 실패: $error';
  }

  @override
  String get deviceInfoTitle => '기기 정보';

  @override
  String get setupGuideTitle => '설정 가이드';

  @override
  String get permissionConfiguredStatus => '설정됨';

  @override
  String get permissionNeedsConfigurationStatus => '설정 필요';

  @override
  String get backgroundPermissionTitle => '백그라운드 실행 권한';

  @override
  String get actualBatteryOptimizationStatusTitle => '실제 배터리 최적화 상태';

  @override
  String get keyDialogProviderNotSavedHint => 'API 키를 추가하기 전에 공급자를 저장하세요.';

  @override
  String get keyDialogNameLabel => '키 이름';

  @override
  String get keyDialogApiKeyLabel => 'API 키';

  @override
  String get keyDialogApiKeyLabelMulti => 'API 키 (한 줄에 하나)';

  @override
  String get keyDialogApiKeyHintMulti => '한 줄에 하나의 API 키. 가져오기는 모든 키를 스캔합니다.';

  @override
  String get keyDialogPriorityLabel => '우선 순위 (100 = 동적 할당)';

  @override
  String get keyDialogModelsLabel => '지원 모델 (한 줄에 하나)';

  @override
  String get keyDialogPhaseFetchModels => '모델 가져오기';

  @override
  String get keyDialogPhaseFetchBalance => '잔액 가져오기';

  @override
  String get keyDialogPhaseScanKeys => '키 스캔';

  @override
  String get keyDialogPhaseSaveKeys => '키 저장';

  @override
  String get keyDialogPhaseSaveKey => '키 저장';

  @override
  String get keyDialogPhaseSaveBalance => '잔액 저장';

  @override
  String get keyDialogPhaseFetchComplete => '가져오기 완료';

  @override
  String get keyDialogPhaseSaveFailed => '저장 실패';

  @override
  String get keyDialogFallbackKeyName => '현재 키';

  @override
  String keyDialogPreparingScan(int count) {
    return '$count개의 API 키를 스캔 준비 중…';
  }

  @override
  String keyDialogFetchingModelsFor(String label) {
    return '$label의 모델 가져오는 중…';
  }

  @override
  String keyDialogFetchingBalanceFor(String label) {
    return '$label의 잔액 가져오는 중…';
  }

  @override
  String keyDialogModelFetchFailed(String label, String error) {
    return '$label 모델 가져오기 실패: $error';
  }

  @override
  String keyDialogBalanceFetchFailed(String label, String error) {
    return '$label 잔액 가져오기 실패: $error';
  }

  @override
  String keyDialogModelsCountText(int count) {
    return '$count개 모델';
  }

  @override
  String get keyDialogModelFetchSkipped => '모델 가져오기 실패, 건너뜀';

  @override
  String keyDialogBalanceSuffixSuccess(String value) {
    return ', 잔액: $value';
  }

  @override
  String get keyDialogBalanceSuffixFailed => ', 잔액 실패';

  @override
  String keyDialogScanLine(
    String label,
    String modelMessage,
    String balanceMessage,
  ) {
    return '$label: $modelMessage$balanceMessage';
  }

  @override
  String keyDialogModelFetchSummarySuccess(
    int ok,
    int total,
    int merged,
    String balanceHint,
    String failedHint,
  ) {
    return '모델 가져오기 완료: $ok/$total 키 성공, $merged개 모델 병합$balanceHint$failedHint';
  }

  @override
  String get keyDialogModelFetchSummaryNone =>
      '어떤 키에서도 모델을 반환하지 않았습니다. 현재 수동 모델 목록은 변경되지 않습니다.';

  @override
  String get keyDialogPreparingSave => '저장 준비 중…';

  @override
  String keyDialogSavingItem(String label) {
    return '$label 저장 중…';
  }

  @override
  String keyDialogSavingBalanceItem(String label) {
    return '$label의 잔액 저장 중…';
  }

  @override
  String keyDialogImportedKeys(
    int count,
    String balanceHint,
    String skippedHint,
  ) {
    return '$count개의 API 키를 가져왔습니다$balanceHint$skippedHint';
  }

  @override
  String keyDialogApiKeySaved(String balanceHint) {
    return 'API 키 저장됨$balanceHint';
  }

  @override
  String get keyDialogNoNewKey => '새 키 없음: 입력한 API 키가 모두 이미 존재합니다.';

  @override
  String keyDialogSaveFailed(String error) {
    return 'API 키 저장 실패: $error';
  }

  @override
  String keyDialogBalanceHintFraction(int ok, int total) {
    return ', 잔액 $ok/$total';
  }

  @override
  String keyDialogSkippedDuplicates(int count) {
    return ', 중복 키 $count개 건너뜀';
  }

  @override
  String keyDialogFailedItemsHint(int count) {
    return ', $count개 실패';
  }

  @override
  String keyDialogFinalSummary(
    int modelOk,
    int modelTotal,
    int balanceOk,
    int balanceTotal,
  ) {
    return '모델 $modelOk/$modelTotal, 잔액 $balanceOk/$balanceTotal';
  }

  @override
  String get segmentSampleIntervalExplain =>
      '단일 세그먼트 요약을 생성할 때 스크린샷을 샘플링하는 간격입니다. 값이 작을수록 더 많은 세부 정보를 포착하지만 토큰 사용량이 늘어납니다. 값이 클수록 비용이 절감되지만 짧은 이벤트를 놓칠 수 있습니다.';

  @override
  String get segmentDurationExplain =>
      '단일 다이내믹 세그먼트의 최대 길이입니다. 이 시간을 초과하면 활동이 계속되더라도 새 세그먼트를 시작합니다. 짧을수록 세부 요약, 길수록 넓은 맥락이 됩니다.';

  @override
  String get dynamicMergeMaxSpanExplain =>
      '인접한 여러 다이내믹 세그먼트가 하나의 요약으로 병합될 수 있는 최대 시간 범위입니다. 0으로 설정하면 제한이 없습니다.';

  @override
  String get dynamicMergeMaxGapExplain =>
      '인접한 두 다이내믹 세그먼트 사이에 허용되는 최대 공백 시간입니다. 이를 초과하면 병합되지 않습니다. 0으로 설정하면 제한이 없습니다.';

  @override
  String get dynamicMergeMaxImagesExplain =>
      '한 번의 병합 요약에 모델로 전달되는 스크린샷의 최대 수입니다. 값이 클수록 더 많은 맥락이 제공되지만 비용과 지연 시간이 증가합니다. 0으로 설정하면 제한이 없습니다.';

  @override
  String get aiRequestIntervalExplain =>
      '앱이 보내는 AI 요청 사이의 최소 간격입니다. 공급자가 속도 제한을 적용하거나 전체 사용량을 줄이려면 값을 늘리세요.';

  @override
  String get segmentsJsonAutoRetryTitle => '자동 재시도 횟수';

  @override
  String segmentsJsonAutoRetryDesc(int count) {
    return 'AI 응답이 요구되는 형식과 일치하지 않을 때 자동으로 재요청하는 횟수입니다 (0 = 끔, 기본값 1). 현재: $count';
  }

  @override
  String get segmentsJsonAutoRetryExplain =>
      'AI는 가끔 파싱할 수 없거나 필요한 구조와 일치하지 않는 내용을 반환합니다. 그럴 때 앱은 설정된 횟수만큼 자동으로 재요청하여 성공률을 높이지만, 시간과 토큰을 더 소비합니다.';
}
