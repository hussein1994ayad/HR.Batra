// روابط المستمسكات: أي شكل غير قائمة (كائن {} بعد التصفير، null) = قائمة فارغة، والشاشات ما توكف.

import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/core/models/models.dart';

void main() {
  test('strings() reads a list and tolerates anything else', () {
    expect(<String, dynamic>{'d': ['a', 'b']}.strings('d'), ['a', 'b']);
    expect(<String, dynamic>{'d': <String, dynamic>{}}.strings('d'), isEmpty);
    expect(<String, dynamic>{'d': null}.strings('d'), isEmpty);
    expect(<String, dynamic>{}.strings('d'), isEmpty);
  });

  test('an employee whose documents were stored as {} still loads', () {
    final e = ManagedEmployee.fromMap(<String, dynamic>{'id': 'e1', 'full_name': 'مدير النظام', 'role': 'admin', 'document_urls': <String, dynamic>{}});
    expect(e.documentUrls, isEmpty);
  });
}
