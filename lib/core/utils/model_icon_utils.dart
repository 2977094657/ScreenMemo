import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

/// 模型图标匹配工具类
/// 提供统一的模型名称到图标路径的映射逻辑
class ModelIconUtils {
  ModelIconUtils._();

  // 资产清单缓存（仅加载一次），用于动态匹配 svg 文件
  static Set<String>? _iconAssets;
  static bool _manifestLoading = false;

  static Future<void> _ensureManifestLoaded() async {
    if (_iconAssets != null || _manifestLoading) return;
    _manifestLoading = true;
    try {
      final manifestJson = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> map =
          json.decode(manifestJson) as Map<String, dynamic>;
      final set = <String>{};
      for (final entry in map.keys) {
        if (entry is String &&
            entry.startsWith('assets/icons/ai/') &&
            entry.toLowerCase().endsWith('.svg')) {
          set.add(entry.toLowerCase());
        }
      }
      _iconAssets = set;
    } catch (_) {
      _iconAssets = <String>{};
    } finally {
      _manifestLoading = false;
    }
  }

  /// 预加载图标资产清单（建议在应用启动或页面 initState 调用）
  static Future<void> preload() => _ensureManifestLoaded();

  static const Map<String, String> _aliases = {
    // 常见别名/归一化
    'chatglm': 'zhipu',
    'glm': 'zhipu',
    'zhipu': 'zhipu',
    'ernie': 'wenxin',
    'iflytek': 'spark',
    'xinghuo': 'spark',
    'google': 'gemini',
    'anthropic': 'claude',
    'xai': 'grok',
    'moonshot': 'moonshot',
    'kimi': 'kimi',
  };

  static Iterable<String> _candidateTokens(String s) {
    final original = s.toLowerCase();
    // 统一分隔符，去掉无关字符
    String norm = original.replaceAll(RegExp(r'[\s_/]+'), '-');
    norm = norm.replaceAll(RegExp(r'[^a-z0-9\-]'), '-');
    norm = norm.replaceAll(RegExp(r'-{2,}'), '-').trim();
    if (norm.startsWith('-')) norm = norm.substring(1);
    if (norm.endsWith('-')) norm = norm.substring(0, norm.length - 1);

    final root = norm
        .split('-')
        .firstWhere((e) => e.isNotEmpty, orElse: () => norm);

    // 候选顺序：别名(root) -> 别名(norm) -> root -> norm
    final ordered = <String>[];
    final seen = <String>{};

    void add(String t) {
      if (t.isEmpty) return;
      if (!seen.contains(t)) {
        ordered.add(t);
        seen.add(t);
      }
    }

    add(_aliases[root] ?? root);
    add(_aliases[norm] ?? norm);
    add(root);
    add(norm);

    return ordered;
  }

  static String? _dynamicGuessByName(String name) {
    final assets = _iconAssets;
    if (assets == null || assets.isEmpty) return null;

    for (final token in _candidateTokens(name)) {
      final p1 = 'assets/icons/ai/$token-color.svg';
      if (assets.contains(p1)) return p1;
      final p2 = 'assets/icons/ai/$token.svg';
      if (assets.contains(p2)) return p2;
    }
    return null;
  }

  /// 根据模型名称返回对应的 SVG 图标路径
  ///
  /// 匹配规则（按优先级）：
  /// 1. Gemini 系列 -> gemini-color.svg
  /// 2. Claude/Anthropic 系列 -> claude-color.svg
  /// 3. DeepSeek 系列 -> deepseek-color.svg
  /// 4. Qwen/通义/阿里 系列 -> qwen-color.svg
  /// 5. GLM/智谱 系列 -> zhipu-color.svg
  /// 6. Grok/xAI 系列 -> grok.svg
  /// 7. GPT/OpenAI/o3 系列 -> openai.svg
  /// 8. 默认 -> openai.svg
  static String getIconPath(String? modelName) {
    if (modelName == null || modelName.trim().isEmpty) {
      return 'assets/icons/ai/openai.svg';
    }
    final m = modelName.toLowerCase();

    // Google Gemini
    if (m.contains('gemini')) {
      return 'assets/icons/ai/gemini-color.svg';
    }

    // Anthropic Claude
    if (m.contains('claude') || m.contains('anthropic')) {
      return 'assets/icons/ai/claude-color.svg';
    }

    // Mistral / Mixtral
    if (m.contains('mistral') || m.contains('mixtral')) {
      return 'assets/icons/ai/mistral-color.svg';
    }

    // Meta Llama
    if (m.contains('llama')) {
      return 'assets/icons/ai/meta-color.svg';
    }

    // Gemma
    if (m.contains('gemma')) {
      return 'assets/icons/ai/gemma-color.svg';
    }

    // DeepSeek
    if (m.contains('deepseek')) {
      return 'assets/icons/ai/deepseek-color.svg';
    }

    // Qwen / 通义 / Ali
    if (m.contains('qwen') ||
        m.contains('dashscope') ||
        m.contains('ali') ||
        m.contains('通义')) {
      return 'assets/icons/ai/qwen-color.svg';
    }

    // Zhipu / GLM
    if (m.contains('glm') ||
        m.contains('chatglm') ||
        m.contains('智谱') ||
        m.contains('zhipu')) {
      return 'assets/icons/ai/zhipu-color.svg';
    }

    // Baidu / Wenxin / ERNIE
    if (m.contains('wenxin') || m.contains('ernie') || m.contains('baidu')) {
      return 'assets/icons/ai/wenxin-color.svg';
    }

    // Tencent / Hunyuan
    if (m.contains('hunyuan') || m.contains('tencent')) {
      return 'assets/icons/ai/hunyuan-color.svg';
    }

    // iFlytek / Spark / Xinghuo
    if (m.contains('spark') ||
        m.contains('iflytek') ||
        m.contains('讯飞') ||
        m.contains('xinghuo')) {
      return 'assets/icons/ai/spark-color.svg';
    }

    // InternLM / 书生
    if (m.contains('internlm') || m.contains('书生')) {
      return 'assets/icons/ai/internlm-color.svg';
    }

    // 01.ai / Yi
    if (m.contains('yi') || m.contains('01-ai') || m.contains('zeroone')) {
      return 'assets/icons/ai/yi-color.svg';
    }

    // xAI / Grok
    if (m.contains('grok') || m.contains('xai')) {
      return 'assets/icons/ai/grok.svg';
    }

    // Perplexity
    if (m.contains('perplexity') || m.contains('sonar')) {
      return 'assets/icons/ai/perplexity-color.svg';
    }

    // Groq
    if (m.contains('groq')) {
      return 'assets/icons/ai/groq.svg';
    }

    // Ollama
    if (m.contains('ollama')) {
      return 'assets/icons/ai/ollama.svg';
    }

    // Moonshot / Kimi
    if (m.contains('kimi') || m.contains('moonshot')) {
      if (m.contains('kimi')) {
        return 'assets/icons/ai/kimi-color.svg';
      }
      return 'assets/icons/ai/moonshot.svg';
    }

    // Microsoft Phi
    if (m.contains('phi')) {
      return 'assets/icons/ai/microsoft-color.svg';
    }

    // Vertex AI
    if (m.contains('vertex')) {
      return 'assets/icons/ai/vertexai-color.svg';
    }

    // Bedrock (AWS)
    if (m.contains('bedrock') || m.contains('aws')) {
      return 'assets/icons/ai/bedrock-color.svg';
    }

    // OpenRouter / Together
    if (m.contains('openrouter')) {
      return 'assets/icons/ai/openrouter.svg';
    }
    if (m.contains('together')) {
      return 'assets/icons/ai/together-color.svg';
    }

    // GPT / OpenAI / o3 / o1
    if (m.contains('gpt') ||
        m.contains('openai') ||
        m.contains('o3') ||
        m.contains('o1')) {
      return 'assets/icons/ai/openai.svg';
    }

    // 动态兜底：根据清单匹配 {token}-color.svg / {token}.svg
    _ensureManifestLoaded();
    final dyn = _dynamicGuessByName(m);
    if (dyn != null) return dyn;

    // 默认
    return 'assets/icons/ai/openai.svg';
  }

  /// 根据提供商类型返回对应的 SVG 图标路径
  ///
  /// 用于提供商列表展示
  static String getProviderIconPath(String? providerType) {
    if (providerType == null || providerType.trim().isEmpty) {
      return 'assets/icons/ai/openai.svg';
    }

    final type = providerType.toLowerCase();

    switch (type) {
      case 'openai':
        return 'assets/icons/ai/openai.svg';

      case 'azure_openai':
      case 'azure':
        return 'assets/icons/ai/openai.svg';

      case 'claude':
      case 'anthropic':
        return 'assets/icons/ai/claude-color.svg';

      case 'gemini':
      case 'google':
        return 'assets/icons/ai/gemini-color.svg';

      case 'mistral':
        return 'assets/icons/ai/mistral-color.svg';

      case 'groq':
        return 'assets/icons/ai/groq.svg';

      case 'openrouter':
        return 'assets/icons/ai/openrouter.svg';

      case 'together':
        return 'assets/icons/ai/together-color.svg';

      case 'perplexity':
        return 'assets/icons/ai/perplexity-color.svg';

      case 'ollama':
        return 'assets/icons/ai/ollama.svg';

      case 'deepseek':
        return 'assets/icons/ai/deepseek-color.svg';

      case 'qwen':
      case 'dashscope':
      case 'alibaba':
      case 'alibabacloud':
        return 'assets/icons/ai/qwen-color.svg';

      case 'glm':
      case 'chatglm':
      case 'zhipu':
        return 'assets/icons/ai/zhipu-color.svg';

      case 'grok':
      case 'xai':
        return 'assets/icons/ai/grok.svg';

      case 'baidu':
      case 'wenxin':
      case 'ernie':
        return 'assets/icons/ai/wenxin-color.svg';

      case 'iflytek':
      case 'spark':
        return 'assets/icons/ai/spark-color.svg';

      case 'tencent':
      case 'tencentcloud':
      case 'hunyuan':
        return 'assets/icons/ai/hunyuan-color.svg';

      case 'vertexai':
        return 'assets/icons/ai/vertexai-color.svg';

      case 'bedrock':
      case 'aws':
        return 'assets/icons/ai/bedrock-color.svg';

      case 'meta':
      case 'llama':
        return 'assets/icons/ai/meta-color.svg';

      case 'cohere':
        return 'assets/icons/ai/cohere-color.svg';

      default:
        _ensureManifestLoaded();
        final dyn2 = _dynamicGuessByName(type);
        return dyn2 ?? 'assets/icons/ai/openai.svg';
    }
  }
}
