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
import '../widgets/ui_components.dart';
import '../services/flutter_logger.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/nsfw_guard.dart';

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
  bool _initialized = false;

  // 移除调试日志

  @override
  void initState() {
    super.initState();
    // Android：通过原生方法通道隐藏状态栏（仅顶部）
    if (Platform.isAndroid) {
      _platform.invokeMethod('hideStatusBar');
    }
  }

  Future<void> _openCurrentLink() async {
    if (_screenshots.isEmpty) return;
    final url = _screenshots[_currentIndex].pageUrl;
    if (url == null || url.isEmpty) return;
    try {
      // 记录点击打开链接的日志（Flutter 与原生）
      // ignore: unawaited_futures
      FlutterLogger.info('UI.查看器-打开链接 url='+url);
      // ignore: unawaited_futures
      FlutterLogger.nativeInfo('UI', 'viewer open link: '+url);
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  Future<void> _showLinkDialog() async {
    if (_screenshots.isEmpty) return;
    final url = _screenshots[_currentIndex].pageUrl;
    if (url == null || url.isEmpty) return;
    await showUIDialog<void>(
      context: context,
      title: '链接',
      content: SelectableText(url, textAlign: TextAlign.center),
      barrierDismissible: true,
      actions: [
        UIDialogAction<void>(
          text: '复制',
          style: UIDialogActionStyle.primary,
          closeOnPress: true,
          onPressed: (ctx) async {
            try {
              await Clipboard.setData(ClipboardData(text: url));
              // ignore: unawaited_futures
              FlutterLogger.info('UI.查看器-复制链接 成功');
              // ignore: unawaited_futures
              FlutterLogger.nativeInfo('UI', 'viewer copy link success');
              if (mounted) {
                UINotifier.success(context, 'Copied');
              }
            } catch (e) {
              // ignore: unawaited_futures
              FlutterLogger.error('UI.查看器-复制链接 失败: '+e.toString());
              // ignore: unawaited_futures
              FlutterLogger.nativeError('UI', 'viewer copy link failed: '+e.toString());
              if (mounted) {
                UINotifier.error(context, 'Copy failed');
              }
            }
          },
        ),
        UIDialogAction<void>(
          text: '打开',
          style: UIDialogActionStyle.normal,
          closeOnPress: true,
          onPressed: (ctx) async {
            await _openCurrentLink();
          },
        ),
        const UIDialogAction<void>(
          text: '取消',
          style: UIDialogActionStyle.normal,
          closeOnPress: true,
        ),
      ],
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_initialized) return;

    // 获取路由参数（仅初始化一次，避免后续依赖变化导致索引重置）
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (args != null) {
      _screenshots = args['screenshots'] as List<ScreenshotRecord>;
      _currentIndex = args['initialIndex'] as int;
      _appName = args['appName'] as String;
      _appInfo = args['appInfo'] as AppInfo;
      _pageController = PageController(initialPage: _currentIndex);
      _initialized = true;
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
      // 记录UI删除操作日志
      // ignore: unawaited_futures
      FlutterLogger.info('UI.查看器-删除当前-发起 id=${screenshot.id} 包=${_appInfo.packageName} 路径=${screenshot.filePath}');
      // ignore: unawaited_futures
      FlutterLogger.nativeInfo('UI', 'viewer delete start id=${screenshot.id}');
      try {
        final success = await ScreenshotService.instance.deleteScreenshot(screenshot.id!, _appInfo.packageName);
        if (success) {
          // ignore: unawaited_futures
          FlutterLogger.info('UI.查看器-删除当前-成功 id=${screenshot.id}');
          // ignore: unawaited_futures
          FlutterLogger.nativeInfo('UI', 'viewer delete success id=${screenshot.id}');
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
            UINotifier.success(context, '截图已删除');
          }
        } else {
          // ignore: unawaited_futures
          FlutterLogger.warn('UI.查看器-删除当前-失败 id=${screenshot.id}');
          // ignore: unawaited_futures
          FlutterLogger.nativeWarn('UI', 'viewer delete failed id=${screenshot.id}');
          if (mounted) {
            UINotifier.error(context, '删除失败');
          }
        }
      } catch (e) {
        // ignore: unawaited_futures
        FlutterLogger.error('UI.查看器-删除当前-异常: $e');
        // ignore: unawaited_futures
        FlutterLogger.nativeError('UI', 'viewer delete exception: $e');
        if (mounted) {
          UINotifier.error(context, '删除失败: $e');
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
          if (screenshot.pageUrl != null && screenshot.pageUrl!.isNotEmpty)
            _buildInfoRow('页面链接', screenshot.pageUrl!),
          if (screenshot.fileSize > 0)
            _buildInfoRow('文件大小', _formatFileSize(screenshot.fileSize)),
        ],
      ),
      actions: const [UIDialogAction(text: '确定')],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final labelColor = onSurface.withOpacity(0.7);
    final valueColor = onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: labelColor,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: valueColor),
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
                if (_screenshots.isNotEmpty &&
                    _screenshots[_currentIndex].pageUrl != null &&
                    _screenshots[_currentIndex].pageUrl!.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.link),
                    onPressed: _showLinkDialog,
                    tooltip: '链接',
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
            // 当当前图片被识别为 NSFW 时，初始以信息栏提示+点击空白即可查看（此处不做强制遮挡避免与缩放手势冲突）
            if (_screenshots.isNotEmpty &&
                NsfwDetector.isNsfwUrl(_screenshots[_currentIndex].pageUrl))
              Positioned(
                bottom: 24,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      '内容警告：成人内容 · 轻触继续',
                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            // 按需求：大图查看页不显示顶部链接遮罩，仅保留右上角链接图标
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