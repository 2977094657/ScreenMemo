import 'package:flutter_test/flutter_test.dart';
import 'package:screen_memo/models/ai_request_log.dart';
import 'package:screen_memo/features/ai/application/native_ai_request_log_parser.dart';

void main() {
  test('parses structured native request logs into traces', () {
    final String text = '''
2026-03-12 10:00:00.000 [INFO] SegmentSummaryManager: AIREQ PROMPT_BEGIN id=seg101
2026-03-12 10:00:00.001 [INFO] SegmentSummaryManager: AI 提示词完整内容开始 >>>
2026-03-12 10:00:00.002 [INFO] SegmentSummaryManager: summarize window 101
2026-03-12 10:00:00.003 [INFO] SegmentSummaryManager: AI 提示词完整内容结束 <<<
2026-03-12 10:00:00.004 [INFO] SegmentSummaryManager: AIREQ PROMPT_END id=seg101
2026-03-12 10:00:00.005 [INFO] SegmentSummaryManager: AIREQ START id=seg101 provider=google segment_id=101 is_merge=false url=https://api.example.com/v1beta/models/gemini:streamGenerateContent?alt=sse model=gemini-2.0 images_attached=3 images_total=3 prompt_len=120
2026-03-12 10:00:01.000 [INFO] SegmentSummaryManager: AIREQ RESP id=seg101 code=200 took_ms=995 attempt=1/3
2026-03-12 10:00:01.001 [INFO] SegmentSummaryManager: AIREQ RESP_BODY_BEGIN id=seg101
2026-03-12 10:00:01.002 [INFO] SegmentSummaryManager: AI 响应完整内容开始 >>>
2026-03-12 10:00:01.003 [INFO] SegmentSummaryManager: data: {"text":"done"}
2026-03-12 10:00:01.004 [INFO] SegmentSummaryManager: AI 响应完整内容结束 <<<
2026-03-12 10:00:01.005 [INFO] SegmentSummaryManager: AIREQ RESP_BODY_END id=seg101
2026-03-12 10:00:01.006 [INFO] SegmentSummaryManager: AIREQ DONE id=seg101 content_len=20 response_len=18
''';

    final List<AIRequestTrace> traces = parseNativeAiRequestLogText(text);

    expect(traces, hasLength(1));
    final AIRequestTrace trace = traces.single;
    expect(trace.source, AIRequestLogSource.nativeLog);
    expect(trace.logContext, 'segment=101');
    expect(trace.providerName, 'google');
    expect(trace.model, 'gemini-2.0');
    expect(trace.imagesCount, 3);
    expect(trace.request?.uri?.toString(), contains('api.example.com'));
    expect(trace.request?.body, contains('summarize window 101'));
    expect(trace.response?.statusCode, 200);
    expect(trace.response?.body, contains('done'));
  });

  test(
    'parses legacy native request failures and deduplicates duplicate lines',
    () {
      final String text = '''
2026-03-12 11:00:00.000 [INFO] SegmentSummaryManager: AI 准备：提供方=openai-compat, 模型=gpt-4.1, baseUrl=https://relay.example.com, 段ID=202, 合并=false, 文本长度=10, 文本长度(含规则)=12, 图片数=2, 字节数=20, 缺失图片=0, 前几个文件=a.png
2026-03-12 11:00:00.400 [INFO] SegmentSummaryManager: AI 准备：提供方=openai-compat, 模型=gpt-4.1, baseUrl=https://relay.example.com, 段ID=202, 合并=false, 文本长度=10, 文本长度(含规则)=12, 图片数=2, 字节数=20, 缺失图片=0, 前几个文件=a.png
2026-03-12 11:00:00.800 [INFO] SegmentSummaryManager: AI 请求(OpenAI兼容)：地址=https://relay.example.com/v1/chat/completions 模型=gpt-4.1 图片数=2
2026-03-12 11:00:01.200 [INFO] SegmentSummaryManager: AI 响应元信息(OpenAI兼容)：code=500 耗时毫秒=350 尝试=1/3
2026-03-12 11:00:01.300 [ERROR] SegmentSummaryManager: AI 请求失败(OpenAI兼容)：code=500 尝试=1/3 body=bad gateway
''';

      final List<AIRequestTrace> traces = parseNativeAiRequestLogText(text);

      expect(traces, hasLength(1));
      final AIRequestTrace trace = traces.single;
      expect(trace.logContext, 'segment=202');
      expect(trace.providerName, 'openai-compat');
      expect(trace.response?.statusCode, 500);
      expect(trace.error, contains('AI 请求失败'));
      expect(
        trace.rawBlocks.where((String line) => line.contains('AI 准备：')).length,
        1,
      );
    },
  );
}
