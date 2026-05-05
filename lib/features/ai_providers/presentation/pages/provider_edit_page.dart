import 'dart:async';
import 'package:flutter/material.dart';
import 'package:screen_memo/core/widgets/ui_components.dart';
import 'package:screen_memo/l10n/app_localizations.dart';
import 'package:screen_memo/features/ai/application/ai_context_budgets.dart';
import 'package:screen_memo/features/ai/application/ai_providers_service.dart';
import 'package:screen_memo/features/ai/application/models_dev_catalog_service.dart';
import 'package:screen_memo/features/ai/application/provider_key_batch_maintenance_service.dart';
import 'package:screen_memo/core/theme/app_theme.dart';
import 'package:screen_memo/core/widgets/model_logo.dart';
import 'package:screen_memo/core/widgets/ui_dialog.dart';
import 'package:screen_memo/core/logging/flutter_logger.dart';
import 'package:screen_memo/models/models_dev_limits.dart';

part 'provider_edit_page_state_part.dart';
part 'provider_edit_page_batch_part.dart';
part 'provider_edit_page_save_part.dart';
part 'provider_edit_page_models_part.dart';
part 'provider_edit_page_keys_part.dart';
part 'provider_edit_page_form_part.dart';

enum _ProviderKeySortMode {
  runtime,
  balanceDesc,
  balanceAsc,
  successDesc,
  recentSuccessDesc,
  failureDesc,
  continuousFailureDesc,
  newestDesc,
}

class _ModelCostDisplayItem {
  const _ModelCostDisplayItem({required this.label, required this.value});

  final String label;
  final String value;
}

/// 提供商编辑页（新建/编辑）
class ProviderEditPage extends StatefulWidget {
  final int? providerId;

  const ProviderEditPage({super.key, this.providerId});

  @override
  State<ProviderEditPage> createState() => _ProviderEditPageState();
}

class _ProviderEditPageState extends State<ProviderEditPage> {
  final _svc = AIProvidersService.instance;
  final _batchSvc = ProviderKeyBatchMaintenanceService.instance;
  final _modelsDev = ModelsDevCatalogService.instance;

  final _nameCtrl = TextEditingController();
  final _baseUrlCtrl = TextEditingController();
  final _chatPathCtrl = TextEditingController(text: '/v1/chat/completions');
  final _modelsPathCtrl = TextEditingController(
    text: defaultModelsPathForType(AIProviderTypes.openai),
  );
  final _azureApiVerCtrl = TextEditingController(text: '2024-02-15');
  final _modelInputCtrl = TextEditingController();

  String _type = AIProviderTypes.openai;
  bool _useResponseApi = false;

  /// 余额查询接口类型，'none' / 'new_api' / 'sub2api'。
  String _balanceEndpointType = AIBalanceEndpointTypes.none;

  /// 余额为 0 时自动删除该 key。
  bool _balanceAutoDeleteZeroKey = false;

  bool _loading = true;
  bool _saving = false;
  bool _fetching = false;
  bool _batchRunning = false;
  ProviderKeyBatchProgress? _batchProgress;

  _ProviderKeySortMode _keySortMode = _ProviderKeySortMode.runtime;

  List<String> _models = <String>[];
  final Map<String, ModelsDevModelInfo> _modelInfoByName =
      <String, ModelsDevModelInfo>{};
  List<AIProviderKey> _keys = <AIProviderKey>[];
  AIProvider? _loaded;
  bool _geminiNoticeShown = false;
  int _modelInfoLoadSeq = 0;

  void _providerEditSetState(VoidCallback fn) => setState(fn);

  Future<void> _showGeminiRegionDialog() async {
    if (!mounted) return;
    await showUIDialog<void>(
      context: context,
      title: AppLocalizations.of(context).geminiRegionDialogTitle,
      message: AppLocalizations.of(context).geminiRegionDialogMessage,
      actions: [UIDialogAction(text: AppLocalizations.of(context).gotIt)],
    );
  }

  void _showGeminiRegionNotice() {
    if (_geminiNoticeShown || !mounted) return;
    _geminiNoticeShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      UINotifier.warning(
        context,
        l10n.geminiRegionToast,
        duration: const Duration(seconds: 4),
      );
    });
  }

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
            UINotifier.error(
              context,
              AppLocalizations.of(context).providerNotFound,
            );
            Navigator.of(context).pop();
          }
          return;
        }
        _loaded = p;
        _keys = await _svc.listProviderKeys(p.id!);
        _nameCtrl.text = p.name;
        _type = p.type;
        _baseUrlCtrl.text = p.baseUrl ?? '';
        _chatPathCtrl.text = p.chatPath ?? '/v1/chat/completions';
        final path = p.modelsPath.trim();
        if (path.isEmpty) {
          _modelsPathCtrl.text = defaultModelsPathForType(_type);
        } else {
          _modelsPathCtrl.text = path;
        }
        _useResponseApi = p.useResponseApi;
        _balanceEndpointType = p.balanceEndpointType;
        _balanceAutoDeleteZeroKey = p.balanceAutoDeleteZeroKey;
        _models = _aggregateKeyModels(_keys);
        if (_models.isEmpty) _models = List<String>.from(p.models);
        if (p.type == AIProviderTypes.azureOpenAI) {
          final v = (p.extra['azure_api_version'] as String?) ?? '2024-02-15';
          _azureApiVerCtrl.text = v;
        }
        if (p.type == AIProviderTypes.gemini) {
          _showGeminiRegionNotice();
        }
      } else {
        _applyTypeDefaults(AIProviderTypes.openai, initial: true);
      }
      unawaited(_loadModelMetadataFor(_models));
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
    _chatPathCtrl.dispose();
    _modelsPathCtrl.dispose();
    _azureApiVerCtrl.dispose();
    _modelInputCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.providerId == null
        ? AppLocalizations.of(context).createProviderTitle
        : AppLocalizations.of(context).editProviderTitle;
    final theme = Theme.of(context);
    final displayKeys = _displayKeys;

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
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      AppTheme.spacing4,
                      AppTheme.spacing4,
                      AppTheme.spacing4,
                      0,
                    ),
                    sliver: SliverList.list(
                      children: [
                        _buildProviderConfigCard(theme),
                        const SizedBox(height: AppTheme.spacing5),
                        _buildKeysHeaderCard(theme),
                      ],
                    ),
                  ),
                  if (_loaded != null && displayKeys.isNotEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.spacing4,
                      ),
                      sliver: SliverList.builder(
                        itemCount: displayKeys.length,
                        itemBuilder: (context, index) =>
                            _buildProviderKeyCard(displayKeys[index], index),
                      ),
                    ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      AppTheme.spacing4,
                      AppTheme.spacing4,
                      AppTheme.spacing4,
                      AppTheme.spacing4,
                    ),
                    sliver: SliverList.list(
                      children: [
                        _buildModelsCard(theme),
                        const SizedBox(height: AppTheme.spacing6),
                        _buildBottomActions(),
                        const SizedBox(height: AppTheme.spacing4),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
