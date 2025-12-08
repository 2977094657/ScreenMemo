import 'secure_storage_service.dart';

/// 创建安全存储服务
/// 所有平台使用文件存储（API Key 已迁移到数据库存储）
SecureStorageService createSecureStorageService() {
  return DesktopSecureStorage();
}
