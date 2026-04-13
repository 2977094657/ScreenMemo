import 'dart:convert';

import 'ai_settings_service.dart';
import 'memory_ai_contracts.dart';
import 'memory_ai_tool_helper.dart';
import 'memory_entity_models.dart';
import 'nocturne_memory_entity_prompts.dart';

class MemoryEntityMergePlannerService {
  MemoryEntityMergePlannerService._internal();

  static final MemoryEntityMergePlannerService instance =
      MemoryEntityMergePlannerService._internal();

  Future<MemoryStructuredDecisionResult<MemoryEntityMergePlan>> plan({
    required MemoryVisualCandidate candidate,
    required MemoryEntityResolutionDecision resolution,
    required List<MemoryEntityExemplar> currentExemplars,
    MemoryEntityDossier? matched,
  }) async {
    final Map<String, dynamic> inputPayload = <String, dynamic>{
      'candidate': candidate.toJson(),
      'resolution': resolution.toJson(),
      'matched_entity': matched?.toJson(includeFilePaths: false),
      'current_exemplars': currentExemplars
          .map((item) => item.toJson(includeFilePath: false))
          .toList(growable: false),
    };
    final List<Map<String, Object?>> apiParts = <Map<String, Object?>>[
      <String, Object?>{
        'type': 'text',
        'text': jsonEncode(<String, dynamic>{
          'candidate': candidate.toJson(),
          'resolution': resolution.toJson(),
          'matched_entity_id': matched?.entityId,
        }),
      },
      ...await MemoryAIContracts.buildExemplarApiParts(
        heading: 'current_candidate_exemplars',
        exemplars: currentExemplars,
        maxImages: 3,
      ),
      if (matched == null)
        <String, Object?>{'type': 'text', 'text': 'matched_entity=null'}
      else
        ...await MemoryAIContracts.buildDossierApiParts(
          heading: 'matched_entity_dossier',
          dossiers: <MemoryEntityDossier>[matched],
          maxImagesPerDossier: 2,
        ),
    ];
    final MemoryStructuredToolResult result = await MemoryAIToolHelper.instance
        .callObjectTool(
          logContext: 'memory_entity_merge_${candidate.candidateId}',
          context: 'memory',
          messages: <AIMessage>[
            AIMessage(
              role: 'system',
              content: NocturneMemoryEntityPrompts.mergePlanSystemPrompt(),
            ),
            AIMessage(role: 'user', content: '', apiContent: apiParts),
          ],
          toolName: 'memory_entity_merge_plan',
          toolDescription:
              'Create a high quality merge plan for the resolved entity.',
          parametersSchema: _schema,
        );
    return MemoryStructuredDecisionResult<MemoryEntityMergePlan>(
      value: MemoryEntityMergePlan.fromJson(result.payload),
      inputJson: encodeJsonPretty(inputPayload),
      outputJson: encodeJsonPretty(result.payload),
      modelUsed: result.modelUsed,
    );
  }

  static const Map<String, dynamic> _schema = <String, dynamic>{
    'type': 'object',
    'properties': <String, dynamic>{
      'preferred_name': <String, dynamic>{'type': 'string'},
      'aliases_to_add': <String, dynamic>{
        'type': 'array',
        'items': <String, dynamic>{'type': 'string'},
      },
      'summary_rewrite': <String, dynamic>{'type': 'string'},
      'visual_signature_summary': <String, dynamic>{'type': 'string'},
      'claims_to_upsert': <String, dynamic>{
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
      'events_to_append': <String, dynamic>{
        'type': 'array',
        'items': <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'note': <String, dynamic>{'type': 'string'},
            'evidence_frames': <String, dynamic>{
              'type': 'array',
              'items': <String, dynamic>{'type': 'integer'},
            },
          },
          'required': <String>['note', 'evidence_frames'],
        },
      },
      'notes': <String, dynamic>{'type': 'string'},
    },
    'required': <String>[
      'preferred_name',
      'aliases_to_add',
      'summary_rewrite',
      'visual_signature_summary',
      'claims_to_upsert',
      'events_to_append',
    ],
  };
}
