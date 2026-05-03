import 'package:flutter_test/flutter_test.dart';
import 'package:screen_memo/models/ai_request_log.dart';
import 'package:screen_memo/features/ai/application/ai_request_log_parser.dart';

void main() {
  test('AITrace non-stream REQ+RESP aggregates into 1 trace', () {
    final String req = [
      '[AITrace] REQ t1',
      'POST https://example.com/v1/chat/completions',
      'ctx=chat api=openai.chat.completions stream=0',
      'provider=OpenRouter(12) type=openrouter',
      'model=gpt-4.1 tools=2 images=1',
      'headers={"authorization":"Bearer ***","content-type":"application/json"}',
      'body={"model":"gpt-4.1","messages":[{"role":"user","content":"hi"}]}',
    ].join('\n');

    final String resp = [
      '[AITrace] RESP t1',
      '200 https://example.com/v1/chat/completions',
      'ctx=chat api=openai.chat.completions stream=0 tookMs=321',
      'provider=OpenRouter(12) type=openrouter',
      'model=gpt-4.1 bodyLen=1234 promptTokens=11 completionTokens=22 totalTokens=33',
      'headers={"content-type":"application/json"}',
      'body={"id":"chatcmpl_x","choices":[]}',
    ].join('\n');

    final List<AIRequestTrace> traces = parseAiTraceMessages(<String>[
      req,
      resp,
    ]);
    expect(traces, hasLength(1));

    final AIRequestTrace tr = traces.single;
    expect(tr.source, AIRequestLogSource.aiTrace);
    expect(tr.traceId, 't1');
    expect(tr.streaming, isFalse);
    expect(tr.durationMs, 321);
    expect(tr.logContext, 'chat');
    expect(tr.apiType, 'openai.chat.completions');
    expect(tr.providerName, 'OpenRouter');
    expect(tr.providerId, '12');
    expect(tr.providerType, 'openrouter');
    expect(tr.model, 'gpt-4.1');
    expect(tr.toolsCount, 2);
    expect(tr.imagesCount, 1);

    expect(tr.request?.method, 'POST');
    expect(tr.request?.uri?.host, 'example.com');
    expect(tr.request?.headers?['authorization'], 'Bearer ***');
    expect(tr.request?.body, contains('"messages"'));

    expect(tr.response?.statusCode, 200);
    expect(tr.response?.bodyLen, 1234);
    expect(tr.response?.headers?['content-type'], 'application/json');
    expect(tr.response?.body, contains('"choices"'));
    expect(tr.usagePromptTokens, 11);
    expect(tr.usageCompletionTokens, 22);
    expect(tr.usageTotalTokens, 33);

    expect(tr.rawBlocks.length, 2);
  });

  test('AITrace streaming REQ+RESP+STREAM_DONE aggregates summary fields', () {
    final String req = [
      'REQ t2',
      'POST https://example.com/v1/responses',
      'ctx=rebuild api=openai.responses stream=1',
      'provider=OpenAI(1) type=openai',
      'model=gpt-4.1 tools=0 images=0',
      'headers={"x-test":"1"}',
      'body={"input":"hi"}',
    ].join('\n');

    final String resp = [
      'RESP t2',
      '200 https://example.com/v1/responses',
      'ctx=rebuild api=openai.responses stream=1',
      'provider=OpenAI(1) type=openai',
      'model=gpt-4.1',
      'headers={"content-type":"text/event-stream"}',
    ].join('\n');

    final String done = [
      'STREAM_DONE t2',
      'ctx=rebuild api=openai.responses tookMs=987',
      'provider=OpenAI(1) type=openai',
      'model=gpt-4.1 contentLen=10 reasoningLen=5 toolCalls=1 ttftMs=120 promptTokens=44 completionTokens=55 totalTokens=99',
    ].join('\n');

    final List<AIRequestTrace> traces = parseAiTraceMessages(<String>[
      req,
      resp,
      done,
    ]);
    expect(traces, hasLength(1));

    final AIRequestTrace tr = traces.single;
    expect(tr.streaming, isTrue);
    expect(tr.durationMs, 987);
    expect(tr.streamSummary?.contentLen, 10);
    expect(tr.streamSummary?.reasoningLen, 5);
    expect(tr.streamSummary?.toolCalls, 1);
    expect(tr.ttftMs, 120);
    expect(tr.usagePromptTokens, 44);
    expect(tr.usageCompletionTokens, 55);
    expect(tr.usageTotalTokens, 99);
    expect(tr.response?.statusCode, 200);
  });

  test('AITrace STREAM_ERR marks trace as error and retains error text', () {
    final String req = [
      'REQ t3',
      'POST https://example.com/v1/responses',
      'ctx=rebuild api=openai.responses stream=1',
      'provider=OpenAI(1) type=openai',
      'model=gpt-4.1 tools=0 images=0',
      'headers={"x-test":"1"}',
      'body={"input":"hi"}',
    ].join('\n');

    final String err = [
      'STREAM_ERR t3',
      'ctx=rebuild api=openai.responses tookMs=123',
      'provider=OpenAI(1) type=openai',
      'model=gpt-4.1',
      'error=Exception: boom',
    ].join('\n');

    final List<AIRequestTrace> traces = parseAiTraceMessages(<String>[
      req,
      err,
    ]);
    expect(traces, hasLength(1));

    final AIRequestTrace tr = traces.single;
    expect(tr.isError, isTrue);
    expect(tr.error, contains('boom'));
  });

  test('AITrace provider line parses name/id/type', () {
    final String req = [
      'REQ t4',
      'POST https://example.com/v1/responses',
      'ctx=x api=openai.responses stream=0',
      'provider=OpenRouter(123) type=openrouter',
      'model=gpt-4.1 tools=0 images=0',
      'headers={"x-test":"1"}',
      'body={"input":"hi"}',
    ].join('\n');

    final AIRequestTrace tr = parseAiTraceMessages(<String>[req]).single;
    expect(tr.providerName, 'OpenRouter');
    expect(tr.providerId, '123');
    expect(tr.providerType, 'openrouter');
    expect(tr.usagePromptTokens, isNull);
    expect(tr.usageCompletionTokens, isNull);
    expect(tr.usageTotalTokens, isNull);
    expect(tr.ttftMs, isNull);
  });

  test(
    'AITrace invalid JSON headers do not crash and remain in raw blocks',
    () {
      final String req = [
        'REQ t5',
        'POST https://example.com/v1/responses',
        'ctx=x api=openai.responses stream=0',
        'model=gpt-4.1 tools=0 images=0',
        'headers={"authorization":"Bearer ***"', // truncated JSON
        'body={not json',
      ].join('\n');

      final AIRequestTrace tr = parseAiTraceMessages(<String>[req]).single;
      expect(tr.request?.headers, isNull);
      expect(tr.request?.body, '{not json');
      expect(tr.rawBlocks.single, contains('headers={"authorization"'));
    },
  );

  test('gateway_log text parses REQ/RESP sections and attributes extra= blocks', () {
    final String text = [
      '[12:00:00.000] orphan line before first REQ',
      '[12:00:00.010] REQ POST https://example.com/v1/responses stream=1 google=0 bodyLen=123',
      '[12:00:00.011] REQ headers',
      '[12:00:00.012] extra={"authorization":"Bearer ***","content-type":"application/json"}',
      '[12:00:00.020] REQ body',
      r'[12:00:00.021] extra="{\"model\":\"gpt-4.1\"}"',
      '[12:00:01.000] RESP status=200 contentType=application/json bodyLen=456',
      '[12:00:01.001] extra={"headers":{"content-type":"application/json","x-test":"1"}}',
      '[12:00:01.100] PARSED openai contentLen=10 toolCalls=0 reasoningLen=0 ttftMs=88 promptTokens=8 completionTokens=9 totalTokens=17',
    ].join('\n');

    final GatewayLogParseResult parsed = parseGatewayLogTextDetailed(text);
    expect(parsed.leadingOrphans, hasLength(1));
    expect(parsed.traces, hasLength(1));

    final AIRequestTrace tr = parsed.traces.single;
    expect(tr.source, AIRequestLogSource.gatewayLog);
    expect(tr.streaming, isTrue);
    expect(tr.request?.method, 'POST');
    expect(tr.request?.uri?.host, 'example.com');
    expect(tr.request?.bodyLen, 123);
    expect(tr.request?.headers?['authorization'], 'Bearer ***');
    expect(tr.request?.body, contains('gpt-4.1'));

    expect(tr.response?.statusCode, 200);
    expect(tr.response?.contentType, 'application/json');
    expect(tr.response?.bodyLen, 456);
    expect(tr.response?.headers?['x-test'], '1');

    expect(tr.streamSummary?.contentLen, 10);
    expect(tr.streamSummary?.toolCalls, 0);
    expect(tr.streamSummary?.reasoningLen, 0);
    expect(tr.ttftMs, 88);
    expect(tr.usagePromptTokens, 8);
    expect(tr.usageCompletionTokens, 9);
    expect(tr.usageTotalTokens, 17);
  });

  test('segment trace parses request header/prompt/images and response', () {
    final String rawReq = [
      '=== AI Request ===',
      'provider=google',
      'url=https://example.com/v1beta/models/gemini-1.5-pro:streamGenerateContent?alt=sse',
      'model=gemini-1.5-pro',
      'segment_id=42',
      'images_attached=2',
      '',
      'prompt:',
      'hello',
      'world',
      '',
      'images:',
      '#1 time=2025-01-01T00:00:00Z app=Demo file=a.png path=/tmp/a.png mime=image/png bytes=123',
      '#2 time=2025-01-01T00:00:01Z app=Demo file=b.png path=/tmp/b.png mime=image/png bytes=456',
    ].join('\n');
    const String rawResp = 'data: {"ok":true}';

    final List<AIRequestTrace> traces = parseSegmentTrace(
      rawRequest: rawReq,
      rawResponse: rawResp,
      segmentId: 42,
    );
    expect(traces, hasLength(1));

    final AIRequestTrace tr = traces.single;
    expect(tr.source, AIRequestLogSource.segmentTrace);
    expect(tr.traceId, '42');
    expect(tr.providerName, 'google');
    expect(tr.model, 'gemini-1.5-pro');
    expect(tr.imagesCount, 2);
    expect(tr.request?.method, 'POST');
    expect(tr.request?.uri?.host, 'example.com');
    expect(tr.request?.body, contains('hello'));
    expect(tr.request?.body, contains('images:'));
    expect(tr.response?.body, contains('data:'));
  });

  test('segment trace exception response sets error and keeps error body', () {
    final String rawReq = [
      '=== AI Request (exception) ===',
      'base_url=https://example.com',
      'model=gemini-1.5-pro',
      'segment_id=9',
      'note=prompt not captured',
    ].join('\n');
    final String rawResp = [
      '=== AI Response (exception) ===',
      'message=Exception: boom',
      '',
      'stacktrace line 1',
    ].join('\n');

    final List<AIRequestTrace> traces = parseSegmentTrace(
      rawRequest: rawReq,
      rawResponse: rawResp,
    );
    expect(traces, hasLength(1));

    final AIRequestTrace tr = traces.single;
    expect(tr.isError, isTrue);
    expect(tr.error, contains('boom'));
    expect(tr.response?.errorBody, contains('stacktrace'));
    expect(tr.request?.uri?.host, 'example.com');
  });
}
