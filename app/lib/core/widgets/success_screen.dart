import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../theme/app_colors.dart';

/// Full-screen success state used at the end of provisioning flows.
class SuccessScreen extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? hint;
  final String buttonLabel;
  final VoidCallback onPressed;

  const SuccessScreen({
    super.key,
    required this.title,
    required this.subtitle,
    this.hint,
    this.buttonLabel = 'Done',
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final appColors = theme.extension<AppColors>()!;

    return Padding(
      padding: const EdgeInsets.all(AppConstants.spacingXxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: appColors.successContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check_rounded,
              size: 40,
              color: appColors.success,
            ),
          ),
          const SizedBox(height: AppConstants.spacingXxl),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: AppConstants.spacingSm),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: AppConstants.spacingLg),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spacingMd,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: colors.secondaryContainer,
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusFull),
                ),
                child: Text(
                  hint!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSecondaryContainer,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: AppConstants.spacingHuge),
          FilledButton(
            onPressed: onPressed,
            child: Text(buttonLabel),
          ),
        ],
      ),
    );
  }
}
