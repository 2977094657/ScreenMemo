import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screen_memo/app/navigation/bottom_navigation_config.dart';
import 'package:screen_memo/app/navigation/customize_bottom_navigation_page.dart';
import 'package:screen_memo/core/constants/user_settings_keys.dart';
import 'package:screen_memo/data/database/screenshot_database.dart';
import 'package:screen_memo/l10n/app_localizations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dbRoot;

  Widget buildHarness(Widget child) {
    return MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );
  }

  Future<void> pumpEditor(
    WidgetTester tester,
    List<BottomNavItemId> initialItems,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 1000));
    await tester.pumpWidget(
      buildHarness(CustomizeBottomNavigationPage(initialItems: initialItems)),
    );
    await tester.pump();
  }

  Finder candidateFinder(BottomNavItemId id) {
    return find.byKey(ValueKey<String>('candidate_${id.storageValue}'));
  }

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dbRoot = await Directory.systemTemp.createTemp('screen_memo_nav_test_');
    await ScreenshotDatabase.instance.initializeForDesktop(dbRoot.path);
  });

  tearDown(() async {
    try {
      await TestWidgetsFlutterBinding.instance.setSurfaceSize(null);
    } catch (_) {}
    await ScreenshotDatabase.instance.disposeDesktop();
    if (await dbRoot.exists()) {
      await dbRoot.delete(recursive: true);
    }
  });

  test('normalizes invalid stored navigation config to defaults', () {
    expect(
      BottomNavigationConfig.normalizeItems(null),
      BottomNavigationConfig.defaultItems,
    );
    expect(
      BottomNavigationConfig.normalizeItems(<BottomNavItemId>[
        BottomNavItemId.home,
        BottomNavItemId.favorites,
      ]),
      BottomNavigationConfig.defaultItems,
    );
    expect(
      BottomNavigationConfig.parseItems(
        jsonEncode(<String>['home', 'unknown', 'settings']),
      ),
      isNull,
    );
  });

  test('saves and loads persisted navigation config', () async {
    const List<BottomNavItemId> expected = <BottomNavItemId>[
      BottomNavItemId.home,
      BottomNavItemId.timeline,
      BottomNavItemId.dynamic,
      BottomNavItemId.storage,
    ];

    await BottomNavigationConfig.saveItems(expected);

    final db = await ScreenshotDatabase.instance.database;
    final rows = await db.query(
      'user_settings',
      where: 'key = ?',
      whereArgs: <Object>[UserSettingKeys.bottomNavigationItems],
    );
    expect(rows, hasLength(1));
    expect(await BottomNavigationConfig.loadItems(), expected);
  });

  testWidgets('editor keeps home locked and returns selected items', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 1000));
    List<BottomNavItemId>? result;
    await tester.pumpWidget(
      buildHarness(
        Builder(
          builder: (BuildContext context) {
            return Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    result = await Navigator.of(context)
                        .push<List<BottomNavItemId>>(
                          MaterialPageRoute(
                            builder: (_) => CustomizeBottomNavigationPage(
                              initialItems: const <BottomNavItemId>[
                                BottomNavItemId.home,
                                BottomNavItemId.favorites,
                                BottomNavItemId.ai,
                                BottomNavItemId.settings,
                              ],
                            ),
                          ),
                        );
                  },
                  child: const Text('open editor'),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open editor'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('首页'), findsWidgets);
    expect(find.byIcon(Icons.check), findsNWidgets(3));
    expect(find.byIcon(Icons.remove), findsNWidgets(3));

    await tester.tap(
      find.descendant(
        of: candidateFinder(BottomNavItemId.dynamic),
        matching: find.byIcon(Icons.add),
      ),
    );
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: candidateFinder(BottomNavItemId.storage),
        matching: find.byIcon(Icons.add),
      ),
    );
    await tester.pump();

    expect(
      find.descendant(
        of: candidateFinder(BottomNavItemId.dynamic),
        matching: find.byIcon(Icons.add),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: candidateFinder(BottomNavItemId.storage),
        matching: find.byIcon(Icons.add),
      ),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey<String>('confirm_bottom_nav')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(result, <BottomNavItemId>[
      BottomNavItemId.home,
      BottomNavItemId.favorites,
      BottomNavItemId.ai,
      BottomNavItemId.settings,
      BottomNavItemId.dynamic,
      BottomNavItemId.storage,
    ]);
  });

  testWidgets('editor prevents removing below minimum item count', (
    WidgetTester tester,
  ) async {
    await pumpEditor(tester, const <BottomNavItemId>[
      BottomNavItemId.home,
      BottomNavItemId.favorites,
      BottomNavItemId.settings,
    ]);

    await tester.tap(find.byIcon(Icons.remove).first);
    await tester.pump();

    expect(find.text('至少保留 3 个菜单'), findsOneWidget);
    expect(find.byIcon(Icons.remove), findsNWidgets(2));
  });

  testWidgets('editor prevents adding above maximum item count', (
    WidgetTester tester,
  ) async {
    await pumpEditor(tester, const <BottomNavItemId>[
      BottomNavItemId.home,
      BottomNavItemId.favorites,
      BottomNavItemId.ai,
      BottomNavItemId.timeline,
      BottomNavItemId.settings,
      BottomNavItemId.dynamic,
    ]);

    await tester.tap(
      find.descendant(
        of: candidateFinder(BottomNavItemId.storage),
        matching: find.byIcon(Icons.add),
      ),
    );
    await tester.pump();

    expect(find.text('最多只能添加 6 个菜单'), findsOneWidget);
  });

  testWidgets('editor preview fills the row with even item widths', (
    WidgetTester tester,
  ) async {
    await pumpEditor(tester, const <BottomNavItemId>[
      BottomNavItemId.home,
      BottomNavItemId.favorites,
      BottomNavItemId.settings,
    ]);

    final double homeWidth = tester.getSize(find.text('首页').first).width;
    final double favoritesWidth = tester.getSize(find.text('收藏').last).width;
    final double settingsWidth = tester.getSize(find.text('设置').last).width;

    // Text widths differ, but their Expanded parent centers should be evenly spaced.
    final double homeCenter = tester.getCenter(find.text('首页').first).dx;
    final double favoritesCenter = tester.getCenter(find.text('收藏').last).dx;
    final double settingsCenter = tester.getCenter(find.text('设置').last).dx;
    expect(
      favoritesCenter - homeCenter,
      closeTo(settingsCenter - favoritesCenter, 1),
    );
    expect(homeWidth, greaterThan(0));
    expect(favoritesWidth, greaterThan(0));
    expect(settingsWidth, greaterThan(0));
  });
}
