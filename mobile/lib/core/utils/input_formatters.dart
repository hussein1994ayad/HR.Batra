import 'package:flutter/services.dart';

import 'arabic_format.dart';

/// يكتب الأرقام بفواصل آلاف نقطية أثناء الإدخال (1500000 → 1.500.000)
/// مع الحفاظ على موضع المؤشر بين الأرقام.
class DotThousandsSeparatorInputFormatter extends TextInputFormatter {
  static final _digit = RegExp('[0-9]');

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;
    final digits = newValue.text.replaceAll(RegExp('[^0-9]'), '');
    if (digits.isEmpty) return newValue.copyWith(text: '');
    final parsed = double.tryParse(digits);
    if (parsed == null) return oldValue;

    final formatted = formatThousands(parsed);
    final cursor = newValue.selection.baseOffset.clamp(0, newValue.text.length);
    final digitsBeforeCursor = _digit.allMatches(newValue.text.substring(0, cursor)).length;

    var offset = 0;
    var seen = 0;
    while (seen < digitsBeforeCursor && offset < formatted.length) {
      if (_digit.hasMatch(formatted[offset])) seen++;
      offset++;
    }
    return TextEditingValue(text: formatted, selection: TextSelection.collapsed(offset: offset));
  }
}
