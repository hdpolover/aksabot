/// Reusable form-field validators.
///
/// Each method returns `null` on success or an error message string on failure,
/// matching the signature expected by [TextFormField.validator].
abstract final class Validators {
  static final _emailRegex = RegExp(r'^[\w\-\.+]+@([\w-]+\.)+[\w-]{2,}$');

  static String? required(String? value, [String fieldName = 'This field']) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    return null;
  }

  static String? email(String? value) {
    final req = required(value, 'Email');
    if (req != null) return req;
    if (!_emailRegex.hasMatch(value!.trim())) {
      return 'Enter a valid email';
    }
    return null;
  }

  static String? password(String? value, {int minLength = 6}) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }
    if (value.length < minLength) {
      return 'Password must be at least $minLength characters';
    }
    return null;
  }

  static String? name(String? value) {
    return required(value, 'Name');
  }
}
