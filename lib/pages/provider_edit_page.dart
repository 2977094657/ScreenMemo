import 'dart:async';
import 'package:flutter/material.dart';
import 'package:screen_memo/widgets/ui_components.dart';
import 'package:screen_memo/l10n/app_localizations.dart';
import '../services/ai_providers_service.dart';
import '../theme/app_theme.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../utils/model_icon_utils.dart';

/// 提供商编辑页（新建/编辑）
class ProviderEditPage extends StatefulWidget {
  final int? providerId;

  const ProviderEditPage({super.key, this.providerId});

  @override
  State<ProviderEditPage> createState() => _ProviderEditPageState();
}

class _ProviderEditPageState extends State<ProviderEditPage> {
  final _svc = AIProvidersService.instance;

  final _nameCtrl = TextEditingController();
  final _baseUrlCtrl = TextEditingController();
  final _apiKeyCtrl = TextEditingController();
  final _chatPathCtrl = TextEditingController(text: '/v1/chat/completions');
  final _azureApiVerCtrl = TextEditingController(text: '2024-02-15');
  final _modelInputCtrl = TextEditingController();

  String _type = AIProviderTypes.openai;
  bool _useResponseApi = false;

  bool _loading = true;
  bool _saving = false;
  bool _fetching = false;

  List<String> _models = <String>[];
  AIProvider? _loaded;

  @override
  void initState() {
    super.initState();
    _initLoad();
  }

  Future<void> _initLoad() async {
    try {
      if (widget.providerId != null) {
        final p = await _svc.getProvider(widget.providerId!);
        if (p == null) {
          if (mounted) {
            UINotifier.error(context, AppLocalizations.of(context).providerNotFound);
            Navigator.of(context).pop();
          }
          return;
        }
        _loaded = p;
        final apiKey = await _svc.getApiKey(p.id!);
        _nameCtrl.text = p.name;
        _type = p.type;
        _baseUrlCtrl.text = p.baseUrl ?? '';
        _chatPathCtrl.text = p.chatPath ?? '/v1/chat/completions';
        _useResponseApi = p.useResponseApi;
        _models = List<String>.from(p.models);
        _apiKeyCtrl.text = apiKey ?? '';
        if (p.type == AIProviderTypes.azureOpenAI) {
          final v = (p.extra['azure_api_version'] as String?) ?? '2024-02-15';
          _azureApiVerCtrl.text = v;
        }
      } else {
        _applyTypeDefaults(AIProviderTypes.openai, initial: true);
      }
    } catch (e) {
      if (mounted) {
        UINotifier.error(context, AppLocalizations.of(context).pleaseTryAgain);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _baseUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    _chatPathCtrl.dispose();
    _azureApiVerCtrl.dispose();
    _modelInputCtrl.dispose();
    super.dispose();
  }

  void _applyTypeDefaults(String t, {bool initial = false}) {
    _type = t;
    String? baseDefault;
    switch (t) {
      case AIProviderTypes.openai:
        baseDefault = 'https://api.openai.com';
        break;
      case AIProviderTypes.claude:
        baseDefault = 'https://api.anthropic.com';
        break;
      case AIProviderTypes.gemini:
        baseDefault = 'https://generativelanguage.googleapis.com';
        break;
      case AIProviderTypes.azureOpenAI:
        baseDefault = '';
        break;
      case AIProviderTypes.custom:
        baseDefault = '';
        break;
    }
    if (initial) {
      _baseUrlCtrl.text = baseDefault ?? '';
    } else {
      final cur = _baseUrlCtrl.text.trim();
      if (cur.isEmpty ||
          cur == 'https://api.openai.com' ||
          cur == 'https://api.anthropic.com' ||
          cur == 'https://generativelanguage.googleapis.com') {
        _baseUrlCtrl.text = baseDefault ?? '';
      }
    }
    if (t == AIProviderTypes.openai || t == AIProviderTypes.custom) {
      _chatPathCtrl.text = _chatPathCtrl.text.isEmpty ? '/v1/chat/completions' : _chatPathCtrl.text;
    }
    _models = <String>[];
  }

  String _friendlyType(String t) {
    switch (t) {
      case AIProviderTypes.openai:
        return 'OpenAI';
      case AIProviderTypes.azureOpenAI:
        return 'Azure OpenAI';
      case AIProviderTypes.claude:
        return 'Claude';
      case AIProviderTypes.gemini:
        return 'Gemini';
      case AIProviderTypes.custom:
        return AppLocalizations.of(context).customLabel;
      default:
        return t;
    }
  }

  String _baseUrlHint() {
    switch (_type) {
      case AIProviderTypes.openai:
        return AppLocalizations.of(context).baseUrlHintOpenAI;
      case AIProviderTypes.claude:
        return AppLocalizations.of(context).baseUrlHintClaude;
      case AIProviderTypes.gemini:
        return AppLocalizations.of(context).baseUrlHintGemini;
      case AIProviderTypes.azureOpenAI:
        return AppLocalizations.of(context).baseUrlHintAzure('{resource}');
      case AIProviderTypes.custom:
        return AppLocalizations.of(context).baseUrlHintCustom;
      default:
        return 'Base URL';
    }
  }

  Future<void> _refreshModels() async {
    if (_fetching) return;
    final name = _nameCtrl.text.trim();
    final apiKey = _apiKeyCtrl.text.trim();
    final base = _baseUrlCtrl.text.trim();
    if (name.isEmpty) {
      UINotifier.error(context, AppLocalizations.of(context).nameRequiredError);
      return;
    }
    if (apiKey.isEmpty) {
      UINotifier.error(context, AppLocalizations.of(context).apiKeyRequiredError);
      return;
    }
    if (_type == AIProviderTypes.azureOpenAI && base.isEmpty) {
      UINotifier.error(context, AppLocalizations.of(context).baseUrlRequiredForAzureError);
      return;
    }
    setState(() => _fetching = true);
    try {
      final tmp = AIProvider(
        id: _loaded?.id,
        name: name,
        type: _type,
        baseUrl: base.isEmpty ? null : base,
        chatPath: _chatPathCtrl.text.trim().isEmpty ? null : _chatPathCtrl.text.trim(),
        useResponseApi: _useResponseApi,
        enabled: true,
        isDefault: false,
        models: const <String>[],
        extra: _buildExtra(),
        orderIndex: _loaded?.orderIndex ?? 0,
      );
      final fetched = await _svc.fetchModels(provider: tmp, apiKey: apiKey);
      if (mounted) {
        setState(() => _models = fetched);
        UINotifier.success(context, AppLocalizations.of(context).modelsUpdatedToast(fetched.length));
      }
    } catch (e) {
      if (mounted) {
        UINotifier.error(context, AppLocalizations.of(context).fetchModelsFailedHint);
      }
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  Map<String, dynamic> _buildExtra() {
    final map = <String, dynamic>{};
    if (_type == AIProviderTypes.azureOpenAI) {
      map['azure_api_version'] = _azureApiVerCtrl.text.trim().isEmpty
          ? '2024-02-15'
          : _azureApiVerCtrl.text.trim();
    }
    if (_models.isNotEmpty) {
      map['default_model'] = _models.first;
    }
    return map;
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameCtrl.text.trim();
    String base = _baseUrlCtrl.text.trim();
    final apiKey = _apiKeyCtrl.text.trim();
    final chatPath = _chatPathCtrl.text.trim().isEmpty ? null : _chatPathCtrl.text.trim();

    if (name.isEmpty) {
      UINotifier.error(context, AppLocalizations.of(context).nameRequiredError);
      return;
    }
    final nameOk = await _svc.isNameAvailable(name, excludeId: _loaded?.id);
    if (!nameOk) {
      UINotifier.error(context, AppLocalizations.of(context).nameAlreadyExistsError);
      return;
    }
    if (_type.isEmpty) {
      UINotifier.error(context, AppLocalizations.of(context).operationFailed);
      return;
    }
    if (_type == AIProviderTypes.azureOpenAI ||
        _type == AIProviderTypes.claude ||
        _type == AIProviderTypes.gemini ||
        _type == AIProviderTypes.custom) {
      if (base.isEmpty) {
      UINotifier.error(context, AppLocalizations.of(context).baseUrlRequiredForAzureError);
        return;
      }
    }
    if (_type == AIProviderTypes.openai && base.isEmpty) {
      base = 'https://api.openai.com';
    }
    if (apiKey.isEmpty) {
      UINotifier.error(context, AppLocalizations.of(context).apiKeyRequiredError);
      return;
    }
    if (_models.isEmpty) {
      UINotifier.error(context, AppLocalizations.of(context).atLeastOneModelRequiredError);
      return;
    }

    setState(() => _saving = true);
    try {
      if (_loaded == null) {
        final id = await _svc.createProvider(
          name: name,
          type: _type,
          baseUrl: base,
          chatPath: chatPath,
          useResponseApi: _useResponseApi,
          enabled: true,
          isDefault: false,
          extra: _buildExtra(),
          models: _models,
          apiKey: apiKey,
        );
        if (id == null) {
          throw Exception('Insert failed');
        }
      } else {
        final ok = await _svc.updateProvider(
          id: _loaded!.id!,
          name: name,
          type: _type,
          baseUrl: base,
          chatPath: chatPath,
          useResponseApi: _useResponseApi,
          enabled: true,
          isDefault: false,
          extra: _buildExtra(),
          models: _models,
          apiKey: apiKey,
        );
        if (!ok) {
          throw Exception('Update failed');
        }
      }
      if (!mounted) return;
      UINotifier.success(context, AppLocalizations.of(context).saveSuccess);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        UINotifier.error(context, AppLocalizations.of(context).saveFailedError(e.toString()));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _addModelChip() {
    final m = _modelInputCtrl.text.trim();
    if (m.isEmpty) return;
    setState(() {
      if (!_models.contains(m)) {
        _models = List<String>.from(_models)..add(m);
      }
      _modelInputCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.providerId == null ? AppLocalizations.of(context).createProviderTitle : AppLocalizations.of(context).editProviderTitle;
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        title: Text(title),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(AppTheme.spacing4),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: _save,
              child: Text(AppLocalizations.of(context).actionSave),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : GestureDetector(
              onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppTheme.spacing4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildTextInput(
                            label: AppLocalizations.of(context).groupNameLabel,
                            controller: _nameCtrl,
                            hint: AppLocalizations.of(context).groupNameHint,
                          ),
                          const SizedBox(height: AppTheme.spacing3),
                          _buildTypePicker(),
                          const SizedBox(height: AppTheme.spacing3),
                          _buildTextInput(
                            label: AppLocalizations.of(context).baseUrlLabel,
                            controller: _baseUrlCtrl,
                            hint: _baseUrlHint(),
                          ),
                          const SizedBox(height: AppTheme.spacing3),
                          _buildTextInput(
                            label: AppLocalizations.of(context).apiKeyLabel,
                            controller: _apiKeyCtrl,
                            hint: AppLocalizations.of(context).apiKeyHint,
                            obscure: true,
                          ),
                          if (_type == AIProviderTypes.openai || _type == AIProviderTypes.custom) ...[
                            const SizedBox(height: AppTheme.spacing3),
                            _buildTextInput(
                              label: AppLocalizations.of(context).chatPathOptionalLabel,
                              controller: _chatPathCtrl,
                              hint: '/v1/chat/completions',
                            ),
                            const SizedBox(height: AppTheme.spacing2),
                            _buildSwitchRow(
                              label: (() {
                                final s = AppLocalizations.of(context).useResponseApiLabel;
                                return s.replaceAll(RegExp(r'（.*?）|\(.*?\)'), '').trim();
                              })(),
                              value: _useResponseApi,
                              onChanged: (v) => setState(() => _useResponseApi = v),
                            ),
                          ],
                          if (_type == AIProviderTypes.azureOpenAI) ...[
                            const SizedBox(height: AppTheme.spacing3),
                            _buildTextInput(
                              label: AppLocalizations.of(context).azureApiVersionLabel,
                              controller: _azureApiVerCtrl,
                              hint: AppLocalizations.of(context).azureApiVersionHint,
                            ),
                          ],
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: AppTheme.spacing4),
                    
                    _buildSectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                AppLocalizations.of(context).modelsCountLabel(_models.length),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Spacer(),
                              TextButton.icon(
                                onPressed: _fetching ? null : _refreshModels,
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppTheme.spacing2,
                                    vertical: AppTheme.spacing1,
                                  ),
                                ),
                                icon: _fetching
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.refresh, size: 18),
                                label: Text(AppLocalizations.of(context).actionRefresh),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppTheme.spacing3),
                          
                          // 手动添加模型（移到最前面）
                          Text(
                            AppLocalizations.of(context).manualAddModelLabel,
                            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: AppTheme.spacing1),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 40,
                                  child: TextField(
                                    controller: _modelInputCtrl,
                                    textAlignVertical: TextAlignVertical.center,
                                    style: Theme.of(context).textTheme.bodyMedium,
                                    decoration: InputDecoration(
                                      isDense: false,
                                      hintText: AppLocalizations.of(context).inputAndAddModelHint,
                                      hintStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: AppTheme.mutedForeground,
                                      ),
                                      contentPadding: const EdgeInsets.symmetric(
                                        horizontal: AppTheme.spacing3,
                                        vertical: 0,
                                      ),
                                    ),
                                    onSubmitted: (_) => _addModelChip(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppTheme.spacing2),
                              SizedBox(
                                height: 40,
                                child: ElevatedButton(
                                  onPressed: _addModelChip,
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppTheme.spacing4,
                                    ),
                                  ),
                                  child: Text(AppLocalizations.of(context).actionAdd),
                                ),
                              ),
                            ],
                          ),
                          
                          if (_models.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: AppTheme.spacing3,
                              ),
                              child: Text(
                                AppLocalizations.of(context).fetchModelsHint,
                                style: theme.textTheme.bodySmall,
                              ),
                            )
                          else ...[
                            const SizedBox(height: AppTheme.spacing3),
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _models.length,
                              separatorBuilder: (c, i) => Container(
                                height: 1,
                                color: Theme.of(c).colorScheme.outline.withOpacity(0.6),
                              ),
                              itemBuilder: (c, i) {
                                final m = _models[i];
                                return ListTile(
                                  leading: SvgPicture.asset(
                                    ModelIconUtils.getIconPath(m),
                                    width: 20, height: 20,
                                  ),
                                  title: Text(m, style: Theme.of(c).textTheme.bodyMedium),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.close, size: 18),
                                    onPressed: () {
                                      setState(() {
                                        _models = List<String>.from(_models)..removeAt(i);
                                      });
                                    },
                                  ),
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: AppTheme.spacing6),
                    
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: AppTheme.spacing3),
                            ),
                            child: Text(AppLocalizations.of(context).dialogCancel),
                          ),
                        ),
                        const SizedBox(width: AppTheme.spacing3),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _saving ? null : _save,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: AppTheme.spacing3),
                            ),
                            child: Text(AppLocalizations.of(context).actionSave),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppTheme.spacing4),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSectionCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.spacing3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: child,
    );
  }

  Widget _buildTextInput({
    required String label,
    required TextEditingController controller,
    String? hint,
    bool obscure = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppTheme.spacing1),
        TextField(
          controller: controller,
          obscureText: obscure,
          style: Theme.of(context).textTheme.bodyMedium,
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppTheme.mutedForeground,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacing3,
              vertical: AppTheme.spacing2,
            ),
          ),
          onChanged: (v) {
            if (controller == _baseUrlCtrl || controller == _apiKeyCtrl) {
              setState(() {
                _models = <String>[];
              });
            }
          },
        ),
      ],
    );
  }

  Widget _buildTypePicker() {
    final items = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: AIProviderTypes.openai, child: Text('OpenAI')),
      const DropdownMenuItem(value: AIProviderTypes.azureOpenAI, child: Text('Azure OpenAI')),
      const DropdownMenuItem(value: AIProviderTypes.claude, child: Text('Claude')),
      const DropdownMenuItem(value: AIProviderTypes.gemini, child: Text('Gemini')),
      DropdownMenuItem(value: AIProviderTypes.custom, child: Text(AppLocalizations.of(context).customLabel)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context).interfaceTypeLabel,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppTheme.spacing1),
        DropdownButtonFormField<String>(
          value: _type,
          isDense: true,
          items: items,
          onChanged: (v) {
            if (v == null) return;
            setState(() {
              _applyTypeDefaults(v);
            });
          },
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacing3,
              vertical: AppTheme.spacing2,
            ),
          ),
        ),
        const SizedBox(height: AppTheme.spacing1),
        Text(
          AppLocalizations.of(context).currentTypeLabel(_friendlyType(_type)),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildSwitchRow({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spacing1),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildModelChip(String model) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing2,
        vertical: AppTheme.spacing1,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            model,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(width: AppTheme.spacing1),
          InkWell(
            onTap: () {
              setState(() {
                _models = List<String>.from(_models)..remove(model);
              });
            },
            child: Icon(
              Icons.close,
              size: 14,
              color: Theme.of(context).colorScheme.onSecondaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}
                