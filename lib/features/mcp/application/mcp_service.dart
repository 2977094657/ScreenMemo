import 'package:flutter/services.dart';

class McpService {
  McpService._();

  static const MethodChannel _channel = MethodChannel(
    'com.fqyw.screen_memo/accessibility',
  );

  static Future<McpServerStatus> getStatus() async {
    final Map<dynamic, dynamic>? raw = await _channel.invokeMapMethod(
      'getMcpServerStatus',
    );
    return McpServerStatus.fromMap(raw);
  }

  static Future<McpServerStatus> start() async {
    final Map<dynamic, dynamic>? raw = await _channel.invokeMapMethod(
      'startMcpServer',
    );
    return McpServerStatus.fromMap(raw);
  }

  static Future<McpServerStatus> stop() async {
    final Map<dynamic, dynamic>? raw = await _channel.invokeMapMethod(
      'stopMcpServer',
    );
    return McpServerStatus.fromMap(raw);
  }

  static Future<McpServerStatus> resetToken() async {
    final Map<dynamic, dynamic>? raw = await _channel.invokeMapMethod(
      'resetMcpToken',
    );
    return McpServerStatus.fromMap(raw);
  }
}

class McpServerStatus {
  const McpServerStatus({
    required this.enabled,
    required this.running,
    required this.port,
    required this.endpoint,
    required this.lanIp,
    required this.token,
    required this.lastError,
    required this.lastStartedAt,
  });

  final bool enabled;
  final bool running;
  final int port;
  final String endpoint;
  final String lanIp;
  final String token;
  final String? lastError;
  final int lastStartedAt;

  factory McpServerStatus.fromMap(Map<dynamic, dynamic>? raw) {
    final Map<dynamic, dynamic> map = raw ?? const <dynamic, dynamic>{};
    int asInt(Object? value, int fallback) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse('$value') ?? fallback;
    }

    bool asBool(Object? value) {
      if (value is bool) return value;
      return '$value'.toLowerCase() == 'true';
    }

    String asString(Object? value) {
      if (value == null) return '';
      return '$value';
    }

    final String error = asString(map['lastError']).trim();
    return McpServerStatus(
      enabled: asBool(map['enabled']),
      running: asBool(map['running']),
      port: asInt(map['port'], 37621),
      endpoint: asString(map['endpoint']),
      lanIp: asString(map['lanIp']),
      token: asString(map['token']),
      lastError: error.isEmpty ? null : error,
      lastStartedAt: asInt(map['lastStartedAt'], 0),
    );
  }

  bool get hasEndpoint => endpoint.trim().isNotEmpty;
}
