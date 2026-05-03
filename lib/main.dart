import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:screen_memo/app/screen_memo_app.dart';
import 'package:screen_memo/core/logging/flutter_logger.dart';
import 'package:screen_memo/core/performance/startup_profiler.dart';
import 'package:screen_memo/features/permissions/application/permission_service.dart';
import 'package:screen_memo/features/capture/application/screenshot_service.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 初始化日志（默认开启；读取用户偏好）
  await FlutterLogger.init();
  await FlutterLogger.info('应用启动');
  StartupProfiler.mark('main.ensureInitialized.done');

  // 提前计算首屏需要用到的首启/引导信息
  final permissionService = PermissionService.instance;
  final bool onboardingCompleted = await permissionService
      .isOnboardingCompleted();
  final bool isFirstLaunch = await permissionService.isFirstLaunch();
  final bool showOnboarding = !onboardingCompleted && isFirstLaunch;

  void appRunner() {
    // 统一使用 Zone 拦截所有 print，并通过 FlutterLogger 输出
    runZonedGuarded(
      () {
        // 拦截 debugPrint 与 FlutterError
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message == null) return;
          // ignore: discarded_futures
          FlutterLogger.debug(message);
        };
        FlutterError.onError = (FlutterErrorDetails details) {
          // ignore: discarded_futures
          FlutterLogger.handle(
            details.exception,
            details.stack ?? StackTrace.current,
            tag: 'Flutter错误',
            message: details.exceptionAsString(),
          );
        };
        PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
          // ignore: discarded_futures
          FlutterLogger.handle(error, stack, tag: '未捕获异常');
          return false; // 继续默认处理
        };

        // 预先初始化 ScreenshotService，尽早注册 MethodChannel 回调处理器
        // ignore: unnecessary_statements
        ScreenshotService.instance;

        StartupProfiler.begin('runApp');
        runApp(
          ScreenMemoApp(
            initialShowOnboarding: showOnboarding,
            isFirstLaunch: isFirstLaunch,
          ),
        );
        StartupProfiler.end('runApp');
      },
      (e, s) {
        // ignore: discarded_futures
        FlutterLogger.handle(e, s, tag: 'Zone异常');
      },
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) {
          // ignore: discarded_futures
          FlutterLogger.handlePrint(line);
        },
      ),
    );
  }

  const sentryDsn = String.fromEnvironment('SENTRY_DSN');
  if (sentryDsn.isNotEmpty) {
    await SentryFlutter.init((options) {
      options.dsn = sentryDsn;
      options.tracesSampleRate = 0.0;
    }, appRunner: appRunner);
  } else {
    appRunner();
  }
}
