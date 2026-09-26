import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// نص خطأ مفهوم للمستخدم: رسائل السيرفر العربية كما هي، والشبكة برسالة واضحة.
String errorText(Object error) {
  if (error is PostgrestException) return error.message;
  if (error is AuthException) return error.message;
  if (error is StorageException) return error.message;
  if (error is SocketException || error is TimeoutException) return 'لا يوجد اتصال بالإنترنت، حاول مرة ثانية.';
  return 'حدث خطأ غير متوقع، حاول مرة ثانية.';
}
