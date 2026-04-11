import 'package:flutter/material.dart';

import '../constants/app_constants.dart';

/// Horizontal segmented progress bar for multi-step flows.
class StepProgressBar extends StatelessWidget {
  final int current;
  final int total;

  const StepProgressBar({super.key, required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacingXxl,
        vertical: AppConstants.spacingMd,
      ),
      child: Row(
        children: List.generate(total, (index) {
          final active = index <= current;
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(
                right: index < total - 1 ? AppConstants.spacingXs : 0,
              ),
              height: 4,
              decoration: BoxDecoration(
                color: active ? colors.primary : colors.outlineVariant,
                borderRadius: BorderRadius.circular(AppConstants.spacingXxs),
              ),
            ),
          );
        }),
      ),
    );
  }
}
