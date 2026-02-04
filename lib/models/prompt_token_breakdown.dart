import 'package:flutter/material.dart';

/// Token breakdown keys stored in `ai_conversations.last_prompt_breakdown_json`.
///
/// Keep keys stable for DB compatibility.
enum PromptTokenPart {
  systemPrompt('system_prompt'),
  toolSchema('tool_schema'),
  toolInstruction('tool_instruction'),
  conversationContext('conversation_context'),
  atomicMemory('atomic_memory'),
  extraSystem('extra_system'),
  historyUser('history_user'),
  historyAssistant('history_assistant'),
  historyTool('history_tool'),
  userMessage('user_message');

  const PromptTokenPart(this.key);
  final String key;

  static PromptTokenPart? fromKey(String key) {
    for (final v in PromptTokenPart.values) {
      if (v.key == key) return v;
    }
    return null;
  }
}

extension PromptTokenPartX on PromptTokenPart {
  String labelZh() {
    switch (this) {
      case PromptTokenPart.systemPrompt:
        return '系统提示词';
      case PromptTokenPart.toolSchema:
        return '工具 schema';
      case PromptTokenPart.toolInstruction:
        return '工具指令';
      case PromptTokenPart.conversationContext:
        return '对话记忆';
      case PromptTokenPart.atomicMemory:
        return '原子记忆';
      case PromptTokenPart.extraSystem:
        return '其他系统信息';
      case PromptTokenPart.historyUser:
        return '历史(User)';
      case PromptTokenPart.historyAssistant:
        return '历史(Assistant)';
      case PromptTokenPart.historyTool:
        return '历史(Tool)';
      case PromptTokenPart.userMessage:
        return '本次输入';
    }
  }

  String labelEn() {
    switch (this) {
      case PromptTokenPart.systemPrompt:
        return 'System';
      case PromptTokenPart.toolSchema:
        return 'Tool schema';
      case PromptTokenPart.toolInstruction:
        return 'Tool instruction';
      case PromptTokenPart.conversationContext:
        return 'Conversation memory';
      case PromptTokenPart.atomicMemory:
        return 'Atomic memory';
      case PromptTokenPart.extraSystem:
        return 'Other system';
      case PromptTokenPart.historyUser:
        return 'History (User)';
      case PromptTokenPart.historyAssistant:
        return 'History (Assistant)';
      case PromptTokenPart.historyTool:
        return 'History (Tool)';
      case PromptTokenPart.userMessage:
        return 'User message';
    }
  }

  Color color(ThemeData theme) {
    // Storage-usage style palette: high contrast but not neon.
    switch (this) {
      case PromptTokenPart.systemPrompt:
        return theme.colorScheme.primary;
      case PromptTokenPart.toolSchema:
        return const Color(0xFF0EA5E9); // sky-500
      case PromptTokenPart.toolInstruction:
        return const Color(0xFF14B8A6); // teal-500
      case PromptTokenPart.conversationContext:
        return const Color(0xFF22C55E); // green-500
      case PromptTokenPart.atomicMemory:
        return const Color(0xFFA855F7); // purple-500
      case PromptTokenPart.extraSystem:
        return const Color(0xFF64748B); // slate-500
      case PromptTokenPart.historyUser:
        return const Color(0xFF3B82F6); // blue-500
      case PromptTokenPart.historyAssistant:
        return const Color(0xFF10B981); // emerald-500
      case PromptTokenPart.historyTool:
        return const Color(0xFF6366F1); // indigo-500
      case PromptTokenPart.userMessage:
        return const Color(0xFFEF4444); // red-500
    }
  }
}
