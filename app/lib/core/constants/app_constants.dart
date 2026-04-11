/// App-wide constants — single source of truth for sizing, spacing, durations,
/// and string keys used across the app.
abstract final class AppConstants {
  // -- App info --
  static const String appName = 'Aksabot';

  // -- Spacing (used for padding, margins, gaps) --
  static const double spacingXxs = 2;
  static const double spacingXs = 4;
  static const double spacingSm = 8;
  static const double spacingMd = 12;
  static const double spacingLg = 16;
  static const double spacingXl = 20;
  static const double spacingXxl = 24;
  static const double spacingXxxl = 32;
  static const double spacingHuge = 40;
  static const double spacingMassive = 48;

  // -- Border radius --
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 20;
  static const double radiusFull = 999;

  // -- Icon sizes --
  static const double iconSm = 16;
  static const double iconMd = 20;
  static const double iconLg = 24;
  static const double iconXl = 32;
  static const double iconXxl = 48;
  static const double iconHuge = 64;
  static const double iconMassive = 80;

  // -- Component sizes --
  static const double buttonHeight = 48;
  static const double avatarSm = 32;
  static const double avatarMd = 48;
  static const double avatarLg = 56;
  static const double statusDotSize = 8;

  // -- Durations --
  static const Duration animFast = Duration(milliseconds: 150);
  static const Duration animNormal = Duration(milliseconds: 300);
  static const Duration animSlow = Duration(milliseconds: 500);
  static const Duration snackBarDuration = Duration(seconds: 4);

  // -- Network --
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 30);
}
