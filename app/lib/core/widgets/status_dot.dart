import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../theme/app_colors.dart';

/// A small circular indicator for online/offline/warning status.
class StatusDot extends StatelessWidget {
  final StatusDotVariant variant;
  final double size;

  const StatusDot({
    super.key,
    required this.variant,
    this.size = AppConstants.statusDotSize,
  });

  const StatusDot.online({super.key, this.size = AppConstants.statusDotSize})
      : variant = StatusDotVariant.online;

  const StatusDot.offline({super.key, this.size = AppConstants.statusDotSize})
      : variant = StatusDotVariant.offline;

  const StatusDot.warning({super.key, this.size = AppConstants.statusDotSize})
      : variant = StatusDotVariant.warning;

  @override
  Widget build(BuildContext context) {
    final appColors = Theme.of(context).extension<AppColors>()!;
    final colors = Theme.of(context).colorScheme;

    final Color color;
    switch (variant) {
      case StatusDotVariant.online:
        color = appColors.success;
      case StatusDotVariant.offline:
        color = colors.outline;
      case StatusDotVariant.warning:
        color = appColors.warning;
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

enum StatusDotVariant { online, offline, warning }
