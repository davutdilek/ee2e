import 'package:flutter/material.dart';

import '../core/connection_status.dart';

class ConnectionIndicator extends StatelessWidget {
  const ConnectionIndicator({super.key, required this.status});

  final ConnectionStatus status;

  Color _color(BuildContext context) {
    switch (status) {
      case ConnectionStatus.online:
        return Colors.green;
      case ConnectionStatus.connecting:
      case ConnectionStatus.reconnecting:
        return Colors.amber;
      case ConnectionStatus.failed:
        return Theme.of(context).colorScheme.error;
      case ConnectionStatus.offline:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color(context);
    final isWorking = status == ConnectionStatus.connecting ||
        status == ConnectionStatus.reconnecting;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 12,
          height: 12,
          child: isWorking
              ? CircularProgressIndicator(strokeWidth: 2, color: color)
              : DecoratedBox(
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
        ),
        const SizedBox(width: 8),
        Text(status.label, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}
