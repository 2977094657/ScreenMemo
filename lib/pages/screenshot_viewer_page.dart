import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_dialog.dart';
import '../models/screenshot_record.dart';
import '../models/app_info.dart';
import '../services/screenshot_service.dart';

/// 截图查看器页面
class ScreenshotViewerPage extends StatefulWidget {
  const ScreenshotViewerPage({super.key});

  @override
  State<ScreenshotViewerPage> createState() => _ScreenshotViewerPageState();
}

class _ScreenshotViewerPageState extends State<ScreenshotViewerPage> {
  static const MethodChannel _platform = MethodChannel('com.fqyw.screen_memo/accessibility');
  late List<ScreenshotRecord> _screenshots;
  late int _currentIndex;
  late String _appName;
  late AppInfo _appInfo;
  late PageController _pageController;
  bool _showAppBar = true;

  // 移除调试日志

  @override
  void initState() {
    super.initState();
    // Android：通过原生方法通道隐藏状态栏（仅顶部）
    if (Platform.isAndroid) {
      _platform.invokeMethod('hideStatusBar');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // 获取路由参数
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (args != null) {
      _screenshots = args['screenshots'] as List<ScreenshotRecord>;
      _currentIndex = args['initialIndex'] as int;
      _appName = args['appName'] as String;
      _appInfo = args['appInfo'] as AppInfo;
      _pageController = PageController(initialPage: _currentIndex);
    }

    // 去除额外 dump
  }

  @override
  void dispose() {
    // Android：恢复状态栏
    if (Platform.isAndroid) {
      _platform.invokeMethod('showStatusBar');
    }
    _pageController.dispose();
    super.dispose();
  }

  void _toggleAppBar() {
    setState(() {
      _showAppBar = !_showAppBar;
    });
  }



  Future<void> _deleteCurrentImage() async {
    final screenshot = _screenshots[_currentIndex];
    
    final confirmed = await showUIDialog<bool>(
      context: context,
      title: '确认删除',
      message: '确定要删除这张截图吗？此操作无法撤销。',
      actions: const [
        UIDialogAction<bool>(text: '取消', result: false),
        UIDialogAction<bool>(text: '删除', style: UIDialogActionStyle.destructive, result: true),
      ],
      barrierDismissible: false,
    );

    if (confirmed == true && screenshot.id != null) {
      try {
        final success = await ScreenshotService.instance.deleteScreenshot(screenshot.id!);
        if (success) {
          setState(() {
            _screenshots.removeAt(_currentIndex);
            
            // 调整当前索引
            if (_screenshots.isEmpty) {
              Navigator.of(context).pop(); // 没有图片了，返回上一页
              return;
            } else if (_currentIndex >= _screenshots.length) {
              _currentIndex = _screenshots.length - 1;
            }
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

  void _showImageInfo() {
    final screenshot = _screenshots[_currentIndex];
    final file = File(screenshot.filePath);

    showUIDialog<void>(
      context: context,
      title: '截图信息',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoRow('应用名称', screenshot.appName),
          _buildInfoRow('截图时间', _formatDateTime(screenshot.captureTime)),
          _buildInfoRow('文件路径', screenshot.filePath),
          if (screenshot.fileSize > 0)
            _buildInfoRow('文件大小', _formatFileSize(screenshot.fileSize)),
          FutureBuilder<bool>(
            future: file.exists(),
            builder: (context, snapshot) {
              return _buildInfoRow(
                '文件状态',
                snapshot.data == true ? '存在' : '不存在',
              );
            },
          ),
        ],
      ),
      actions: const [UIDialogAction(text: '确定')],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: AppTheme.mutedForeground,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: AppTheme.foreground),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? Theme.of(context).scaffoldBackgroundColor
          : Colors.black,
      extendBodyBehindAppBar: true,
      appBar: _showAppBar
          ? AppBar(
              backgroundColor: Theme.of(context).brightness == Brightness.dark
                  ? Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.85)
                  : Colors.black.withValues(alpha: 0.7),
              elevation: 0,
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 应用图标
                  if (_appInfo.icon != null)
                    Container(
                      width: 24,
                      height: 24,
                      margin: const EdgeInsets.only(right: 8),
                      child: Image.memory(
                        _appInfo.icon!,
                        width: 24,
                        height: 24,
                        fit: BoxFit.contain,
                      ),
                    )
                  else
                    Container(
                      width: 24,
                      height: 24,
                      margin: const EdgeInsets.only(right: 8),
                      child: const Icon(
                        Icons.android,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  // 应用名称和计数
                  Flexible(
                    child: Text(
                      '$_appName (${_currentIndex + 1}/${_screenshots.length})',
                      style: const TextStyle(color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              iconTheme: const IconThemeData(color: Colors.white),
              actions: [
                IconButton(
                  icon: const Icon(Icons.info_outline),
                  onPressed: _showImageInfo,
                  tooltip: '图片信息',
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _deleteCurrentImage,
                  tooltip: '删除图片',
                ),
              ],
            )
          : null,
      body: GestureDetector(
        onTap: _toggleAppBar,
        child: Stack(
          children: [
            PhotoViewGallery.builder(
          scrollPhysics: const BouncingScrollPhysics(),
          builder: (BuildContext context, int index) {
            final screenshot = _screenshots[index];
            final file = File(screenshot.filePath);

            return PhotoViewGalleryPageOptions(
              imageProvider: FileImage(file),
              initialScale: PhotoViewComputedScale.contained,
              minScale: PhotoViewComputedScale.contained, // 最小缩放为原图比例，不能再缩小
              maxScale: PhotoViewComputedScale.covered * 4.0,
              errorBuilder: (context, error, stackTrace) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.broken_image,
                        color: Colors.white54,
                        size: 64,
                      ),
                      SizedBox(height: 16),
                      Text(
                        '图片加载失败',
                        style: TextStyle(color: Colors.white54),
                      ),
                    ],
                  ),
                );
              },
            );
          },
          itemCount: _screenshots.length,
          loadingBuilder: (context, event) => const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
          backgroundDecoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? Theme.of(context).scaffoldBackgroundColor
                : Colors.black,
          ),
          pageController: _pageController,
          onPageChanged: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
            ),
            if (Theme.of(context).brightness == Brightness.dark)
              IgnorePointer(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.5),
                ),
              ),
          ],
        ),
      ),
    );
  }



  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}/${dateTime.month.toString().padLeft(2, '0')}/${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
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
}