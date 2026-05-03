import 'dart:convert';

import 'package:screen_memo/features/ai/application/ai_settings_service.dart';
import 'package:screen_memo/features/nocturne_memory/application/memory_ai_contracts.dart';
import 'package:screen_memo/features/nocturne_memory/application/memory_ai_tool_helper.dart';
import 'package:screen_memo/features/nocturne_memory/application/memory_entity_models.dart';
import 'package:screen_memo/features/nocturne_memory/application/nocturne_memory_entity_prompts.dart';

class MemoryEntityAuditService {
  MemoryEntityAuditService._internal();

  static final MemoryEntityAuditService instance =
      MemoryEntityAuditService._internal();

  Future<MemoryStructuredDecisionResult<MemoryEntityAuditDecision>> audit({
    required MemoryVisualCandidate candidate,
    required MemoryEntityResolutionDecision resolution,
    required MemoryEntityMergePlan mergePlan,
    required List<MemoryEntityDossier> shortlist,
    required List<MemoryEntityExemplar> currentExemplars,
  }) async {
    final Map<String, dynamic> inputPayload = <String, dynamic>{
      'candidate': candidate.toJson(),
      'resolution': resolution.toJson(),
      'merge_plan': mergePlan.toJson(),
      'shortlist': shortlist
          .map((item) => item.toJson(includeFilePaths: false))
          .toList(growable: false),
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
          'merge_plan': mergePlan.toJson(),
          'shortlist_count': shortlist.length,
        }),
      },
      ...await MemoryAIContracts.buildExemplarApiParts(
        heading: 'current_candidate_exemplars',
        exemplars: currentExemplars,
        maxImages: 3,
      ),
      if (shortlist.isEmpty)
        <String, Object?>{'type': 'text', 'text': 'shortlist=[]'}
      else
        ...await MemoryAIContracts.buildDossierApiParts(
          heading: 'shortlist_dossiers',
          dossiers: shortlist,
          maxImagesPerDossier: 2,
        ),
    ];
    final MemoryStructuredToolResult result = await MemoryAIToolHelper.instance
        .callObjectTool(
          logContext: 'memory_entity_audit_${candidate.candidateId}',
          context: 'memory',
          messages: <AIMessage>[
            AIMessage(
              role: 'system',
              content: NocturneMemoryEntityPrompts.auditSystemPrompt(),
            ),
            AIMessage(role: 'user', content: '', apiContent: apiParts),
          ],
          toolName: 'memory_entity_audit',
          toolDescription: 'Audit whether this entity write should proceed.',
          parametersSchema: _schema,
        );
    return MemoryStructuredDecisionResult<MemoryEntityAuditDecision>(
      value: MemoryEntityAuditDecision.fromJson(result.payload),
      inputJson: encodeJsonPretty(inputPayload),
      outputJson: encodeJsonPretty(result.payload),
      modelUsed: result.modelUsed,
    );
  }

  static const Map<String, dynamic> _schema = <String, dynamic>{
    'type': 'object',
    'properties': <String, dynamic>{
      'action': <String, dynamic>{'type': 'string'},
      'confidence': <String, dynamic>{'type': 'number'},
      'suggested_entity_id': <String, dynamic>{'type': 'string'},
      'reasons': <String, dynamic>{
        'type': 'array',
        'items': <String, dynamic>{'type': 'string'},
      },
      'notes': <String, dynamic>{'type': 'string'},
    },
    'required': <String>['action', 'confidence', 'reasons'],
  };
}
