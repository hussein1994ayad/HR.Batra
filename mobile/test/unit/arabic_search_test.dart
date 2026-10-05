import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/core/utils/arabic_format.dart';

void main() {
  test('normalizeArabicForSearch unifies letter forms and strips diacritics', () {
    expect(normalizeArabicForSearch('  أحمد إبراهيم '), 'احمد ابراهيم');
    expect(normalizeArabicForSearch('فاطمة'), 'فاطمه');
    expect(normalizeArabicForSearch('مُصْطَفى'), 'مصطفي');
    expect(normalizeArabicForSearch('مسؤول هيئة'), 'مسوول هييه');
    expect(normalizeArabicForSearch('ABC'), 'abc');
  });
}
