// =========================================================================
// HR Pro v6.0 - Unit tests for attendance punch handling and OTA safety
// =========================================================================

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/core/constants/constants.dart';
import 'package:hr_pro/core/services/attendance_sync_service.dart';
import 'package:hr_pro/core/services/ota_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('AttendanceSyncService.isNetworkError', () {
    test('server replies are not network errors (never queued offline)', () {
      expect(
        AttendanceSyncService.isNetworkError(
          const PostgrestException(message: 'هذا الجهاز غير معتمد للبصمة'),
        ),
        isFalse,
      );
      expect(AttendanceSyncService.isNetworkError(const AuthException('expired')), isFalse);
    });

    test('transport failures are network errors (queued offline)', () {
      expect(AttendanceSyncService.isNetworkError(const SocketException('no route')), isTrue);
      expect(AttendanceSyncService.isNetworkError(TimeoutException('slow')), isTrue);
    });
  });

  group('PunchResult', () {
    test('saved result carries server status and offline flag', () {
      final r = PunchResult.saved({'ok': true, 'status': 'late', 'offline': true});
      expect(r.ok, isTrue);
      expect(r.status, 'late');
      expect(r.offline, isTrue);
      expect(r.queued, isFalse);
    });

    test('rejected result keeps the server code and message', () {
      final r = PunchResult.rejected('out_of_range', 'أنت خارج نطاق الفرع');
      expect(r.ok, isFalse);
      expect(r.code, 'out_of_range');
      expect(r.message, contains('خارج'));
    });

    test('queued result is marked offline', () {
      const r = PunchResult.queued();
      expect(r.ok, isTrue);
      expect(r.queued, isTrue);
      expect(r.offline, isTrue);
    });
  });

  group('OtaService.isTrustedDownloadUrl', () {
    final host = Uri.parse(AppConstants.supabaseUrl).host;
    final bucketUrl = 'https://$host/storage/v1/object/public/ota-updates/hr-pro-1.0.3.apk';

    test('accepts APKs from the project ota-updates bucket on Android', () {
      expect(OtaService.isTrustedDownloadUrl(bucketUrl, isIOS: false), isTrue);
    });

    test('rejects other hosts, other buckets and plain http', () {
      expect(OtaService.isTrustedDownloadUrl('https://evil.example.com/app.apk', isIOS: false), isFalse);
      expect(
        OtaService.isTrustedDownloadUrl(
          'https://$host/storage/v1/object/public/avatars/app.apk',
          isIOS: false,
        ),
        isFalse,
      );
      expect(OtaService.isTrustedDownloadUrl(bucketUrl.replaceFirst('https', 'http'), isIOS: false), isFalse);
      expect(OtaService.isTrustedDownloadUrl('', isIOS: false), isFalse);
    });

    test('iOS only allows App Store and TestFlight links', () {
      expect(OtaService.isTrustedDownloadUrl('https://apps.apple.com/app/id123', isIOS: true), isTrue);
      expect(OtaService.isTrustedDownloadUrl('https://testflight.apple.com/join/abc', isIOS: true), isTrue);
      expect(OtaService.isTrustedDownloadUrl(bucketUrl, isIOS: true), isFalse);
    });
  });
}
