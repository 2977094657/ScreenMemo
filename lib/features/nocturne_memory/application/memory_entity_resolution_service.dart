import 'dart:convert';

import 'package:screen_memo/features/ai/application/ai_settings_service.dart';
import 'package:screen_memo/features/nocturne_memory/application/memory_ai_contracts.dart';
import 'package:screen_memo/features/nocturne_memory/application/memory_ai_tool_helper.dart';
import 'package:screen_memo/features/nocturne_memory/application/memory_entity_models.dart';
import 'package:screen_memo/features/nocturne_memory/application/nocturne_memory_entity_prompts.dart';

class MemoryEntityResolutionService {
  MemoryEntityResolutionService._internal();

  static final MemoryEntityResolutionService instance =
      MemoryEntityResolutionService._internal();

  Future<MemoryEntityResolutionWorkflowResult> resolve({
    required MemoryVisualCandidate candidate,
    required List<MemoryEntityDossier> shortlist,
    required List<MemoryEntityExemplar> currentExemplars,
  }) async {
    final MemoryStructuredDecisionResult<MemoryEntityResolutionDecision>
    resolverA = await _resolvePass(
      candidate: candidate,
      shortlist: shortlist,
      currentExemplars: currentExemplars,
      stageLabel: 'resolution_a',
      systemPrompt: NocturneMemoryEntityPrompts.resolutionSystemPrompt(),
      passHint: 'resolver_pass=A',
    );
    final MemoryStructuredDecisionResult<MemoryEntityResolutionDecision>
    resolverB = await _resolvePass(
      candidate: candidate,
      shortlist: shortlist,
      currentExemplars: currentExemplars,
      stageLabel: 'resolution_b',
      systemPrompt: NocturneMemoryEntityPrompts.resolutionSystemPrompt(),
      passHint: 'resolver_pass=B',
    );

    final List<MemoryPipelineAuditEntry> auditTrail =
        <MemoryPipelineAuditEntry>[
          _toAuditEntry(stage: 'resolution_a', result: resolverA),
          _toAuditEntry(stage: 'resolution_b', result: resolverB),
        ];

    if (_isAgreement(resolverA.value, resolverB.value) &&
        _isHighConfidence(resolverA.value) &&
        _isHighConfidence(resolverB.value)) {
      final MemoryStructuredDecisionResult<MemoryEntityResolutionDecision>
      chosen = resolverA.value.confidence >= resolverB.value.confidence
          ? resolverA
          : resolverB;
      return MemoryEntityResolutionWorkflowResult(
        finalResult: chosen,
        auditTrail: auditTrail,
      );
    }

    final MemoryStructuredDecisionResult<MemoryEntityResolutionDecision>
    arbiter = await _resolveArbiter(
      candidate: candidate,
      shortlist: shortlist,
      currentExemplars: currentExemplars,
      resolverA: resolverA,
      resolverB: resolverB,
    );
    final MemoryStructuredDecisionResult<MemoryEntityResolutionDecision>
    normalizedArbiter = _normalizeArbiterResult(arbiter);
    auditTrail.add(
      _toAuditEntry(stage: 'resolution_arbiter', result: normalizedArbiter),
    );
    return MemoryEntityResolutionWorkflowResult(
      finalResult: normalizedArbiter,
      auditTrail: auditTrail,
    );
  }

  Future<MemoryStructuredDecisionResult<MemoryEntityResolutionDecision>>
  _resolvePass({
    required MemoryVisualCandidate candidate,
    required List<MemoryEntityDossier> shortlist,
    required List<MemoryEntityExemplar> currentExemplars,
    required String stageLabel,
    required String systemPrompt,
    required String passHint,
  }) async {
    final Map<String, dynamic> inputPayload = <String, dynamic>{
      'candidate': candidate.toJson(),
      'shortlist': shortlist
          .map((item) => item.toJson(includeFilePaths: false))
          .toList(growable: false),
      'current_exemplars': currentExemplars
          .map((item) => item.toJson(includeFilePath: false))
          .toList(growable: false),
      'pass_hint': passHint,
    };
    final List<Map<String, Object?>> apiParts = <Map<String, Object?>>[
      <String, Object?>{
        'type': 'text',
        'text': jsonEncode(<String, dynamic>{
          'pass_hint': passHint,
          'candidate': candidate.toJson(),
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
    final MemoryStructuredToolResult
    result = await MemoryAIToolHelper.instance.callObjectTool(
      logContext: 'memory_entity_${stageLabel}_${candidate.candidateId}',
      context: 'memory',
      messages: <AIMessage>[
        AIMessage(role: 'system', content: systemPrompt),
        AIMessage(role: 'user', content: '', apiContent: apiParts),
      ],
      toolName: 'memory_entity_resolution',
      toolDescription:
          'Resolve whether the visual entity matches an existing entity or should create a new one.',
      parametersSchema: _schema,
    );
    return MemoryStructuredDecisionResult<MemoryEntityResolutionDecision>(
      value: MemoryEntityResolutionDecision.fromJson(result.payload),
      inputJson: encodeJsonPretty(inputPayload),
      outputJson: encodeJsonPretty(result.payload),
      modelUsed: result.modelUsed,
    );
  }

  Future<MemoryStructuredDecisionResult<MemoryEntityResolutionDecision>>
  _resolveArbiter({
    required MemoryVisualCandidate candidate,
    required List<MemoryEntityDossier> shortlist,
    required List<MemoryEntityExemplar> currentExemplars,
    required MemoryStructuredDecisionResult<MemoryEntityResolutionDecision>
    resolverA,
    required MemoryStructuredDecisionResult<MemoryEntityResolutionDecision>
    resolverB,
  }) async {
    final Map<String, dynamic> inputPayload = <String, dynamic>{
      'candidate': candidate.toJson(),
      'shortlist': shortlist
          .map((item) => item.toJson(includeFilePaths: false))
          .toList(growable: false),
      'current_exemplars': currentExemplars
          .map((item) => item.toJson(includeFilePath: false))
          .toList(growable: false),
      'resolver_a': resolverA.value.toJson(),
      'resolver_b': resolverB.value.toJson(),
    };
    final List<Map<String, Object?>> apiParts = <Map<String, Object?>>[
      <String, Object?>{
        'type': 'text',
        'text': jsonEncode(<String, dynamic>{
          'candidate': candidate.toJson(),
          'resolver_a': resolverA.value.toJson(),
          'resolver_b': resolverB.value.toJson(),
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
    final MemoryStructuredToolResult
    result = await MemoryAIToolHelper.instance.callObjectTool(
      logContext: 'memory_entity_resolution_arbiter_${candidate.candidateId}',
      context: 'memory',
      messages: <AIMessage>[
        AIMessage(
          role: 'system',
          content: NocturneMemoryEntityPrompts.resolutionArbiterSystemPrompt(),
        ),
        AIMessage(role: 'user', content: '', apiContent: apiParts),
      ],
      toolName: 'memory_entity_resolution',
      toolDescription:
          'Arbitrate between two entity resolution decisions and return the final decision.',
      parametersSchema: _schema,
    );
    return MemoryStructuredDecisionResult<MemoryEntityResolutionDecision>(
      value: MemoryEntityResolutionDecision.fromJson(result.payload),
      inputJson: encodeJsonPretty(inputPayload),
      outputJson: encodeJsonPretty(result.payload),
      modelUsed: result.modelUsed,
    );
  }

  MemoryPipelineAuditEntry _toAuditEntry({
    required String stage,
    required MemoryStructuredDecisionResult<MemoryEntityResolutionDecision>
    result,
  }) {
    return MemoryPipelineAuditEntry(
      stage: stage,
      action: result.value.action.wireName,
      confidence: result.value.confidence,
      modelUsed: result.modelUsed,
      inputJson: result.inputJson,
      outputJson: result.outputJson,
      payloadJson: result.outputJson,
    );
  }

  bool _isHighConfidence(MemoryEntityResolutionDecision decision) {
    return !decision.needsReview && decision.confidence >= 0.72;
  }

  bool _isAgreement(
    MemoryEntityResolutionDecision a,
    MemoryEntityResolutionDecision b,
  ) {
    if (a.action != b.action) return false;
    switch (a.action) {
      case MemoryEntityResolutionAction.matchExisting:
      case MemoryEntityResolutionAction.addAliasToExisting:
        return (a.matchedEntityId ?? '').trim() ==
            (b.matchedEntityId ?? '').trim();
      case MemoryEntityResolutionAction.createNew:
        return true;
      case MemoryEntityResolutionAction.reviewRequired:
        return true;
    }
  }

  MemoryStructuredDecisionResult<MemoryEntityResolutionDecision>
  _normalizeArbiterResult(
    MemoryStructuredDecisionResult<MemoryEntityResolutionDecision> result,
  ) {
    final MemoryEntityResolutionDecision decision = result.value;
    if (decision.action == MemoryEntityResolutionAction.reviewRequired ||
        decision.needsReview ||
        decision.confidence >= 0.58) {
      return result;
    }
    final MemoryEntityResolutionDecision normalized =
        MemoryEntityResolutionDecision(
          action: MemoryEntityResolutionAction.reviewRequired,
          confidence: decision.confidence,
          matchedEntityId: null,
          suggestedPreferredName: decision.suggestedPreferredName,
          aliasesToAdd: decision.aliasesToAdd,
          reasons: <String>[...decision.reasons, '仲裁置信度偏低，转入人工复核'],
          conflicts: decision.conflicts,
          needsReview: true,
        );
    return MemoryStructuredDecisionResult<MemoryEntityResolutionDecision>(
      value: normalized,
      inputJson: result.inputJson,
      outputJson: encodeJsonPretty(normalized.toJson()),
      modelUsed: result.modelUsed,
    );
  }

  static const Map<String, dynamic> _schema = <String, dynamic>{
    'type': 'object',
    'properties': <String, dynamic>{
      'decision': <String, dynamic>{'type': 'string'},
      'confidence': <String, dynamic>{'type': 'number'},
      'matched_entity_id': <String, dynamic>{'type': 'string'},
      'suggested_preferred_name': <String, dynamic>{'type': 'string'},
      'aliases_to_add': <String, dynamic>{
        'type': 'array',
        'items': <String, dynamic>{'type': 'string'},
      },
      'reasons': <String, dynamic>{
        'type': 'array',
        'items': <String, dynamic>{'type': 'string'},
      },
      'conflicts': <String, dynamic>{
        'type': 'array',
        'items': <String, dynamic>{'type': 'string'},
      },
      'needs_review': <String, dynamic>{'type': 'boolean'},
    },
    'required': <String>[
      'decision',
      'confidence',
      'reasons',
      'conflicts',
      'needs_review',
    ],
  };
}
