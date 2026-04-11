import 'package:flutter/material.dart';

/// Semantic colors not covered by Material's [ColorScheme].
///
/// Access via `Theme.of(context).extension<AppColors>()!`.
class AppColors extends ThemeExtension<AppColors> {
  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;

  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;

  final Color info;
  final Color onInfo;
  final Color infoContainer;
  final Color onInfoContainer;

  const AppColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.info,
    required this.onInfo,
    required this.infoContainer,
    required this.onInfoContainer,
  });

  // -- Light palette (vibrant, bold) --
  static const light = AppColors(
    success: Color(0xFF059669),
    onSuccess: Colors.white,
    successContainer: Color(0xFFD1FAE5),
    onSuccessContainer: Color(0xFF064E32),
    warning: Color(0xFFEA580C),
    onWarning: Colors.white,
    warningContainer: Color(0xFFFFF7ED),
    onWarningContainer: Color(0xFF7C2D12),
    info: Color(0xFF2563EB),
    onInfo: Colors.white,
    infoContainer: Color(0xFFEFF6FF),
    onInfoContainer: Color(0xFF1E3A5F),
  );

  // -- Dark palette (punchy, high contrast) --
  static const dark = AppColors(
    success: Color(0xFF34D399),
    onSuccess: Color(0xFF052E14),
    successContainer: Color(0xFF065F46),
    onSuccessContainer: Color(0xFFA7F3D0),
    warning: Color(0xFFFB923C),
    onWarning: Color(0xFF431407),
    warningContainer: Color(0xFF9A3412),
    onWarningContainer: Color(0xFFFED7AA),
    info: Color(0xFF60A5FA),
    onInfo: Color(0xFF0C1C36),
    infoContainer: Color(0xFF1E40AF),
    onInfoContainer: Color(0xFFBFDBFE),
  );

  @override
  AppColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? info,
    Color? onInfo,
    Color? infoContainer,
    Color? onInfoContainer,
  }) {
    return AppColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      info: info ?? this.info,
      onInfo: onInfo ?? this.onInfo,
      infoContainer: infoContainer ?? this.infoContainer,
      onInfoContainer: onInfoContainer ?? this.onInfoContainer,
    );
  }

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer: Color.lerp(successContainer, other.successContainer, t)!,
      onSuccessContainer:
          Color.lerp(onSuccessContainer, other.onSuccessContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      warningContainer: Color.lerp(warningContainer, other.warningContainer, t)!,
      onWarningContainer:
          Color.lerp(onWarningContainer, other.onWarningContainer, t)!,
      info: Color.lerp(info, other.info, t)!,
      onInfo: Color.lerp(onInfo, other.onInfo, t)!,
      infoContainer: Color.lerp(infoContainer, other.infoContainer, t)!,
      onInfoContainer: Color.lerp(onInfoContainer, other.onInfoContainer, t)!,
    );
  }
}
