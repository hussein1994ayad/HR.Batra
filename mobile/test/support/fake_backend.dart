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
    if (path.startsWith('/storage/v1/bucket')) {
      return http.Response('[]', 200, headers: _json);
    }
    return http.Response('{}', 200, headers: _json);
  }

  static http.Response _rest(http.Request req, String table) {
    if (req.method != 'GET' && req.method != 'HEAD') {
      final body = req.body.isEmpty ? null : jsonDecode(req.body);
      final echo = body is List ? body : (body == null ? <Object?>[] : [body]);
      return http.Response(jsonEncode(echo), 201, headers: _json);
    }
    var rows = List<Map<String, dynamic>>.from(tables[table] ?? const []);
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
      anonKey: 'test-anon-key',
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
      'id.flutter/background_service_ios',
      'com.llfbandit.app_links/messages',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
        if (call.method == 'getAll') return <String, dynamic>{};
        if (call.method == 'checkPermission' || call.method == 'checkPermissionStatus') return 1;
        return null;
      });
    }
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
