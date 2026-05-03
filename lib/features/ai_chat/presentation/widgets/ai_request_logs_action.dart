import 'dart:async';

typedef AIRequestLogsActionHandler = FutureOr<void> Function();

class AIRequestLogsAction {
  const AIRequestLogsAction({
    required this.label,
    required this.onPressed,
    this.enabled = true,
  });

  final String label;
  final AIRequestLogsActionHandler onPressed;
  final bool enabled;
}
