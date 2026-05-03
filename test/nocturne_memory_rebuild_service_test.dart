import 'package:flutter_test/flutter_test.dart';
import 'package:screen_memo/features/nocturne_memory/application/nocturne_memory_entity_prompts.dart';

void main() {
  test('visual extraction prompt enforces visual-only evidence contract', () {
    final String prompt =
        NocturneMemoryEntityPrompts.visualExtractionSystemPrompt(maxImages: 10);

    expect(prompt, contains('只能依据截图本身可见信息做判断'));
    expect(prompt, contains('严禁把截图理解为 OCR 纯文本任务'));
    expect(prompt, contains('facts: 只写稳定事实'));
    expect(prompt, contains('每条 fact 都必须给出 evidence_frames'));
    expect(prompt, isNot(contains('create_memory')));
    expect(prompt, isNot(contains('update_memory')));
  });

  test('resolution prompt describes entity-first match decisions', () {
    final String prompt = NocturneMemoryEntityPrompts.resolutionSystemPrompt();

    expect(prompt, contains('MATCH_EXISTING'));
    expect(prompt, contains('CREATE_NEW'));
    expect(prompt, contains('ADD_ALIAS_TO_EXISTING'));
    expect(prompt, contains('REVIEW_REQUIRED'));
    expect(prompt, contains('规则检索只是 shortlist'));
  });

  test('merge plan prompt requires structured claims and events evidence', () {
    final String prompt = NocturneMemoryEntityPrompts.mergePlanSystemPrompt();

    expect(prompt, contains('claims_to_upsert'));
    expect(prompt, contains('events_to_append'));
    expect(prompt, contains('每条 claim 都必须给 evidence_frames'));
    expect(prompt, contains('每条 event 都必须给 evidence_frames'));
  });

  test('audit prompt blocks duplicate, ambiguous, and low-evidence writes', () {
    final String prompt = NocturneMemoryEntityPrompts.auditSystemPrompt();

    expect(prompt, contains('APPROVE'));
    expect(prompt, contains('BLOCK_DUPLICATE'));
    expect(prompt, contains('BLOCK_AMBIGUOUS'));
    expect(prompt, contains('BLOCK_LOW_EVIDENCE'));
  });
}
