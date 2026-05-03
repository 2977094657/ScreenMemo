import 'dart:convert';

import 'package:screen_memo/features/ai/application/ai_settings_service.dart';
import 'package:screen_memo/features/nocturne_memory/application/memory_ai_contracts.dart';
import 'package:screen_memo/features/nocturne_memory/application/memory_ai_tool_helper.dart';
import 'package:screen_memo/features/nocturne_memory/application/memory_entity_models.dart';
import 'package:screen_memo/features/nocturne_memory/application/nocturne_memory_entity_prompts.dart';

class MemoryVisualExtractionService {
  MemoryVisualExtractionService._internal();

  static final MemoryVisualExtractionService instance =
      MemoryVisualExtractionService._internal();

  Future<MemoryBatchExtractionResult> extractBatch({
    required int segmentId,
    required int batchIndex,
    required List<Map<String, dynamic>> samples,
  }) async {
    if (samples.isEmpty) {
      return const MemoryBatchExtractionResult(
        entities: <MemoryVisualCandidate>[],
      );
    }

    final List<Map<String, Object?>> apiParts = <Map<String, Object?>>[
      <String, Object?>{
        'type': 'text',
        'text': '以下截图来自同一时间窗口。请只提炼可进入长期记忆候选层的实体，不要输出页面 OCR 抄录。',
      },
    ];
    for (int index = 0; index < samples.length; index += 1) {
      final Map<String, dynamic> sample = samples[index];
      final List<MemoryAIImagePayload> payloads =
          await MemoryAIContracts.buildVisualEvidencePayloads(
            (sample['file_path'] ?? '').toString(),
            batchSize: samples.length,
          );
      final int captureTime = _toInt(sample['capture_time']);
      final String appName = ((sample['app_name'] as String?) ?? '').trim();
      final int daySpanCount = _toInt(
        sample['cross_day_count'] ?? sample['distinct_day_count'],
      );
      final int appearanceCount = _toInt(
        sample['appearance_count'] ?? sample['segment_occurrence_count'],
      );
      for (final MemoryAIImagePayload payload in payloads) {
        apiParts.add(<String, Object?>{
          'type': 'text',
          'text':
              'frame=$index variant=${payload.label} time=$captureTime app=${appName.isEmpty ? 'unknown' : appName} batch_position=$index cross_day_count=$daySpanCount appearance_count=$appearanceCount',
        });
        apiParts.add(<String, Object?>{
          'type': 'image_url',
          'image_url': <String, Object?>{'url': payload.dataUrl},
        });
      }
    }

    final MemoryStructuredToolResult result = await MemoryAIToolHelper.instance
        .callObjectTool(
          logContext: 'memory_visual_extract_s${segmentId}_b$batchIndex',
          context: 'memory',
          messages: <AIMessage>[
            AIMessage(
              role: 'system',
              content: NocturneMemoryEntityPrompts.visualExtractionSystemPrompt(
                maxImages: samples.length,
              ),
            ),
            AIMessage(role: 'user', content: '', apiContent: apiParts),
          ],
          toolName: 'memory_visual_extract',
          toolDescription:
              'Extract stable memory entity candidates from screenshots.',
          parametersSchema: _schema,
        );

    final List<MemoryVisualCandidate> entities = <MemoryVisualCandidate>[];
    final dynamic rawEntities = result.payload['entities'];
    if (rawEntities is List) {
      for (final dynamic raw in rawEntities) {
        if (raw is! Map) continue;
        final MemoryVisualCandidate candidate = MemoryVisualCandidate.fromJson(
          Map<String, dynamic>.from(raw),
        );
        if (candidate.rootKey.isEmpty ||
            candidate.entityType.isEmpty ||
            candidate.preferredName.isEmpty) {
          continue;
        }
        entities.add(candidate);
      }
    }

    return MemoryBatchExtractionResult(
      entities: entities,
      modelUsed: result.modelUsed,
      rawPayload: const JsonEncoder.withIndent('  ').convert(result.payload),
    );
  }

  int _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static const Map<String, dynamic> _schema = <String, dynamic>{
    'type': 'object',
    'properties': <String, dynamic>{
      'entities': <String, dynamic>{
        'type': 'array',
        'items': <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'candidate_id': <String, dynamic>{'type': 'string'},
            'root_key': <String, dynamic>{'type': 'string'},
            'entity_type': <String, dynamic>{'type': 'string'},
            'preferred_name': <String, dynamic>{'type': 'string'},
            'aliases': <String, dynamic>{
              'type': 'array',
              'items': <String, dynamic>{'type': 'string'},
            },
            'visual_signature_summary': <String, dynamic>{'type': 'string'},
            'stable_visual_cues': <String, dynamic>{
              'type': 'array',
              'items': <String, dynamic>{'type': 'string'},
            },
            'facts': <String, dynamic>{
              'type': 'array',
              'items': <String, dynamic>{
                'type': 'object',
                'properties': <String, dynamic>{
                  'fact_type': <String, dynamic>{'type': 'string'},
                  'slot_key': <String, dynamic>{'type': 'string'},
                  'value': <String, dynamic>{'type': 'string'},
                  'cardinality': <String, dynamic>{'type': 'string'},
                  'confidence': <String, dynamic>{'type': 'number'},
                  'evidence_frames': <String, dynamic>{
                    'type': 'array',
                    'items': <String, dynamic>{'type': 'integer'},
                  },
                },
                'required': <String>[
                  'fact_type',
                  'value',
                  'cardinality',
                  'confidence',
                  'evidence_frames',
                ],
              },
            },
            'confidence': <String, dynamic>{'type': 'number'},
            'evidence_frames': <String, dynamic>{
              'type': 'array',
              'items': <String, dynamic>{'type': 'integer'},
            },
            'should_skip': <String, dynamic>{'type': 'boolean'},
            'skip_reason': <String, dynamic>{'type': 'string'},
          },
          'required': <String>[
            'candidate_id',
            'root_key',
            'entity_type',
            'preferred_name',
            'visual_signature_summary',
            'facts',
            'confidence',
            'evidence_frames',
            'should_skip',
          ],
        },
      },
    },
    'required': <String>['entities'],
  };
}
