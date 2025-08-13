import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import '../theme/app_theme.dart';
import '../models/app_info.dart';
import '../models/screenshot_record.dart';
import '../services/screenshot_service.dart';
import '../services/path_service.dart';
import '../widgets/ui_components.dart';

class ScreenshotGalleryPage extends StatefulWidget {
  const ScreenshotGalleryPage({super.key});

  @override
  State<ScreenshotGalleryPage> createState() => _ScreenshotGalleryPageState();
}

class _ScreenshotGalleryPageState extends State<ScreenshotGalleryPage> {
  late AppInfo _appInfo;
  late String _packageName;
  List<ScreenshotRecord> _screenshots = [];
  bool _isLoading = true;
  String? _error;
  Directory? _baseDir;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (args != null) {
      _appInfo = args['appInfo'] as AppInfo;
      _packageName = args['packageName'] as String;
      _loadInitialData();
    } else {
       setState(() {
        _error = '参数错误';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadInitialData() async {
    try {
      // 使用PathService获取正确的外部文件目录
      final dir = await PathService.getExternalFilesDir(null);

      if (dir == null) {
        throw Exception("无法获取应用目录");
      }

      print('PathService返回的目录: ${dir.path}');

      setState(() {
        _baseDir = dir;
      });
      await _loadScreenshots();
    } catch (e) {
       setState(() {
        _error = '初始化失败: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadScreenshots() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      print('=== 开始加载截图 ===');
      print('应用包名: $_packageName');
      print('基础目录: ${_baseDir?.path}');

      // 先触发一次同步，确保本地新增文件入库
      await ScreenshotService.instance.syncDatabaseWithFiles(packageName: _packageName);
      final screenshots = await ScreenshotService.instance.getScreenshotsByApp(_packageName);
      print('从数据库获取到 ${screenshots.length} 张截图');

      // 检查实际文件是否存在
      for (int i = 0; i < screenshots.length; i++) {
        final screenshot = screenshots[i];
        final absolutePath = screenshot.filePath;
        final file = File(absolutePath);
        final exists = await file.exists();
        print('截图 ${i + 1}: $absolutePath - 文件存在: $exists');
      }

      // 同时检查预期的截图目录
      if (_baseDir != null) {
        final expectedDir = Directory('${_baseDir!.path}/output/screen/$_packageName');
        print('检查预期目录: ${expectedDir.path}');
        if (await expectedDir.exists()) {
          final files = await expectedDir.list().toList();
          print('目录中实际文件数量: ${files.length}');
          for (final file in files) {
            if (file is File && file.path.toLowerCase().endsWith('.png')) {
              print('发现PNG文件: ${file.path}');
            }
          }
        } else {
          print('预期目录不存在');
        }
      }

      setState(() {
        _screenshots = screenshots;
        _isLoading = false;
      });
    } catch (e) {
      print('加载截图失败: $e');
      setState(() {
        _error = '加载截图失败: $e';
        _isLoading = false;
      });
    }
  }

  void _viewScreenshot(ScreenshotRecord screenshot, int index) {
    Navigator.pushNamed(
      context,
      '/screenshot_viewer',
      arguments: {
        'screenshots': _screenshots,
        'initialIndex': index,
        'appName': _appInfo.appName,
        'appInfo': _appInfo, // 传递完整的appInfo对象，包含图标
      },
    );
  }

  Future<void> _deleteScreenshot(ScreenshotRecord screenshot) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        ),
        title: const Text('确认删除'),
        content: const Text('确定要删除这张截图吗？此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消', style: TextStyle(color: AppTheme.mutedForeground)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除', style: TextStyle(color: AppTheme.destructive)),
          ),
        ],
      ),
    );

    if (confirmed == true && screenshot.id != null) {
      try {
        final success = await ScreenshotService.instance.deleteScreenshot(screenshot.id!);
        if (success) {
          setState(() {
            _screenshots.removeWhere((s) => s.id == screenshot.id);
          });
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('截图已删除'),
                backgroundColor: AppTheme.success,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('删除失败'),
                backgroundColor: AppTheme.destructive,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('删除失败: $e'),
              backgroundColor: AppTheme.destructive,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Row(
          children: [
            if (_appInfo.icon != null)
              Container(
                width: 24,
                height: 24,
                margin: const EdgeInsets.only(right: 8),
                child: Image.memory(_appInfo.icon!, fit: BoxFit.contain),
              )
            else
              const Icon(Icons.android, size: 20, color: AppTheme.foreground),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _appInfo.appName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '${_screenshots.length}张 · ${_formatTotalSizeMBGBTB(_screenshots.fold<int>(0, (sum, r) => sum + r.fileSize))}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w400,
                    ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadScreenshots,
            tooltip: '刷新',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: AppTheme.spacing4),
            Text(
              '正在加载截图...',
              style: TextStyle(color: AppTheme.mutedForeground),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: AppTheme.destructive,
            ),
            const SizedBox(height: AppTheme.spacing4),
            Text(
              _error!,
              style: const TextStyle(color: AppTheme.destructive),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTheme.spacing4),
            UIButton(
              text: '重试',
              onPressed: _loadInitialData,
              variant: UIButtonVariant.outline,
            ),
          ],
        ),
      );
    }

    if (_screenshots.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.photo_library_outlined,
              size: 64,
              color: AppTheme.mutedForeground,
            ),
            SizedBox(height: AppTheme.spacing4),
            Text(
              '暂无截图',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: AppTheme.mutedForeground,
              ),
            ),
            SizedBox(height: AppTheme.spacing2),
            Text(
              '开启截图监控后，截图将显示在这里',
              style: TextStyle(color: AppTheme.mutedForeground),
            ),
          ],
        ),
      );
    }

    return _buildGalleryGrid();
  }

  Widget _buildGalleryGrid() {
    return Padding(
      padding: const EdgeInsets.all(AppTheme.spacing1), // 减少外边距
      child: GridView.builder(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + AppTheme.spacing6,
        ),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: AppTheme.spacing1, // 减少间距
          mainAxisSpacing: AppTheme.spacing1, // 减少间距
          childAspectRatio: 0.45, // 显著增加图片高度，确保图片显示完整
        ),
        itemCount: _screenshots.length,
        itemBuilder: (context, index) {
          final screenshot = _screenshots[index];
          return _buildScreenshotItem(screenshot, index);
        },
      ),
    );
  }

  Widget _buildScreenshotItem(ScreenshotRecord screenshot, int index) {
    if (_baseDir == null) {
      return _buildErrorItem("应用目录未初始化");
    }

    final absolutePath = path.join(_baseDir!.path, screenshot.filePath);
    final file = File(absolutePath);

    return GestureDetector(
      onTap: () => _viewScreenshot(screenshot, index),
      onLongPress: () => _deleteScreenshot(screenshot),
      child: Stack(
        children: [
          // 图片直接显示，无容器包装
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            child: Builder(
              builder: (context) {
                final isDark = Theme.of(context).brightness == Brightness.dark;
                final imageWidget = Image.file(
                  file,
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.cover, // 使用cover填满容器
                  errorBuilder: (context, error, stackTrace) {
                    print("图片加载失败: $error, path: ${file.path}");
                    return _buildErrorItem('图片丢失或损坏');
                  },
                );
                if (!isDark) return imageWidget;
                return ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    Colors.black.withValues(alpha: 0.5),
                    BlendMode.darken,
                  ),
                  child: imageWidget,
                );
              },
            ),
          ),
          // 底部信息遮罩
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing2,
                vertical: AppTheme.spacing1,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.7),
                  ],
                ),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(AppTheme.radiusMd),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatFileSize(screenshot.fileSize),
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white.withOpacity(0.85)
                          : Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    _formatDateTime(screenshot.captureTime),
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white.withOpacity(0.85)
                          : Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorItem(String message) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.muted,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: AppTheme.destructive, size: 32),
            const SizedBox(height: 4),
            Text(
              message,
              style: const TextStyle(color: AppTheme.destructive, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);
    
    if (diff.inMinutes < 1) {
      return '刚刚';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}分钟前';
    } else if (diff.inDays < 1) {
      return '${diff.inHours}小时前';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}天前';
    } else {
      return '${dateTime.month}/${dateTime.day} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '${bytes}B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)}KB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
  }

  /// 将字节格式化为最小MB，然后GB/TB
  String _formatTotalSizeMBGBTB(int bytes) {
    const double kb = 1024;
    const double mb = kb * 1024;
    const double gb = mb * 1024;
    const double tb = gb * 1024;

    if (bytes >= tb) {
      return (bytes / tb).toStringAsFixed(2) + 'TB';
    } else if (bytes >= gb) {
      return (bytes / gb).toStringAsFixed(2) + 'GB';
    } else {
      // 最小单位MB（包含 <1MB 的情况）
      return (bytes / mb).toStringAsFixed(2) + 'MB';
    }
  }
}
