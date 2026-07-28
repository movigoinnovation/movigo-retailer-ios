import 'package:flutter/services.dart';

/// Normalises any pasted phone number to a clean 10-digit Indian mobile number.
///
/// Handles:
///   +91 94259 50621  →  9425950621
///   91-9425950621    →  9425950621
///   09425950621      →  9425950621
///   9425950621       →  9425950621 (no change)
class PhoneNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Strip everything that isn't a digit
    String digits = newValue.text.replaceAll(RegExp(r'[^\d]'), '');

    // Strip country code variants
    if (digits.length == 12 && digits.startsWith('91')) {
      digits = digits.substring(2); // +91XXXXXXXXXX
    } else if (digits.length == 13 && digits.startsWith('091')) {
      digits = digits.substring(3); // 091XXXXXXXXXX
    } else if (digits.length == 11 && digits.startsWith('0')) {
      digits = digits.substring(1); // 0XXXXXXXXXX
    }

    // Hard-cap at 10 digits — take rightmost 10 if somehow still longer
    if (digits.length > 10) {
      digits = digits.substring(digits.length - 10);
    }

    return TextEditingValue(
      text: digits,
      selection: TextSelection.collapsed(offset: digits.length),
    );
  }
}
