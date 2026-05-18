import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:screen_memo/data/database/screenshot_database.dart';
import 'package:screen_memo/features/ai/application/ai_chat_service.dart';
import 'package:screen_memo/features/ai/application/ai_image_generation_service.dart';
import 'package:screen_memo/features/ai/application/ai_providers_service.dart';
import 'package:screen_memo/features/ai/application/ai_settings_service.dart';
import 'package:screen_memo/features/ai_chat/presentation/widgets/markdown_math.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const String _onePixelPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    try {
      await ScreenshotDatabase.instance.disposeDesktop();
    } catch (_) {}
  });

  test('generate_image tool schema exists with expected parameters', () {
    final List<Map<String, dynamic>> tools = AIChatService.defaultChatTools();
    final Map<String, dynamic> tool = tools.firstWhere((
      Map<String, dynamic> item,
    ) {
      final Map<String, dynamic> fn = Map<String, dynamic>.from(
        item['function'] as Map,
      );
      return fn['name'] == 'generate_image';
    });

    final Map<String, dynamic> fn = Map<String, dynamic>.from(
      tool['function'] as Map,
    );
    final Map<String, dynamic> params = Map<String, dynamic>.from(
      fn['parameters'] as Map,
    );
    final Map<String, dynamic> properties = Map<String, dynamic>.from(
      params['properties'] as Map,
    );

    expect(params['required'], contains('prompt'));
    expect(
      properties.keys,
      containsAll(<String>[
        'prompt',
        'count',
        'aspect_ratio',
        'quality',
        'output_format',
      ]),
    );
    expect(properties['aspect_ratio']['enum'], <String>[
      'square',
      'portrait',
      'landscape',
    ]);
    expect(properties['output_format']['enum'], <String>[
      'png',
      'jpeg',
      'webp',
    ]);
  });

  test('image generation parameters normalize and clamp locally', () {
    final AIImageGenerationParams params =
        AIImageGenerationParams.fromJson(<String, dynamic>{
          'prompt': '  draw a clean icon  ',
          'count': 99,
          'aspect_ratio': 'wide',
          'quality': 'HIGH',
          'output_format': 'jpg',
          'reference_image_paths': List<String>.generate(
            20,
            (int index) => ' ref_$index.png ',
          ),
        });

    expect(params.prompt, 'draw a clean icon');
    expect(params.count, 10);
    expect(params.aspectRatio, 'landscape');
    expect(params.size, '1536x1024');
    expect(params.quality, 'high');
    expect(params.outputFormat, 'jpeg');
    expect(params.referenceImagePaths.length, 16);
    expect(params.referenceImagePaths.first, 'ref_0.png');
    expect(params.hasReferenceImages, isTrue);

    expect(AIImageGenerationParams.normalizeCount(-2), 1);
    expect(AIImageGenerationParams.sizeForAspectRatio('portrait'), '1024x1536');
    expect(AIImageGenerationParams.sizeForAspectRatio('square'), '1024x1024');
  });

  test('image endpoint URI does not duplicate v1 path', () {
    expect(
      AIImageGenerationService.buildImagesGenerationsUri(
        'https://api.openai.com',
      ).toString(),
      'https://api.openai.com/v1/images/generations',
    );
    expect(
      AIImageGenerationService.buildImagesGenerationsUri(
        'https://api.openai.com/v1',
      ).toString(),
      'https://api.openai.com/v1/images/generations',
    );
    expect(
      AIImageGenerationService.buildImagesGenerationsUri(
        'https://example.com/openai/v1/',
      ).toString(),
      'https://example.com/openai/v1/images/generations',
    );
  });

  test('image edit endpoint URI does not duplicate v1 path', () {
    expect(
      AIImageGenerationService.buildImagesEditsUri(
        'https://api.openai.com',
      ).toString(),
      'https://api.openai.com/v1/images/edits',
    );
    expect(
      AIImageGenerationService.buildImagesEditsUri(
        'https://api.openai.com/v1',
      ).toString(),
      'https://api.openai.com/v1/images/edits',
    );
    expect(
      AIImageGenerationService.buildImagesEditsUri(
        'https://example.com/openai/v1/',
      ).toString(),
      'https://example.com/openai/v1/images/edits',
    );
  });

  test('reference image edit request uses multipart edits endpoint', () async {
    final Directory tmp = await Directory.systemTemp.createTemp(
      'screen_memo_generated_images_edit_',
    );
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    var editCalls = 0;
    var generationCalls = 0;
    Future<void>? serverDone;
    try {
      final Directory root = Directory(p.join(tmp.path, 'root'));
      await root.create(recursive: true);
      await ScreenshotDatabase.instance.initializeForDesktop(root.path);

      final File reference = File(p.join(tmp.path, 'reference.png'));
      await reference.writeAsBytes(
        img.encodePng(img.Image(width: 1, height: 1)),
      );

      serverDone = () async {
        await for (final HttpRequest req in server) {
          final String path = req.uri.path;
          final ContentType? contentType = req.headers.contentType;
          if (req.method == 'POST' && path == '/v1/images/edits') {
            editCalls += 1;
            expect(contentType?.mimeType, startsWith('multipart/form-data'));
            final String boundary = contentType?.parameters['boundary'] ?? '';
            expect(boundary, isNotEmpty);
            final String body = await latin1.decoder.bind(req).join();
            expect(body, contains('name="model"'));
            expect(body, contains('gpt-image-test'));
            expect(body, contains('name="prompt"'));
            expect(body, contains('edit with reference'));
            expect(body, contains('name="image"'));
            expect(body, contains('filename="reference.png"'));
            expect(body.toLowerCase(), contains('content-type: image/png'));
            req.response.statusCode = HttpStatus.ok;
            req.response.headers.contentType = ContentType.json;
            req.response.write(
              jsonEncode(<String, dynamic>{
                'data': <Map<String, dynamic>>[
                  <String, dynamic>{'b64_json': _onePixelPngBase64},
                ],
              }),
            );
            await req.response.close();
            continue;
          }

          if (req.method == 'POST' && path == '/v1/images/generations') {
            generationCalls += 1;
            await utf8.decoder.bind(req).join();
            req.response.statusCode = HttpStatus.internalServerError;
            await req.response.close();
            continue;
          }

          await utf8.decoder.bind(req).join();
          req.response.statusCode = HttpStatus.notFound;
          await req.response.close();
        }
      }();

      final String baseUrl = 'http://127.0.0.1:${server.port}';
      final int? providerId = await AIProvidersService.instance.createProvider(
        name: 'Edit image provider',
        type: AIProviderTypes.openai,
        baseUrl: baseUrl,
        models: const <String>['gpt-image-test'],
        apiKey: 'sk-test',
        isDefault: true,
      );
      expect(providerId, isNotNull);
      await ScreenshotDatabase.instance.setAIContext(
        context: kAiImageGenerationContext,
        providerId: providerId!,
        model: 'gpt-image-test',
      );

      final AIImageGenerationResult result = await HttpOverrides.runZoned(
        () {
          return AIImageGenerationService.instance.generate(
            params: AIImageGenerationParams(
              prompt: 'edit with reference',
              referenceImagePaths: <String>[reference.path],
            ),
            conversationId: 'cid-edit-test',
            assistantCreatedAtMs: 123,
            toolCallId: 'call_edit',
          );
        },
        createHttpClient: (SecurityContext? context) {
          return _RealHttpOverrides().createHttpClient(context);
        },
      );

      expect(result.ok, isTrue, reason: result.error);
      expect(editCalls, 1);
      expect(generationCalls, 0);
      expect(result.images.single['marker'], contains('[generated-image:'));
      expect(result.images.single['reference_image_count'], 1);
      final List<Map<String, dynamic>> rows = await ScreenshotDatabase.instance
          .listAiGeneratedImagesByToolCallId('call_edit');
      expect(rows, hasLength(1));
      expect(rows.single['file_path'], result.images.single['file_path']);
    } finally {
      await server.close(force: true);
      if (serverDone != null) {
        await serverDone.timeout(const Duration(seconds: 1), onTimeout: () {});
      }
      try {
        await ScreenshotDatabase.instance.disposeDesktop();
      } catch (_) {}
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    }
  });

  test(
    'image generation context must be explicitly configured without fallback',
    () async {
      final Directory tmp = await Directory.systemTemp.createTemp(
        'screen_memo_generated_images_context_',
      );
      try {
        final Directory root = Directory(p.join(tmp.path, 'root'));
        await root.create(recursive: true);
        await ScreenshotDatabase.instance.initializeForDesktop(root.path);

        final int? providerId = await AIProvidersService.instance
            .createProvider(
              name: 'Default chat provider',
              type: AIProviderTypes.openai,
              baseUrl: 'https://example.com',
              models: const <String>['gpt-chat'],
              apiKey: 'sk-test',
              isDefault: true,
            );
        expect(providerId, isNotNull);

        final AISettingsService settings = AISettingsService.instance;
        final List<AIEndpoint> unconfigured = await settings
            .getEndpointCandidates(context: kAiImageGenerationContext);
        expect(unconfigured, isEmpty);

        await ScreenshotDatabase.instance.setAIContext(
          context: kAiImageGenerationContext,
          providerId: 999999,
          model: 'gpt-image-test',
        );
        final List<AIEndpoint> missingProvider = await settings
            .getEndpointCandidates(context: kAiImageGenerationContext);
        expect(missingProvider, isEmpty);

        await ScreenshotDatabase.instance.setAIContext(
          context: kAiImageGenerationContext,
          providerId: providerId!,
          model: '',
        );
        final List<AIEndpoint> missingModel = await settings
            .getEndpointCandidates(context: kAiImageGenerationContext);
        expect(missingModel, isEmpty);

        await ScreenshotDatabase.instance.setAIContext(
          context: kAiImageGenerationContext,
          providerId: providerId,
          model: 'gpt-image-test',
        );
        final List<AIEndpoint> configured = await settings
            .getEndpointCandidates(context: kAiImageGenerationContext);
        expect(configured, hasLength(1));
        expect(configured.single.model, 'gpt-image-test');
        expect(configured.single.providerId, providerId);
      } finally {
        try {
          await ScreenshotDatabase.instance.disposeDesktop();
        } catch (_) {}
        if (await tmp.exists()) {
          await tmp.delete(recursive: true);
        }
      }
    },
  );

  test(
    'generated image DB lookup excludes soft-deleted images by default',
    () async {
      final Directory tmp = await Directory.systemTemp.createTemp(
        'screen_memo_generated_images_db_',
      );
      try {
        final Directory root = Directory(p.join(tmp.path, 'root'));
        await root.create(recursive: true);
        await ScreenshotDatabase.instance.initializeForDesktop(root.path);

        final File image = File(
          p.join(
            root.path,
            'output',
            'ai',
            'generated_images',
            '2026-05',
            'sample.png',
          ),
        );
        await image.parent.create(recursive: true);
        await image.writeAsBytes(base64Decode(_onePixelPngBase64));

        final int id = await ScreenshotDatabase.instance.insertAiGeneratedImage(
          conversationId: 'cid',
          assistantCreatedAt: 1,
          toolCallId: 'call_1',
          prompt: 'sample',
          model: 'gpt-image-test',
          providerId: 7,
          filePath: image.path,
          mimeType: 'image/png',
          size: '1024x1024',
          quality: 'medium',
          outputFormat: 'png',
        );

        expect(id, greaterThan(0));
        final Map<String, String> found = await ScreenshotDatabase.instance
            .findAiGeneratedImagePathsByFilenames(<String>{'sample.png'});
        expect(found['sample.png'], image.path);
        final List<Map<String, dynamic>> byCall = await ScreenshotDatabase
            .instance
            .listAiGeneratedImagesByToolCallId('call_1');
        expect(byCall, hasLength(1));
        expect(byCall.single['file_path'], image.path);

        await ScreenshotDatabase.instance.softDeleteAiGeneratedImage(id);
        final Map<String, String> hidden = await ScreenshotDatabase.instance
            .findAiGeneratedImagePathsByFilenames(<String>{'sample.png'});
        expect(hidden, isEmpty);

        final Map<String, String> includeDeleted = await ScreenshotDatabase
            .instance
            .findAiGeneratedImagePathsByFilenames(<String>{
              'sample.png',
            }, includeDeleted: true);
        expect(includeDeleted['sample.png'], image.path);
      } finally {
        try {
          await ScreenshotDatabase.instance.disposeDesktop();
        } catch (_) {}
        if (await tmp.exists()) {
          await tmp.delete(recursive: true);
        }
      }
    },
  );

  test(
    'chat follow-up attaches previous generated images for context',
    () async {
      final Directory tmp = await Directory.systemTemp.createTemp(
        'screen_memo_generated_image_context_',
      );
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      Map<String, dynamic>? chatRequest;
      Future<void>? serverDone;
      try {
        final Directory root = Directory(p.join(tmp.path, 'root'));
        await root.create(recursive: true);
        await ScreenshotDatabase.instance.initializeForDesktop(root.path);

        final File image = File(
          p.join(
            root.path,
            'output',
            'ai',
            'generated_images',
            '2026-05',
            'followup.png',
          ),
        );
        await image.parent.create(recursive: true);
        await image.writeAsBytes(base64Decode(_onePixelPngBase64));

        await ScreenshotDatabase.instance.insertAiGeneratedImage(
          conversationId: 'cid-generated-context',
          assistantCreatedAt: 2,
          toolCallId: 'manual_call',
          prompt: 'draw a sample',
          model: 'gpt-image-test',
          providerId: 7,
          filePath: image.path,
          mimeType: 'image/png',
          size: '1024x1024',
          quality: 'medium',
          outputFormat: 'png',
        );
        await AISettingsService.instance
            .saveChatHistoryByCid('cid-generated-context', <AIMessage>[
              AIMessage(role: 'user', content: 'draw a sample'),
              AIMessage(
                role: 'assistant',
                content: '[generated-image: followup.png]',
              ),
            ]);

        serverDone = () async {
          await for (final HttpRequest req in server) {
            final String path = req.uri.path;
            final String body = await utf8.decoder.bind(req).join();
            if (req.method == 'POST' && path == '/v1/chat/completions') {
              chatRequest = jsonDecode(body) as Map<String, dynamic>;
              req.response.statusCode = HttpStatus.ok;
              req.response.headers.contentType = ContentType.json;
              req.response.write(
                jsonEncode(<String, dynamic>{
                  'choices': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'message': <String, dynamic>{
                        'role': 'assistant',
                        'content': 'I can see the previous generated image.',
                      },
                    },
                  ],
                  'model': 'chat-test',
                }),
              );
              await req.response.close();
              continue;
            }

            req.response.statusCode = HttpStatus.notFound;
            await req.response.close();
          }
        }();

        final String baseUrl = 'http://127.0.0.1:${server.port}';
        final int? providerId = await AIProvidersService.instance
            .createProvider(
              name: 'Generated context provider',
              type: AIProviderTypes.openai,
              baseUrl: baseUrl,
              models: const <String>['chat-test'],
              apiKey: 'sk-test',
              isDefault: true,
            );
        expect(providerId, isNotNull);
        await ScreenshotDatabase.instance.setAIContext(
          context: 'chat',
          providerId: providerId!,
          model: 'chat-test',
        );

        await HttpOverrides.runZoned(
          () async {
            await AIChatService.instance.sendMessageWithDisplayOverride(
              'what is in the image?',
              'what is in the image?',
              includeHistory: true,
              persistHistory: true,
              persistHistoryTail: true,
              conversationCid: 'cid-generated-context',
            );
          },
          createHttpClient: (SecurityContext? context) {
            return _RealHttpOverrides().createHttpClient(context);
          },
        );

        expect(chatRequest, isNotNull);
        final List<dynamic> messages =
            chatRequest!['messages'] as List<dynamic>;
        final Map<String, dynamic> userMessage = Map<String, dynamic>.from(
          messages.last as Map,
        );
        final List<dynamic> content = userMessage['content'] as List<dynamic>;
        expect(
          content.where(
            (dynamic item) =>
                item is Map &&
                item['type'] == 'text' &&
                (item['text'] as String).contains(
                  'Previous generated images from this conversation',
                ),
          ),
          isNotEmpty,
        );
        expect(
          content.where(
            (dynamic item) =>
                item is Map &&
                item['type'] == 'image_url' &&
                ((item['image_url'] as Map)['url'] as String).startsWith(
                  'data:image/png;base64,',
                ),
          ),
          hasLength(1),
        );
      } finally {
        await server.close(force: true);
        if (serverDone != null) {
          await serverDone.timeout(
            const Duration(seconds: 1),
            onTimeout: () {},
          );
        }
        try {
          await ScreenshotDatabase.instance.disposeDesktop();
        } catch (_) {}
        if (await tmp.exists()) {
          await tmp.delete(recursive: true);
        }
      }
    },
  );

  test(
    'successful generate_image ends the tool loop without model follow-up',
    () async {
      final Directory tmp = await Directory.systemTemp.createTemp(
        'screen_memo_generated_images_loop_',
      );
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      var chatCalls = 0;
      var imageCalls = 0;
      Future<void>? serverDone;
      try {
        final Directory root = Directory(p.join(tmp.path, 'root'));
        await root.create(recursive: true);
        await ScreenshotDatabase.instance.initializeForDesktop(root.path);

        serverDone = () async {
          await for (final HttpRequest req in server) {
            final String path = req.uri.path;
            final String body = await utf8.decoder.bind(req).join();
            if (req.method == 'POST' && path == '/v1/chat/completions') {
              chatCalls += 1;
              if (chatCalls > 1) {
                req.response.statusCode = HttpStatus.internalServerError;
                req.response.write('unexpected follow-up call');
                await req.response.close();
                continue;
              }
              expect(body, contains('"tools"'));
              req.response.statusCode = HttpStatus.ok;
              req.response.headers.set(
                HttpHeaders.contentTypeHeader,
                'text/event-stream; charset=utf-8',
              );
              req.response.write(
                'data: ${jsonEncode(<String, dynamic>{
                  'choices': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'delta': <String, dynamic>{
                        'tool_calls': <Map<String, dynamic>>[
                          <String, dynamic>{
                            'index': 0,
                            'id': 'call_image_1',
                            'type': 'function',
                            'function': <String, dynamic>{
                              'name': 'generate_image',
                              'arguments': jsonEncode(<String, dynamic>{'prompt': 'one small pixel', 'count': 1}),
                            },
                          },
                        ],
                      },
                      'finish_reason': 'tool_calls',
                    },
                  ],
                })}\n\n',
              );
              req.response.write('data: [DONE]\n\n');
              await req.response.close();
              continue;
            }

            if (req.method == 'POST' && path == '/v1/images/generations') {
              imageCalls += 1;
              final Map<String, dynamic> imageRequest =
                  jsonDecode(body) as Map<String, dynamic>;
              expect(imageRequest['model'], 'gpt-image-test');
              expect(imageRequest['n'], 1);
              req.response.statusCode = HttpStatus.ok;
              req.response.headers.contentType = ContentType.json;
              req.response.write(
                jsonEncode(<String, dynamic>{
                  'data': <Map<String, dynamic>>[
                    <String, dynamic>{'b64_json': _onePixelPngBase64},
                  ],
                }),
              );
              await req.response.close();
              continue;
            }

            req.response.statusCode = HttpStatus.notFound;
            await req.response.close();
          }
        }();

        final String baseUrl = 'http://127.0.0.1:${server.port}';
        final int? providerId = await AIProvidersService.instance
            .createProvider(
              name: 'Loop test provider',
              type: AIProviderTypes.openai,
              baseUrl: baseUrl,
              models: const <String>['chat-test', 'gpt-image-test'],
              apiKey: 'sk-test',
              isDefault: true,
            );
        expect(providerId, isNotNull);
        await ScreenshotDatabase.instance.setAIContext(
          context: 'chat',
          providerId: providerId!,
          model: 'chat-test',
        );
        await ScreenshotDatabase.instance.setAIContext(
          context: kAiImageGenerationContext,
          providerId: providerId,
          model: 'gpt-image-test',
        );

        final ({AIMessage completed, List<AIStreamEvent> events}) outcome =
            await HttpOverrides.runZoned(
              () async {
                final AIStreamingSession session = await AIChatService.instance
                    .sendMessageStreamedV2WithDisplayOverride(
                      'draw one image',
                      'draw one image',
                      includeHistory: true,
                      persistHistory: true,
                      persistHistoryTail: true,
                      tools: AIChatService.defaultChatTools(),
                      toolChoice: 'auto',
                      conversationCid: 'cid-loop-test',
                      uiUserCreatedAtMs: DateTime.now().millisecondsSinceEpoch,
                      uiAssistantCreatedAtMs:
                          DateTime.now().millisecondsSinceEpoch + 1,
                    );
                final List<AIStreamEvent> events = await session.stream
                    .toList();
                final AIMessage completed = await session.completed;
                return (completed: completed, events: events);
              },
              createHttpClient: (SecurityContext? context) {
                return _RealHttpOverrides().createHttpClient(context);
              },
            );
        final AIMessage completed = outcome.completed;
        final List<AIStreamEvent> events = outcome.events;

        expect(chatCalls, 1);
        expect(imageCalls, 1);
        expect(completed.content, contains('[generated-image:'));
        final List<Map<String, dynamic>> uiPayloads = events
            .where((AIStreamEvent event) => event.kind == 'ui')
            .map(
              (AIStreamEvent event) =>
                  jsonDecode(event.data) as Map<String, dynamic>,
            )
            .toList(growable: false);
        final Map<String, dynamic> beginPayload = uiPayloads.firstWhere(
          (Map<String, dynamic> payload) =>
              payload['type'] == 'tool_batch_begin',
        );
        final List<dynamic> tools = beginPayload['tools'] as List<dynamic>;
        expect(
          (tools.single
              as Map<String, dynamic>)['generated_image_loading_count'],
          1,
        );
        final Map<String, dynamic> endPayload = uiPayloads.firstWhere(
          (Map<String, dynamic> payload) => payload['type'] == 'tool_call_end',
        );
        expect(endPayload['generated_image_markers'], isNotEmpty);
        expect(
          events.where(
            (AIStreamEvent event) =>
                event.kind == 'content' &&
                event.data.contains('[generated-image:'),
          ),
          isNotEmpty,
        );

        final Map<String, String> paths = await ScreenshotDatabase.instance
            .findAiGeneratedImagePathsByFilenames(
              RegExp(r'\[generated-image:\s*([^\]\s]+)\]')
                  .allMatches(completed.content)
                  .map((RegExpMatch m) => m.group(1)!)
                  .toSet(),
            );
        expect(paths, hasLength(1));
        expect(await File(paths.values.single).exists(), isTrue);
      } finally {
        await server.close(force: true);
        if (serverDone != null) {
          await serverDone.timeout(
            const Duration(seconds: 1),
            onTimeout: () {},
          );
        }
        try {
          await ScreenshotDatabase.instance.disposeDesktop();
        } catch (_) {}
        if (await tmp.exists()) {
          await tmp.delete(recursive: true);
        }
      }
    },
  );

  test('partial image generation success still ends the tool loop', () async {
    final Directory tmp = await Directory.systemTemp.createTemp(
      'screen_memo_generated_images_partial_',
    );
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    var chatCalls = 0;
    var imageCalls = 0;
    Future<void>? serverDone;
    try {
      final Directory root = Directory(p.join(tmp.path, 'root'));
      await root.create(recursive: true);
      await ScreenshotDatabase.instance.initializeForDesktop(root.path);

      serverDone = () async {
        await for (final HttpRequest req in server) {
          final String path = req.uri.path;
          final String body = await utf8.decoder.bind(req).join();
          if (req.method == 'POST' && path == '/v1/chat/completions') {
            chatCalls += 1;
            if (chatCalls > 1) {
              req.response.statusCode = HttpStatus.internalServerError;
              req.response.write('unexpected follow-up call');
              await req.response.close();
              continue;
            }
            req.response.statusCode = HttpStatus.ok;
            req.response.headers.set(
              HttpHeaders.contentTypeHeader,
              'text/event-stream; charset=utf-8',
            );
            req.response.write(
              'data: ${jsonEncode(<String, dynamic>{
                'choices': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'delta': <String, dynamic>{
                      'tool_calls': <Map<String, dynamic>>[
                        <String, dynamic>{
                          'index': 0,
                          'id': 'call_image_partial',
                          'type': 'function',
                          'function': <String, dynamic>{
                            'name': 'generate_image',
                            'arguments': jsonEncode(<String, dynamic>{'prompt': 'two small pixels', 'count': 2}),
                          },
                        },
                      ],
                    },
                    'finish_reason': 'tool_calls',
                  },
                ],
              })}\n\n',
            );
            req.response.write('data: [DONE]\n\n');
            await req.response.close();
            continue;
          }

          if (req.method == 'POST' && path == '/v1/images/generations') {
            imageCalls += 1;
            final Map<String, dynamic> imageRequest =
                jsonDecode(body) as Map<String, dynamic>;
            expect(imageRequest['n'], 2);
            req.response.statusCode = HttpStatus.ok;
            req.response.headers.contentType = ContentType.json;
            req.response.write(
              jsonEncode(<String, dynamic>{
                'data': <Map<String, dynamic>>[
                  <String, dynamic>{'b64_json': _onePixelPngBase64},
                  <String, dynamic>{'b64_json': ''},
                ],
              }),
            );
            await req.response.close();
            continue;
          }

          req.response.statusCode = HttpStatus.notFound;
          await req.response.close();
        }
      }();

      final String baseUrl = 'http://127.0.0.1:${server.port}';
      final int? providerId = await AIProvidersService.instance.createProvider(
        name: 'Partial image provider',
        type: AIProviderTypes.openai,
        baseUrl: baseUrl,
        models: const <String>['chat-test', 'gpt-image-test'],
        apiKey: 'sk-test',
        isDefault: true,
      );
      expect(providerId, isNotNull);
      await ScreenshotDatabase.instance.setAIContext(
        context: 'chat',
        providerId: providerId!,
        model: 'chat-test',
      );
      await ScreenshotDatabase.instance.setAIContext(
        context: kAiImageGenerationContext,
        providerId: providerId,
        model: 'gpt-image-test',
      );

      final AIMessage completed = await HttpOverrides.runZoned(
        () async {
          final AIStreamingSession session = await AIChatService.instance
              .sendMessageStreamedV2WithDisplayOverride(
                'draw two images',
                'draw two images',
                includeHistory: true,
                persistHistory: true,
                persistHistoryTail: true,
                tools: AIChatService.defaultChatTools(),
                toolChoice: 'auto',
                conversationCid: 'cid-partial-test',
                uiUserCreatedAtMs: DateTime.now().millisecondsSinceEpoch,
                uiAssistantCreatedAtMs:
                    DateTime.now().millisecondsSinceEpoch + 1,
              );
          await session.stream.drain<void>();
          return session.completed;
        },
        createHttpClient: (SecurityContext? context) {
          return _RealHttpOverrides().createHttpClient(context);
        },
      );

      expect(chatCalls, 1);
      expect(imageCalls, 1);
      expect(completed.content, contains('[generated-image:'));
      final List<Map<String, dynamic>> rows = await ScreenshotDatabase.instance
          .listAiGeneratedImagesByToolCallId('call_image_partial');
      expect(rows, hasLength(1));
    } finally {
      await server.close(force: true);
      if (serverDone != null) {
        await serverDone.timeout(const Duration(seconds: 1), onTimeout: () {});
      }
      try {
        await ScreenshotDatabase.instance.disposeDesktop();
      } catch (_) {}
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    }
  });

  test(
    'generate_image does not retry another image endpoint on failure',
    () async {
      final Directory tmp = await Directory.systemTemp.createTemp(
        'screen_memo_generated_images_no_retry_',
      );
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      var imageCalls = 0;
      Future<void>? serverDone;
      try {
        final Directory root = Directory(p.join(tmp.path, 'root'));
        await root.create(recursive: true);
        await ScreenshotDatabase.instance.initializeForDesktop(root.path);

        serverDone = () async {
          await for (final HttpRequest req in server) {
            final String path = req.uri.path;
            await utf8.decoder.bind(req).join();
            if (req.method == 'POST' && path == '/v1/images/generations') {
              imageCalls += 1;
              req.response.statusCode = HttpStatus.internalServerError;
              req.response.headers.contentType = ContentType.json;
              req.response.write(
                jsonEncode(<String, dynamic>{'error': 'first endpoint failed'}),
              );
              await req.response.close();
              continue;
            }

            req.response.statusCode = HttpStatus.notFound;
            await req.response.close();
          }
        }();

        final String baseUrl = 'http://127.0.0.1:${server.port}';
        final int? providerId = await AIProvidersService.instance
            .createProvider(
              name: 'No retry image provider',
              type: AIProviderTypes.openai,
              baseUrl: baseUrl,
              models: const <String>['gpt-image-test'],
              apiKey: '',
              isDefault: true,
            );
        expect(providerId, isNotNull);
        await AIProvidersService.instance.createProviderKey(
          providerId: providerId!,
          name: 'first',
          apiKey: 'sk-first',
          models: const <String>['gpt-image-test'],
          priority: 1,
          orderIndex: 0,
        );
        await AIProvidersService.instance.createProviderKey(
          providerId: providerId,
          name: 'second',
          apiKey: 'sk-second',
          models: const <String>['gpt-image-test'],
          priority: 2,
          orderIndex: 1,
        );
        await ScreenshotDatabase.instance.setAIContext(
          context: kAiImageGenerationContext,
          providerId: providerId,
          model: 'gpt-image-test',
        );

        final AIImageGenerationResult result = await HttpOverrides.runZoned(
          () {
            return AIImageGenerationService.instance.generate(
              params: const AIImageGenerationParams(prompt: 'one failed image'),
              conversationId: 'cid-no-retry-test',
              assistantCreatedAtMs: 1,
              toolCallId: 'call_no_retry',
            );
          },
          createHttpClient: (SecurityContext? context) {
            return _RealHttpOverrides().createHttpClient(context);
          },
        );

        expect(result.ok, isFalse);
        expect(result.error, contains('Image generation request failed'));
        expect(imageCalls, 1);
        final List<Map<String, dynamic>> rows = await ScreenshotDatabase
            .instance
            .listAiGeneratedImagesByToolCallId('call_no_retry');
        expect(rows, isEmpty);
      } finally {
        await server.close(force: true);
        if (serverDone != null) {
          await serverDone.timeout(
            const Duration(seconds: 1),
            onTimeout: () {},
          );
        }
        try {
          await ScreenshotDatabase.instance.disposeDesktop();
        } catch (_) {}
        if (await tmp.exists()) {
          await tmp.delete(recursive: true);
        }
      }
    },
  );

  test('generated image marker detection covers streaming placeholders', () {
    expect(
      containsGeneratedImageMarker(
        'Generating now [generated-image-loading: call_1_1]',
      ),
      isTrue,
    );
    expect(
      containsGeneratedImageMarker('Done [generated-image: sample.webp]'),
      isTrue,
    );
    expect(containsGeneratedImageMarker('No generated image here'), isFalse);
  });

  testWidgets('generated-image marker renders unavailable placeholder safely', (
    WidgetTester tester,
  ) async {
    final MarkdownMathConfig config = MarkdownMathConfig();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownBody(
            data: preprocessForChatMarkdown(
              'Here is the result:\n\n[generated-image: missing.png]',
            ),
            builders: config.builders,
            blockSyntaxes: config.blockSyntaxes,
            inlineSyntaxes: config.inlineSyntaxes,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));

    expect(find.text('Image unavailable'), findsOneWidget);
  });

  testWidgets('generated-image-loading marker renders skeleton safely', (
    WidgetTester tester,
  ) async {
    final MarkdownMathConfig config = MarkdownMathConfig();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownBody(
            data: preprocessForChatMarkdown(
              'Generating now [generated-image-loading: call_1_1]',
            ),
            builders: config.builders,
            blockSyntaxes: config.blockSyntaxes,
            inlineSyntaxes: config.inlineSyntaxes,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.textContaining('[generated-image-loading:', findRichText: true),
      findsNothing,
    );
    expect(find.byType(Shimmer), findsOneWidget);
  });

  testWidgets('generated-image-loading skeleton fills available row width', (
    WidgetTester tester,
  ) async {
    final MarkdownMathConfig config = MarkdownMathConfig();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: MarkdownBody(
              data: preprocessForChatMarkdown(
                '[generated-image-loading: call_1_1]',
              ),
              builders: config.builders,
              blockSyntaxes: config.blockSyntaxes,
              inlineSyntaxes: config.inlineSyntaxes,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final Finder placeholder = find.byWidgetPredicate(
      (Widget widget) =>
          widget is SizedBox && widget.width == 360 && widget.height == 220,
    );

    expect(placeholder, findsOneWidget);
    expect(tester.getSize(placeholder), const Size(360, 220));
  });
}
