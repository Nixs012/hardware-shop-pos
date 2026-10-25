class MpesaUtils {
  /// Regular expression for a valid 10-character alphanumeric M-Pesa transaction code.
  static final RegExp _validCodeRegex = RegExp(r'^[A-Z0-9]{10}$');
  static final RegExp _allowedCharsRegex = RegExp(r'^[A-Z0-9]+$');

  /// Cleans the input: strips all spaces, converts to uppercase, and truncates to 10 chars.
  static String sanitizeCode(String? input) {
    if (input == null) return '';
    final cleaned = input.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    if (cleaned.length > 10) {
      return cleaned.substring(0, 10);
    }
    return cleaned;
  }

  /// Returns true if [code] is exactly 10 uppercase letters and digits.
  static bool isValidCode(String? code) {
    if (code == null) return false;
    final cleaned = code.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    return _validCodeRegex.hasMatch(cleaned);
  }

  /// Returns a user-friendly error message if [code] is invalid, or null if valid.
  static String? getValidationError(String? code) {
    if (code == null || code.trim().isEmpty) {
      return 'M-Pesa transaction code is required.';
    }
    final cleaned = code.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    if (!_allowedCharsRegex.hasMatch(cleaned)) {
      return 'Code must contain only letters and numbers.';
    }
    if (cleaned.length < 10) {
      return 'Code must be exactly 10 characters (${cleaned.length}/10 entered).';
    }
    if (cleaned.length > 10) {
      return 'Code cannot exceed 10 characters.';
    }
    return null;
  }
}
