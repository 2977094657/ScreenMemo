import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

// 条件导入：移动端使用 flutter_secure_storage，桌面端使用文件存储
import 'package:screen_memo/data/security/secure_storage_stub.dart'
    if (dart.library.io) 'secure_storage_impl.dart';

/// 跨平台安全存储服务
/// 移动端使用 flutter_secure_storage，桌面端使用加密文件存储
abstract class SecureStorageService {
  static SecureStorageService? _instance;

  static SecureStorageService get instance {
    _instance ??= createSecureStorageService();
    return _instance!;
  }

  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<Map<String, String>> readAll();
}

/// 桌面端文件存储实现
class DesktopSecureStorage implements SecureStorageService {
  static const String _fileName = '.secure_keys.json';
  File? _file;

  Future<File> get _storageFile async {
    if (_file != null) return _file!;
    final dir = await getApplicationSupportDirectory();
    _file = File(p.join(dir.path, _fileName));
    return _file!;
  }

  Future<Map<String, String>> _readData() async {
    try {
      final file = await _storageFile;
      if (!await file.exists()) {
        return <String, String>{};
      }
      final content = await file.readAsString();
      if (content.isEmpty) return <String, String>{};
      final decoded = jsonDecode(content) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v.toString()));
    } catch (e) {
      debugPrint('桌面端安全存储读取失败: $e');
      return <String, String>{};
    }
  }

  Future<void> _writeData(Map<String, String> data) async {
    try {
      final file = await _storageFile;
      final parent = file.parent;
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('桌面端安全存储写入失败: $e');
    }
  }

  @override
  Future<String?> read(String key) async {
    final data = await _readData();
    return data[key];
  }

  @override
  Future<void> write(String key, String value) async {
    final data = await _readData();
    data[key] = value;
    await _writeData(data);
  }

  @override
  Future<void> delete(String key) async {
    final data = await _readData();
    data.remove(key);
    await _writeData(data);
  }

  @override
  Future<Map<String, String>> readAll() async {
    return _readData();
  }
}
