import 'package:flutter/widgets.dart';

String buildPromptTimeZoneOffset(Duration offset) {
  final int minutes = offset.inMinutes;
  final String sign = minutes >= 0 ? '+' : '-';
  final int absMinutes = minutes.abs();
  final String hh = (absMinutes ~/ 60).toString().padLeft(2, '0');
  final String mm = (absMinutes % 60).toString().padLeft(2, '0');
  return 'UTC$sign$hh:$mm';
}

String buildPromptLocalDateTime(DateTime now) {
  final String year = now.year.toString().padLeft(4, '0');
  final String month = now.month.toString().padLeft(2, '0');
  final String day = now.day.toString().padLeft(2, '0');
  final String hour = now.hour.toString().padLeft(2, '0');
  final String minute = now.minute.toString().padLeft(2, '0');
  final String second = now.second.toString().padLeft(2, '0');
  final String offset = buildPromptTimeZoneOffset(now.timeZoneOffset);
  return '$year-$month-$day'
      'T$hour:$minute:$second'
      '${offset.substring(3)}';
}

String buildCurrentDateTimeSystemMessage(Locale locale, {DateTime? now}) {
  final DateTime effectiveNow = now ?? DateTime.now();
  final String localDateTime = buildPromptLocalDateTime(effectiveNow);
  final String tzOffset = buildPromptTimeZoneOffset(
    effectiveNow.timeZoneOffset,
  );
  final String tzName = effectiveNow.timeZoneName.trim();
  final String tzDisplay = tzName.isEmpty ? tzOffset : '$tzName ($tzOffset)';
  final bool zh = locale.languageCode.toLowerCase().startsWith('zh');

  if (zh) {
    return [
      '当前设备本地日期时间（本轮请求的可信时间）: $localDateTime',
      '当前时区: $tzDisplay。',
      '当用户询问“今天 / 明天 / 昨天 / 现在 / 当前日期 / 当前时间”等相对时间时，以上述时间为准。',
    ].join('\n');
  }

  return [
    'Current device-local datetime (authoritative for this request): $localDateTime',
    'Current timezone: $tzDisplay.',
    'When the user asks about relative time such as today / tomorrow / yesterday / now / current date / current time, use this time as ground truth.',
  ].join('\n');
}

String buildAppMarkerSystemMessage(Locale locale) {
  final bool zh = locale.languageCode.toLowerCase().startsWith('zh');
  if (zh) {
    return [
      '若需要在正文里提及应用名称，请使用特殊标记，便于前端渲染应用图标。',
      '格式1：[app: 应用名]',
      '格式2：[app: 应用名|应用包名]',
      '若已知包名，优先使用格式2，例如：[app: 微信|com.tencent.mm]、[app: QQ|com.tencent.mobileqq]。',
      '请直接输出裸标记，不要再包裹反引号、代码块、链接、加粗或其他 Markdown 语法。',
      '仅在真正表示应用名称时使用该标记，不要给普通名词或网站名添加此标记。',
    ].join('\n');
  }

  return [
    'When you mention an app name in the visible answer, use the special marker so the frontend can render the app icon.',
    'Format 1: [app: App Name]',
    'Format 2: [app: App Name|app.package.name]',
    'If the package name is known, prefer format 2, for example [app: WeChat|com.tencent.mm] or [app: QQ|com.tencent.mobileqq].',
    'Output the marker directly without wrapping it in backticks, code blocks, links, bold text, or other Markdown syntax.',
    'Use this marker only for actual app names, not for generic nouns or website names.',
  ].join('\n');
}
