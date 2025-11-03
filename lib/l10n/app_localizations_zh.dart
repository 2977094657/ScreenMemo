// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '屏忆';

  @override
  String get settingsTitle => '设置';

  @override
  String get searchPlaceholder => '搜索截图...';

  @override
  String get homeEmptyTitle => '暂无监控应用';

  @override
  String get homeEmptySubtitle => '请在设置中选择要监控的应用';

  @override
  String get navSelectApps => '选择监控应用';

  @override
  String get dialogOk => '确定';

  @override
  String get dialogCancel => '取消';

  @override
  String get dialogDone => '完成';

  @override
  String get permissionStatusTitle => '权限状态检查';

  @override
  String get permissionMissing => '权限缺失';

  @override
  String get startScreenshot => '开始截屏';

  @override
  String get stopScreenshot => '停止截屏';

  @override
  String get screenshotEnabledToast => '截屏已启用';

  @override
  String get screenshotDisabledToast => '截屏已停用';

  @override
  String get intervalSettingTitle => '设置截屏间隔';

  @override
  String get intervalLabel => '间隔时间（秒）';

  @override
  String get intervalHint => '请输入5-60的整数';

  @override
  String intervalSavedToast(Object seconds) {
    return '截屏间隔已设置为 $seconds 秒';
  }

  @override
  String get languageSettingTitle => '语言设置';

  @override
  String get languageSystem => '跟随系统';

  @override
  String get languageChinese => '简体中文';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageJapanese => '日语';

  @override
  String get languageKorean => '韩语';

  @override
  String languageChangedToast(Object name) {
    return '已切换为 $name';
  }

  @override
  String get nsfwWarningTitle => '内容警告：成人内容';

  @override
  String get nsfwWarningSubtitle => '该内容已被标记为成人内容';

  @override
  String get show => '显示';

  @override
  String get appSearchPlaceholder => '搜索应用...';

  @override
  String selectedCount(Object count) {
    return '已选择 $count 个';
  }

  @override
  String get refreshAppsTooltip => '刷新应用列表';

  @override
  String get selectAll => '全选';

  @override
  String get clearAll => '清空';

  @override
  String get noAppsFound => '没有找到应用';

  @override
  String get noAppsMatched => '没有匹配的应用';

  @override
  String stepProgress(Object current, Object total) {
    return '步骤 $current / $total';
  }

  @override
  String get onboardingWelcomeTitle => '欢迎使用 屏忆';

  @override
  String get onboardingWelcomeDesc => '智能备忘与信息管理工具，帮助您高效记录、整理和回顾重要信息。';

  @override
  String get onboardingKeyFeaturesTitle => '主要功能';

  @override
  String get featureSmartNotes => '智能信息记录';

  @override
  String get featureQuickSearch => '快速内容搜索';

  @override
  String get featureLocalStorage => '本地数据存储';

  @override
  String get featureUsageAnalytics => '使用习惯分析';

  @override
  String get onboardingPermissionsTitle => '授权必要权限';

  @override
  String get refreshPermissionStatus => '刷新权限状态';

  @override
  String get onboardingPermissionsDesc => '为了提供完整的功能体验，需要授权以下权限：';

  @override
  String get storagePermissionTitle => '存储权限';

  @override
  String get storagePermissionDesc => '保存截图文件到设备存储';

  @override
  String get notificationPermissionTitle => '通知权限';

  @override
  String get notificationPermissionDesc => '显示服务状态通知';

  @override
  String get accessibilityPermissionTitle => '无障碍服务';

  @override
  String get accessibilityPermissionDesc => '监听应用切换并执行截图';

  @override
  String get usageStatsPermissionTitle => '使用统计权限';

  @override
  String get usageStatsPermissionDesc => '确保检测前台应用';

  @override
  String get batteryOptimizationTitle => '电池优化白名单';

  @override
  String get batteryOptimizationDesc => '确保截图服务常驻运行';

  @override
  String get pleaseCompleteInSystemSettings => '请在系统设置中完成授权，然后返回应用';

  @override
  String get autostartPermissionTitle => '自启动权限';

  @override
  String get autostartPermissionDesc => '允许应用在后台自动重启';

  @override
  String get permissionsFooterNote => '权限授权后将持久保存，可随时在系统设置中修改';

  @override
  String get grantedLabel => '已授权';

  @override
  String get authorizeAction => '授权';

  @override
  String get onboardingSelectAppsTitle => '选择监控应用';

  @override
  String get onboardingSelectAppsDesc => '请选择需要进行截图监控的应用，至少选择一个应用才能继续。';

  @override
  String get onboardingDoneTitle => '设置完成！';

  @override
  String get onboardingDoneDesc => '所有权限已成功授权，您现在可以开始使用屏忆的截图功能了。';

  @override
  String get nextStepTitle => '下一步';

  @override
  String get onboardingNextStepDesc => '点击“开始使用”进入主界面，开始体验强大的截图功能。';

  @override
  String get prevStep => '上一步';

  @override
  String get startUsing => '开始使用';

  @override
  String get finishSelection => '完成选择';

  @override
  String get nextStep => '下一步';

  @override
  String get confirmPermissionSettingsTitle => '确认权限设置';

  @override
  String get confirmAutostartQuestion => '您是否已经在系统设置中完成了“自启动权限”的配置？';

  @override
  String get notYet => '还没有';

  @override
  String get done => '已完成';

  @override
  String get startingScreenshotServiceInfo => '正在启动截屏服务...';

  @override
  String get startServiceFailedCheckPermissions => '启动截屏服务失败，请检查权限设置';

  @override
  String get startFailedTitle => '启动失败';

  @override
  String get startFailedUnknown => '启动失败：未知错误';

  @override
  String get tipIfProblemPersists => '提示：如果问题持续，请尝试重新启动应用或重新配置权限';

  @override
  String get autoDisabledDueToPermissions => '由于权限不足，截屏功能已自动关闭';

  @override
  String get refreshingPermissionsInfo => '正在刷新权限状态...';

  @override
  String get permissionsRefreshed => '权限状态已刷新';

  @override
  String refreshPermissionsFailed(Object error) {
    return '刷新权限状态失败: $error';
  }

  @override
  String get screenRecordingPermissionTitle => '屏幕录制权限';

  @override
  String get goToSettings => '前往设置';

  @override
  String get notGrantedLabel => '未授权';

  @override
  String get removeMonitoring => '移除监测';

  @override
  String selectedItemsCount(Object count) {
    return '已选择 $count 项';
  }

  @override
  String get whySomeAppsHidden => '为什么有些应用不显示？';

  @override
  String get excludedAppsTitle => '已排除的应用';

  @override
  String get excludedAppsIntro => '以下应用会被排除，不能选择：';

  @override
  String get excludedThisApp => '· 本应用（避免自我干扰）';

  @override

  @override
  String get excludedImeApps => '· 输入法（键盘）应用：';

  @override
  String get excludedImeAppsFiltered => '· 输入法（键盘）应用（已自动过滤）';

  @override
  String currentDefaultIme(Object name, Object package) {
    return '当前默认输入法：$name ($package)';
  }

  @override
  String get imeExplainText =>
      '当你在其它应用中弹出键盘时，系统会切换到输入法窗口。如果不排除，会被误认为正在使用输入法，从而导致截图浮窗判断错误。我们已自动排除输入法应用，并在检测到输入法时，仍会将浮窗移到弹出输入法之前的应用。';

  @override
  String get gotIt => '知道了';

  @override
  String get unknownIme => '未知输入法';

  @override
  String get intervalRangeNote => '范围：5-60 秒，默认值：5 秒。';

  @override
  String get intervalInvalidInput => '请输入 5-60 的有效整数';

  @override
  String get removeMonitoringMessage => '仅移除监测，不会删除对应图片。是否继续？';

  @override
  String get remove => '移除';

  @override
  String removedMonitoringToast(Object count) {
    return '已移除监测 $count 个应用（不删除图片）';
  }

  @override
  String checkPermissionStatusFailed(Object error) {
    return '检查权限状态失败: $error';
  }

  @override
  String get accessibilityNotEnabledDetail => '无障碍服务未启用\n请前往设置页面启用无障碍服务';

  @override
  String get storagePermissionNotGrantedDetail => '存储权限未授予\n请前往设置页面授予存储权限';

  @override
  String get serviceNotRunningDetail => '服务未正常运行\n请尝试重新启动应用';

  @override
  String get androidVersionNotSupportedDetail => '系统版本不支持\n需要Android 11.0或以上版本';

  @override
  String get permissionsSectionTitle => '权限设置';

  @override
  String get displayAndSortSectionTitle => '显示与排序';

  @override
  String get screenshotSectionTitle => '截屏设置';

  @override
  String get segmentSummarySectionTitle => '时间段总结';

  @override
  String get dailyReminderSectionTitle => '每日总结提醒';

  @override
  String get aiAssistantSectionTitle => 'AI 助手';

  @override
  String get dataBackupSectionTitle => '数据与备份';

  @override
  String get actionSet => '设置';

  @override
  String get actionEnter => '进入';

  @override
  String get actionExport => '导出';

  @override
  String get actionImport => '导入';

  @override
  String get actionCopyPath => '复制路径';

  @override
  String get actionOpen => '去开启';

  @override
  String get actionTrigger => '触发';

  @override
  String get allPermissionsGranted => '已全部授权';

  @override
  String permissionsMissingCount(Object count) {
    return '尚有 $count 项权限未授权';
  }

  @override
  String get exportSuccessTitle => '导出完成';

  @override
  String get exportFileExportedTo => '文件已导出至：';

  @override
  String get pathCopiedToast => '已复制路径';

  @override
  String get exportFailedTitle => '导出失败';

  @override
  String get pleaseTryAgain => '请稍后重试';

  @override
  String get importCompleteTitle => '导入完成';

  @override
  String get dataExtractedTo => '数据已解压到:';

  @override
  String get importFailedTitle => '导入失败';

  @override
  String get importFailedCheckZip => '请检查ZIP文件并重试。';

  @override
  String get noMediaProjectionNeeded => '已使用无障碍服务截图，无需屏幕录制权限';

  @override
  String get autostartPermissionMarked => '自启动权限已标记为已授权';

  @override
  String requestPermissionFailed(Object error) {
    return '请求权限失败: $error';
  }

  @override
  String get expireCleanupSaved => '过期清理设置已保存';

  @override
  String get dailyNotifyTriggered => '已触发通知';

  @override
  String get dailyNotifyTriggerFailed => '触发通知失败或内容为空';

  @override
  String get refreshPermissionStatusTooltip => '刷新权限状态';

  @override
  String get grantedStatus => '已授权';

  @override
  String get notGrantedStatus => '去授权';

  @override
  String get privacyModeTitle => '隐私模式';

  @override
  String get privacyModeDesc => '对敏感内容自动模糊遮挡';

  @override
  String get homeSortingTitle => '首页排序';

  @override
  String get screenshotIntervalTitle => '截屏间隔';

  @override
  String screenshotIntervalDesc(Object seconds) {
    return '当前间隔：$seconds 秒';
  }

  @override
  String get screenshotQualityTitle => '截图质量';

  @override
  String get currentSizeLabel => '当前大小：';

  @override
  String get clickToModifyHint => '（点击数字可修改）';

  @override
  String get screenshotExpireTitle => '截图过期清理';

  @override
  String get currentExpireDaysLabel => '当前过期天数:';

  @override
  String expireDaysUnit(Object days) {
    return '$days天';
  }

  @override
  String get exportDataTitle => '导出数据';

  @override
  String get exportDataDesc => '导出 ZIP 至 Download/ScreenMemory';

  @override
  String get importDataTitle => '导入数据';

  @override
  String get importDataDesc => '将ZIP文件导入到应用存储';

  @override
  String get aiAssistantTitle => 'AI 助手';

  @override
  String get aiAssistantDesc => '配置 AI 接口与模型，并进行多轮对话测试';

  @override
  String get segmentSampleIntervalTitle => '采样间隔（秒）';

  @override
  String segmentSampleIntervalDesc(Object seconds) {
    return '当前：$seconds 秒';
  }

  @override
  String get segmentDurationTitle => '时间段时长（分钟）';

  @override
  String segmentDurationDesc(Object minutes) {
    return '当前：$minutes 分钟';
  }

  @override
  String get aiRequestIntervalTitle => 'AI 请求最小间隔（秒）';

  @override
  String aiRequestIntervalDesc(Object seconds) {
    return '当前：$seconds 秒（最低1秒）';
  }

  @override
  String get dailyReminderTimeTitle => '每日总结提醒时间';

  @override
  String get currentTimeLabel => '当前：';

  @override
  String get testNotificationTitle => '测试通知';

  @override
  String get testNotificationDesc => '立即触发\"今日总结\"通知';

  @override
  String get enableBannerNotificationTitle => '开启横幅/悬浮通知';

  @override
  String get enableBannerNotificationDesc => '允许在屏幕顶部弹出通知（横幅/悬浮）';

  @override
  String get setIntervalDialogTitle => '设置截屏间隔';

  @override
  String get intervalSecondsLabel => '间隔时间（秒）';

  @override
  String get intervalInputHint => '请输入 5-60 的整数';

  @override
  String get intervalRangeHint => '范围：5-60 秒，默认 5 秒';

  @override
  String get intervalInvalidError => '请输入 5-60 的有效整数';

  @override
  String intervalSavedSuccess(Object seconds) {
    return '截屏间隔已设置为 $seconds 秒';
  }

  @override
  String get setTargetSizeDialogTitle => '设置目标大小（单位KB）';

  @override
  String get targetSizeKbLabel => '目标大小（KB）';

  @override
  String get targetSizeInvalidError => '请输入 >= 50 的有效整数';

  @override
  String targetSizeSavedSuccess(Object kb) {
    return '目标大小已设置为 $kb KB';
  }

  @override
  String get setExpireDaysDialogTitle => '设置截图过期天数';

  @override
  String get expireDaysLabel => '过期天数';

  @override
  String get expireDaysInputHint => '请输入 >= 1 的整数';

  @override
  String get expireDaysInvalidError => '请输入 >= 1 的有效整数';

  @override
  String expireDaysSavedSuccess(Object days) {
    return '已设置为 $days 天';
  }

  @override
  String get sortTimeNewToOld => '时间（新→旧）';

  @override
  String get sortTimeOldToNew => '时间（旧→新）';

  @override
  String get sortSizeLargeToSmall => '大小（大→小）';

  @override
  String get sortSizeSmallToLarge => '大小（小→大）';

  @override
  String get sortCountManyToFew => '数量（多→少）';

  @override
  String get sortCountFewToMany => '数量（少→多）';

  @override
  String get sortFieldTime => '时间';

  @override
  String get sortFieldCount => '数量';

  @override
  String get sortFieldSize => '大小';

  @override
  String get selectHomeSortingTitle => '选择首页排序';

  @override
  String currentSortingLabel(Object sorting) {
    return '当前：$sorting';
  }

  @override
  String get privacyModeEnabledToast => '已开启隐私模式';

  @override
  String get privacyModeDisabledToast => '已关闭隐私模式';

  @override
  String get screenshotQualitySettingsSaved => '截图质量设置已保存';

  @override
  String saveFailedError(Object error) {
    return '保存失败: $error';
  }

  @override
  String get setReminderTimeTitle => '设置提醒时间（24小时制）';

  @override
  String get hourLabel => '小时(0-23)';

  @override
  String get minuteLabel => '分钟(0-59)';

  @override
  String get timeInputHint => '提示：点击数字直接输入；范围为 0-23 时与 0-59 分。';

  @override
  String get invalidHourError => '请输入 0-23 的有效小时';

  @override
  String get invalidMinuteError => '请输入 0-59 的有效分钟';

  @override
  String timeSetSuccess(Object hour, Object minute) {
    return '已设置为 $hour:$minute';
  }

  @override
  String reminderScheduleSuccess(Object hour, Object minute) {
    return '已设置每日提醒时间为 $hour:$minute';
  }

  @override
  String get reminderDisabledSuccess => '已关闭每日提醒';

  @override
  String get reminderScheduleFailed => '调度每日提醒失败（可能平台不支持）';

  @override
  String saveReminderSettingsFailed(Object error) {
    return '保存提醒设置失败: $error';
  }

  @override
  String searchFailedError(Object error) {
    return '搜索失败: $error';
  }

  @override
  String get searchInputHintOcr => '在此输入关键词，以 OCR 文本检索截图';

  @override
  String get noMatchingScreenshots => '没有匹配的截图';

  @override
  String get imageMissingOrCorrupted => '图片丢失或损坏';

  @override
  String get actionClear => '清除';

  @override
  String get actionRefresh => '刷新';

  @override
  String get noScreenshotsTitle => '暂无截图';

  @override
  String get noScreenshotsSubtitle => '开启截图监控后，截图将显示在这里';

  @override
  String get confirmDeleteTitle => '确认删除';

  @override
  String get confirmDeleteMessage => '确定要删除这张截图吗？此操作无法撤销。';

  @override
  String get actionDelete => '删除';

  @override
  String get actionContinue => '继续';

  @override
  String get linkTitle => '链接';

  @override
  String get actionCopy => '复制';

  @override
  String get imageInfoTitle => '截图信息';

  @override
  String get deleteImageTooltip => '删除图片';

  @override
  String get imageLoadFailed => '图片加载失败';

  @override
  String get labelAppName => '应用名称';

  @override
  String get labelCaptureTime => '截图时间';

  @override
  String get labelFilePath => '文件路径';

  @override
  String get labelPageLink => '页面链接';

  @override
  String get labelFileSize => '文件大小';

  @override
  String get tapToContinue => '轻触继续';

  @override
  String get appDirUninitialized => '应用目录未初始化';

  @override
  String get actionRetry => '重试';

  @override
  String get deleteSelectedTooltip => '删除所选';

  @override
  String get noMatchingResults => '无匹配结果';

  @override
  String dayTabToday(Object count) {
    return '今天 $count';
  }

  @override
  String dayTabYesterday(Object count) {
    return '昨天 $count';
  }

  @override
  String dayTabMonthDayCount(Object month, Object day, Object count) {
    return '$month月$day日 $count';
  }

  @override
  String get screenshotDeletedToast => '截图已删除';

  @override
  String get deleteFailed => '删除失败';

  @override
  String deleteFailedWithError(Object error) {
    return '删除失败: $error';
  }

  @override
  String get imageInfoTooltip => '图片信息';

  @override
  String get copySuccess => '已复制';

  @override
  String get copyFailed => '复制失败';

  @override
  String deletedCountToast(Object count) {
    return '已删除 $count 张截图';
  }

  @override
  String get invalidArguments => '参数错误';

  @override
  String initFailedWithError(Object error) {
    return '初始化失败: $error';
  }

  @override
  String loadMoreFailedWithError(Object error) {
    return '加载更多失败: $error';
  }

  @override
  String get confirmDeleteAllTitle => '确认删除所有截图';

  @override
  String deleteAllMessage(Object count) {
    return '将删除当前范围内的所有 $count 张截图及其文件夹，此操作不可恢复。';
  }

  @override
  String deleteSelectedMessage(Object count) {
    return '将删除选中的 $count 张截图，且不可恢复。是否继续？';
  }

  @override
  String get deleteFailedRetry => '删除失败，请重试';

  @override
  String keptAndDeletedSummary(Object keep, Object deleted) {
    return '已保留 $keep 张，删除 $deleted 张';
  }

  @override
  String dailySummaryTitle(Object date) {
    return '每日总结 $date';
  }

  @override
  String dailySummarySlotMorningTitle(Object date) {
    return '晨间速览 $date';
  }

  @override
  String dailySummarySlotNoonTitle(Object date) {
    return '午间速览 $date';
  }

  @override
  String dailySummarySlotEveningTitle(Object date) {
    return '傍晚速览 $date';
  }

  @override
  String dailySummarySlotNightTitle(Object date) {
    return '夜间速览 $date';
  }

  @override
  String get actionGenerate => '生成';

  @override
  String get actionRegenerate => '重生成';

  @override
  String get generateSuccess => '已生成';

  @override
  String get generateFailed => '生成失败';

  @override
  String get noDailySummaryToday => '暂无今日总结';

  @override
  String get generateDailySummary => '生成今日总结';

  @override
  String get statisticsTitle => '统计';

  @override
  String get overviewTitle => '总览';

  @override
  String get monitoredApps => '监控应用';

  @override
  String get totalScreenshots => '总截图';

  @override
  String get todayScreenshots => '今日截图';

  @override
  String get storageUsage => '存储占用';

  @override
  String get appStatisticsTitle => '应用统计';

  @override
  String screenshotCountWithLast(Object count, Object last) {
    return '截图数量: $count | 最后截图: $last';
  }

  @override
  String get none => '暂无';

  @override
  String get usageTrendsTitle => '使用趋势';

  @override
  String get trendChartTitle => '趋势图表';

  @override
  String get comingSoon => '功能开发中，敬请期待';

  @override
  String get timelineTitle => '时间线';

  @override
  String get pressBackAgainToExit => '再按一次退出屏忆';

  @override
  String get segmentStatusTitle => '动态';

  @override
  String get autoWatchingHint => '后台自动检测中…';

  @override
  String get noEvents => '暂无事件';

  @override
  String get noEventsSubtitle => '事件段落和AI总结将显示在这里';

  @override
  String get activeSegmentTitle => '进行中的时间段';

  @override
  String sampleEverySeconds(Object seconds) {
    return '每 $seconds 秒采样';
  }

  @override
  String get dailySummaryShort => '每日总结';

  @override
  String get viewOrGenerateForDay => '查看或生成该日总结';

  @override
  String get mergedEventTag => '合并事件';

  @override
  String get collapse => '收起内容';

  @override
  String get expandMore => '展开更多';

  @override
  String viewImagesCount(Object count) {
    return '查看图片 ($count)';
  }

  @override
  String hideImagesCount(Object count) {
    return '收起图片 ($count)';
  }

  @override
  String get deleteEventTooltip => '删除事件';

  @override
  String get confirmDeleteEventMessage => '确定删除该事件？此操作不会删除任何图片文件。';

  @override
  String get eventDeletedToast => '事件已删除';

  @override
  String get regenerationQueued => '已加入重生成队列';

  @override
  String get alreadyQueuedOrFailed => '已在队列或失败';

  @override
  String get retryFailed => '重试失败';

  @override
  String get copyResultsTooltip => '复制结果';

  @override
  String get saveImageTooltip => '保存到相册';

  @override
  String get saveImageSuccess => '已保存到相册';

  @override
  String get saveImageFailed => '保存失败';

  @override
  String get requestGalleryPermissionFailed => '请求相册权限失败';

  @override
  String get aiSystemPromptLanguagePolicy =>
      '无论输入上下文（事件/截图文本/用户消息）使用何种语言，你必须严格忽略其语言，始终使用当前应用语言输出内容。如果当前应用为简体中文，则所有回答、标题、摘要、标签、结构化字段与错误信息均必须使用简体中文撰写；除非用户在消息中明确要求使用其他语言。';

  @override
  String get aiSettingsTitle => 'AI 设置与测试';

  @override
  String get connectionSettingsTitle => '连接设置';

  @override
  String get actionSave => '保存';

  @override
  String get clearConversation => '清空会话';

  @override
  String get deleteGroup => '删除分组';

  @override
  String get streamingRequestTitle => '流式请求';

  @override
  String get streamingRequestHint => '开启后将使用流式响应（默认开启）';

  @override
  String get streamingEnabledToast => '流式已开启';

  @override
  String get streamingDisabledToast => '流式已关闭';

  @override
  String get promptManagerTitle => '提示词管理';

  @override
  String get promptManagerHint =>
      '为“普通事件总结”“合并事件总结”“每日总结”“晨间行动建议”配置提示词；支持 Markdown 渲染。留空或重置将使用默认提示词。';

  @override
  String get promptAddonGeneralInfo =>
      '默认模板包含结构化字段并由系统维护，仅允许在此追加不涉及数据结构的补充说明（如语气、风格、注意事项）。留空表示不添加附加说明。';

  @override
  String get promptAddonInputHint => '请输入附加说明（可留空）';

  @override
  String get promptAddonHelperText => '建议仅描述语气、输出风格或优先级，禁止修改字段结构或要求生成 JSON。';

  @override
  String get promptAddonEmptyPlaceholder => '未添加附加说明';

  @override
  String get promptAddonSuggestionSegment =>
      '建议示例：\n- 用一句话限定整体语气或受众\n- 指出需要关注的关键信息或安全要点\n- 避免要求修改 JSON 字段或结构';

  @override
  String get promptAddonSuggestionMerge =>
      '建议示例：\n- 强调合并后要关注的主题或对比点\n- 指明避免重复描述、聚焦差异总结\n- 勿要求改变结构化字段';

  @override
  String get promptAddonSuggestionDaily =>
      '建议示例：\n- 指定每日总结语气（如“偏向行动复盘”）\n- 提醒突出关键成果或风险\n- 禁止修改输出字段名称';

  @override
  String get promptAddonSuggestionMorning =>
      '建议示例：\n- 强调人文关怀、节奏调节或小确幸\n- 提醒模型避免模板化与任务驱动语气\n- 禁止要求改变 JSON 字段或频繁使用问句';

  @override
  String get normalEventPromptLabel => '普通事件提示词';

  @override
  String get mergeEventPromptLabel => '合并事件提示词';

  @override
  String get dailySummaryPromptLabel => '每日总结提示词';

  @override
  String get morningInsightsPromptLabel => '晨间行动提示词';

  @override
  String get actionEdit => '编辑';

  @override
  String get savingLabel => '保存中';

  @override
  String get resetToDefault => '重置默认';

  @override
  String get chatTestTitle => '对话测试';

  @override
  String get actionSend => '发送';

  @override
  String get sendingLabel => '发送中';

  @override
  String get baseUrlLabel => '接口地址';

  @override
  String get baseUrlHint => '例如：https://api.openai.com';

  @override
  String get apiKeyLabel => 'API 密钥';

  @override
  String get apiKeyHint => '例如：sk-... 或其他服务商 Token';

  @override
  String get modelLabel => '模型';

  @override
  String get modelHint => '例如：gpt-4o-mini / gpt-4o / 兼容模型';

  @override
  String get siteGroupsTitle => '站点分组';

  @override
  String get siteGroupsHint => '可配置多个站点作为备用；发送失败时自动切换';

  @override
  String get rename => '重命名';

  @override
  String get addGroup => '新增分组';

  @override
  String get showGroupSelector => '显示分组选择';

  @override
  String get ungroupedSingleConfig => '未分组（单一配置）';

  @override
  String get inputMessageHint => '请输入消息';

  @override
  String get saveSuccess => '已保存';

  @override
  String get savedCurrentGroupToast => '已保存当前分组';

  @override
  String get savedNormalPromptToast => '已保存普通事件提示词';

  @override
  String get savedMergePromptToast => '已保存合并事件提示词';

  @override
  String get savedDailyPromptToast => '已保存每日总结提示词';

  @override
  String get resetToDefaultPromptToast => '已重置为默认提示词';

  @override
  String resetFailedWithError(Object error) {
    return '重置失败: $error';
  }

  @override
  String get clearSuccess => '已清空';

  @override
  String clearFailedWithError(Object error) {
    return '清空失败: $error';
  }

  @override
  String get messageCannotBeEmpty => '消息不能为空';

  @override
  String sendFailedWithError(Object error) {
    return '发送失败: $error';
  }

  @override
  String get groupSwitchedToUngrouped => '已切换到未分组';

  @override
  String get groupSwitched => '已切换分组';

  @override
  String get groupNotSelected => '未选择分组';

  @override
  String get groupNotFound => '分组不存在';

  @override
  String get renameGroupTitle => '重命名分组';

  @override
  String get groupNameLabel => '分组名称';

  @override
  String get groupNameHint => '请输入新的分组名称';

  @override
  String get nameCannotBeEmpty => '名称不能为空';

  @override
  String get renameSuccess => '已重命名';

  @override
  String renameFailedWithError(Object error) {
    return '重命名失败: $error';
  }

  @override
  String get groupAddedToast => '已新增分组';

  @override
  String addGroupFailedWithError(Object error) {
    return '新增分组失败: $error';
  }

  @override
  String get groupDeletedToast => '已删除分组';

  @override
  String deleteGroupFailedWithError(Object error) {
    return '删除分组失败: $error';
  }

  @override
  String loadGroupFailedWithError(Object error) {
    return '加载分组失败: $error';
  }

  @override
  String siteGroupDefaultName(Object index) {
    return '站点组$index';
  }

  @override
  String get defaultLabel => '默认';

  @override
  String get customLabel => '已自定义';

  @override
  String get normalShortLabel => '普通：';

  @override
  String get mergeShortLabel => '合并：';

  @override
  String get dailyShortLabel => '每日：';

  @override
  String timeRangeLabel(Object range) {
    return '时间段：$range';
  }

  @override
  String statusLabel(Object status) {
    return '状态：$status';
  }

  @override
  String samplesTitle(Object count) {
    return '样本($count)';
  }

  @override
  String get aiResultTitle => 'AI 结果';

  @override
  String modelValueLabel(Object model) {
    return 'Model：$model';
  }

  @override
  String get tagMergedCopy => '标记：合并事件';

  @override
  String categoriesLabel(Object categories) {
    return '类别：$categories';
  }

  @override
  String errorLabel(Object error) {
    return '错误：$error';
  }

  @override
  String summaryLabel(Object summary) {
    return '摘要：$summary';
  }

  @override
  String get autostartPermissionNote => '自启动权限因厂商而异，无法自动检测。请根据实际设置情况选择。';

  @override
  String monthDayTime(Object month, Object day, Object hour, Object minute) {
    return '$month月$day日 $hour:$minute';
  }

  @override
  String yearMonthDayTime(
    Object year,
    Object month,
    Object day,
    Object hour,
    Object minute,
  ) {
    return '$year年$month月$day日 $hour:$minute';
  }

  @override
  String imagesCountLabel(Object count) {
    return '$count张';
  }

  @override
  String get apps => '应用';

  @override
  String get images => '图片';

  @override
  String get days => '天';

  @override
  String get justNow => '刚刚';

  @override
  String minutesAgo(Object minutes) {
    return '$minutes分钟前';
  }

  @override
  String hoursAgo(Object hours) {
    return '$hours小时前';
  }

  @override
  String daysAgo(Object days) {
    return '$days天前';
  }

  @override
  String searchResultsCount(Object count) {
    return '找到 $count 张图片';
  }

  @override
  String get searchFiltersTitle => '筛选';

  @override
  String get filterByTime => '时间';

  @override
  String get filterByApp => '应用';

  @override
  String get filterBySize => '大小';

  @override
  String get filterTimeAll => '全部';

  @override
  String get filterTimeToday => '今天';

  @override
  String get filterTimeYesterday => '昨天';

  @override
  String get filterTimeLast7Days => '最近7天';

  @override
  String get filterTimeLast30Days => '最近30天';

  @override
  String get filterTimeCustomRange => '自定义范围';

  @override
  String get filterAppAll => '全部应用';

  @override
  String get filterSizeAll => '全部大小';

  @override
  String get filterSizeSmall => '< 100 KB';

  @override
  String get filterSizeMedium => '100 KB - 1 MB';

  @override
  String get filterSizeLarge => '> 1 MB';

  @override
  String get applyFilters => '应用';

  @override
  String get resetFilters => '重置';

  @override
  String get selectDateRange => '选择日期范围';

  @override
  String get startDate => '开始日期';

  @override
  String get endDate => '结束日期';

  @override
  String get noResultsForFilters => '没有符合当前筛选条件的图片';

  @override
  String get openLink => '打开';

  @override
  String get favoritePageTitle => '收藏';

  @override
  String get noFavoritesTitle => '暂无收藏';

  @override
  String get noFavoritesSubtitle => '在截图列表长按图片进入多选模式后收藏';

  @override
  String get noteLabel => '备注';

  @override
  String get updatedAt => '更新于 ';

  @override
  String get clickToAddNote => '点击添加备注...';

  @override
  String get noteUnchanged => '备注无变化';

  @override
  String get noteSaved => '备注已保存';

  @override
  String get favoritesRemoved => '已取消收藏';

  @override
  String get operationFailed => '操作失败';

  @override
  String get cannotGetAppDir => '无法获取应用目录';

  @override
  String get nsfwSettingsSectionTitle => 'NSFW 设置';

  @override
  String get blockedDomainListTitle => '禁用域名清单';

  @override
  String get addDomainPlaceholder => '输入域名或 *.example.com';

  @override
  String get addRuleAction => '添加';

  @override
  String get previewAction => '预览';

  @override
  String get removeAction => '移除';

  @override
  String get clearAction => '清空';

  @override
  String get clearAllRules => '清空所有规则';

  @override
  String get clearAllRulesConfirmTitle => '确认清空规则';

  @override
  String get clearAllRulesMessage => '将移除所有禁用域名规则，此操作不可恢复。';

  @override
  String previewAffectsCount(Object count) {
    return '预计影响 $count 张图片';
  }

  @override
  String affectCountLabel(Object count) {
    return '影响：$count 张';
  }

  @override
  String get confirmAddRuleTitle => '确认添加规则';

  @override
  String confirmAddRuleMessage(Object rule) {
    return '将添加规则：$rule';
  }

  @override
  String get ruleAddedToast => '规则已添加';

  @override
  String get ruleRemovedToast => '规则已移除';

  @override
  String get invalidDomainInputError => '请输入合法域名（支持 *.example.com）';

  @override
  String get manualMarkNsfw => '标记为 NSFW';

  @override
  String get manualUnmarkNsfw => '取消 NSFW 标记';

  @override
  String get manualMarkSuccess => '已标记为 NSFW';

  @override
  String get manualUnmarkSuccess => '已取消 NSFW 标记';

  @override
  String get manualMarkFailed => '操作失败';

  @override
  String get nsfwTagLabel => 'NSFW';

  @override
  String get nsfwBlockedByRulesHint => '该图片因域名规则被遮罩。请前往“设置 > NSFW 域名”管理。';

  @override
  String get providersTitle => '提供商';

  @override
  String get actionNew => '新建';

  @override
  String get actionAdd => '添加';

  @override
  String get noProvidersYetHint => '暂无提供商，可点击“新建”创建。';

  @override
  String confirmDeleteProviderMessage(Object name) {
    return '确定删除提供商“$name”吗？此操作不可恢复。';
  }

  @override
  String get loadingConversations => '正在加载会话…';

  @override
  String get noConversations => '暂无会话';

  @override
  String get deleteConversationTitle => '删除会话';

  @override
  String confirmDeleteConversationMessage(Object title) {
    return '确定要删除会话“$title”吗？';
  }

  @override
  String get untitledConversationLabel => '未命名会话';

  @override
  String get searchProviderPlaceholder => '搜索提供商';

  @override
  String get searchModelPlaceholder => '搜索模型';

  @override
  String providerSelectedToast(Object name) {
    return '已选择提供商：$name';
  }

  @override
  String get pleaseSelectProviderFirst => '请先选择提供商';

  @override
  String get noModelsForProviderHint => '该提供商无可用模型，请在“提供商”页刷新或手动添加';

  @override
  String get noModelsDetectedHint => '未检测到可用模型，可点击“刷新”或手动添加。';

  @override
  String modelSwitchedToast(Object model) {
    return '已切换模型：$model';
  }

  @override
  String get providerLabel => '提供商';

  @override
  String sendMessageToModelPlaceholder(Object model) {
    return '给 $model 发送消息';
  }

  @override
  String get deepThinkingLabel => '深度思考';

  @override
  String get thinkingInProgress => '思考中…';

  @override
  String get requestStoppedInfo => '已停止请求';

  @override
  String get reasoningLabel => 'Reasoning:';

  @override
  String get answerLabel => 'Answer:';

  @override
  String get aiSelfModeEnabledToast => '个人助手：对话将结合您的数据上下文';

  @override
  String selectModelWithCounts(Object filtered, Object total) {
    return '选择模型（$filtered/$total）';
  }

  @override
  String modelsCountLabel(Object count) {
    return '模型（$count）';
  }

  @override
  String get manualAddModelLabel => '手动添加模型';

  @override
  String get inputAndAddModelHint => '输入并添加，如 gpt-4o-mini';

  @override
  String get fetchModelsHint => '可点击“刷新”自动获取；失败时可手动添加模型名称。';

  @override
  String get interfaceTypeLabel => '接口类型';

  @override
  String currentTypeLabel(Object type) {
    return '当前：$type';
  }

  @override
  String get nameRequiredError => '名称必填';

  @override
  String get nameAlreadyExistsError => '名称已存在';

  @override
  String get apiKeyRequiredError => 'API Key 必填';

  @override
  String get baseUrlRequiredForAzureError => 'Azure OpenAI 需填写 Base URL';

  @override
  String get atLeastOneModelRequiredError => '至少添加一个模型';

  @override
  String modelsUpdatedToast(Object count) {
    return '已更新模型（$count）';
  }

  @override
  String get fetchModelsFailedHint => '获取模型失败，可手动添加。';

  @override
  String get useResponseApiLabel => '使用 Response API（仅OpenAI官方支持，第三方服务建议关闭）';

  @override
  String get chatPathOptionalLabel => 'Chat Path（可选）';

  @override
  String get azureApiVersionLabel => 'Azure API Version';

  @override
  String get azureApiVersionHint => '如 2024-02-15';

  @override
  String get baseUrlHintOpenAI => '例如：https://api.openai.com（留空则默认）';

  @override
  String get baseUrlHintClaude => '例如：https://api.anthropic.com';

  @override
  String get baseUrlHintGemini =>
      '例如：https://generativelanguage.googleapis.com';

  @override
  String baseUrlHintAzure(Object resource) {
    return '必填，例如：https://$resource.openai.azure.com';
  }

  @override
  String get baseUrlHintCustom => '请输入兼容 OpenAI 的 Base URL';

  @override
  String get createProviderTitle => '新建提供商';

  @override
  String get editProviderTitle => '编辑提供商';

  @override
  String get deletedToast => '已删除';

  @override
  String get providerNotFound => '提供商不存在';

  @override
  String get conversationsSectionTitle => '对话';

  @override
  String get displaySectionTitle => '显示';

  @override
  String get streamRenderImagesTitle => '流式期间实时渲染图片';

  @override
  String get streamRenderImagesDesc => '可能影响滚动流畅度';

  @override
  String get themeColorTitle => '主题颜色';

  @override
  String get themeColorDesc => '自定义应用主色调';

  @override
  String get chooseThemeColorTitle => '选择主题颜色';

  @override
  String get loggingTitle => '日志打印';

  @override
  String get loggingDesc => '开启后统一打印所有日志（默认开启）';

  @override
  String get loggingAiTitle => 'AI 日志';

  @override
  String get loggingScreenshotTitle => '截图日志';

  @override
  String get loggingAiDesc => '记录 AI 请求与响应日志';

  @override
  String get loggingScreenshotDesc => '记录截图采集与清理过程日志';

  @override
  String get themeModeAuto => '自动';

  @override
  String get themeModeLight => '浅色';

  @override
  String get themeModeDark => '深色';

  @override
  String get aiEmptySelfTitle => '个人助手已就绪';

  @override
  String get aiEmptySelfSubtitle => '直接提问，我会结合您的数据上下文来回答。';
}
