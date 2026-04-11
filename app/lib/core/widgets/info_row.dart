import 'package:flutter/material.dart';

import '../constants/app_constants.dart';

/// A compact label–value row with an optional leading icon.
class InfoRow extends StatelessWidget {
  final IconData? icon;
  final String label;
  final String value;

  const InfoRow({
    super.key,
    this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: AppConstants.iconSm, color: colors.onSurfaceVariant),
          const SizedBox(width: AppConstants.spacingSm),
        ],
        Text(
          '$label: ',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
