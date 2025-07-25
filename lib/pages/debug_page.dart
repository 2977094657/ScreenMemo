import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart' as path_provider;
import '../services/screenshot_database.dart';
import '../services/screenshot_service.dart';
import '../services/path_service.dart';

class DebugPage extends StatefulWidget {
  const DebugPage({super.key});

  @override
  State<DebugPage> createState() => _DebugPageState();
}

class _DebugPageState extends State<DebugPage> {
  String _debugInfo = '点击"开始调试"按钮获取信息';
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('调试信息'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ElevatedButton(
              onPressed: _isLoading ? null : _startDebug,
              child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('开始调试'),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _debugInfo,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startDebug() async {
    setState(() {
      _isLoading = true;
      _debugInfo = '正在收集调试信息...\n';
    });

    final buffer = StringBuffer();
    
    try {
      buffer.writeln('=== 截图调试信息 ===');
      buffer.writeln('时间: ${DateTime.now()}');
      buffer.writeln();

      // 1. 检查存储目录
      buffer.writeln('1. 存储目录检查:');
      try {
        // 使用PathService获取所有路径信息
        final allPaths = await PathService.getAllPaths();
        buffer.writeln('=== PathService路径信息 ===');
        allPaths.forEach((key, value) {
          buffer.writeln('$key: $value');
        });
        buffer.writeln();

        // 传统path_provider路径（用于对比）
        buffer.writeln('=== 传统path_provider路径 ===');
        final externalDir = await path_provider.getExternalStorageDirectory();
        buffer.writeln('外部存储目录: ${externalDir?.path ?? "null"}');

        final appDocDir = await path_provider.getApplicationDocumentsDirectory();
        buffer.writeln('应用文档目录: ${appDocDir.path}');
        
        // 检查预期的截图目录结构
        if (externalDir != null) {
          final outputDir = Directory('${externalDir.path}/output');
          buffer.writeln('输出目录存在: ${await outputDir.exists()}');
          
          final screenDir = Directory('${externalDir.path}/output/screen');
          buffer.writeln('截图目录存在: ${await screenDir.exists()}');
          
          if (await screenDir.exists()) {
            final appDirs = await screenDir.list().toList();
            buffer.writeln('应用目录数量: ${appDirs.length}');
            
            for (final appDir in appDirs) {
              if (appDir is Directory) {
                final appName = appDir.path.split('/').last;
                final files = await appDir.list().where((f) => f is File && f.path.toLowerCase().endsWith('.png')).toList();
                buffer.writeln('  $appName: ${files.length} 张截图');
                
                // 显示前3个文件的详细信息
                for (int i = 0; i < files.length && i < 3; i++) {
                  final file = files[i] as File;
                  final stat = await file.stat();
                  buffer.writeln('    ${file.path.split('/').last}: ${stat.size} bytes, ${stat.modified}');
                }
                if (files.length > 3) {
                  buffer.writeln('    ... 还有 ${files.length - 3} 个文件');
                }
              }
            }
          }
        }
      } catch (e) {
        buffer.writeln('存储目录检查失败: $e');
      }
      
      buffer.writeln();

      // 2. 检查数据库
      buffer.writeln('2. 数据库检查:');
      try {
        final database = ScreenshotDatabase.instance;
        final db = await database.database;
        
        // 获取数据库路径
        buffer.writeln('数据库路径: ${db.path}');
        
        // 检查表是否存在
        final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
        buffer.writeln('数据库表: ${tables.map((t) => t['name']).join(', ')}');
        
        // 获取截图记录总数
        final countResult = await db.rawQuery('SELECT COUNT(*) as count FROM screenshots');
        final totalCount = countResult.first['count'] as int;
        buffer.writeln('截图记录总数: $totalCount');
        
        // 获取按应用分组的统计
        final appStats = await db.rawQuery('''
          SELECT app_package_name, app_name, COUNT(*) as count, 
                 MAX(capture_time) as last_capture
          FROM screenshots 
          WHERE is_deleted = 0 
          GROUP BY app_package_name 
          ORDER BY count DESC
        ''');
        
        buffer.writeln('按应用统计:');
        for (final stat in appStats) {
          final packageName = stat['app_package_name'];
          final appName = stat['app_name'];
          final count = stat['count'];
          final lastCapture = stat['last_capture'] as int?;
          final lastTime = lastCapture != null 
            ? DateTime.fromMillisecondsSinceEpoch(lastCapture)
            : null;
          buffer.writeln('  $appName ($packageName): $count 张, 最后截图: $lastTime');
        }
        
        // 获取最近的10条记录
        buffer.writeln();
        buffer.writeln('最近10条记录:');
        final recentRecords = await db.rawQuery('''
          SELECT * FROM screenshots 
          WHERE is_deleted = 0 
          ORDER BY capture_time DESC 
          LIMIT 10
        ''');
        
        for (final record in recentRecords) {
          final captureTime = DateTime.fromMillisecondsSinceEpoch(record['capture_time'] as int);
          final filePath = record['file_path'];
          final fileExists = await File(filePath as String).exists();
          buffer.writeln('  ${record['app_name']}: $filePath (存在: $fileExists) - $captureTime');
        }
        
      } catch (e) {
        buffer.writeln('数据库检查失败: $e');
      }
      
      buffer.writeln();

      // 3. 检查特定应用 (QQ)
      buffer.writeln('3. QQ应用检查:');
      try {
        final qqRecords = await ScreenshotService.instance.getScreenshotsByApp('com.tencent.mobileqq');
        buffer.writeln('QQ截图记录数: ${qqRecords.length}');
        
        for (int i = 0; i < qqRecords.length && i < 5; i++) {
          final record = qqRecords[i];
          final file = File(record.filePath);
          final exists = await file.exists();
          buffer.writeln('  ${record.filePath} - 存在: $exists, 时间: ${record.captureTime}');
        }
      } catch (e) {
        buffer.writeln('QQ应用检查失败: $e');
      }

      buffer.writeln();
      buffer.writeln('=== 调试信息收集完成 ===');

    } catch (e) {
      buffer.writeln('调试过程中发生错误: $e');
    }

    setState(() {
      _debugInfo = buffer.toString();
      _isLoading = false;
    });
  }


}
