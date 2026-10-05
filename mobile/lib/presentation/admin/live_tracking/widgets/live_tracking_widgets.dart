// أجزاء عرض التتبع الحي: عدّاد الحالات، الخريطة، كارت الموظف المختار.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/logic/tracking_rules.dart';
import '../../../../core/models/models.dart';
import '../../../shared/ui/ui.dart';

/// لون واسم حالة الموظف بالتتبع.
(AppTone, String) trackStatusStyle(TrackStatus s) => switch (s) {
      TrackStatus.inside => (AppTone.success, 'داخل الفرع'),
      TrackStatus.outside => (AppTone.danger, 'خارج النطاق'),
      TrackStatus.checkedOut => (AppTone.warning, 'انصراف'),
      TrackStatus.absent => (AppTone.neutral, 'لم يبصم'),
    };

class TrackingStatusCounter extends StatelessWidget {
  const TrackingStatusCounter({super.key, required this.status, required this.count, required this.selected, required this.onTap});
  final TrackStatus status;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (tone, label) = trackStatusStyle(status);
    return Semantics(
      button: true,
      selected: selected,
      label: '$label: $count',
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.control,
        child: AnimatedContainer(
          duration: AppMotion.of(context, AppMotion.fast),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
          decoration: BoxDecoration(
            color: selected ? tone.container : Colors.transparent,
            borderRadius: AppRadius.control,
            border: Border.all(color: selected ? tone.color.withValues(alpha: 0.5) : AppColors.border),
          ),
          child: ExcludeSemantics(
            child: Column(
              children: [
                Text('$count', style: AppText.titleSm.copyWith(color: tone == AppTone.neutral ? AppColors.textPrimary : tone.color)),
                Text(label, style: AppText.overline, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LiveTrackingMap extends StatelessWidget {
  const LiveTrackingMap({
    super.key,
    required this.controller,
    required this.center,
    required this.branches,
    required this.employees,
    required this.focused,
    required this.showTrail,
    required this.onTapEmployee,
  });

  final MapController controller;
  final LatLng center;
  final List<BranchModel> branches;
  final List<TrackedEmployee> employees;
  final TrackedEmployee? focused;
  final bool showTrail;
  final ValueChanged<TrackedEmployee> onTapEmployee;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: FlutterMap(
        mapController: controller,
        options: MapOptions(initialCenter: center, initialZoom: 13.5, minZoom: 4, maxZoom: 18, backgroundColor: AppColors.surface2),
        children: [
          appMapTiles(),
          CircleLayer(
            circles: [
              for (final b in branches)
                if (b.hasLocation)
                  CircleMarker(
                    point: LatLng(b.latitude!, b.longitude!),
                    radius: b.radiusMeters ?? 100,
                    useRadiusInMeter: true,
                    color: AppColors.brand.withValues(alpha: 0.12),
                    borderColor: AppColors.brand,
                    borderStrokeWidth: 2,
                  ),
            ],
          ),
          if (showTrail && focused != null && focused!.trail.length >= 2)
            PolylineLayer(polylines: [Polyline(points: focused!.trail, strokeWidth: 4, color: AppColors.brand, borderStrokeWidth: 1.5, borderColor: AppColors.bg)]),
          MarkerLayer(
            markers: [
              for (final t in employees)
                if (t.position != null) _marker(t),
              if (focused?.checkInPoint != null)
                Marker(
                  point: focused!.checkInPoint!,
                  child: Container(
                    decoration: BoxDecoration(color: AppColors.surface3, shape: BoxShape.circle, border: Border.all(color: AppColors.success, width: 2)),
                    child: const Icon(Icons.flag_rounded, size: 16, color: AppColors.success),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Marker _marker(TrackedEmployee t) {
    final isFocused = focused?.id == t.id;
    final (tone, label) = trackStatusStyle(t.status);
    final size = isFocused ? 44.0 : 34.0;
    return Marker(
      point: t.position!,
      width: size + 8,
      height: size + 8,
      child: Semantics(
        button: true,
        label: '${t.name}، $label',
        child: GestureDetector(
          onTap: () => onTapEmployee(t),
          child: Center(
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: tone == AppTone.neutral ? AppColors.surface3 : tone.color,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.bg, width: isFocused ? 3 : 2),
                boxShadow: AppElevation.low,
              ),
              alignment: Alignment.center,
              child: Text(
                t.name.characters.first,
                style: AppText.label.copyWith(color: tone == AppTone.neutral ? AppColors.textPrimary : AppColors.onStatus, fontSize: isFocused ? 16 : 13, height: 1),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TrackingFocusCard extends StatelessWidget {
  const TrackingFocusCard({super.key, required this.item, required this.showTrail, required this.onToggleTrail, required this.onClose});
  final TrackedEmployee item;
  final bool showTrail;
  final VoidCallback onToggleTrail;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final (tone, label) = trackStatusStyle(item.status);
    return ContentWidth(
      maxWidth: 520,
      child: Material(
        color: AppColors.surface1,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.card, side: BorderSide(color: tone.color.withValues(alpha: 0.5))),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.sm, AppSpace.xs, AppSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  AppAvatar(name: item.name, url: item.employee['avatar_url']?.toString(), size: 40, tone: tone),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name, style: AppText.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(item.branchName, style: AppText.caption),
                      ],
                    ),
                  ),
                  StatusBadge(label, tone: tone, dot: true),
                  IconButton(tooltip: 'إغلاق', icon: const Icon(Icons.close_rounded, size: 20), onPressed: onClose),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              Wrap(
                spacing: AppSpace.lg,
                runSpacing: AppSpace.xs,
                children: [
                  if (item.checkIn != null) TrackingFact(Icons.login_rounded, Fmt.time(item.checkIn)),
                  if (item.checkOut != null) TrackingFact(Icons.logout_rounded, Fmt.time(item.checkOut)),
                  if (item.distanceToBranch != null) TrackingFact(Icons.near_me_rounded, 'عن الفرع ${formatDistance(item.distanceToBranch!)}'),
                  if (item.lastSeen != null) TrackingFact(Icons.update_rounded, Fmt.relative(item.lastSeen)),
                  if (item.batteryLevel != null) TrackingFact(Icons.battery_std_rounded, '${item.batteryLevel}%'),
                  if (item.isMoving) const TrackingFact(Icons.directions_walk_rounded, 'يتحرك'),
                ],
              ),
              if (item.trail.length >= 2) ...[
                const SizedBox(height: AppSpace.sm),
                Row(
                  children: [
                    const Icon(Icons.route_rounded, size: 18, color: AppColors.brand),
                    const SizedBox(width: AppSpace.xs),
                    Expanded(child: Text('المسار ${item.totalDistanceKm.toStringAsFixed(2)} كم · ${item.trail.length} نقطة', style: AppText.bodySm)),
                    TextButton(onPressed: onToggleTrail, child: Text(showTrail ? 'إخفاء' : 'إظهار')),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class TrackingFact extends StatelessWidget {
  const TrackingFact(this.icon, this.text, {super.key});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.textMuted),
          const SizedBox(width: AppSpace.xs),
          Text(text, style: AppText.bodySm.copyWith(color: AppColors.textPrimary)),
        ],
      );
}
