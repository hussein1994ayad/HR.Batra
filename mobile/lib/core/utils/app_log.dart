// سجلات التطبيق التشخيصية — مكان واحد لكل الرسائل بدل debugPrint المتفرق.
// حالياً تطبع نفس الشي بالضبط مثل debugPrint (نفس الرسالة ونفس التقطيع)؛
// إذا احتجنا لاحقاً أداة سجلات أو إرسال الأخطاء لخدمة خارجية، يتغير هنا فقط.

import 'package:flutter/foundation.dart';

void appLog(String? message) => debugPrint(message);
