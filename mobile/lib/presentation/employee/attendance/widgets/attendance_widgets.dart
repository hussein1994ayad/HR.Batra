// أجزاء عرض شاشة البصمة: خريطة الفرع، كارت الموقع والمسافة، وكارت دوام اليوم.
// كلها عرض فقط؛ الحالة ومنطق البصمة باقيين بالشاشة.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/services/precise_location.dart';
import '../../../shared/ui/ui.dart';

/// خريطة الفرع: دائرة النطاق + علامة الفرع + موقع الموظف الحالي.
class AttendanceBranchMap extends StatelessWidget {
  const AttendanceBranchMap({
    super.key,
    required this.mapController,
    required this.branchLat,
    required this.branchLng,
    required this.branchRadius,
    required this.branchName,
    required this.currentPosition,
  });

  final MapController mapController;
  final double branchLat;
  final double branchLng;
  final double branchRadius;
  final String branchName;
  final Position? currentPosition;

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: mapController,
      options: MapOptions(initialCenter: LatLng(branchLat, branchLng), initialZoom: 15.0, backgroundColor: AppColors.surface1),
      children: [
        appMapTiles(),
        CircleLayer(
          circles: [
            CircleMarker(
              point: LatLng(branchLat, branchLng),
              color: AppColors.brand.withValues(alpha: 0.14),
              borderStrokeWidth: 2,
              borderColor: AppColors.brand,
              useRadiusInMeter: true,
              radius: branchRadius,
            ),
          ],
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: LatLng(branchLat, branchLng),
              width: 44,
              height: 44,
              child: Semantics(
                label: 'موقع $branchName',
                child: Container(
                  decoration: BoxDecoration(color: AppColors.brand, shape: BoxShape.circle, border: Border.all(color: AppColors.bg, width: 3)),
                  child: const Icon(Icons.business_rounded, color: AppColors.onBrand, size: 20),
                ),
              ),
            ),
            if (currentPosition != null)
              Marker(
                point: LatLng(currentPosition!.latitude, currentPosition!.longitude),
                width: 28,
                height: 28,
                child: Semantics(
                  label: 'موقعك الحالي',
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.info,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.textPrimary, width: 3),
                      boxShadow: AppElevation.low,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// اسم الفرع، المسافة عنه، دقة GPS، وحالة النطاق.
class AttendanceLocationCard extends StatelessWidget {
  const AttendanceLocationCard({
    super.key,
    required this.branchName,
    required this.branchRadius,
    required this.currentPosition,
    required this.distanceToBranch,
    required this.inRange,
    required this.mockDetected,
  });

  final String branchName;
  final double branchRadius;
  final Position? currentPosition;
  final double? distanceToBranch;
  final bool inRange;
  final bool mockDetected;

  @override
  Widget build(BuildContext context) {
    final tone = mockDetected
        ? AppTone.danger
        : currentPosition == null
            ? AppTone.neutral
            : inRange
                ? AppTone.success
                : AppTone.warning;
    final label = mockDetected
        ? 'موقع مزيّف'
        : currentPosition == null
            ? 'بلا موقع'
            : inRange
                ? 'داخل النطاق'
                : 'خارج النطاق';
    final distanceText = distanceToBranch == null
        ? 'بانتظار إشارة GPS'
        : inRange
            ? 'تبعد ${distanceToBranch!.round()} م عن الفرع'
            : 'باقي ${(distanceToBranch! - branchRadius).round()} م للدخول بالنطاق';
    return AppCard(
      child: Row(
        children: [
          ToneIcon(inRange ? Icons.where_to_vote_rounded : Icons.location_searching_rounded, tone: tone, size: 48),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(branchName, style: AppText.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(distanceText, style: AppText.bodySm),
                if (currentPosition != null)
                  Text('دقة GPS: ${currentPosition!.accuracy.round()} م · النطاق ${branchRadius.round()} م', style: AppText.caption),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          StatusBadge(label, tone: tone, dot: true),
        ],
      ),
    );
  }
}

/// حضور وانصراف اليوم + الدوام المعتمد للموظف.
class AttendanceTodayCard extends StatelessWidget {
  const AttendanceTodayCard({super.key, required this.todayAttendance, required this.workSchedule});

  final Map<String, dynamic>? todayAttendance;
  final Map<String, dynamic>? workSchedule;

  @override
  Widget build(BuildContext context) {
    DateTime? parse(Object? v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
    final hasCheckIn = todayAttendance?['check_in_time'] != null;
    final hasCheckOut = todayAttendance?['check_out_time'] != null;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('اليوم · ${Fmt.dateWithDay(DateTime.now())}', style: AppText.label),
          const SizedBox(height: AppSpace.sm),
          KeyValueRow('الحضور', hasCheckIn ? Fmt.time(parse(todayAttendance!['check_in_time'])) : '--:--', icon: Icons.login_rounded),
          KeyValueRow('الانصراف', hasCheckOut ? Fmt.time(parse(todayAttendance!['check_out_time'])) : '--:--', icon: Icons.logout_rounded),
          if (workSchedule != null)
            KeyValueRow(
              'الدوام المعتمد',
              '${Fmt.timeOfDay(workSchedule!['check_in_time']?.toString())} - ${Fmt.timeOfDay(workSchedule!['check_out_time']?.toString())}',
              icon: Icons.schedule_rounded,
            ),
        ],
      ),
    );
  }
}

/// رسالة الخطأ تحت كارت الموقع، مع "إعادة المحاولة" و"فتح الإعدادات" إذا الموقع الدقيق مرفوض.
class AttendanceErrorCard extends StatelessWidget {
  const AttendanceErrorCard({super.key, required this.message, required this.preciseDenied, required this.onRetry});

  final String message;
  final bool preciseDenied;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      tone: AppTone.danger,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.danger),
              const SizedBox(width: AppSpace.md),
              Expanded(child: Text(message.trim(), style: AppText.bodySm.copyWith(color: AppColors.textPrimary))),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              if (preciseDenied)
                const AppButton.secondary(label: 'فتح الإعدادات', icon: Icons.settings_rounded, size: AppButtonSize.small, onPressed: PreciseLocation.openSettings),
              AppButton.secondary(label: 'إعادة المحاولة', icon: Icons.refresh_rounded, size: AppButtonSize.small, onPressed: onRetry),
            ],
          ),
        ],
      ),
    );
  }
}

/// اختيار حضور/انصراف + زر البصمة + سطر الحالة تحته.
class AttendancePunchControls extends StatelessWidget {
  const AttendancePunchControls({
    super.key,
    required this.selectedType,
    required this.onTypeChanged,
    required this.submitting,
    required this.mockDetected,
    required this.hasPosition,
    required this.inRange,
    required this.onSubmit,
  });

  final String selectedType;
  final ValueChanged<String> onTypeChanged;
  final bool submitting;
  final bool mockDetected;
  final bool hasPosition;
  final bool inRange;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'check_in', label: Text('حضور'), icon: Icon(Icons.login_rounded)),
            ButtonSegment(value: 'check_out', label: Text('انصراف'), icon: Icon(Icons.logout_rounded)),
          ],
          selected: {selectedType},
          showSelectedIcon: false,
          onSelectionChanged: (s) {
            AppHaptics.select();
            onTypeChanged(s.first);
          },
        ),
        const SizedBox(height: AppSpace.md),
        AppButton(
          label: selectedType == 'check_out' ? 'بصمة الانصراف' : 'بصمة الحضور',
          icon: Icons.fingerprint_rounded,
          variant: selectedType == 'check_out' ? AppButtonVariant.warning : AppButtonVariant.primary,
          size: AppButtonSize.large,
          expand: true,
          loading: submitting,
          haptic: false,
          onPressed: mockDetected || !hasPosition ? null : onSubmit,
        ),
        const SizedBox(height: AppSpace.sm),
        Text(
          mockDetected
              ? 'البصمة موقوفة لأن الجهاز يستعمل موقعاً مزيّفاً.'
              : !hasPosition
                  ? 'ننتظر تحديد موقعك حتى تقدر تبصم.'
                  : inRange
                  ? 'أنت داخل نطاق الفرع، تقدر تبصم الآن.'
                  : 'اقترب من الفرع حتى تدخل ضمن النطاق المسموح.',
          style: AppText.caption.copyWith(color: mockDetected ? AppColors.danger : null),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// ملاحظة الخصوصية أسفل الشاشة.
class AttendancePrivacyNote extends StatelessWidget {
  const AttendancePrivacyNote({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.privacy_tip_outlined, size: 16, color: AppColors.textMuted),
        SizedBox(width: AppSpace.sm),
        Expanded(
          child: Text(
            'نستعمل موقعك فقط لتأكيد وجودك في الفرع أثناء ساعات الدوام الرسمية.',
            style: AppText.caption,
          ),
        ),
      ],
    );
  }
}

/// رسالة نجاح البصمة (أو حفظها بالجهاز بدون إنترنت).
class PunchSuccessDialog extends StatelessWidget {
  const PunchSuccessDialog({super.key, required this.isCheckIn, required this.isSynced, required this.note});

  final bool isCheckIn;
  final bool isSynced;

  /// تنبيه التأخير/الخروج المبكر، أو null.
  final String? note;

  @override
  Widget build(BuildContext context) {
    final tone = isSynced ? AppTone.success : AppTone.warning;
    return AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(AppSpace.xxl, AppSpace.xxl, AppSpace.xxl, AppSpace.lg),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ToneIcon(isSynced ? Icons.check_rounded : Icons.cloud_off_rounded, tone: tone, size: 72),
          const SizedBox(height: AppSpace.xl),
          Text(isCheckIn ? 'تم تسجيل حضورك' : 'تم تسجيل انصرافك', style: AppText.title, textAlign: TextAlign.center),
          const SizedBox(height: AppSpace.sm),
          Text(
            isSynced
                ? '${Fmt.time(DateTime.now())} — ${note ?? (isCheckIn ? 'دوام موفق' : 'شكراً على يومك')}'
                : 'انقطع الإنترنت، فحفظنا البصمة بالجهاز وسنرسلها تلقائياً عند عودة الاتصال.',
            style: AppText.bodySm,
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [AppButton(label: 'تم', expand: true, onPressed: () => Navigator.of(context).pop())],
    );
  }
}
