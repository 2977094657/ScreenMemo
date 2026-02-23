import 'package:flutter/material.dart';
import '../services/ime_exclusion_service.dart';
import '../theme/app_theme.dart';

class ExclusionHelpPage extends StatefulWidget {
  const ExclusionHelpPage({super.key});

  @override
  State<ExclusionHelpPage> createState() => _ExclusionHelpPageState();
}

class _ExclusionHelpPageState extends State<ExclusionHelpPage> {
  List<Map<String, String>> _imeList = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await ImeExclusionService.getEnabledImeList();
      if (!mounted) return;
      setState(() {
        _imeList = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('已排除的应用')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppTheme.spacing4),
              children: [
                Text(
                  '以下应用会被排除，不可选择：',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: AppTheme.spacing3),
                const Text('· 本应用（避免自循环）'),
                const SizedBox(height: AppTheme.spacing3),
                const Text('· 输入法（键盘）应用：'),
                const SizedBox(height: AppTheme.spacing2),
                if (_imeList.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(left: AppTheme.spacing2),
                    child: Text('  - （已自动过滤）'),
                  )
                else ...[
                  for (final m in _imeList)
                    Padding(
                      padding: const EdgeInsets.only(left: AppTheme.spacing2, bottom: 6),
                      child: Text('  - ${((m['appName'] ?? '').trim().isNotEmpty) ? (m['appName'] ?? '') : '未知输入法'}'),
                    ),
                ],
              ],
            ),
    );
  }
}
