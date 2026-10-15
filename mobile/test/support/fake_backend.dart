// خادم Supabase وهمي داخل الذاكرة للاختبارات — يرد على REST/RPC/Storage/Auth
// من بيانات fixtures.dart، ولا يتصل بالإنترنت أبداً.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/core/services/auth_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fixtures.dart';

/// حالة الخادم الوهمي — يمكن للاختبار تبديل الجداول أو جعل كل طلب يفشل.
class FakeBackend {
  FakeBackend._();

  static Map<String, List<Map<String, dynamic>>> tables = buildFixtures();
  static bool failAll = false;
  static final List<String> requests = [];
  static bool _initialized = false;

  static void reset({String role = 'admin', bool fail = false}) {
    tables = buildFixtures(role: role);
    failAll = fail;
    requests.clear();
    AuthService.currentUserRole = role;
  }

  static Future<http.Response> _handle(http.Request req) async {
    final res = await _route(req);
    return http.Response.bytes(res.bodyBytes, res.statusCode, headers: res.headers, request: req);
  }

  static Future<http.Response> _route(http.Request req) async {
    final path = req.url.path;
    requests.add('${req.method} $path');
    if (failAll && !path.startsWith('/auth/')) {
      return http.Response(jsonEncode({'message': 'offline'}), 500, headers: _json);
    }
    // مبالغ الحركات وأجر اليوم للأدمن بس (تدقيق 14/10: المبالغ تكشف الراتب)
    if (path == '/rest/v1/rpc/get_payroll_event_amounts') {
      final rows = AuthService.currentUserRole != 'admin'
          ? const <Map<String, dynamic>>[]
          : [
              for (final e in tables['payroll_events'] ?? const <Map<String, dynamic>>[])
                {'event_id': e['id'], 'employee_id': e['employee_id'], 'event_date': e['event_date'], 'event_type': e['event_type'], 'amount': e['amount']},
            ];
      return http.Response(jsonEncode(rows), 200, headers: _json);
    }
    if (path == '/rest/v1/rpc/payroll_day_rates' && AuthService.currentUserRole != 'admin') {
      return http.Response('[]', 200, headers: _json);
    }
    if (path == '/rest/v1/rpc/get_employee_pay' && !tables.containsKey('rpc:get_employee_pay')) {
      return http.Response(jsonEncode(_employeePay()), 200, headers: _json);
    }
    if (path.startsWith('/rest/v1/rpc/')) {
      final rows = tables['rpc:${path.substring('/rest/v1/rpc/'.length)}'];
      // RPC يرجع كائناً واحداً (jsonb): صف واحد فيه '__single'
      if (rows != null && rows.length == 1 && rows.first.containsKey('__single')) {
        return http.Response(jsonEncode({...rows.first}..remove('__single')), 200, headers: _json);
      }
      return http.Response(rows == null ? 'null' : jsonEncode(rows), 200, headers: _json);
    }
    if (path.startsWith('/rest/v1/')) {
      return _rest(req, path.substring('/rest/v1/'.length));
    }
    if (path.startsWith('/auth/v1/user')) {
      return http.Response(jsonEncode(_user), 200, headers: _json);
    }
    if (path.startsWith('/storage/v1/object/list')) {
      return http.Response('[]', 200, headers: _json);
    }
    // رفع ملف (صورة التعهد، المرفقات): نفس شكل رد Supabase
    if (req.method == 'POST' && path.startsWith('/storage/v1/object/') && !path.startsWith('/storage/v1/object/sign')) {
      return http.Response(jsonEncode({'Key': path.substring('/storage/v1/object/'.length), 'Id': 'fake-object'}), 200, headers: _json);
    }
    if (path.startsWith('/storage/v1/bucket')) {
      return http.Response('[]', 200, headers: _json);
    }
    return http.Response('{}', 200, headers: _json);
  }

  // مثل السيرفر (تدقيق 14/10/2026، BUG-005): أعمدة الراتب ما تنقرا من جدول الموظفين، تنقرا من get_employee_pay
  static const _salaryColumns = {'monthly_salary_iqd', 'future_salary_iqd', 'future_salary_month'};

  static const _eventMoneyColumns = {'amount', 'amount_override', 'daily_rate', 'minute_rate'};

  static bool _readsSalary(String select, [Set<String> hidden = _salaryColumns]) => select
      .replaceAll(RegExp(r'([^()]*)'), '')
      .split(',')
      .map((c) => c.trim())
      .any((c) => c == '*' || hidden.contains(c));

  /// الأدمن: رواتب الكل. غيره: راتبه هو بس.
  static List<Map<String, dynamic>> _employeePay() => [
        for (final e in tables['employees'] ?? const <Map<String, dynamic>>[])
          if (AuthService.currentUserRole == 'admin' || e['id'] == kTestUserId)
            {
              'employee_id': e['id'],
              for (final k in _salaryColumns) k: e[k],
            },
      ];

  static http.Response _rest(http.Request req, String table) {
    if (req.method != 'GET' && req.method != 'HEAD') {
      final body = req.body.isEmpty ? null : jsonDecode(req.body);
      // الحذف بدون جسم: يرجع سطر محذوف (مثل return=representation) حتى «ما تغيّر شي» ما يطلع بالغلط
      final echo = body is List ? body : (body == null ? <Object?>[if (req.method == 'DELETE') {'id': 'deleted'}] : [body]);
      return http.Response(jsonEncode(echo), 201, headers: _json);
    }
    if ((table == 'employees' && _readsSalary(req.url.queryParameters['select'] ?? '*')) ||
        (table == 'payroll_events' && _readsSalary(req.url.queryParameters['select'] ?? '*', _eventMoneyColumns))) {
      return http.Response(jsonEncode({'code': '42501', 'message': 'permission denied for table $table'}), 401, headers: _json);
    }
    var rows = List<Map<String, dynamic>>.from(tables[table] ?? const []);
    if (table == 'employees') {
      rows = [for (final r in rows) {for (final e in r.entries) if (!_salaryColumns.contains(e.key)) e.key: e.value}];
    }
    req.url.queryParameters.forEach((key, value) {
      if (const {'select', 'order', 'limit', 'offset', 'or', 'and'}.contains(key)) return;
      if (value.startsWith('eq.')) {
        final v = value.substring(3);
        rows = rows.where((r) => !r.containsKey(key) || '${r[key]}' == v).toList();
      } else if (value.startsWith('in.(')) {
        final set = value.substring(4, value.length - 1).split(',').map((s) => s.replaceAll('"', '')).toSet();
        rows = rows.where((r) => !r.containsKey(key) || set.contains('${r[key]}')).toList();
      } else if (value == 'is.null') {
        rows = rows.where((r) => r[key] == null).toList();
      }
    });
    final limit = int.tryParse(req.url.queryParameters['limit'] ?? '');
    if (limit != null && rows.length > limit) rows = rows.take(limit).toList();
    final headers = {..._json, 'content-range': '0-${rows.isEmpty ? 0 : rows.length - 1}/${rows.length}'};
    final wantsObject = (req.headers['Accept'] ?? req.headers['accept'] ?? '').contains('vnd.pgrst.object');
    if (wantsObject) {
      if (rows.isEmpty) {
        return http.Response(jsonEncode({'code': 'PGRST116', 'message': 'no rows'}), 406, headers: _json);
      }
      return http.Response(jsonEncode(rows.first), 200, headers: headers);
    }
    return http.Response(jsonEncode(rows), 200, headers: headers);
  }

  static const _json = {'content-type': 'application/json; charset=utf-8'};

  static final Map<String, dynamic> _user = {
    'id': kTestUserId,
    'aud': 'authenticated',
    'role': 'authenticated',
    'email': 'E-001@batra.test',
    'app_metadata': {'provider': 'email'},
    'user_metadata': <String, dynamic>{},
    'created_at': '2025-03-01T00:00:00Z',
  };

  static String _fakeJwt() {
    String b64(Map<String, dynamic> m) => base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
    return '${b64({'alg': 'HS256', 'typ': 'JWT'})}.${b64({'sub': kTestUserId, 'exp': 4102444800, 'role': 'authenticated'})}.sig';
  }

  /// يهيّئ Supabase مرة واحدة بعميل HTTP وهمي وجلسة مستخدم مسجّل.
  static Future<void> ensureInitialized() async {
    _mockPlatformChannels();
    if (_initialized) return;
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://fake.supabase.test',
      publishableKey: 'test-anon-key',
      httpClient: MockClient(_handle),
      debug: false,
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
        autoRefreshToken: false,
        detectSessionInUri: false,
      ),
    );
    await Supabase.instance.client.auth.setInitialSession(jsonEncode({
      'access_token': _fakeJwt(),
      'token_type': 'bearer',
      'expires_in': 3600,
      'expires_at': 4102444800,
      'refresh_token': 'fake-refresh',
      'user': _user,
    }));
    _initialized = true;
  }

  /// قنوات المنصّة (الموقع، الجهاز، الإشعارات...) ترجع null في الاختبار بدل الاستثناء.
  static void _mockPlatformChannels() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final name in const [
      'flutter.baseflow.com/geolocator',
      'flutter.baseflow.com/geolocator_android',
      'flutter.baseflow.com/geolocator_apple',
      'flutter.baseflow.com/permissions/methods',
      'dev.fluttercommunity.plus/device_info',
      'dev.fluttercommunity.plus/package_info',
      'dexterous.com/flutter/local_notifications',
      'plugins.flutter.io/path_provider',
      'plugins.flutter.io/firebase_messaging',
      'id.flutter/background_service',
      'id.flutter/background_service_android',
      'com.llfbandit.app_links/messages',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
        if (call.method == 'getAll') return <String, dynamic>{};
        if (call.method == 'checkPermission' || call.method == 'checkPermissionStatus') return 1;
        return null;
      });
    }
    // مكتبة خدمة الخلفية بالآيفون تستعمل JSON (بالترميز العادي ترجع "Message corrupted" على المحاكي)
    messenger.setMockMethodCallHandler(const MethodChannel('id.flutter/background_service_ios', JSONMethodCodec()), (call) async => null);
    for (final name in const [
      'flutter.baseflow.com/geolocator_updates',
      'flutter.baseflow.com/geolocator_updates_android',
      'flutter.baseflow.com/geolocator_updates_apple',
      'flutter.baseflow.com/geolocator_service_updates',
      'flutter.baseflow.com/geolocator_service_updates_android',
      'flutter.baseflow.com/geolocator_service_updates_apple',
    ]) {
      messenger.setMockStreamHandler(EventChannel(name), MockStreamHandler.inline(onListen: (_, __) {}));
    }
  }
}
