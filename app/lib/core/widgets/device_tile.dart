import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../theme/app_colors.dart';
import 'status_dot.dart';

/// Compact device tile for 2-column grid layouts.
///
/// Inspired by Google Home device tiles — shows icon, name, subtitle,
/// and tints the background based on device state (online = primary tint,
/// offline = neutral surface).
class DeviceTile extends StatelessWidget {
  final String name;
  final String? subtitle;
  final IconData icon;
  final bool isOnline;
  /// When non-null, shows a BLE presence badge next to the status dot.
  /// true = advertising (phone visible to device), false = not advertising.
  final bool? bleAdvertising;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const DeviceTile({
    super.key,
    required this.name,
    this.subtitle,
    this.icon = Icons.smart_toy_outlined,
    this.isOnline = false,
    this.bleAdvertising,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final appColors = theme.extension<AppColors>()!;

    // Semantic background: subtle primary tint when online, neutral when off
    final bgColor = isOnline
        ? colors.primaryContainer.withValues(alpha: 0.4)
        : colors.surfaceContainerHigh;

    final iconColor = isOnline
        ? colors.primary
        : colors.onSurfaceVariant;

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spacingLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon row with status dot
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isOnline
                          ? colors.primary.withValues(alpha: 0.15)
                          : colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                    ),
                    child: Icon(icon, color: iconColor, size: AppConstants.iconLg),
                  ),
                  const Spacer(),
                  if (bleAdvertising == true) ...
                    [
                      Icon(
                        Icons.sensors_rounded,
                        size: 13,
                        color: colors.primary,
                      ),
                      const SizedBox(width: 4),
                    ],
                  StatusDot(
                    variant: isOnline
                        ? StatusDotVariant.online
                        : StatusDotVariant.offline,
                    size: 10,
                  ),
                ],
              ),
              const SizedBox(height: AppConstants.spacingMd),

              // Name
              Text(
                name,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),

              // Subtitle (status text)
              if (subtitle != null) ...[
                const SizedBox(height: AppConstants.spacingXxs),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isOnline ? appColors.success : colors.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact tile for locally-provisioned devices (not yet backend-registered).
class LocalDeviceTile extends StatelessWidget {
  final String name;
  final String ssid;
  final bool hasIp;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const LocalDeviceTile({
    super.key,
    required this.name,
    required this.ssid,
    this.hasIp = false,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return DeviceTile(
      name: name,
      subtitle: hasIp ? 'On network' : ssid,
      icon: Icons.smart_toy_outlined,
      isOnline: hasIp,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}
