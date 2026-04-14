import 'package:flutter/material.dart';

/// Shared dialog helper. Use [AppDialog.confirm] for any destructive or
/// confirmable action.
abstract class AppDialog {
  /// Shows a confirmation dialog and returns `true` if the user confirmed,
  /// `false` or `null` if they cancelled.
  ///
  /// Buttons are laid out in the content (not actions) to avoid OverflowBar
  /// stacking: full-width FilledButton for the primary action, TextButton
  /// for cancel centred below it.
  ///
  /// [icon] is optional — shown above the title when provided.
  /// [iconColor] defaults to [ColorScheme.primary].
  /// [destructive] colours the confirm button with [ColorScheme.error].
  static Future<bool?> confirm(
    BuildContext context, {
    required String title,
    required String body,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    IconData? icon,
    Color? iconColor,
    bool destructive = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final theme = Theme.of(ctx);
        return AlertDialog(
          icon: icon != null
              ? Icon(icon, color: iconColor ?? cs.primary)
              : null,
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(body, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 24),
              FilledButton(
                style: destructive
                    ? FilledButton.styleFrom(backgroundColor: cs.error)
                    : null,
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(confirmLabel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(cancelLabel),
              ),
            ],
          ),
        );
      },
    );
  }
}
