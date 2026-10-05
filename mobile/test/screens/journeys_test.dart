// رحلات المستخدم محلياً بأسلوب الآيفون (Cupertino، سحب الرجوع، الكيبورد) على مقاسات آيفون حقيقية،
// وعلى أندرويد كمرجع. نفس الرحلات تنشغل على المحاكي بـ integration_test/user_journeys_test.dart.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import '../support/fake_backend.dart';
import '../support/journeys.dart';

class _Device {
  const _Device(this.name, this.width, this.height, this.top, this.bottom, this.platform);
  final String name;
  final double width, height, top, bottom;
  final TargetPlatform platform;
}

const _devices = [
  _Device('iphone_pro_island', 402, 874, 62, 34, TargetPlatform.iOS),
  _Device('iphone_se', 375, 667, 20, 0, TargetPlatform.iOS),
  _Device('ipad', 834, 1194, 24, 20, TargetPlatform.iOS),
  _Device('android', 412, 915, 24, 16, TargetPlatform.android),
];

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final device in _devices) {
    for (final j in kJourneys) {
      testWidgets('${device.name}: ${j.name}', (tester) async {
        await tester.runAsync(FakeBackend.ensureInitialized);
        const dpr = 3.0;
        tester.view
          ..devicePixelRatio = dpr
          ..physicalSize = Size(device.width, device.height) * dpr
          ..padding = FakeViewPadding(top: device.top * dpr, bottom: device.bottom * dpr)
          ..viewPadding = FakeViewPadding(top: device.top * dpr, bottom: device.bottom * dpr);
        addTearDown(tester.view.reset);
        debugDefaultTargetPlatformOverride = device.platform;
        try {
          await runJourney(tester, j, (_) async {});
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }
}
