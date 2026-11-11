// The corner radii used to live here; they are with the other shapes now.
export 'app_shapes.dart' show AppRadius;

/// The spacing scale. Every gap and padding in the app is one of these.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}
